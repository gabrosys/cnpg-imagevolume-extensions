#!/usr/bin/env bash
# Applies the extension manifest and waits for the rolling update to finish.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/_demo.sh"

announce_target
load_ext_image

start=$SECONDS
render "$ROOT/manifests/cnpg/cluster-extension.yaml" | k -n "$NAMESPACE" apply -f -
wait_extension_rollout "$EXT_IMAGE"
echo "rolling update finished in $((SECONDS - start))s"
k -n "$NAMESPACE" get cluster "$CLUSTER_NAME"
