#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/kind/_kind.sh"
require_kind_context

CNPG_CHART_VERSION="0.29.1" # operator 1.30.1

helm repo add cnpg https://cloudnative-pg.github.io/charts >/dev/null
helm repo update cnpg >/dev/null
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --kube-context "$KIND_CONTEXT" \
  --version "$CNPG_CHART_VERSION" \
  --namespace cnpg-system --create-namespace --wait
k -n cnpg-system get pods
