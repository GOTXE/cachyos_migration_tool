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
export XDG_CONFIG_HOME="$TMP/config"
export XDG_STATE_HOME="$TMP/state"
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
export LOGFILE="$TMP/test.log"
unset BACKUP_HOST_LABEL

# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/src/lib/os.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/bootstrap.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/restic_backup.sh"

# Copias de las funciones reales para restaurarlas tras cada simulación.
ORIG_RUN_CMD="$(declare -f run_cmd)"
ORIG_RUN_SHELL="$(declare -f run_shell)"
restore_real_runners() {
    eval "$ORIG_RUN_CMD"
    eval "$ORIG_RUN_SHELL"
}

# =====================================================================
# install_restic_package por familia de distribución
# =====================================================================
CALLS=()
run_cmd() { CALLS+=("$*"); }
log_package_batch_state() { :; }

check_install() {
    local fixture="$1" expected="$2"
    CALLS=()
    OS_RELEASE_FILE="$ROOT/tests/fixtures/os-release/$fixture"
    install_restic_package >/dev/null
    assert_eq "${CALLS[*]}" "$expected" "install_restic_package en $fixture"
}
check_install cachyos "sudo pacman -S --needed --noconfirm restic"
check_install debian "sudo apt-get install -y restic"
check_install fedora "sudo dnf install -y restic"
check_install opensuse-tumbleweed "sudo zypper --non-interactive install restic"

CALLS=()
OS_RELEASE_FILE="$ROOT/tests/fixtures/os-release/unknown"
rc=0
out="$(install_restic_package 2>&1)" || rc=$?
assert_eq "$rc" "1" "familia desconocida devuelve 1"
assert_contains "$out" "[ERROR]" "mensaje de error con instrucciones"
assert_eq "${#CALLS[@]}" "0" "familia desconocida no instala nada"
restore_real_runners

# =====================================================================
# Unidades systemd y excludes
# =====================================================================
for unit in restic-maintenance.service restic-maintenance.timer; do
    assert_file "$ROOT/assets/systemd/user/$unit"
done
TIMER="$(cat "$ROOT/assets/systemd/user/restic-maintenance.timer")"
assert_contains "$TIMER" "OnCalendar=Sun *-*-* 12:00:00" "timer de mantenimiento semanal"
assert_contains "$TIMER" "Persistent=true" "timer persistente"
assert_contains "$TIMER" "RandomizedDelaySec=30min" "retardo aleatorio"
assert_contains "$(cat "$ROOT/assets/systemd/user/restic-maintenance.service")" "restic-backup maintenance" "el servicio ejecuta maintenance"

EXCLUDES="$(cat "$ROOT/assets/templates/restic-excludes.txt")"
assert_contains "$EXCLUDES" "/home/*/Downloads" "excluye Downloads"
for pattern in '**/build' '**/dist' '**/target'; do
    if printf '%s\n' "$EXCLUDES" | grep -Fxq -- "$pattern"; then
        fail "$pattern no debería excluirse (pueden ser datos de usuario)"
    fi
done
assert_contains "$EXCLUDES" "**/node_modules" "node_modules sigue excluido"

# install-timer / disable-timer gestionan ambos timers (se registra y se ejecuta con stubs)
stub_setup
stub_cmd systemctl
CALLS=()
run_cmd() { CALLS+=("$*"); "$@"; }
run_shell() { CALLS+=("$*"); }
restic_backup_install_timer >/dev/null 2>&1
joined="${CALLS[*]}"
assert_contains "$joined" "enable --now restic-backup.timer" "install-timer: timer principal"
assert_contains "$joined" "enable --now restic-maintenance.timer" "install-timer: timer de mantenimiento"
assert_file "$XDG_CONFIG_HOME/systemd/user/restic-maintenance.timer"
assert_file "$XDG_CONFIG_HOME/systemd/user/restic-maintenance.service"
CALLS=()
restic_backup_disable_timer >/dev/null 2>&1
joined="${CALLS[*]}"
assert_contains "$joined" "restic-backup.timer" "disable-timer: timer principal"
assert_contains "$joined" "restic-maintenance.timer" "disable-timer: timer de mantenimiento"
restore_real_runners
stub_teardown

# =====================================================================
# Runner generado
# =====================================================================
DRY_MODE=false
restic_backup_install_runtime_script >/dev/null
RUNNER="$HOME/.local/bin/restic-backup"
assert_file "$RUNNER"
assert_file "$HOME/.local/lib/cachyos-migration-tool/inventory.sh"
bash -n "$RUNNER" || fail "el runner generado tiene errores de sintaxis"

