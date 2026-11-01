#!/usr/bin/env bash
# Asserts the kind environment is usable: operator, ImageVolume support, Prometheus.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/_assert.sh"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/kind/_kind.sh"

require_kind_context || exit 1

echo "operator"
READY=$(k -n cnpg-system get deployment -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null)
assert_eq "1" "$READY" "cnpg_operator_ready"
VER=$(k -n cnpg-system get deployment -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null)
assert_contains "$VER" ":1.30.1" "cnpg_operator_is_1.30.1"

echo "image volume"
k delete pod imgvol-check --ignore-not-found --wait >/dev/null 2>&1
k apply -f - >/dev/null <<POD
apiVersion: v1
kind: Pod
metadata:
  name: imgvol-check
spec:
  restartPolicy: Never
  containers:
    - name: c
      image: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
      command: ["sleep", "3600"]
      volumeMounts:
        - { name: ext, mountPath: /ext }
  volumes:
    - name: ext
      image:
        reference: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie
        pullPolicy: IfNotPresent
POD
if k wait --for=condition=Ready pod/imgvol-check --timeout=90s >/dev/null 2>&1; then
  _ok "image_volume_pod_ready"
  LS=$(k exec imgvol-check -- ls /ext 2>&1)
  assert_contains "$LS" "lib" "image_volume_has_lib"
  assert_contains "$LS" "share" "image_volume_has_share"
else
  _bad "image_volume_pod_ready"
  k describe pod imgvol-check | tail -8
fi
k delete pod imgvol-check --ignore-not-found --wait=false >/dev/null 2>&1

echo "prometheus"
PR=$(k -n monitoring get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
assert_eq "Running" "$PR" "prometheus_running"
SEL=$(k -n monitoring get prometheus -o jsonpath='{.items[0].spec.podMonitorNamespaceSelector}' 2>/dev/null)
assert_eq "{}" "$SEL" "prometheus_selects_all_namespaces"
SEL=$(k -n monitoring get prometheus -o jsonpath='{.items[0].spec.podMonitorSelector}' 2>/dev/null)
assert_eq "{}" "$SEL" "prometheus_selects_all_podmonitors"

summary
