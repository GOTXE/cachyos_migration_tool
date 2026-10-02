#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/stubs.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; stub_teardown' EXIT

FIXTURE="$ROOT/tests/fixtures/backup-v1"
stub_setup
stub_cmd sudo 99

restore_into() {
    local home="$1"
    local backup="$2"
    shift 2
    mkdir -p "$home"
    env HOME="$home" LOGFILE="$TMP/restore.log" AUTO_CONFIRM_ENV=1 \
        bash "$ROOT/migration.sh" restore --source "$backup" --force "$@" 2>&1
}

# --- v1 con backup_selection.txt: las rutas anidadas se reparan ---
HOME_A="$TMP/home-a"
out="$(restore_into "$HOME_A" "$FIXTURE")" || { printf '%s\n' "$out" >&2; fail "restore v1 falló"; }
assert_file "$HOME_A/.config/Code/User/settings.json"
assert_no_file "$HOME_A/Code"
assert_file "$HOME_A/.bashrc"
assert_file "$HOME_A/Documents/notes.txt"
assert_file "$HOME_A/Projects/demo/README.md"
assert_contains "$out" "formato v1" "aviso de formato v1"

# --- v1 sin backup_selection.txt: comportamiento antiguo + aviso ---
OLD="$TMP/backup-v1-sin-seleccion"
cp -r "$FIXTURE" "$OLD"
rm -f "$OLD/logs/backup_selection.txt"
HOME_B="$TMP/home-b"
out="$(restore_into "$HOME_B" "$OLD")" || { printf '%s\n' "$out" >&2; fail "restore v1 sin selección falló"; }
assert_file "$HOME_B/Code/User/settings.json"
assert_no_file "$HOME_B/.config/Code"
assert_contains "$out" "backup_selection.txt" "aviso por falta de backup_selection.txt"

# --- sudo no se usó ---
assert_eq "$(cat "$STUB_LOG")" "" "restore v1 no llama a sudo"

printf 'OK restore v1\n'
