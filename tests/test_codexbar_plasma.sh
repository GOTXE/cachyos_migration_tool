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
# shellcheck disable=SC1091
source "$ROOT/src/modules/codexbar_plasma.sh"

DRY_MODE=false
AUTO_CONFIRM=true
# Independiente del usuario que ejecute el test (en CI puede ser root).
current_uid() { printf '1000\n'; }
OS_RELEASE_FILE="$ROOT/tests/fixtures/os-release/cachyos"

# --- fixtures del release: .plasmoid (zip) válido, con Id erróneo y checksums ---
FIX="$TMP/fixtures"
mkdir -p "$FIX/good" "$FIX/bad"
make_plasmoid() {
    local dir="$1" id="$2"
    printf '{"KPlugin":{"Id":"%s","Version":"0.2.43"}}\n' "$id" >"$dir/metadata.json"
    (cd "$dir" && python3 -m zipfile -c codexbar-plasma.plasmoid metadata.json)
    (cd "$dir" && printf '%s  codexbar-plasma.plasmoid\n' "$(sha256sum codexbar-plasma.plasmoid | cut -d' ' -f1)" >codexbar-plasma.plasmoid.sha256)
}
make_plasmoid "$FIX/good" "app.codexbar.plasma"
make_plasmoid "$FIX/bad" "app.otro.widget"

# --- stubs ---
stub_setup
STATE="$TMP/installed.state"
CURL_LOG="$TMP/curl.log"
export STATE CURL_LOG
export CURL_FIXTURE_DIR="$FIX/good"

printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$CURL_LOG"\nout=""\nprev=""\nfor a in "$@"; do\n  [ "$prev" = "-o" ] && out="$a"\n  prev="$a"\n  url="$a"\ndone\ncase "$url" in\n  *.sha256) cp "$CURL_FIXTURE_DIR/codexbar-plasma.plasmoid.sha256" "$out" ;;\n  *) cp "$CURL_FIXTURE_DIR/codexbar-plasma.plasmoid" "$out" ;;\nesac\n' >"$STUB_DIR/curl"
printf '#!/bin/bash\nprintf "kpackagetool6 %%s\\n" "$*" >>"%s"\ncase "$*" in\n  *" -l"*|*"-l") [ -f "$STATE" ] && cat "$STATE" || true ;;\n  *" -i "*) echo app.codexbar.plasma >"$STATE" ;;\n  *" -r "*) rm -f "$STATE" ;;\nesac\nexit 0\n' "$STUB_LOG" >"$STUB_DIR/kpackagetool6"
chmod +x "$STUB_DIR/curl" "$STUB_DIR/kpackagetool6"
stub_cmd systemctl 1

# El host de desarrollo puede tener una CLI codexbar real: se controla desde el test.
CODEXBAR_PRESENT=false
codexbar_cli_available() { [ "$CODEXBAR_PRESENT" = true ]; }

kcalls() { grep -c '^kpackagetool6 .* -[iur] ' "$STUB_LOG" || true; }

# --- instalación nueva -> -i ---
rm -f "$STATE" "$CURL_LOG"; : >"$STUB_LOG"
out="$(install_codexbar_plasma 2>&1)" || { printf '%s\n' "$out" >&2; fail "instalación nueva falló"; }
assert_contains "$(cat "$STUB_LOG")" "-t Plasma/Applet -i " "instalación nueva usa -i"
assert_not_contains "$(cat "$STUB_LOG")" "-t Plasma/Applet -u " "instalación nueva no usa -u"
assert_contains "$(cat "$CURL_LOG")" "https://github.com/Lucenx9/codexbar-plasma/releases/latest/download/codexbar-plasma.plasmoid" "URL latest del asset"
assert_contains "$(cat "$CURL_LOG")" "releases/latest/download/codexbar-plasma.plasmoid.sha256" "URL latest del checksum"
assert_contains "$(cat "$CURL_LOG")" "--proto =https --tlsv1.2 --max-time 120" "curl con opciones seguras"
assert_contains "$out" 'Añade "CodexBar" desde Añadir widgets del panel.' "mensaje final"
assert_not_contains "$out" "Para recargarlo" "instalación nueva no sugiere recarga"
assert_contains "$out" "General → Managed CLI → Use managed CLI" "aviso de CLI gestionada sin --with-cli"

