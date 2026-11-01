#!/usr/bin/env bash
# Assertion helpers for smoke.sh and scripts/kind/check.sh. Source it and call `summary` last.

PASS=0
FAIL=0
LAST_OUTPUT=""

_ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
_bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }

assert_eq() { # EXPECTED ACTUAL MSG
  if [ "$1" = "$2" ]; then _ok "$3"; else _bad "$3 (expected '$1', got '$2')"; fi
}

assert_contains() { # HAYSTACK NEEDLE MSG
  case "$1" in *"$2"*) _ok "$3" ;; *) _bad "$3 (missing '$2' in '$1')" ;; esac
}

assert_fails() { # MSG CMD... ; stores combined output in LAST_OUTPUT
  local msg="$1"
  shift
  if LAST_OUTPUT=$("$@" 2>&1); then _bad "$msg (command succeeded)"; else _ok "$msg"; fi
}

summary() {
  printf '%s passed, %s failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
