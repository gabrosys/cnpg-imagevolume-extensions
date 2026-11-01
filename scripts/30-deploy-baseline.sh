#!/usr/bin/env bash
# Namespace, metrics ConfigMap, PodMonitor and the cluster without the extension.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/_demo.sh"

announce_target

ensure_namespace
M="$ROOT/manifests/cnpg"
for f in metrics-configmap podmonitor cluster-baseline; do
  render "$M/$f.yaml" | k -n "$NAMESPACE" apply -f -
done
wait_cluster_ready
k -n "$NAMESPACE" get cluster "$CLUSTER_NAME"
