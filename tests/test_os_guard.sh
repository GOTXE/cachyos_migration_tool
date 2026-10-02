#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/Documents" "$TMP/dest"
printf 'x\n' >"$HOME/Documents/a.txt"
export LOGFILE="$TMP/test.log"
FIX="$ROOT/tests/fixtures/os-release"

run_cli() {
    local fixture="$1"
    shift
    OS_RELEASE_FILE="$FIX/$fixture" AUTO_CONFIRM_ENV=1 BACKUP_SELECTION_FROM_TUI=1 \
        SELECTED_CONFIG_ITEMS_RAW=".bashrc" SELECTED_DATA_DIRS_RAW="$HOME/Documents" \
        bash "$ROOT/src/main.sh" "$@" 2>&1 </dev/null
}

# --- los comandos solo-Arch se bloquean fuera de Arch ---
for cmd in "bootstrap --dry-run" "tui-bootstrap-run" "configure-vaapi-brave --dry-run" \
           "install-mbp-watch --dry-run" "install-talk2ai --dry-run" \
           "install-codexbar-tray --dry-run" "install-youtube-force-h264 --dry-run"; do
    for fixture in debian fedora; do
        rc=0
        # shellcheck disable=SC2086
        out="$(run_cli "$fixture" $cmd)" || rc=$?
        assert_eq "$rc" "1" "'$cmd' en $fixture debe salir con 1"
        assert_contains "$out" "[ERROR] Este comando solo está soportado en Arch/CachyOS (detectado: $fixture)." "mensaje de '$cmd' en $fixture"
    done
done

# --- Arch/CachyOS no se bloquea ---
for fixture in cachyos arch; do
    rc=0
    out="$(run_cli "$fixture" bootstrap --list-blocks)" || rc=$?
    assert_eq "$rc" "0" "bootstrap --list-blocks en $fixture"
    assert_not_contains "$out" "solo está soportado" "sin guarda en $fixture"
done

# --- backup/restore/postcheck/test no se bloquean en Debian ---
rc=0
out="$(run_cli debian backup --dry-run --target "$TMP/dest")" || rc=$?
assert_eq "$rc" "0" "backup --dry-run en debian"
assert_not_contains "$out" "solo está soportado" "backup no bloqueado"

rc=0
out="$(run_cli debian test catalog)" || rc=$?
assert_not_contains "$out" "solo está soportado" "test no bloqueado"

rc=0
out="$(run_cli debian restore --source "$TMP/no-existe" --dry-run)" || rc=$?
assert_not_contains "$out" "solo está soportado" "restore no bloqueado"

rc=0
out="$(run_cli debian restic-backup status)" || rc=$?
assert_not_contains "$out" "solo está soportado" "restic-backup no bloqueado"

rc=0
out="$(run_cli debian install-codexbar-plasma --dry-run)" || rc=$?
assert_not_contains "$out" "solo está soportado" "install-codexbar-plasma no bloqueado"

printf 'OK os guard\n'
