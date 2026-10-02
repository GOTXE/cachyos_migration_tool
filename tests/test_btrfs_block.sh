#!/usr/bin/env bash
# shellcheck disable=SC2034
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
source "$ROOT/src/modules/bootstrap.sh"

FIX="$ROOT/tests/fixtures/boot"

# --- detect_bootloader ---
check_boot() {
    local fixture="$1" expected="$2"
    BOOT_ROOT_PREFIX="$FIX/$fixture"
    assert_eq "$(detect_bootloader)" "$expected" "bootloader de $fixture"
}
check_boot limine limine
check_boot grub grub
check_boot systemd-boot systemd-boot
check_boot unknown unknown

# limine.conf en otras ubicaciones admitidas
for rel in boot/limine.conf efi/limine.conf boot/efi/limine.conf boot/EFI/limine/limine.conf; do
    tree="$TMP/tree-$(printf '%s' "$rel" | tr '/' '_')"
    mkdir -p "$tree/$(dirname "$rel")"
    : >"$tree/$rel"
    BOOT_ROOT_PREFIX="$tree"
    assert_eq "$(detect_bootloader)" "limine" "limine.conf en $rel"
done

# precedencia: limine > grub > systemd-boot
both="$TMP/both"
mkdir -p "$both/boot/limine" "$both/boot/grub" "$both/boot/loader"
: >"$both/boot/limine/limine.conf"
: >"$both/boot/grub/grub.cfg"
: >"$both/boot/loader/loader.conf"
BOOT_ROOT_PREFIX="$both"
assert_eq "$(detect_bootloader)" "limine" "limine tiene prioridad"
rm "$both/boot/limine/limine.conf"
assert_eq "$(detect_bootloader)" "grub" "grub antes que systemd-boot"

# systemd-boot en $PREFIX/efi/loader/loader.conf
efi="$TMP/efi-tree"
mkdir -p "$efi/efi/loader"
: >"$efi/efi/loader/loader.conf"
BOOT_ROOT_PREFIX="$efi"
assert_eq "$(detect_bootloader)" "systemd-boot" "loader.conf bajo efi/"

# --- paquetes por bootloader ---
DRY_MODE=false
AUTO_CONFIRM=true
CALLS=()
run_cmd() { CALLS+=("$*"); }
stub_setup
stub_cmd snapper 0 'Config | Subvolume'

check_packages() {
    local fixture="$1" bootpkg="$2"
    CALLS=()
    BOOT_ROOT_PREFIX="$FIX/$fixture"
    configure_btrfs_snapshots >/dev/null
    local calls="${CALLS[*]}"
    assert_contains "$calls" "snapper" "$fixture: snapper"
    assert_contains "$calls" "snap-pac" "$fixture: snap-pac"
    assert_contains "$calls" "$bootpkg" "$fixture: $bootpkg"
    assert_not_contains "$calls" "grub-btrfs " "$fixture: sin grub-btrfs"
}
check_packages limine limine-snapper-sync
check_packages grub grub-btrfs-support
check_packages systemd-boot sdboot-manage

# limine no instala los paquetes de otros bootloaders
CALLS=()
BOOT_ROOT_PREFIX="$FIX/limine"
configure_btrfs_snapshots >/dev/null
assert_not_contains "${CALLS[*]}" "grub-btrfs-support" "limine: sin grub-btrfs-support"
assert_not_contains "${CALLS[*]}" "sdboot-manage" "limine: sin sdboot-manage"

# bootloader desconocido: aviso, return 1 y nada instalado
CALLS=()
BOOT_ROOT_PREFIX="$FIX/unknown"
rc=0
out="$(configure_btrfs_snapshots 2>&1)" || rc=$?
assert_eq "$rc" "1" "bootloader desconocido devuelve 1"
assert_eq "${#CALLS[@]}" "0" "bootloader desconocido no instala nada"
assert_contains "$out" "bootloader" "aviso de bootloader desconocido"

# --- aviso de subvolúmenes y guía de la wiki si no hay config root ---
BOOT_ROOT_PREFIX="$FIX/limine"
out="$(configure_btrfs_snapshots 2>&1)"
assert_contains "$out" "NO modifica particiones" "se mantiene el aviso de subvolúmenes"
assert_contains "$out" "wiki.cachyos.org/configuration/btrfs_snapshots" "guía de la wiki sin config root"

stub_cmd snapper 0 $'Config | Subvolume\n-------+----------\nroot   | /'
out="$(configure_btrfs_snapshots 2>&1)"
assert_not_contains "$out" "wiki.cachyos.org/configuration/btrfs_snapshots" "sin guía si ya existe la config root"

# --- visibilidad del bloque según el sistema de ficheros raíz ---
detect_root_filesystem() { printf 'btrfs\n'; }
assert_contains "$(get_bootstrap_checklist_items)" "btrfs|Snapshots BTRFS (Snapper)|OFF" "btrfs visible con raíz btrfs"
detect_root_filesystem() { printf 'ext4\n'; }
assert_not_contains "$(get_bootstrap_checklist_items)" "btrfs|" "btrfs oculto con raíz ext4"
detect_root_filesystem() { printf '\n'; }
assert_not_contains "$(get_bootstrap_checklist_items)" "btrfs|" "btrfs oculto sin FS detectado"

printf 'OK btrfs block\n'