# --- ya instalado -> -u (segunda ejecución, idempotente) ---
: >"$STUB_LOG"
out="$(install_codexbar_plasma 2>&1)"
assert_contains "$(cat "$STUB_LOG")" "-t Plasma/Applet -u " "ya instalado usa -u"
assert_not_contains "$(cat "$STUB_LOG")" "-t Plasma/Applet -i " "ya instalado no usa -i"
assert_contains "$out" "systemctl --user restart plasma-plasmashell.service" "sugerencia de recarga tras actualizar"

# --- checksum alterado: no se instala ---
rm -f "$STATE"; : >"$STUB_LOG"
BAD_SUM="$TMP/badsum"
mkdir -p "$BAD_SUM"
cp "$FIX/good/codexbar-plasma.plasmoid" "$BAD_SUM/"
printf '%064d  codexbar-plasma.plasmoid\n' 0 >"$BAD_SUM/codexbar-plasma.plasmoid.sha256"
CURL_FIXTURE_DIR="$BAD_SUM"
rc=0
out="$(install_codexbar_plasma 2>&1)" || rc=$?
assert_eq "$([ "$rc" -ne 0 ] && echo fail || echo ok)" "fail" "checksum alterado devuelve ≠0"
assert_contains "$out" "Checksum de CodexBar Plasma no válido; no se instala." "mensaje de checksum"
assert_eq "$(kcalls)" "0" "checksum alterado: sin -i/-u"

# --- fichero .sha256 con formato inválido ---
printf 'esto no es un checksum\n' >"$BAD_SUM/codexbar-plasma.plasmoid.sha256"
rc=0
install_codexbar_plasma >/dev/null 2>&1 || rc=$?
assert_eq "$([ "$rc" -ne 0 ] && echo fail || echo ok)" "fail" "formato de checksum inválido devuelve ≠0"
assert_eq "$(kcalls)" "0" "formato inválido: sin -i/-u"

# --- Id distinto: no se instala ---
CURL_FIXTURE_DIR="$FIX/bad"
rc=0
out="$(install_codexbar_plasma 2>&1)" || rc=$?
assert_eq "$([ "$rc" -ne 0 ] && echo fail || echo ok)" "fail" "Id distinto devuelve ≠0"
assert_eq "$(kcalls)" "0" "Id distinto: sin -i/-u"
CURL_FIXTURE_DIR="$FIX/good"

# --- versiones ---
rm -f "$CURL_LOG"; : >"$STUB_LOG"
rc=0
out="$(install_codexbar_plasma --version 0.2 2>&1)" || rc=$?
assert_eq "$rc" "2" "versión inválida devuelve 2"
assert_contains "$out" "[ERROR]" "versión inválida: mensaje"
assert_no_file "$CURL_LOG"

rm -f "$STATE"
install_codexbar_plasma --version v0.2.43 >/dev/null 2>&1
assert_contains "$(cat "$CURL_LOG")" "/releases/download/v0.2.43/codexbar-plasma.plasmoid" "URL con versión fija"
assert_contains "$(cat "$CURL_LOG")" "/releases/download/v0.2.43/codexbar-plasma.plasmoid.sha256" "URL del checksum con versión fija"

# --- DRY_MODE: no descarga ---
rm -f "$CURL_LOG" "$STATE"; : >"$STUB_LOG"
DRY_MODE=true
out="$(install_codexbar_plasma 2>&1)"
DRY_MODE=false
assert_no_file "$CURL_LOG"
assert_eq "$(kcalls)" "0" "dry-run: sin -i/-u"
assert_contains "$out" "releases/latest/download/codexbar-plasma.plasmoid" "dry-run muestra la URL"
assert_contains "$out" "kpackagetool6" "dry-run muestra el comando kpackagetool6"

