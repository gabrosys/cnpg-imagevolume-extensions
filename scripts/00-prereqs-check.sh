#!/usr/bin/env bash
# Checks the tools the scripts need. helm, docker and kind matter only for the kind environment.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"

MISSING=0
ok()   { printf '[OK]   %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1"; shift; for l in "$@"; do printf '       %s\n' "$l"; done; MISSING=1; }

for cmd in curl sed grep; do
  command -v "$cmd" >/dev/null && ok "$cmd" || fail "$cmd not found"
done

if command -v kind >/dev/null; then
  command -v helm >/dev/null && ok "helm" || fail "helm not found (needed for kind)"
  ok "kind"
  docker info >/dev/null 2>&1 && ok "docker daemon" || fail "docker daemon not reachable (needed for kind)"
  docker buildx version >/dev/null 2>&1 && ok "docker buildx" || fail "docker buildx not found (needed for kind image build)"
else
  echo "[skip] kind not installed (only needed for the kind environment)"
fi

if c=$(pick_client 2>&1); then
  ok "kube client: $c"
elif [ -n "$(server_minor 2>/dev/null)" ]; then
  fail "kube client" "$c"          # a cluster is reachable but no client fits it
elif command -v oc >/dev/null || command -v kubectl >/dev/null; then
  ok "kube client present (no reachable context yet)"
else
  fail "neither oc nor kubectl found"
fi

exit $MISSING
