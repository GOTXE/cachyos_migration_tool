#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"

fail() {
    printf 'TEST FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    printf '%s\n' "$haystack" | grep -Fq "$needle" || fail "$label: missing '$needle'"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if printf '%s\n' "$haystack" | grep -Fq "$needle"; then
        fail "$label: unexpected '$needle'"
    fi
}

MACBOOK_MODEL="GenericPC"

detect_facetimehd_camera() {
    printf 'no\n'
}

check_profile() {
    local profile="$1"
    local expect_hwaccel="$2"
    local expect_vaapi="$3"
    local catalog

    detect_gpu_profile() {
        printf '%s\n' "$profile"
    }

    catalog="$(get_bootstrap_checklist_items)"

    if [ "$expect_hwaccel" = yes ]; then
        assert_contains "$catalog" "hwaccel|Aceleración HW Chromium/Brave|OFF" "$profile hwaccel"
    else
        assert_not_contains "$catalog" "hwaccel|Aceleración HW Chromium/Brave|OFF" "$profile hwaccel"
    fi

    if [ "$expect_vaapi" = yes ]; then
        assert_contains "$catalog" "vaapi|VA-API Brave/Chromium (Intel)|OFF" "$profile vaapi"
    else
        assert_not_contains "$catalog" "vaapi|VA-API Brave/Chromium (Intel)|OFF" "$profile vaapi"
    fi
}

check_profile intel-only no yes
check_profile amd-only yes no
check_profile nvidia-only yes no
check_profile intel+amd yes yes
check_profile intel+nvidia yes yes
check_profile unknown no no

printf 'OK GPU catalog capabilities\n'
