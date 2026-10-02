#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/stubs.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; stub_teardown' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LOGFILE="$TMP/test.log"

# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/backup.sh"

export TZ=UTC
export BACKUP_NOW_EPOCH=1790951405   # 2026-10-02 14:30:05 UTC
REGEX='^[A-Za-z0-9._-]+_[0-9]{2}_[0-9]{2}_[0-9]{4}-[0-9]{2}[:h][0-9]{2}(_[0-9]+)?$'
DEST="$TMP/dest"
mkdir -p "$DEST"
BACKUP_FS_TYPE="ext4"

# etiqueta saneada
BACKUP_HOST_LABEL='Mi PC/01'
assert_eq "$(backup_host_label)" "Mi-PC-01" "host saneado"
assert_eq "$(build_backup_name "$DEST")" "Mi-PC-01_02_10_2026-14:30" "nombre canónico"
[[ "$(build_backup_name "$DEST")" =~ $REGEX ]] || fail "el nombre no cumple la regex"

# se conserva mayúscula/minúscula y los puntos de la etiqueta explícita
BACKUP_HOST_LABEL='Box.Lan'
assert_eq "$(backup_host_label)" "Box.Lan" "etiqueta explícita conserva puntos"

# uname -n sin dominio
unset BACKUP_HOST_LABEL
stub_setup
stub_cmd uname 0 'box.lan'
assert_eq "$(backup_host_label)" "box" "uname -n sin dominio"
assert_eq "$(build_backup_name "$DEST")" "box_02_10_2026-14:30" "nombre con uname"

# hostname vacío -> host
stub_cmd uname 0 ''
assert_eq "$(backup_host_label)" "host" "hostname vacío"
stub_teardown

# timestamp
assert_eq "$(backup_timestamp_label)" "02_10_2026-14:30" "timestamp"

# sistemas de ficheros sin ':'
for fs in exfat vfat msdos ntfs ntfs3 fuseblk cifs smb3; do
    backup_fs_forbids_colon "$fs" || fail "$fs debería prohibir ':'"
done
for fs in ext4 btrfs xfs f2fs zfs ""; do
    backup_fs_forbids_colon "$fs" && fail "$fs no debería prohibir ':'"
done

BACKUP_HOST_LABEL='testhost'
BACKUP_FS_TYPE="exfat"
name="$(build_backup_name "$DEST" 2>/dev/null)"
assert_eq "$name" "testhost_02_10_2026-14h30" "fallback h en exfat"
[[ "$name" =~ $REGEX ]] || fail "el nombre con fallback no cumple la regex"
warn="$(build_backup_name "$DEST" 2>&1 >/dev/null)"
assert_contains "$warn" "exfat" "aviso de sustitución de ':'"

# colisiones
BACKUP_FS_TYPE="ext4"
mkdir "$DEST/testhost_02_10_2026-14:30"
assert_eq "$(build_backup_name "$DEST")" "testhost_02_10_2026-14:30_2" "primer sufijo"
mkdir "$DEST/testhost_02_10_2026-14:30_2"
name="$(build_backup_name "$DEST")"
assert_eq "$name" "testhost_02_10_2026-14:30_3" "segundo sufijo"
[[ "$name" =~ $REGEX ]] || fail "el nombre con sufijo no cumple la regex"

# sin BACKUP_NOW_EPOCH se usa la hora actual (formato válido)
unset BACKUP_NOW_EPOCH
[[ "$(backup_timestamp_label)" =~ ^[0-9]{2}_[0-9]{2}_[0-9]{4}-[0-9]{2}:[0-9]{2}$ ]] || fail "timestamp actual inválido"

printf 'OK backup naming\n'
