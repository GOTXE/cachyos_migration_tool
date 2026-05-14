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

    if ! printf '%s\n' "$haystack" | grep -Fq "$needle"; then
        fail "$label: missing '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if printf '%s\n' "$haystack" | grep -Fq "$needle"; then
        fail "$label: unexpected '$needle'"
    fi
}

detect_facetimehd_camera() {
    printf 'yes\n'
}

detect_gpu_profile() {
    printf 'intel-only\n'
}

MACBOOK_MODEL="MacBookPro12,1"
CATALOG_2015="$(get_bootstrap_checklist_items)"
assert_contains "$CATALOG_2015" "mbpwatch|MBP Watch diagnóstico (systemd)|ON" "catalog 12,1 mbpwatch"
assert_contains "$CATALOG_2015" "plasmoid|Plasmoid KDE MBP Watch|ON" "catalog 12,1 plasmoid"
assert_contains "$CATALOG_2015" "apple|Apple laptop extras|ON" "catalog 12,1 apple"
assert_contains "$CATALOG_2015" "facetime|FaceTime HD camera (AUR)|ON" "catalog 12,1 facetime"
assert_contains "$CATALOG_2015" "vaapi|VA-API Brave/Chromium (Intel Broadwell)|OFF" "catalog 12,1 vaapi"
assert_not_contains "$CATALOG_2015" "hwaccel|Aceleración HW Chromium/Brave|OFF" "catalog 12,1 hwaccel hidden"

MACBOOK_MODEL="MacBookPro8,1"
CATALOG_2011="$(get_bootstrap_checklist_items)"
assert_contains "$CATALOG_2011" "mbpwatch|MBP Watch diagnóstico (systemd)|ON" "catalog 8,1 mbpwatch"
assert_contains "$CATALOG_2011" "apple|Apple laptop extras|ON" "catalog 8,1 apple"
assert_not_contains "$CATALOG_2011" "facetime|FaceTime HD camera (AUR)|ON" "catalog 8,1 facetime hidden"
assert_contains "$CATALOG_2011" "vaapi|VA-API Brave/Chromium (Intel Sandy Bridge)|OFF" "catalog 8,1 vaapi"

MACBOOK_MODEL="MacBookPro9,2"
CATALOG_GENERIC="$(get_bootstrap_checklist_items)"
assert_not_contains "$CATALOG_GENERIC" "mbpwatch|MBP Watch diagnóstico (systemd)|ON" "catalog generic mbpwatch hidden"
assert_not_contains "$CATALOG_GENERIC" "apple|Apple laptop extras|ON" "catalog generic apple hidden"

printf 'OK bootstrap catalog\n'
