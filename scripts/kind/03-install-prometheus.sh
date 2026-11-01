#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/kind/_kind.sh"
require_kind_context

PROM_CHART_VERSION="92.17.0"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update prometheus-community >/dev/null
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --kube-context "$KIND_CONTEXT" \
  --version "$PROM_CHART_VERSION" \
  --namespace monitoring --create-namespace \
  --values "$ROOT/manifests/kind/prometheus-values.yaml" --wait
k -n monitoring rollout status statefulset/prometheus-kube-prometheus-stack-prometheus --timeout=180s
