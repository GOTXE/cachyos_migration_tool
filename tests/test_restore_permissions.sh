#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/restore.sh"

fail() {
    printf 'TEST FAIL: %s\n' "$1" >&2
    exit 1
}

CAPTURED=()
run_cmd() {
    CAPTURED=("$@")
}

assert_contains() {
    local needle="$1"
    printf '%s\n' "${CAPTURED[@]}" | grep -Fq -- "$needle" || fail "missing '$needle'"
}

RESTORE_PRESERVE_PERMISSIONS=false
restore_rsync /backup/configs/ /home/user/ configs
assert_contains "--no-perms"
assert_contains "--chmod=F644,D755"

RESTORE_PRESERVE_PERMISSIONS=true
restore_rsync /backup/configs/ /home/user/ configs
assert_contains "-a"

printf 'OK restore permissions\n'
