#!/usr/bin/env bash
# Shared helpers. Sourcing this file only defines variables and functions.

NAMESPACE="${NAMESPACE:-cnpg-imgvol-demo}"
NS_LABEL="app.kubernetes.io/part-of=cnpg-imagevolume-extensions"

_CLIENT=""

# First of the given commands found on PATH. Used only to query the server.
_probe_client() {
  type -ap "$@" 2>/dev/null | head -1
}

# Minor version of the server behind the current context, e.g. 35.
server_minor() {
  local c
  c=$(_probe_client oc kubectl)
  [ -n "$c" ] || return 1
  "$c" ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} get --raw /version 2>/dev/null | sed -n 's/.*"minor": *"\([0-9]*\).*/\1/p'
}

is_openshift() {
  local c
  c=$(_probe_client oc kubectl)
  [ -n "$c" ] || return 1
  "$c" ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} api-versions 2>/dev/null | grep -qx 'route.openshift.io/v1'
}

# Prints the client to use: $KUBECTL, else oc on OpenShift, else the first
# kubectl on PATH within one minor version of the server.
pick_client() {
  if [ -n "${KUBECTL:-}" ]; then
    echo "$KUBECTL"
    return 0
  fi

  if is_openshift; then
    local oc_path
    oc_path=$(_probe_client oc)
    if [ -z "$oc_path" ]; then
      echo "error: the context is OpenShift but 'oc' is not on PATH (or set KUBECTL)" >&2
      return 1
    fi
    echo "$oc_path"
    return 0
  fi

  local server c minor diff
  server=$(server_minor) || server=""
  if [ -z "$server" ]; then
    echo "error: cannot read the server version from the current context" >&2
    return 1
  fi

  for c in $(type -ap kubectl 2>/dev/null); do
    minor=$("$c" version --client 2>/dev/null | sed -n 's/.*v1\.\([0-9]*\)\..*/\1/p' | head -1)
    [ -n "$minor" ] || continue
    diff=$((minor - server))
    [ "${diff#-}" -le 1 ] && { echo "$c"; return 0; }
  done

  echo "error: no kubectl within version skew of server 1.${server}; install a matching one or set KUBECTL" >&2
  return 1
}

# Runs the picked client against the current context (or KUBE_CONTEXT when set).
k() {
  if [ -z "$_CLIENT" ]; then
    _CLIENT=$(pick_client) || return 1
  fi
  "$_CLIENT" ${KUBE_CONTEXT:+--context "$KUBE_CONTEXT"} "$@"
}

# Substitutes only ${EXT_IMAGE} in FILE and prints the result.
render() {
  local file="$1" esc
  if grep -q '\${EXT_IMAGE}' "$file"; then
    if [ -z "${EXT_IMAGE:-}" ]; then
      echo "error: EXT_IMAGE is required to render $file (run the image build step)" >&2
      return 1
    fi
    esc=$(printf '%s' "$EXT_IMAGE" | sed 's/[&|\\]/\\&/g')
    sed "s|\${EXT_IMAGE}|${esc}|g" "$file"
  else
    cat "$file"
  fi
}

require_ns_ownership() {
  local ns="$1" key="${NS_LABEL%%=*}" want="${NS_LABEL#*=}" got
  got=$(k get namespace "$ns" -o "jsonpath={.metadata.labels.${key//./\\.}}" 2>/dev/null) || got=""
  if [ "$got" != "$want" ]; then
    echo "error: namespace '$ns' is not labeled ${NS_LABEL}; refusing to continue" >&2
    return 1
  fi
}

# Prints the architecture shared by all words in $1 (e.g. "arm64 arm64"); fails on mixed or empty.
single_arch() {
  local uniq
  uniq=$(printf '%s\n' $1 | sort -u)
  if [ -z "$uniq" ]; then
    echo "error: no node architecture found" >&2
    return 1
  fi
  if [ "$(printf '%s\n' "$uniq" | wc -l | tr -d ' ')" -ne 1 ]; then
    echo "error: mixed node architectures ($(echo $uniq)); the extension image must match every node" >&2
    return 1
  fi
  printf '%s\n' "$uniq"
}