# --- no root ---
current_uid() { printf '0\n'; }
rc=0
out="$(install_codexbar_plasma 2>&1)" || rc=$?
assert_eq "$rc" "1" "root devuelve 1"
assert_contains "$out" "Instala CodexBar Plasma como tu usuario de escritorio, no como root." "mensaje de root"
current_uid() { printf '1000\n'; }

# --- CLI: --with-cli en Arch instala la CLI; sin ella solo se avisa ---
CLI_CALLS=0
install_codexbar_cli() { CLI_CALLS=$((CLI_CALLS + 1)); }
rm -f "$STATE"
install_codexbar_plasma --with-cli >/dev/null 2>&1
assert_eq "$CLI_CALLS" "1" "--with-cli instala la CLI en Arch"
rm -f "$STATE"
install_codexbar_plasma >/dev/null 2>&1
assert_eq "$CLI_CALLS" "1" "sin --with-cli no instala la CLI"
OS_RELEASE_FILE="$ROOT/tests/fixtures/os-release/debian"
rm -f "$STATE"
install_codexbar_plasma --with-cli >/dev/null 2>&1
assert_eq "$CLI_CALLS" "1" "--with-cli fuera de Arch no instala la CLI"
OS_RELEASE_FILE="$ROOT/tests/fixtures/os-release/cachyos"

# --- codexbar CLI ya presente ---
CODEXBAR_PRESENT=true
rm -f "$STATE"
out="$(install_codexbar_plasma --with-cli 2>&1)"
assert_eq "$CLI_CALLS" "1" "CLI presente: no se reinstala"
assert_contains "$out" "codexbar" "CLI presente: se informa"
CODEXBAR_PRESENT=false

# --- aviso por codexbar-tray habilitado ---
stub_cmd systemctl 0 enabled
rm -f "$STATE"
out="$(install_codexbar_plasma 2>&1)"
assert_contains "$out" "dos indicadores" "aviso de doble indicador con codexbar-tray"
stub_cmd systemctl 1

# --- desinstalación ---
echo app.codexbar.plasma >"$STATE"; : >"$STUB_LOG"
uninstall_codexbar_plasma >/dev/null 2>&1
assert_contains "$(cat "$STUB_LOG")" "-t Plasma/Applet -r app.codexbar.plasma" "desinstala el widget"
: >"$STUB_LOG"
rc=0
out="$(uninstall_codexbar_plasma 2>&1)" || rc=$?
assert_eq "$rc" "0" "desinstalar sin instalar devuelve 0"
assert_not_contains "$(cat "$STUB_LOG")" " -r " "sin -r si no está instalado"

# --- catálogo y registro de bloques ---
detect_facetimehd_camera() { printf 'no\n'; }
detect_gpu_profile() { printf 'amd-only\n'; }
MACBOOK_MODEL="GenericPC"
assert_contains "$(get_bootstrap_checklist_items)" "codexbar_plasma|CodexBar Plasma (widget panel KDE 6, release verificada)|OFF" "catálogo con kpackagetool6"
NO_KPT="$TMP/empty-path"
mkdir -p "$NO_KPT"
ln -s "$(command -v cat)" "$NO_KPT/cat"
catalog_without="$(PATH="$NO_KPT" get_bootstrap_checklist_items)"
assert_not_contains "$catalog_without" "codexbar_plasma" "catálogo sin kpackagetool6"

# --- postcheck informativo ---
mkdir -p "$HOME/.local/share/plasma/plasmoids/app.codexbar.plasma"
printf '{"KPlugin":{"Id":"app.codexbar.plasma","Version":"0.2.43"}}\n' >"$HOME/.local/share/plasma/plasmoids/app.codexbar.plasma/metadata.json"
echo app.codexbar.plasma >"$STATE"
assert_contains "$(codexbar_plasma_postcheck_line)" "CodexBar Plasma: instalado (0.2.43)" "postcheck instalado"
rm -f "$STATE"
assert_eq "$(codexbar_plasma_postcheck_line)" "CodexBar Plasma: no instalado" "postcheck no instalado"

printf 'OK codexbar plasma\n'
