#!/usr/bin/env bash
# Live-demo helpers.
#   70-show.sh baseline CREATE EXTENSION on the cluster without the extension (it fails)
#   70-show.sh wiring   the mount and the settings that point at it
#   70-show.sh metric   the custom metric as Prometheus sees it
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/_demo.sh"

baseline() {
  echo "app=> CREATE EXTENSION edb_wait_states;"
  psql_app "CREATE EXTENSION edb_wait_states" 2>&1 || true
}

wiring() {
  local pod
  pod=$(primary_pod)
  echo "# /extensions on the primary ($pod)"
  k -n "$NAMESPACE" exec "$pod" -c postgres -- sh -c 'ls /extensions; for d in /extensions/*; do echo "$d:"; ls "$d"; done'
  echo "# settings"
  for g in extension_control_path dynamic_library_path shared_preload_libraries; do
    printf '%s = %s\n' "$g" "$(psql_app "SHOW $g")"
  done
}

metric() {
  local raw rows
  echo "cnpg_edb_wait_states_samples{namespace=\"$NAMESPACE\"}"
  raw=$(prom_query_raw "cnpg_edb_wait_states_samples{namespace=\"$NAMESPACE\"}")
  if [ -z "$raw" ]; then
    echo "  cannot query Prometheus (on OpenShift this needs exec into the user-workload Prometheus pod: cluster-admin; see the README)"
    return 0
  fi
  rows=$(printf '%s' "$raw" | sed 's/{"metric":/\n&/g' |
    sed -n 's/.*"datname":"\([^"]*\)".*"pod":"\([^"]*\)".*"wait_event":"\([^"]*\)".*"wait_event_type":"\([^"]*\)".*"value":\[[^,]*,"\([^"]*\)"\].*/  pod=\2 datname=\1 wait_event_type=\4 wait_event=\3 value=\5/p')
  if [ -n "$rows" ]; then printf '%s\n' "$rows"; else echo "  no series (extension not created yet, no load yet, or not scraped yet)"; fi
}

case "${1:-}" in
  baseline) baseline ;;
  wiring) wiring ;;
  metric) metric ;;
  *) echo "usage: $0 baseline|wiring|metric" >&2; exit 2 ;;
esac
