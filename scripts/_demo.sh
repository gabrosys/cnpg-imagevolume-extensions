#!/usr/bin/env bash
# Helpers that talk to the cluster. Sourced after scripts/_env.sh.

CLUSTER_NAME="demo"
CLUSTER_HEALTHY="Cluster in healthy state"

# API-server proxy path for an instant query against service "namespace/name:port".
prom_proxy_path() {
  local ns="${1%%/*}" rest="${1#*/}"
  printf '/api/v1/namespaces/%s/services/%s/proxy/api/v1/query?query=%s' "$ns" "$rest" "$(urlencode "$2")"
}

# Raw JSON of an instant query. How it reaches Prometheus:
#   PROM_SERVICE=ns/name:port   through the API-server service proxy
#   PROM_NS + PROM_POD          exec into that pod (needs curl or wget in it)
#   OpenShift                   exec into the user-workload Prometheus pod
#   otherwise                   service proxy to the Prometheus installed for kind
prom_query_raw() {
  if [ -n "${PROM_SERVICE:-}" ]; then
    k get --raw "$(prom_proxy_path "$PROM_SERVICE" "$1")" 2>/dev/null
  elif [ -n "${PROM_NS:-}" ] && [ -n "${PROM_POD:-}" ]; then
    _prom_exec "$PROM_NS" "$PROM_POD" "${PROM_CONTAINER:-prometheus}" "$1"
  elif is_openshift; then
    _prom_exec openshift-user-workload-monitoring prometheus-user-workload-0 prometheus "$1"
  else
    k get --raw "$(prom_proxy_path monitoring/kube-prometheus-stack-prometheus:http-web "$1")" 2>/dev/null
  fi
}

_prom_exec() { # NS POD CONTAINER EXPR
  local url="http://localhost:9090/api/v1/query?query=$(urlencode "$4")"
  k -n "$1" exec "$2" -c "$3" -- sh -c "curl -s '$url' 2>/dev/null || wget -qO- '$url'" 2>/dev/null
}

prom_series_count() { count_series "$(prom_query_raw "$1")"; }

wait_for_series() {
  local selector="$1" timeout="$2" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    [ "$(prom_series_count "$selector")" -ge 1 ] && return 0
    sleep 5
    waited=$((waited + 5))
  done
  echo "timeout: no series for $selector after ${timeout}s" >&2
  return 1
}

primary_pod() {
  k -n "$NAMESPACE" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.currentPrimary}'
}

# psql_app SQL: runs SQL as the application user on the primary. The password goes in on stdin,
# so it stays out of process lists and the exec request URL.
psql_app() {
  local pw
  pw=$(k -n "$NAMESPACE" get secret "${CLUSTER_NAME}-app" -o jsonpath='{.data.password}' | base64 -d)
  printf '%s\n' "$pw" | k -n "$NAMESPACE" exec -i "$(primary_pod)" -c postgres -- \
    sh -c 'IFS= read -r PGPASSWORD; export PGPASSWORD; exec psql -h localhost -U app -d app -v ON_ERROR_STOP=1 -Atc "$1"' sh "$1"
}

wait_cluster_ready() {
  k -n "$NAMESPACE" wait --for=condition=Ready "cluster/$CLUSTER_NAME" --timeout="${1:-600s}"
}

pods_with_image() {
  k -n "$NAMESPACE" get pods -l "cnpg.io/cluster=${CLUSTER_NAME},cnpg.io/podRole=instance" \
    -o jsonpath='{range .items[*]}{.spec.volumes[*].image.reference}{"\n"}{end}' | grep -cF "$1" || true
}

# Waits until every instance mounts image $1 and the cluster is healthy again. Every 15 s it
# prints progress and the latest image-pull warning, so a stuck pull shows.
wait_extension_rollout() {
  local image="$1" timeout="${2:-600}" waited=0 want ready phase mounted warn start_ts
  start_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  want=$(k -n "$NAMESPACE" get cluster "$CLUSTER_NAME" -o jsonpath='{.spec.instances}')
  while [ "$waited" -lt "$timeout" ]; do
    ready=$(k -n "$NAMESPACE" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.readyInstances}')
    phase=$(k -n "$NAMESPACE" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.phase}')
    mounted=$(pods_with_image "$image")
    if [ "$mounted" = "$want" ] && [ "$ready" = "$want" ] && [ "$phase" = "$CLUSTER_HEALTHY" ]; then
      return 0
    fi
    if [ $((waited % 15)) -eq 0 ] && [ "$waited" -gt 0 ]; then
      warn=$(k -n "$NAMESPACE" get events --field-selector type=Warning \
        -o jsonpath='{range .items[*]}{.lastTimestamp}{"|"}{.involvedObject.name}{"|"}{.message}{"\n"}{end}' 2>/dev/null |
        awk -F'|' -v s="$start_ts" '$1 >= s && $3 ~ /pull|Pull/ {m=$2": "$3} END {print m}')
      echo "waiting ${waited}s: ${mounted}/${want} pods mount the image, ${ready:-0}/${want} ready${warn:+; last pull warning: $warn}" >&2
    fi
    sleep 3
    waited=$((waited + 3))
  done
  echo "timeout: rollout of $image not finished after ${timeout}s" >&2
  return 1
}

# Deletes the demo Database and cluster (with their PVCs). Refuses a namespace that is not ours;
# does nothing when the namespace does not exist.
reset_demo_objects() {
  k get namespace "$NAMESPACE" >/dev/null 2>&1 || return 0
  require_ns_ownership "$NAMESPACE" || return 1
  k -n "$NAMESPACE" delete database "${CLUSTER_NAME}-app" --ignore-not-found --wait >/dev/null 2>&1
  k -n "$NAMESPACE" delete cluster "$CLUSTER_NAME" --ignore-not-found --cascade=foreground --wait >/dev/null 2>&1
  return 0
}
