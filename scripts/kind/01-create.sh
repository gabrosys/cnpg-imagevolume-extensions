#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/kind/_kind.sh"

if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
  echo "kind cluster '$KIND_CLUSTER' already exists"
else
  kind create cluster --name "$KIND_CLUSTER" --config "$ROOT/manifests/kind/cluster.yaml"
fi
# Select the kind context before any kube client call, so the client matches this server.
kind export kubeconfig --name "$KIND_CLUSTER"
require_kind_context
k get nodes
