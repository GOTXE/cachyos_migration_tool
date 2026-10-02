#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/stubs.sh"

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"; stub_teardown' EXIT
export HOME="$TMP_HOME"
export LOGFILE="$TMP_HOME/test.log"

# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"

expect_valid() {
    validate_disk_selection "$1" "$2" || fail "'$1' de $2 debería ser válido"
}
expect_invalid() {
    if validate_disk_selection "$1" "$2"; then
        fail "'$1' de $2 debería ser inválido"
    fi
}

expect_invalid "0" 3
expect_invalid "-1" 3
expect_invalid "abc" 3
expect_invalid "" 3
expect_valid "1" 3
expect_valid "3" 3
expect_invalid "4" 3

# select_disk: "0" no debe seleccionar el último disco.
stub_setup
stub_cmd lsblk 0 'NAME="sdb1" SIZE="1G" FSTYPE="ext4" LABEL="a" MOUNTPOINT="/mnt/a" TRAN="usb"'
estimate_backup_bytes() { printf '0\n'; }
check_backup_space() { return 0; }
get_mount_available_human() { printf '1G\n'; }

prompt_read() { printf -v "$2" '%s' "0"; }
rc=0
out="$(select_disk 2>&1)" || rc=$?
assert_eq "$rc" "1" "select_disk con 0 devuelve 1"
assert_contains "$out" "Seleccion invalida." "mensaje de selección inválida"

prompt_read() { printf -v "$2" '%s' "1"; }
select_disk >/dev/null 2>&1
assert_eq "$DISK_MOUNT" "/mnt/a" "select_disk con 1 elige el disco"

printf 'OK select_disk\n'
