#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LOGFILE="$TMP/test.log"

# main.sh no ejecuta main al hacer source (guarda BASH_SOURCE == $0).
# shellcheck disable=SC1091
source "$ROOT/src/main.sh"

DRY_MODE=true
RAN="$TMP/ran.txt"

# --- el registro es coherente ---
for id in "${BLOCK_IDS[@]}"; do
    [[ -n "${BLOCK_FN[$id]:-}" ]] || fail "BLOCK_FN sin entrada para $id"
    declare -F "${BLOCK_FN[$id]}" >/dev/null || fail "la función ${BLOCK_FN[$id]} (bloque $id) no existe"
done

# --- el catálogo solo devuelve ids registrados ---
detect_gpu_profile() { printf 'intel+nvidia\n'; }
detect_facetimehd_camera() { printf 'yes\n'; }
for model in MacBookPro12,1 GenericPC; do
    MACBOOK_MODEL="$model"
    while IFS= read -r id; do
        [[ " ${BLOCK_IDS[*]} " == *" $id "* ]] || fail "el catálogo ($model) devuelve '$id' que no está en BLOCK_IDS"
    done < <(block_catalog_visible_ids)
done

# --- stubs que registran su ejecución ---
for id in "${BLOCK_IDS[@]}"; do
    eval "stub_$id() { printf '%s\n' '$id' >>\"$RAN\"; }"
    BLOCK_FN[$id]="stub_$id"
done
configure_shell_paths() { printf 'shell_paths\n' >>"$RAN"; }
verify_ai_tools() { printf 'verify_ai\n' >>"$RAN"; }

# run_bootstrap_blocks se llama como sentencia simple (set -e dentro de los bloques).
run_blocks() {
    : >"$RAN"
    RC=0
    set +e
    run_bootstrap_blocks "$@" >/dev/null 2>&1
    RC=$?
    set -e
}

MACBOOK_MODEL="GenericPC"

# orden de ejecución = orden de BLOCK_IDS
run_blocks node sync
assert_eq "$RC" "0" "node sync termina bien"
assert_eq "$(paste -sd, "$RAN")" "sync,node" "sync antes que node"

# regresión B10: appimage se ejecuta
BLOCK_FN[appimage]=install_appimage_support_package
install_appimage_support_package() { printf 'appimage_real\n' >>"$RAN"; }
run_blocks appimage
assert_eq "$(paste -sd, "$RAN")" "appimage_real" "appimage llama a install_appimage_support_package"
BLOCK_FN[appimage]=stub_appimage

# bloque no compatible con el equipo: error 2 y nada se ejecuta
run_blocks mbpwatch
assert_eq "$RC" "2" "mbpwatch en GenericPC devuelve 2"
assert_eq "$(wc -l <"$RAN")" "0" "mbpwatch en GenericPC no ejecuta nada"

# id desconocido: se valida todo antes de ejecutar nada
run_blocks sync nope
assert_eq "$RC" "2" "id desconocido devuelve 2"
assert_eq "$(wc -l <"$RAN")" "0" "un id desconocido no ejecuta ningún bloque"

# set -e dentro del bloque: un fallo a mitad cuenta aunque la última línea tenga éxito
mid_failure() {
    printf 'mid_start\n' >>"$RAN"
    false
    printf 'mid_end\n' >>"$RAN"
}
BLOCK_FN[sync]=mid_failure
run_blocks sync
assert_eq "$RC" "1" "fallo a mitad de bloque devuelve 1"
assert_eq "$(paste -sd, "$RAN")" "mid_start" "el bloque se aborta en el primer fallo"

# un bloque fallido no impide ejecutar los siguientes
run_blocks sync node
assert_eq "$RC" "1" "retorno final 1 con un bloque fallido"
assert_eq "$(paste -sd, "$RAN")" "mid_start,node" "los bloques siguientes se ejecutan"
BLOCK_FN[sync]=stub_sync

# bloques ai_*: shell_paths y verify tras el último ai_* y antes de mbpwatch
MACBOOK_MODEL="MacBookPro12,1"
run_blocks mbpwatch ai_claude ai_codex
assert_eq "$RC" "0" "ai + mbpwatch terminan bien"
assert_eq "$(paste -sd, "$RAN")" "ai_codex,ai_claude,shell_paths,verify_ai,mbpwatch" "postproceso ai_* antes de mbpwatch"
MACBOOK_MODEL="GenericPC"

# --list-blocks
listing="$(list_bootstrap_blocks)"
assert_not_contains "$listing" "mbpwatch" "list-blocks en GenericPC"
assert_contains "$listing" "sync"$'\t'"ON"$'\t' "list-blocks muestra id, estado y etiqueta"

defaults="$(block_catalog_default_ids | paste -sd, -)"
assert_contains "$defaults" "sync" "ids por defecto incluyen sync"
assert_not_contains "$defaults" "mbpwatch" "ids por defecto sin mbpwatch en GenericPC"

# --- CLI de extremo a extremo (dry-run) ---
out="$(DRY_MODE=true bash "$ROOT/src/main.sh" bootstrap --dry-run --blocks sync,node 2>&1)"
assert_contains "$out" "Bloque 1/2" "CLI --blocks: primer bloque"
assert_contains "$out" "Bloque 2/2" "CLI --blocks: segundo bloque"
assert_not_contains "$out" "Bloque 3/" "CLI --blocks: solo dos bloques"
out="$(bash "$ROOT/src/main.sh" bootstrap --blocks zzz --dry-run 2>&1)" && fail "id desconocido en CLI debería fallar" || true
assert_contains "$out" "Bloque desconocido o no compatible" "CLI con id desconocido"

printf 'OK blocks\n'
