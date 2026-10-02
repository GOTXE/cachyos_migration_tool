#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/stubs.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; stub_teardown' EXIT

# inventory.sh debe poder cargarse sin common.sh.
# shellcheck disable=SC1091
source "$ROOT/src/lib/inventory.sh"

# PATH mínimo: solo utilidades base + stubs (el host puede tener pacman real).
BASE_BIN="$TMP/basebin"
mkdir -p "$BASE_BIN"
for tool in mkdir mktemp mv rm sort cat chmod; do
    ln -s "$(command -v "$tool")" "$BASE_BIN/$tool"
done
stub_setup

run_inventory() {
    local PATH="$STUB_DIR:$BASE_BIN"
    inventory_write "$@"
}

# stub_script <nombre> <cuerpo del script>
stub_script() {
    printf '#!/bin/bash\n%s\n' "$2" >"$STUB_DIR/$1"
    chmod +x "$STUB_DIR/$1"
}

# --- sin gestores: packages/ vacío, sin error ---
META="$TMP/meta-empty"
mkdir -p "$META"
run_inventory "$META"
assert_file "$META/packages"
assert_eq "$(find "$META/packages" -type f | wc -l)" "0" "packages/ vacío sin gestores"
assert_eq "$INVENTORY_MANAGERS" "" "sin gestores"
assert_eq "$INVENTORY_WARNINGS" "" "sin avisos"

# --- Arch: pacman con foráneos vacíos (pacman -Qqem sale con 1) ---
stub_script pacman 'echo "LC_ALL=$LC_ALL" >>"'"$TMP"'/lc.log"
case "$*" in
    "-Qqen") printf "base\nrsync\n" ;;
    "-Qqem") exit 1 ;;
    *) exit 2 ;;
esac'
META="$TMP/meta-arch"
mkdir -p "$META"
run_inventory "$META"
assert_eq "$(cat "$META/packages/pacman-native-explicit.txt")" $'base\nrsync' "pacman nativos"
assert_file "$META/packages/pacman-foreign.txt"
assert_eq "$(wc -c <"$META/packages/pacman-foreign.txt")" "0" "foráneos vacíos válidos"
assert_eq "$INVENTORY_MANAGERS" "pacman" "gestor pacman"
assert_eq "$INVENTORY_WARNINGS" "" "foráneos vacíos no es aviso"
assert_contains "$(cat "$TMP/lc.log")" "LC_ALL=C" "pacman con LC_ALL=C"

# --- Debian + Flatpak + Snap ---
rm -f "$STUB_DIR/pacman"
stub_script apt-mark 'printf "curl\ngit\n"'
stub_script dpkg 'printf "curl\t\t\tinstall\n"'
stub_script flatpak 'printf "org.mozilla.firefox\tflathub\n"'
stub_script snap 'printf "Name Version\ncore 16\n"'
META="$TMP/meta-deb"
mkdir -p "$META"
run_inventory "$META"
assert_eq "$(cat "$META/packages/apt-manual.txt")" $'curl\ngit' "apt-manual"
assert_file "$META/packages/dpkg-selections.txt"
assert_file "$META/flatpak-apps.txt"
assert_file "$META/snap-list.txt"
assert_eq "$INVENTORY_MANAGERS" "apt,dpkg,flatpak,snap" "gestores Debian"

# --- Fedora: rpm ordenado y único; dnf falla -> aviso ---
rm -f "$STUB_DIR"/{apt-mark,dpkg,flatpak,snap}
stub_script rpm 'printf "zlib\nbash\nbash\n"'
stub_script dnf 'exit 1'
META="$TMP/meta-fed"
mkdir -p "$META"
run_inventory "$META" 2>"$TMP/stderr.txt"
stderr="$(cat "$TMP/stderr.txt")"
assert_eq "$(cat "$META/packages/rpm-names.txt")" $'bash\nzlib' "rpm ordenado y único"
assert_no_file "$META/packages/dnf-userinstalled.txt"
assert_eq "$INVENTORY_MANAGERS" "rpm" "dnf fallido no cuenta como gestor"
assert_eq "$INVENTORY_WARNINGS" "dnf-userinstalled" "aviso de dnf"
assert_contains "$stderr" "dnf-userinstalled" "aviso por stderr"
assert_eq "$(find "$META/packages" -name '*.txt.*' | wc -l)" "0" "sin temporales"

# --- openSUSE ---
rm -f "$STUB_DIR"/{rpm,dnf}
stub_script zypper 'printf "S | Name\ni | bash\n"'
META="$TMP/meta-suse"
mkdir -p "$META"
run_inventory "$META"
assert_file "$META/packages/zypper-installed.txt"
assert_eq "$INVENTORY_MANAGERS" "zypper" "gestor zypper"

printf 'OK inventory\n'
