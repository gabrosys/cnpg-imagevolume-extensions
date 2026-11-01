#!/usr/bin/env bash
# Checks the preconditions on the current context (or KUBE_CONTEXT) and prints the fix for
# anything missing. Creates the demo namespace (labelled as ours) and a short-lived test pod in it.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"

announce_target

FAILED=0
pass() { printf '[PASS] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; shift; for l in "$@"; do printf '       %s\n' "$l"; done; }
fail() { printf '[FAIL] %s\n' "$1"; shift; for l in "$@"; do printf '       %s\n' "$l"; done; FAILED=1; }

minor=$(server_minor) || minor=""
if [ -z "$minor" ]; then
  fail "cluster reachable" "cannot read the server version from the current context"
  exit 1
fi
client=$(pick_client 2>&1) || {
  fail "usable kube client" "$client"
  exit 1
}
pass "cluster reachable (server 1.${minor}, client $client)"

crd_out=$(k get crd clusters.postgresql.cnpg.io 2>&1) && crd_ok=1 || crd_ok=0
case "$crd_out" in
  *[Ff]orbidden*)
    fail "permissions" "this script reads CRDs, operator deployments in all namespaces and the user-workload" \
      "monitoring pods, so it needs cluster-admin (see the README)."
    exit 1 ;;
esac
if [ "$crd_ok" = 1 ]; then
  pass "CloudNativePG CRDs installed"
else
  fail "CloudNativePG CRDs installed" "install the operator (kind: scripts/kind/02-install-cnpg.sh; OpenShift: OperatorHub, CloudNativePG)"
fi

img=$(k get deployment -A -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null)
owner=$(k get deployment -A -l app.kubernetes.io/name=cloudnative-pg -o jsonpath='{.items[0].metadata.labels.olm\.owner}' 2>/dev/null)
ver=$(operator_version "$img" "$owner")
if [ -n "$ver" ] && version_ge "$ver" 1.30; then
  pass "operator version $ver (>= 1.30)"
else
  fail "operator version >= 1.30" "found: '${ver:-unknown}' (image ${img:-none})"
fi

if k get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1; then
  pass "PodMonitor CRD present"
else
  fail "PodMonitor CRD present" "install a Prometheus Operator, or enable user-workload monitoring on OpenShift"
fi

if is_openshift; then
  ready=$(k -n openshift-user-workload-monitoring get pod prometheus-user-workload-0 -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
  case "$ready" in
    *true*) pass "user-workload monitoring running (scrapes PodMonitors in user namespaces)" ;;
    *) fail "user-workload monitoring running" \
         "the platform Prometheus does not scrape user namespaces." \
         "If the cluster-monitoring-config ConfigMap already exists, do not replace it: add the line" \
         "'enableUserWorkload: true' to its config.yaml (oc -n openshift-monitoring edit cm cluster-monitoring-config)." \
         "Otherwise, as cluster admin, create it:" \
         "apiVersion: v1" "kind: ConfigMap" "metadata:" "  name: cluster-monitoring-config" \
         "  namespace: openshift-monitoring" "data:" "  config.yaml: |" "    enableUserWorkload: true" ;;
  esac
else
  sel=$(k get prometheus -A -o jsonpath='{range .items[*]}{.spec.podMonitorSelector}{" "}{.spec.podMonitorNamespaceSelector}{"\n"}{end}' 2>/dev/null | grep -F '{} {}' || true)
  if [ -n "$sel" ]; then
    pass "a Prometheus selects every PodMonitor in every namespace"
  else
    fail "a Prometheus selects the demo PodMonitor" \
      "no Prometheus has empty podMonitorSelector and podMonitorNamespaceSelector." \
      "Set podMonitorSelector to match the PodMonitor (it has no labels; use {}) and" \
      "podMonitorNamespaceSelector to match namespace '$NAMESPACE' (use {})."
  fi
fi

ensure_namespace || exit 1   # stop here rather than write into a namespace that is not ours
# Any small extension image works as the probe; this one is published by the CNPG project.
k -n "$NAMESPACE" delete pod imgvol-verify --ignore-not-found --wait >/dev/null 2>&1
k -n "$NAMESPACE" apply -f - >/dev/null <<POD
apiVersion: v1
kind: Pod
metadata:
  name: imgvol-verify
spec:
  restartPolicy: Never
  containers:
    - name: c
      image: registry.k8s.io/pause:3.10
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      volumeMounts:
        - { name: ext, mountPath: /ext }
  volumes:
    - name: ext
      image:
        reference: ghcr.io/cloudnative-pg/pgvector:0.8.1-18-trixie
        pullPolicy: IfNotPresent
POD
if k -n "$NAMESPACE" wait --for=condition=Ready pod/imgvol-verify --timeout=120s >/dev/null 2>&1; then
  pass "cluster admits and runs image volumes"
else
  fail "cluster admits and runs image volumes" \
    "needs Kubernetes 1.35+ (or the ImageVolume gate on 1.33/1.34), a runtime that supports it," \
    "and, on OpenShift, an SCC that allows the 'image' volume type (restricted-v2 does on 4.22)." \
    "$(k -n "$NAMESPACE" get events --field-selector involvedObject.name=imgvol-verify -o jsonpath='{.items[-1:].message}' 2>/dev/null)"
fi
k -n "$NAMESPACE" delete pod imgvol-verify --ignore-not-found --wait=false >/dev/null 2>&1

errf=$(mktemp)
if load_ext_image 2>"$errf"; then
  pass "extension image recorded for this cluster and namespace ($EXT_IMAGE)"
  if is_openshift && ! k -n "$NAMESPACE" get imagestreamtag edbws:latest >/dev/null 2>&1; then
    warn "ImageStream edbws:latest not found in $NAMESPACE" "run make build-image"
  fi
else
  warn "extension image not ready for this cluster and namespace" "$(cat "$errf")" "run make build-image (or set EXT_IMAGE to a reference the cluster can pull)"
fi
rm -f "$errf"

if (require_edb_token) >/dev/null 2>&1; then
  pass "EDB_SUBSCRIPTION_TOKEN available (env or .env), needed to build the edb_wait_states image"
else
  warn "EDB_SUBSCRIPTION_TOKEN not set" "edb_wait_states is downloaded from the EDB repositories; copy .env.example to .env and set the token (only needed to build the image)"
fi

exit $FAILED
