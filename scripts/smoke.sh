#!/usr/bin/env bash
# End-to-end check of the whole demo on the current context. Resets the cluster objects
# first (not the namespace, so a built image survives), then runs every step in order.
# Prerequisite: the extension image build step has run (.ext-image.env or EXT_IMAGE).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_assert.sh"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/_demo.sh"
load_ext_image || exit 1

die() { _bad "$1"; summary; exit 1; }
pod_uids() { k -n "$NAMESPACE" get pods -l "cnpg.io/cluster=$CLUSTER_NAME,cnpg.io/podRole=instance" -o jsonpath='{.items[*].metadata.uid}'; }

announce_target
echo "reset"
reset_demo_objects || die "previous_demo_objects_removed"
_ok "previous_demo_objects_removed"

echo "baseline"
"$ROOT/scripts/30-deploy-baseline.sh" >/dev/null 2>&1 || die "deploy_baseline"
_ok "deploy_baseline"
assert_eq "3" "$(k -n "$NAMESPACE" get cluster "$CLUSTER_NAME" -o jsonpath='{.status.readyInstances}')" "baseline_has_three_ready_instances"
wait_for_series "cnpg_collector_up{namespace=\"$NAMESPACE\",cluster=\"demo\"}" 240 && _ok "metrics_are_scraped_before_the_extension" || die "metrics_are_scraped_before_the_extension"
assert_eq "0" "$(prom_series_count "cnpg_edb_wait_states_samples{namespace=\"$NAMESPACE\"}")" "metric_absent_before_extension"
assert_fails "create_extension_fails_on_baseline" psql_app "CREATE EXTENSION edb_wait_states"
assert_contains "$LAST_OUTPUT" "not available" "baseline_error_says_extension_not_available"

SHOW=$("$ROOT/scripts/70-show.sh" baseline 2>&1)
assert_contains "$SHOW" "CREATE EXTENSION edb_wait_states" "show_baseline_prints_the_statement"
assert_contains "$SHOW" "not available" "show_baseline_prints_the_error"

BEFORE=$(pod_uids)
"$ROOT/scripts/30-deploy-baseline.sh" >/dev/null 2>&1 || die "deploy_baseline_second_run"
assert_eq "$BEFORE" "$(pod_uids)" "deploy_baseline_is_idempotent"

echo "add extension"
OUT=$("$ROOT/scripts/40-add-extension.sh" 2>&1) || die "add_extension"
_ok "add_extension ($(printf '%s\n' "$OUT" | grep 'rolling update finished'))"
assert_contains "$(psql_app 'SHOW extension_control_path')" "/extensions/edb-wait-states/share" "extension_control_path_includes_the_mount"
assert_contains "$(psql_app 'SHOW dynamic_library_path')" "/extensions/edb-wait-states/lib" "dynamic_library_path_includes_the_mount"
assert_contains "$(psql_app 'SHOW shared_preload_libraries')" "edb_wait_states" "extension_is_preloaded"
assert_eq "1" "$(psql_app "SELECT count(*) FROM pg_available_extensions WHERE name = 'edb_wait_states'")" "extension_is_available"
assert_eq "0" "$(psql_app "SELECT count(*) FROM pg_extension WHERE extname = 'edb_wait_states'")" "extension_not_created_yet"

BEFORE=$(pod_uids)
"$ROOT/scripts/40-add-extension.sh" >/dev/null 2>&1 || die "add_extension_second_run"
assert_eq "$BEFORE" "$(pod_uids)" "add_extension_is_idempotent"

echo "database"
"$ROOT/scripts/50-create-database.sh" >/dev/null 2>&1 || die "create_database"
_ok "create_database"
assert_eq "1" "$(psql_app "SELECT count(*) FROM pg_extension WHERE extname = 'edb_wait_states'")" "extension_created_by_database_resource"

echo "load"
"$ROOT/scripts/60-load.sh" >/dev/null 2>&1 && _ok "load_job_completes" || _bad "load_job_completes"
wait_for_series "cnpg_edb_wait_states_samples{namespace=\"$NAMESPACE\",wait_event=\"PgSleep\"}" 240 && _ok "metric_shows_wait_events_after_load" || _bad "metric_shows_wait_events_after_load"

echo "show helpers"
SHOW=$("$ROOT/scripts/70-show.sh" wiring 2>&1)
assert_contains "$SHOW" "/extensions/edb-wait-states" "show_wiring_lists_the_mount"
assert_contains "$SHOW" "extension_control_path" "show_wiring_prints_extension_control_path"
assert_contains "$SHOW" "dynamic_library_path" "show_wiring_prints_dynamic_library_path"
SHOW=$("$ROOT/scripts/70-show.sh" metric 2>&1)
assert_contains "$SHOW" "wait_event=PgSleep" "show_metric_prints_the_series"

summary