CONFIG_ROOT="$XDG_CONFIG_HOME/cachyos-migration-tool"
mkdir -p "$CONFIG_ROOT"
printf 'pw\n' >"$CONFIG_ROOT/restic-password"
printf '/home/*/.cache\n' >"$CONFIG_ROOT/restic-excludes.txt"
cat >"$CONFIG_ROOT/backup.env" <<ENV
BACKUP_SFTP_HOST_LAN="lan-host"
BACKUP_SFTP_HOST_REMOTE="remote-host"
RESTIC_REPOSITORY_LAN="sftp:lan-host:/repo"
RESTIC_REPOSITORY_REMOTE="sftp:remote-host:/repo"
RESTIC_PASSWORD_FILE="$CONFIG_ROOT/restic-password"
BACKUP_SOURCE_HOME="$HOME"
BACKUP_EXCLUDES_FILE="$CONFIG_ROOT/restic-excludes.txt"
BACKUP_ENFORCE_SCHEDULE="0"
BACKUP_HOST_LABEL="Mi PC/01"
ENV

stub_setup
stub_cmd restic
stub_cmd sftp
stub_cmd ssh
stub_cmd systemctl
stub_cmd uname 0 "Linux testhost"
printf '#!/bin/bash\nprintf "base\\n"\n' >"$STUB_DIR/pacman"
chmod +x "$STUB_DIR/pacman"

run_runner() {
    : >"$STUB_LOG"
    bash "$RUNNER" "$@" 2>&1
}

# run: backup con --host y forget SIN --prune
out="$(run_runner run)" || { printf '%s\n' "$out" >&2; fail "el runner run falló"; }
BACKUP_CALL="$(grep -F ' backup ' "$STUB_LOG" | head -n 1)"
FORGET_CALL="$(grep -F ' forget ' "$STUB_LOG" | head -n 1)"
assert_contains "$BACKUP_CALL" "--host Mi-PC-01" "backup con --host saneado"
assert_contains "$BACKUP_CALL" "--one-file-system" "backup con --one-file-system"
assert_contains "$BACKUP_CALL" "--exclude-caches" "backup con --exclude-caches"
assert_contains "$BACKUP_CALL" "--tag workstation" "backup con tag workstation"
assert_contains "$BACKUP_CALL" "--tag automatic" "backup con tag automatic"
assert_contains "$FORGET_CALL" "--host Mi-PC-01" "forget limitado al host"
assert_not_contains "$FORGET_CALL" "--prune" "forget sin --prune"
assert_file "$CONFIG_ROOT/system-state/packages/pacman-native-explicit.txt"
assert_file "$CONFIG_ROOT/system-state/uname.txt"

# maintenance: forget --prune + check parcial, ambos con --retry-lock
out="$(run_runner maintenance)" || { printf '%s\n' "$out" >&2; fail "el runner maintenance falló"; }
FORGET_CALL="$(grep -F ' forget ' "$STUB_LOG" | head -n 1)"
CHECK_CALL="$(grep -F ' check ' "$STUB_LOG" | head -n 1)"
assert_contains "$FORGET_CALL" "--host Mi-PC-01" "maintenance: forget por host"
assert_contains "$FORGET_CALL" "--prune" "maintenance: forget con --prune"
assert_contains "$FORGET_CALL" "--retry-lock 30m" "maintenance: forget con --retry-lock"
assert_contains "$CHECK_CALL" "--read-data-subset=5%" "maintenance: check parcial"
assert_contains "$CHECK_CALL" "--retry-lock 30m" "maintenance: check con --retry-lock"
assert_not_contains "$(cat "$STUB_LOG")" " backup " "maintenance no hace backup"

# rotación de logs
STATE_ROOT="$XDG_STATE_HOME/restic-backup"
printf 'viejo\n' >"$STATE_ROOT/viejo.log"
printf 'nuevo\n' >"$STATE_ROOT/nuevo.log"
touch -d '20 days ago' "$STATE_ROOT/viejo.log"
touch -d '1 day ago' "$STATE_ROOT/nuevo.log"
run_runner status >/dev/null || true
assert_no_file "$STATE_ROOT/viejo.log"
assert_file "$STATE_ROOT/nuevo.log"
assert_file "$STATE_ROOT/latest.log"

# aviso de la contraseña en status
out="$(run_runner status || true)"
assert_contains "$out" "AVISO: guarda una copia de la contraseña de Restic fuera de este equipo (gestor de contraseñas). Ruta local: $CONFIG_ROOT/restic-password" "aviso de contraseña en status"

# retención configurable
echo 'BACKUP_LOG_RETENTION_DAYS="30"' >>"$CONFIG_ROOT/backup.env"
printf 'x\n' >"$STATE_ROOT/veinte.log"
touch -d '20 days ago' "$STATE_ROOT/veinte.log"
run_runner status >/dev/null || true
assert_file "$STATE_ROOT/veinte.log"

printf 'OK restic runner\n'
