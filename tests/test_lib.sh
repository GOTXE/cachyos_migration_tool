#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/stubs.sh"

assert_eq "a" "a" "assert_eq igual"
assert_contains "hola mundo" "mundo" "assert_contains"
assert_not_contains "hola mundo" "adios" "assert_not_contains"

# Las aserciones fallidas deben terminar con código distinto de 0.
if (assert_eq "a" "b" "debe fallar") 2>/dev/null; then
    fail "assert_eq no falla con valores distintos"
fi
if (assert_contains "abc" "z" "debe fallar") 2>/dev/null; then
    fail "assert_contains no falla sin coincidencia"
fi
if (assert_not_contains "abc" "b" "debe fallar") 2>/dev/null; then
    fail "assert_not_contains no falla con coincidencia"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf 'x' >"$TMP/f"
chmod 640 "$TMP/f"
assert_file "$TMP/f"
assert_no_file "$TMP/nope"
assert_mode "$TMP/f" 640
if (assert_file "$TMP/nope") 2>/dev/null; then fail "assert_file no falla"; fi
if (assert_no_file "$TMP/f") 2>/dev/null; then fail "assert_no_file no falla"; fi
if (assert_mode "$TMP/f" 600) 2>/dev/null; then fail "assert_mode no falla"; fi

ORIG_PATH="$PATH"
stub_setup
assert_file "$STUB_DIR"
assert_eq "$STUB_LOG" "$STUB_DIR/calls.log" "STUB_LOG"
stub_cmd mytool 3 "salida"
rc=0
out="$(mytool uno "dos tres")" || rc=$?
assert_eq "$rc" "3" "código de salida del stub"
assert_eq "$out" "salida" "stdout del stub"
assert_contains "$(cat "$STUB_LOG")" "mytool uno dos tres" "registro de llamada"
stub_cmd quiet
quiet
assert_contains "$(cat "$STUB_LOG")" "quiet" "stub por defecto"
saved_dir="$STUB_DIR"
stub_teardown
assert_no_file "$saved_dir"
assert_eq "$PATH" "$ORIG_PATH" "PATH restaurado"

printf 'OK test lib helpers\n'
