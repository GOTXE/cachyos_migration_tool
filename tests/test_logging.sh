#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"

TMP_HOME="$(mktemp -d)"
TMP_CWD="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_CWD"' EXIT

export HOME="$TMP_HOME"
unset LOGFILE XDG_STATE_HOME
cd "$TMP_CWD"

# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"

LOG_DIR="$HOME/.local/state/linux-migration-tool/logs"
assert_no_file "$LOG_DIR"

log "x" >/dev/null
assert_file "$LOG_DIR"
shopt -s nullglob
logs=("$LOG_DIR"/linux_migration_tool_*.log)
cwd_logs=("$TMP_CWD"/*.log)
shopt -u nullglob
assert_eq "${#logs[@]}" "1" "un log bajo XDG state"
assert_eq "${#cwd_logs[@]}" "0" "ningún log en el cwd"
assert_eq "$LOGFILE" "${logs[0]}" "LOGFILE apunta al log creado"

log 'C:\new\table' >/dev/null
assert_contains "$(cat "$LOGFILE")" 'C:\new\table' "barras invertidas literales"

log "${GREEN}ok${NC}" >/dev/null
last_line="$(tail -n 1 "$LOGFILE")"
assert_eq "$last_line" "ok" "log sin secuencias ANSI"
assert_not_contains "$(cat "$LOGFILE")" $'\033' "sin ESC en el fichero"

# La consola sí conserva los colores reales.
console="$(log "${GREEN}ok${NC}")"
assert_contains "$console" $'\033[0;32m' "consola con color"

# LOGFILE del entorno se respeta.
(
    export LOGFILE="$TMP_CWD/custom/mine.log"
    # shellcheck disable=SC1091
    source "$ROOT/src/lib/common.sh"
    log "custom" >/dev/null
    assert_file "$TMP_CWD/custom/mine.log"
)

printf 'OK logging\n'
