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

REGEX='^[A-Za-z0-9._-]+_[0-9]{2}_[0-9]{2}_[0-9]{4}-[0-9]{2}[:h][0-9]{2}(_[0-9]+)?$'

# sudo no debe usarse nunca en el backup.
stub_setup
stub_cmd sudo 99

# --- fixture del HOME de origen ---
HOME1="$TMP/home1"
EXT="$TMP/ext"
mkdir -p "$HOME1/.config/Code/User" "$HOME1/.ssh" "$HOME1/Documents/GITHUB/proj/src" \
         "$HOME1/Documents/GITHUB/proj/node_modules" "$EXT/data1"
printf '{"a":1}\n' >"$HOME1/.config/Code/User/settings.json"
printf 'alias x=y\n' >"$HOME1/.bashrc"
printf 'KEY\n' >"$HOME1/.ssh/id_ed25519"
chmod 600 "$HOME1/.ssh/id_ed25519"
printf 'notas\n' >"$HOME1/Documents/notes.txt"
printf 'raro\n' >"$HOME1/Documents/"'a\b c.txt'
printf 'print(1)\n' >"$HOME1/Documents/GITHUB/proj/src/main.py"
printf 'x\n' >"$HOME1/Documents/GITHUB/proj/node_modules/x"
printf 'externo\n' >"$EXT/data1/f.txt"
git -C "$HOME1/Documents/GITHUB/proj" init -q

CONFIG_SEL=$'.config/Code\n.bashrc\n.ssh'
DATA_SEL="$HOME1/Documents"$'\n'"$EXT/data1"

DEST="$TMP/dest"
mkdir -p "$DEST"

env HOME="$HOME1" LOGFILE="$TMP/backup.log" \
    BACKUP_SELECTION_FROM_TUI=1 AUTO_CONFIRM_ENV=1 BACKUP_HOST_LABEL=testhost \
    SELECTED_CONFIG_ITEMS_RAW="$CONFIG_SEL" SELECTED_DATA_DIRS_RAW="$DATA_SEL" \
    bash "$ROOT/migration.sh" backup --target "$DEST" >"$TMP/backup.out" 2>&1 \
    || { cat "$TMP/backup.out" >&2; fail "el backup falló"; }

BACKUP_DIR="$(find "$DEST" -mindepth 1 -maxdepth 1 -type d)"
assert_eq "$(find "$DEST" -mindepth 1 -maxdepth 1 | wc -l)" "1" "una carpeta de backup"
[[ "$(basename "$BACKUP_DIR")" =~ $REGEX ]] || fail "nombre de backup inválido: $(basename "$BACKUP_DIR")"

# configs con ruta relativa conservada (B1)
assert_file "$BACKUP_DIR/configs/.config/Code/User/settings.json"
assert_no_file "$BACKUP_DIR/configs/Code"
assert_file "$BACKUP_DIR/configs/.bashrc"
assert_mode "$BACKUP_DIR/configs/.ssh/id_ed25519" 600

# datos: home y externos (B5)
assert_file "$BACKUP_DIR/data/home/Documents/notes.txt"
assert_file "$BACKUP_DIR/data/home/Documents/"'a\b c.txt'
assert_no_file "$BACKUP_DIR/data/home/Documents/GITHUB/proj"
assert_file "$BACKUP_DIR/data/external/${EXT#/}/data1/f.txt"

# repos sin node_modules
assert_file "$BACKUP_DIR/repos/Documents/GITHUB/proj/src/main.py"
assert_no_file "$BACKUP_DIR/repos/Documents/GITHUB/proj/node_modules"

# manifest v2
MANIFEST="$(cat "$BACKUP_DIR/metadata/manifest.env")"
assert_contains "$MANIFEST" "FORMAT_VERSION=2" "manifest: versión"
assert_contains "$MANIFEST" "HOST_LABEL=testhost" "manifest: host"
assert_contains "$MANIFEST" "BACKUP_NAME=$(basename "$BACKUP_DIR")" "manifest: nombre"
assert_contains "$MANIFEST" "DATA_ROOTS=home:Documents,external:$EXT/data1" "manifest: DATA_ROOTS"
assert_contains "$MANIFEST" "HOME=$HOME1" "manifest: HOME"
assert_contains "$MANIFEST" "OS_FAMILY=" "manifest: familia"
assert_contains "$MANIFEST" "TOOL_VERSION=" "manifest: versión de la herramienta"
assert_contains "$MANIFEST" "CREATED_AT=" "manifest: fecha"
assert_contains "$MANIFEST" "PKG_MANAGERS=" "manifest: gestores"
assert_contains "$MANIFEST" "INVENTORY_WARNINGS=" "manifest: avisos"
assert_file "$BACKUP_DIR/metadata/user_ids.conf"
assert_file "$BACKUP_DIR/metadata/packages"
assert_no_file "$BACKUP_DIR/metadata/pacman_explicit.txt"
assert_no_file "$BACKUP_DIR/metadata/dpkg_packages.txt"
assert_no_file "$BACKUP_DIR/metadata/flatpak_packages.txt"

