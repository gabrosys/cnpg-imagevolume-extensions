#!/usr/bin/env bash
# Sessions waiting for ~15 s, so edb_wait_states has something to sample.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"

announce_target

k -n "$NAMESPACE" delete job demo-load --ignore-not-found >/dev/null
render "$ROOT/manifests/cnpg/load-job.yaml" | k -n "$NAMESPACE" apply -f -
k -n "$NAMESPACE" wait --for=condition=complete job/demo-load --timeout=180s
