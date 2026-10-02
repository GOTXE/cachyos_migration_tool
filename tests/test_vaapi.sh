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
source "$ROOT/src/lib/os.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/bootstrap.sh"

DRY_MODE=false
AUTO_CONFIRM=true
detect_gpu_profile() { printf 'intel-only\n'; }
log_package_batch_state() { :; }

stub_setup
stub_cmd yay
stub_cmd sudo
stub_cmd vainfo 0 'vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 24.1.0'

CALLS=()
run_cmd() {
    CALLS+=("$*")
    case "$1" in
        mkdir|mv|cp) "$@" ;;
    esac
}

reset_home() {
    rm -rf "$HOME/.config"
    CALLS=()
    : >"$STUB_LOG"
}

VAAPI_CONF="$HOME/.config/environment.d/vaapi.conf"
BRAVE_FLAGS="$HOME/.config/brave-flags.conf"

# --- Intel genérico: intel-media-driver + libva-intel-driver, sin forzar i965 ni tocar Brave ---
reset_home
MACBOOK_MODEL="GenericPC"
configure_vaapi_intel >/dev/null
calls="${CALLS[*]}"
assert_contains "$calls" "intel-media-driver" "genérico: intel-media-driver"
assert_contains "$calls" "libva-intel-driver" "genérico: libva-intel-driver"
assert_contains "$calls" "libva-utils" "genérico: libva-utils"
assert_not_contains "$calls" "libva-intel-driver-irql" "genérico: sin irql"
assert_no_file "$VAAPI_CONF"
assert_no_file "$BRAVE_FLAGS"
assert_contains "$(cat "$STUB_LOG")" "vainfo" "genérico: se ejecuta vainfo"

# --- vaapi.conf heredado de la versión anterior (solo i965): se aparta con .bak ---
reset_home
mkdir -p "$HOME/.config/environment.d"
printf 'LIBVA_DRIVER_NAME=i965\n' >"$VAAPI_CONF"
out="$(configure_vaapi_intel)"
assert_no_file "$VAAPI_CONF"
shopt -s nullglob
baks=("$VAAPI_CONF".bak.*)
shopt -u nullglob
assert_eq "${#baks[@]}" "1" "vaapi.conf heredado renombrado a .bak"
assert_contains "$out" "vaapi.conf.bak." "aviso con la ruta del backup"
assert_eq "$(cat "${baks[0]}")" "LIBVA_DRIVER_NAME=i965" "el .bak conserva el contenido"

# --- vaapi.conf con otro contenido: no se toca ---
reset_home
mkdir -p "$HOME/.config/environment.d"
printf 'LIBVA_DRIVER_NAME=iHD\nOTRA=1\n' >"$VAAPI_CONF"
configure_vaapi_intel >/dev/null
assert_eq "$(cat "$VAAPI_CONF")" $'LIBVA_DRIVER_NAME=iHD\nOTRA=1' "vaapi.conf personalizado intacto"
shopt -s nullglob
baks=("$VAAPI_CONF".bak.*)
shopt -u nullglob
assert_eq "${#baks[@]}" "0" "sin .bak para un vaapi.conf personalizado"

# --- MBP 12,1 (Broadwell) ---
reset_home
MACBOOK_MODEL="MacBookPro12,1"
configure_vaapi_intel >/dev/null
calls="${CALLS[*]}"
assert_contains "$calls" "libva-intel-driver-irql" "mbp12_1: irql"
assert_contains "$calls" "libva-utils" "mbp12_1: libva-utils"
assert_eq "$(cat "$VAAPI_CONF")" "LIBVA_DRIVER_NAME=i965" "mbp12_1: i965"
assert_file "$BRAVE_FLAGS"
assert_contains "$(cat "$BRAVE_FLAGS")" "--ozone-platform-hint=x11" "mbp12_1: flags de Brave"

# segunda ejecución: idempotente (sin .bak nuevos)
configure_vaapi_intel >/dev/null
shopt -s nullglob
baks=("$BRAVE_FLAGS".bak.*)
shopt -u nullglob
assert_eq "${#baks[@]}" "0" "segunda ejecución no crea .bak"

# --- MBP 8,1 (Sandy Bridge) ---
reset_home
MACBOOK_MODEL="MacBookPro8,1"
configure_vaapi_intel >/dev/null
calls="${CALLS[*]}"
assert_contains "$calls" "libva-intel-driver" "mbp8_1: libva-intel-driver"
assert_contains "$calls" "libva-utils" "mbp8_1: libva-utils"
assert_not_contains "$calls" "intel-media-driver" "mbp8_1: sin intel-media-driver"
assert_eq "$(cat "$VAAPI_CONF")" "LIBVA_DRIVER_NAME=i965" "mbp8_1: i965"

# --- vainfo que falla: aviso, no error ---
reset_home
MACBOOK_MODEL="GenericPC"
stub_cmd vainfo 1
rc=0
out="$(configure_vaapi_intel 2>&1)" || rc=$?
assert_eq "$rc" "0" "vainfo fallido no es error"
assert_contains "$out" "vainfo" "aviso por vainfo fallido"

# --- no Intel: no hace nada ---
reset_home
detect_gpu_profile() { printf 'amd-only\n'; }
configure_vaapi_intel >/dev/null
assert_eq "${#CALLS[@]}" "0" "GPU no Intel: sin acciones"
detect_gpu_profile() { printf 'intel-only\n'; }

# =====================================================================
# write_browser_flags_file
# =====================================================================
FLAGS="$TMP/flags/brave-flags.conf"
write_browser_flags_file "$FLAGS" $'--a\n--b' >/dev/null
assert_eq "$(cat "$FLAGS")" $'--a\n--b' "fichero nuevo"

out="$(write_browser_flags_file "$FLAGS" $'--a\n--b')"
shopt -s nullglob
baks=("$FLAGS".bak.*)
shopt -u nullglob
assert_eq "${#baks[@]}" "0" "contenido idéntico: sin .bak"
assert_contains "$out" "sin cambios" "contenido idéntico: se informa"

out="$(write_browser_flags_file "$FLAGS" $'--c')"
shopt -s nullglob
baks=("$FLAGS".bak.*)
shopt -u nullglob
assert_eq "${#baks[@]}" "1" "contenido distinto: .bak creado"
assert_eq "$(cat "${baks[0]}")" $'--a\n--b' "el .bak conserva el contenido anterior"
assert_eq "$(cat "$FLAGS")" "--c" "contenido nuevo escrito"
assert_contains "$out" ".bak." "aviso con la ruta del backup"

printf 'OK vaapi\n'