# selección con rutas originales (formato sin cambios)
SELECTION="$(cat "$BACKUP_DIR/logs/backup_selection.txt")"
assert_contains "$SELECTION" "CONFIG_ITEMS:" "selección: configs"
assert_contains "$SELECTION" ".config/Code" "selección: item anidado"
assert_contains "$SELECTION" "DATA_DIRS:" "selección: datos"
assert_contains "$SELECTION" "$HOME1/Documents" "selección: ruta absoluta"

# sin sudo
assert_eq "$(cat "$STUB_LOG")" "" "el backup no llama a sudo"

# --- enlace roto dentro de un item anidado, destino exFAT simulado ---
HOME3="$TMP/home3"
mkdir -p "$HOME3/.config/Code/User" "$HOME3/Documents"
printf '{}\n' >"$HOME3/.config/Code/User/settings.json"
ln -s /ruta/que/no/existe "$HOME3/.config/Code/roto"
ln -s /ruta/que/no/existe "$HOME3/.config/Code/User/roto2"
ln -s /ruta/que/no/existe "$HOME3/.config/Code/mismo"
printf 'valido\n' >"$HOME3/.config/Code/User/mismo"
printf 'n\n' >"$HOME3/Documents/n.txt"
DEST3="$TMP/dest3"
mkdir -p "$DEST3"

(
    export HOME="$HOME3" LOGFILE="$TMP/exfat.log" BACKUP_HOST_LABEL=exfathost
    # shellcheck disable=SC1091
    source "$ROOT/src/lib/common.sh"
    # shellcheck disable=SC1091
    source "$ROOT/src/lib/os.sh"
    # shellcheck disable=SC1091
    source "$ROOT/src/lib/inventory.sh"
    # shellcheck disable=SC1091
    source "$ROOT/src/modules/backup.sh"
    get_filesystem_type() { printf 'exfat\n'; }
    BACKUP_TARGET="$DEST3"
    BACKUP_SELECTION_FROM_TUI=1
    SELECTED_CONFIG_ITEMS_RAW=".config/Code"
    SELECTED_DATA_DIRS_RAW="$HOME3/Documents"
    backup_system
) >"$TMP/exfat.out" 2>&1 || { cat "$TMP/exfat.out" >&2; fail "el backup en exFAT simulado falló"; }

BACKUP3="$(find "$DEST3" -mindepth 1 -maxdepth 1 -type d)"
assert_contains "$(basename "$BACKUP3")" "h" "fallback h en exFAT"
assert_file "$BACKUP3/configs/.config/Code/User/settings.json"
assert_no_file "$BACKUP3/configs/.config/Code/roto"
assert_no_file "$BACKUP3/configs/.config/Code/User/roto2"
assert_no_file "$BACKUP3/configs/.config/Code/mismo"
# la exclusión está anclada: un fichero válido con el mismo nombre en otro sitio se copia
assert_file "$BACKUP3/configs/.config/Code/User/mismo"
assert_no_file "$BACKUP3/logs/rsync_warnings.txt"
assert_not_contains "$(cat "$TMP/exfat.out")" "CON AVISOS" "sin avisos de rsync por el enlace roto"

# --- dry-run: no escribe nada en el destino ---
DEST4="$TMP/dest4"
mkdir -p "$DEST4"
env HOME="$HOME1" LOGFILE="$TMP/dry.log" BACKUP_SELECTION_FROM_TUI=1 AUTO_CONFIRM_ENV=1 \
    BACKUP_HOST_LABEL=testhost SELECTED_CONFIG_ITEMS_RAW="$CONFIG_SEL" \
    SELECTED_DATA_DIRS_RAW="$DATA_SEL" \
    bash "$ROOT/migration.sh" backup --dry-run --target "$DEST4" >/dev/null 2>&1
