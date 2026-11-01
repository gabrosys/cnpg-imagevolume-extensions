#!/usr/bin/env bash
# kind-only helpers. Sourced after scripts/_env.sh.

KIND_CLUSTER="${KIND_CLUSTER:-cnpg-imgvol}"
KIND_CONTEXT="kind-${KIND_CLUSTER}"

require_kind_context() {
  local current server
  current=$(current_context) || current=""
  if [ "$current" != "$KIND_CONTEXT" ]; then
    echo "error: current context is '${current}', expected '${KIND_CONTEXT}' (kind-only step)" >&2
    return 1
  fi
  server=$(current_server)
  case "$server" in
    https://127.0.0.1:*|https://localhost:*|https://0.0.0.0:*|https://\[::1\]:*) ;;
    *) echo "error: '${current}' points at ${server}, not a local kind cluster" >&2; return 1 ;;
  esac
}
