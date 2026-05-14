#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"

fail() {
    printf 'TEST FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    [ "$expected" = "$actual" ] || fail "$label: expected '$expected', got '$actual'"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if ! printf '%s\n' "$haystack" | grep -Fq "$needle"; then
        fail "$label: missing '$needle'"
    fi
}

MACBOOK_MODEL="MacBookPro12,1"
assert_eq "mbp12_1" "$(get_macbook_profile_id)" "profile id mbp12_1"
assert_eq "MacBook Pro Retina 13\" 2015" "$(get_macbook_profile_label | tr -d '\n')" "profile label 12,1"
assert_contains "$(get_macbook_profile_traits)" "broadwell" "traits 12,1"
assert_contains "$(get_macbook_profile_traits)" "facetimehd" "traits 12,1 facetime"
macbook_profile_has_trait broadwell || fail "trait lookup broadwell failed"

MACBOOK_MODEL="MacBookPro8,1"
assert_eq "mbp8_1" "$(get_macbook_profile_id)" "profile id mbp8_1"
assert_eq "MacBook Pro 13\" Early 2011" "$(get_macbook_profile_label | tr -d '\n')" "profile label 8,1"
assert_contains "$(get_macbook_profile_traits)" "sandybridge" "traits 8,1"
if macbook_profile_has_trait facetimehd; then
    fail "8,1 should not advertise facetimehd"
fi

MACBOOK_MODEL="MacBookPro9,2"
assert_eq "generic" "$(get_macbook_profile_id)" "generic profile id"
assert_eq "Perfil genérico" "$(get_macbook_profile_label | tr -d '\n')" "generic label"

printf 'OK bootstrap profiles\n'