assert_eq "$(find "$DEST4" -mindepth 1 | wc -l)" "0" "dry-run no escribe en el destino"

# =====================================================================
# Restore v2 sobre un HOME vacío
# =====================================================================
restore_into() {
    local home="$1"
    shift
    mkdir -p "$home"
    env HOME="$home" LOGFILE="$TMP/restore.log" AUTO_CONFIRM_ENV=1 \
        bash "$ROOT/migration.sh" restore --source "$BACKUP_DIR" --force "$@" 2>&1
}

: >"$STUB_LOG"
HOME2="$TMP/home2"
rm -rf "$EXT"   # el padre original ya no existe: el destino por defecto debe usarse
out="$(restore_into "$HOME2")" || { printf '%s\n' "$out" >&2; fail "el restore v2 falló"; }

assert_file "$HOME2/.config/Code/User/settings.json"
assert_no_file "$HOME2/Code"
assert_file "$HOME2/.bashrc"
assert_file "$HOME2/Documents/notes.txt"
assert_file "$HOME2/Documents/"'a\b c.txt'
assert_file "$HOME2/Documents/GITHUB/proj/src/main.py"
assert_no_file "$HOME2/Documents/GITHUB/proj/node_modules"
assert_file "$HOME2/restored-external/${EXT#/}/data1/f.txt"
assert_mode "$HOME2/.ssh/id_ed25519" 600
assert_eq "$(cat "$HOME2/Documents/"'a\b c.txt')" "raro" "contenido del fichero con barra invertida"
assert_eq "$(cat "$STUB_LOG")" "" "el restore no llama a sudo"

# --external-to-original con el directorio padre inexistente: aviso y destino por defecto
HOME2B="$TMP/home2b"
out="$(restore_into "$HOME2B" --external-to-original)" || { printf '%s\n' "$out" >&2; fail "restore --external-to-original falló"; }
assert_file "$HOME2B/restored-external/${EXT#/}/data1/f.txt"
assert_no_file "$EXT/data1/f.txt"
assert_contains "$out" "restored-external" "aviso de destino por defecto"

# --external-to-original con el padre existente: ruta original
mkdir -p "$EXT"
HOME2C="$TMP/home2c"
restore_into "$HOME2C" --external-to-original >/dev/null
assert_file "$EXT/data1/f.txt"
assert_no_file "$HOME2C/restored-external"

# formato no soportado: error y HOME intacto
FUTURE="$TMP/backup-futuro"
cp -r "$BACKUP_DIR" "$FUTURE"
sed -i 's/^FORMAT_VERSION=2$/FORMAT_VERSION=3/' "$FUTURE/metadata/manifest.env"
HOME5="$TMP/home5"
mkdir -p "$HOME5"
rc=0
out="$(env HOME="$HOME5" LOGFILE="$TMP/future.log" AUTO_CONFIRM_ENV=1 \
    bash "$ROOT/migration.sh" restore --source "$FUTURE" --force 2>&1)" || rc=$?
assert_eq "$([ "$rc" -ne 0 ] && echo fail || echo ok)" "fail" "FORMAT_VERSION=3 debe fallar"
assert_contains "$out" "Formato de backup no soportado: 3" "mensaje de formato no soportado"
assert_eq "$(find "$HOME5" -mindepth 1 | wc -l)" "0" "HOME intacto con formato no soportado"

# propietario ajeno: aviso con el comando exacto, sin sudo
# (no se puede crear un fichero de otro usuario sin root; se prueba con la función)
(
    export HOME="$TMP/home-own" LOGFILE="$TMP/own.log"
    mkdir -p "$HOME/.ssh"
    # shellcheck disable=SC1091
    source "$ROOT/src/lib/common.sh"
    # shellcheck disable=SC1091
    source "$ROOT/src/modules/restore.sh"
    find() { printf '%s\n' "$1"; }
    FIX_OWNERSHIP=false
    check_restored_ownership >"$TMP/own.out"
    grep -q 'sudo chown -R' "$TMP/own.out" || { echo "falta el comando sudo chown en el aviso" >&2; exit 1; }
) || fail "aviso de ownership"
assert_eq "$(cat "$STUB_LOG")" "" "el aviso de ownership no llama a sudo"

printf 'OK backup roundtrip\n'
