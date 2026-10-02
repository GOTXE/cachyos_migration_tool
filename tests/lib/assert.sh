#!/usr/bin/env bash
# Helpers de aserción compartidos por los tests. Se cargan con `source`.

fail() {
    printf 'TEST FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    [[ "$actual" == "$expected" ]] || fail "$label: esperado '$expected', obtenido '$actual'"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    printf '%s\n' "$haystack" | grep -Fq -- "$needle" || fail "$label: falta '$needle'"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
        fail "$label: no se esperaba '$needle'"
    fi
}

assert_file() {
    [[ -e "$1" ]] || fail "no existe: $1"
}

assert_no_file() {
    [[ ! -e "$1" ]] || fail "no debería existir: $1"
}

assert_mode() {
    local path="$1"
    local expected="$2"
    local actual
    actual="$(stat -c %a "$path")"
    [[ "$actual" == "$expected" ]] || fail "modo de $path: esperado $expected, obtenido $actual"
}
