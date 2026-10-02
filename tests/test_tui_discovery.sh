#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LOGFILE="$TMP/test.log"

# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/src/lib/tui.sh"

SCAN="$TMP/scan"
mkdir -p "$SCAN"
tui_collect_restore_roots() { printf '%s\n' "$SCAN"; }

make_v2() {
    local dir="$1" created="$2" host="$3"
    mkdir -p "$dir/metadata"
    printf 'FORMAT_VERSION=2\nCREATED_AT=%s\nHOST_LABEL=%s\n' "$created" "$host" >"$dir/metadata/manifest.env"
    printf 'USER=u\nUID=1000\nGID=1000\n' >"$dir/metadata/user_ids.conf"
}
make_v1() {
    local dir="$1" mtime="$2"
    mkdir -p "$dir/metadata"
    printf 'USER=u\nUID=1000\nGID=1000\n' >"$dir/metadata/user_ids.conf"
    touch -d "$mtime" "$dir/metadata/user_ids.conf"
}

# El orden alfabético es el inverso del cronológico a propósito.
make_v2 "$SCAN/aaa_05_09_2026-10:00" "2026-09-05T10:00:00+0000" aaa    # más reciente
make_v2 "$SCAN/zzz_01_01_2026-10:00" "2026-01-01T10:00:00+0000" zzz    # más antiguo
make_v1 "$SCAN/mmm_v1" "2026-05-01 10:00:00 UTC"                       # entre ambos
# empate de fecha: el v2 va antes que el v1
make_v2 "$SCAN/tie_v2" "2026-03-01T10:00:00+0000" tie
make_v1 "$SCAN/tie_v1" "2026-03-01 10:00:00 UTC"
# profundidad máxima (5): .../a/b/c/<backup>/metadata/...
make_v2 "$SCAN/d1/d2/deep" "2026-06-01T10:00:00+0000" deep
# no son backups
mkdir -p "$SCAN/nada/metadata"

mapfile -t FOUND < <(tui_find_restore_backups)
expected=(
    "$SCAN/aaa_05_09_2026-10:00"
    "$SCAN/d1/d2/deep"
    "$SCAN/mmm_v1"
    "$SCAN/tie_v2"
    "$SCAN/tie_v1"
    "$SCAN/zzz_01_01_2026-10:00"
)
assert_eq "${#FOUND[@]}" "${#expected[@]}" "número de backups encontrados (sin duplicados)"
for i in "${!expected[@]}"; do
    assert_eq "${FOUND[$i]}" "${expected[$i]}" "posición $i del listado"
done

# _tui_is_backup_dir acepta v2 (manifest) y v1 (user_ids.conf)
_tui_is_backup_dir "$SCAN/aaa_05_09_2026-10:00" || fail "v2 debería ser backup"
_tui_is_backup_dir "$SCAN/mmm_v1" || fail "v1 debería ser backup"
mkdir -p "$SCAN/solo_manifest/metadata"
printf 'FORMAT_VERSION=2\n' >"$SCAN/solo_manifest/metadata/manifest.env"
_tui_is_backup_dir "$SCAN/solo_manifest" || fail "manifest sin user_ids.conf debería ser backup"
_tui_is_backup_dir "$SCAN/nada" && fail "directorio vacío no es backup"

# etiqueta con host para los listados
assert_eq "$(tui_backup_label "$SCAN/aaa_05_09_2026-10:00")" "aaa_05_09_2026-10:00 (equipo: aaa)" "etiqueta v2 con host"
assert_eq "$(tui_backup_label "$SCAN/mmm_v1")" "mmm_v1" "etiqueta v1 sin host"

printf 'OK tui discovery\n'
