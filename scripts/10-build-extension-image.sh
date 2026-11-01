#!/usr/bin/env bash
# Builds the edb_wait_states extension image and makes it reachable from the current
# cluster without publishing it anywhere outside the cluster.
# Needs EDB_SUBSCRIPTION_TOKEN (env or .env); it never ends up in the image.
#   kind:      local docker buildx build, then kind load (tag reference)
#   OpenShift: in-cluster binary build into an ImageStream (digest reference)
#   other:     set EXT_IMAGE to a reference your cluster can pull; nothing is built
# Prints EXT_IMAGE=<reference> as the last line and writes it, with the cluster and
# namespace it is valid for, to .ext-image.env.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"

CONTEXT_DIR="$ROOT/docker/edb-wait-states"
TAG="localhost/edb-wait-states:1.7.0-18-trixie"

announce_target

if [ -n "${EXT_IMAGE:-}" ]; then
  echo "EXT_IMAGE is set; not building. Using $EXT_IMAGE" >&2
  echo "EXT_IMAGE=$EXT_IMAGE"
  exit 0
fi

require_edb_token
ARCH=$(single_arch "$(k get nodes -o jsonpath='{.items[*].status.nodeInfo.architecture}')")
echo "node architecture: $ARCH" >&2

build_kind() {
  local ctx cluster tmp bctx
  ctx=$(current_context)
  case "$ctx" in
    kind-*) cluster="${ctx#kind-}" ;;
    *)
      echo "error: context '$ctx' is neither OpenShift nor a kind cluster, so there is nowhere to build into." >&2
      echo "       Push the extension image to a registry the cluster can pull from and set EXT_IMAGE to its reference." >&2
      exit 1 ;;
  esac
  tmp=$(mktemp -d)
  bctx=$(token_build_context "$CONTEXT_DIR")
  trap 'rm -rf "$tmp" "$bctx"' RETURN
  docker buildx build --platform "linux/$ARCH" --load -t "$TAG" "$bctx" >&2
  docker save --platform "linux/$ARCH" -o "$tmp/image.tar" "$TAG"
  kind load image-archive "$tmp/image.tar" --name "$cluster" >&2
  EXT_IMAGE="$TAG"
}

build_openshift() {
  local bctx
  ensure_namespace
  if ! k -n "$NAMESPACE" get buildconfig edbws >/dev/null 2>&1; then
    k -n "$NAMESPACE" new-build --binary --strategy=docker --name=edbws >&2
  fi
  bctx=$(token_build_context "$CONTEXT_DIR")
  trap 'rm -rf "$bctx"' RETURN
  # --wait makes a failed build a failed script, instead of silently reusing the previous image.
  k -n "$NAMESPACE" start-build edbws --from-dir "$bctx" --follow --wait >&2
  EXT_IMAGE=$(k -n "$NAMESPACE" get imagestreamtag edbws:latest -o jsonpath='{.image.dockerImageReference}')
}

if is_openshift; then build_openshift; else build_kind; fi

printf 'EXT_IMAGE=%s\nEXT_IMAGE_SERVER=%s\nEXT_IMAGE_NAMESPACE=%s\n' \
  "$EXT_IMAGE" "$(current_server)" "$NAMESPACE" > "$ROOT/.ext-image.env"
echo "EXT_IMAGE=$EXT_IMAGE"
