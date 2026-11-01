#!/usr/bin/env bash
# Deletes only our namespace, and only if it carries our label.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/_env.sh"

announce_target

if ! k get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "namespace '$NAMESPACE' does not exist; nothing to do"
  exit 0
fi
require_ns_ownership "$NAMESPACE"
k delete namespace "$NAMESPACE" --wait
forget_ext_image   # the ImageStream went with the namespace
