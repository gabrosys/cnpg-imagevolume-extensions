#!/usr/bin/env bash
# Declarative Database resource that runs CREATE EXTENSION.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"
source "$ROOT/scripts/_demo.sh"

announce_target

render "$ROOT/manifests/cnpg/database.yaml" | k -n "$NAMESPACE" apply -f -
waited=0
until [ "$(k -n "$NAMESPACE" get database demo-app -o jsonpath='{.status.applied}')" = "true" ]; do
  [ "$waited" -ge 120 ] && { echo "timeout: Database demo-app not applied" >&2; exit 1; }
  sleep 2
  waited=$((waited + 2))
done
k -n "$NAMESPACE" get database demo-app