# Creates NAMESPACE with NS_LABEL. An existing namespace must already carry the label; it is never relabeled.
ensure_namespace() {
  if k get namespace "$NAMESPACE" >/dev/null 2>&1; then
    require_ns_ownership "$NAMESPACE"
  else
    k create namespace "$NAMESPACE" >/dev/null && k label namespace "$NAMESPACE" "$NS_LABEL" >/dev/null
  fi
}

# Context and API server of the target. The minified view honors KUBE_CONTEXT.
current_context() { k config view --minify -o jsonpath='{.current-context}' 2>/dev/null; }
current_server()  { k config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null; }

# Prints the target context, server and namespace. Call it first in every script that writes.
announce_target() {
  printf 'target: context=%s server=%s namespace=%s\n' "$(current_context)" "$(current_server)" "$NAMESPACE" >&2
}

_ext_image_file() { printf '%s' "${EXT_IMAGE_FILE:-${ROOT:-.}/.ext-image.env}"; }

forget_ext_image() { rm -f "$(_ext_image_file)"; }

# Loads EXT_IMAGE from the file the build step wrote, unless it is already set. The file records
# the API server and namespace the image is valid for; a different target is an error.
load_ext_image() {
  local f server
  f=$(_ext_image_file)
  [ -n "${EXT_IMAGE:-}" ] && return 0
  EXT_IMAGE_SERVER=""
  EXT_IMAGE_NAMESPACE=""
  if [ -f "$f" ]; then
    # shellcheck disable=SC1090
    source "$f"
  fi
  if [ -z "${EXT_IMAGE:-}" ]; then
    echo "error: EXT_IMAGE is not set and $f is missing; run the image build step first" >&2
    return 1
  fi
  if [ -z "${EXT_IMAGE_SERVER:-}" ] || [ -z "${EXT_IMAGE_NAMESPACE:-}" ]; then
    echo "error: $f does not record the cluster and namespace it was built for; run the image build step again" >&2
    unset EXT_IMAGE
    return 1
  fi
  server=$(current_server)
  if [ "$server" != "$EXT_IMAGE_SERVER" ] || [ "$NAMESPACE" != "$EXT_IMAGE_NAMESPACE" ]; then
    echo "error: $f was built for $EXT_IMAGE_SERVER (namespace $EXT_IMAGE_NAMESPACE) but the target is $server (namespace $NAMESPACE); run the image build step again" >&2
    unset EXT_IMAGE
    return 1
  fi
}

require_edb_token() {
  local f="${ROOT:-.}/.env"
  if [ -z "${EDB_SUBSCRIPTION_TOKEN:-}" ] && [ -f "$f" ]; then
    set -a
    source "$f"
    set +a
  fi
  if [ -z "${EDB_SUBSCRIPTION_TOKEN:-}" ]; then
    echo "error: EDB_SUBSCRIPTION_TOKEN is not set. edb_wait_states needs an EDB subscription token:" >&2
    echo "       copy .env.example to .env and fill it in (or export the variable)" >&2
    return 1
  fi
  export EDB_SUBSCRIPTION_TOKEN
}

# Prints a temporary copy of build context $1 plus the file edb-subscription-token. The caller removes it.
token_build_context() {
  local src="$1" dir
  dir=$(mktemp -d)
  cp -R "$src"/. "$dir"/
  (umask 077 && printf '%s' "$EDB_SUBSCRIPTION_TOKEN" > "$dir/edb-subscription-token")
  printf '%s\n' "$dir"
}

urlencode() {
  local s="$1" i c out=""
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}

count_series() {
  local n
  n=$(printf '%s' "$1" | grep -o '"metric":' | wc -l | tr -d ' ')
  printf '%s\n' "$n"
}

# Operator version from an image tag, or from the OLM owner label (cloudnative-pg.v1.30.1).
operator_version() {
  local image="$1" owner="$2" v="" ref
  ref="${image%%@*}" # drop a digest, which also contains ':'
  case "$ref" in
    *:[0-9]*) v="${ref##*:}" ;;
  esac
  if [ -z "$v" ]; then
    case "$owner" in
      *.v[0-9]*) v="${owner##*.v}" ;;
    esac
  fi
  printf '%s\n' "$v"
}

version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}
