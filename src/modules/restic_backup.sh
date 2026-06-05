#!/usr/bin/env bash

RESTIC_BACKUP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cachyos-migration-tool"
RESTIC_BACKUP_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/restic-backup"
RESTIC_BACKUP_SYSTEM_STATE_DIR="${RESTIC_BACKUP_CONFIG_DIR}/system-state"
RESTIC_BACKUP_SCRIPT_PATH="$HOME/.local/bin/restic-backup"
RESTIC_BACKUP_ENV_PATH="${RESTIC_BACKUP_CONFIG_DIR}/backup.env"
RESTIC_BACKUP_PASSWORD_PATH="${RESTIC_BACKUP_CONFIG_DIR}/restic-password"
RESTIC_BACKUP_EXCLUDES_PATH="${RESTIC_BACKUP_CONFIG_DIR}/restic-excludes.txt"
RESTIC_BACKUP_USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
RESTIC_BACKUP_SERVICE_PATH="${RESTIC_BACKUP_USER_SYSTEMD_DIR}/restic-backup.service"
RESTIC_BACKUP_TIMER_PATH="${RESTIC_BACKUP_USER_SYSTEMD_DIR}/restic-backup.timer"
RESTIC_BACKUP_TEMPLATE_ENV="${PROJECT_ROOT}/assets/templates/backup-restic.env.example"
RESTIC_BACKUP_TEMPLATE_EXCLUDES="${PROJECT_ROOT}/assets/templates/restic-excludes.txt"
RESTIC_BACKUP_TEMPLATE_SERVICE="${PROJECT_ROOT}/assets/systemd/user/restic-backup.service"
RESTIC_BACKUP_TEMPLATE_TIMER="${PROJECT_ROOT}/assets/systemd/user/restic-backup.timer"

restic_backup_expand_path() {
    local RAW_PATH="${1:-}"

    RAW_PATH="${RAW_PATH/#\~/$HOME}"
    RAW_PATH="${RAW_PATH//\$\{HOME\}/$HOME}"
    RAW_PATH="${RAW_PATH//\$HOME/$HOME}"

    printf '%s\n' "$RAW_PATH"
}

restic_backup_env_uses_placeholders() {
    [ "${BACKUP_SFTP_HOST_LAN:-}" = "backup-sftp-lan" ] && return 0
    [ "${BACKUP_SFTP_HOST_REMOTE:-}" = "backup-sftp-remote" ] && return 0
    [ "${BACKUP_SFTP_REPOSITORY_PATH:-}" = "/remote/path/restic" ] && return 0
    return 1
}

restic_backup_load_local_env() {
    [ -r "$RESTIC_BACKUP_ENV_PATH" ] || {
        log "${RED}Falta ${RESTIC_BACKUP_ENV_PATH}. Ejecuta primero: ./migration.sh restic-backup init${NC}"
        return 1
    }

    set -a
    # shellcheck disable=SC1090
    . "$RESTIC_BACKUP_ENV_PATH"
    set +a

    RESTIC_PASSWORD_FILE="$(restic_backup_expand_path "${RESTIC_PASSWORD_FILE:-}")"
    BACKUP_EXCLUDES_FILE="$(restic_backup_expand_path "${BACKUP_EXCLUDES_FILE:-}")"
    BACKUP_SOURCE_HOME="$(restic_backup_expand_path "${BACKUP_SOURCE_HOME:-$HOME}")"
}

restic_backup_probe_host() {
    local TARGET_HOST="$1"
    local CONNECT_TIMEOUT="${BACKUP_CONNECT_TIMEOUT:-8}"

    [ -n "$TARGET_HOST" ] || return 1

    printf 'pwd\nbye\n' | sftp \
        -o BatchMode=yes \
        -o ConnectTimeout="$CONNECT_TIMEOUT" \
        "$TARGET_HOST" >/dev/null 2>&1
}

restic_backup_select_repository() {
    if restic_backup_probe_host "${BACKUP_SFTP_HOST_LAN:-}"; then
        printf '%s\n' "${RESTIC_REPOSITORY_LAN:-}"
        return 0
    fi

    if restic_backup_probe_host "${BACKUP_SFTP_HOST_REMOTE:-}"; then
        printf '%s\n' "${RESTIC_REPOSITORY_REMOTE:-}"
        return 0
    fi

    return 1
}

restic_backup_ensure_template_files() {
    local SOURCE_PATH="$1"
    local TARGET_PATH="$2"
    local MODE="$3"

    if [ ! -e "$TARGET_PATH" ]; then
        run_cmd install -Dm"$MODE" "$SOURCE_PATH" "$TARGET_PATH"
    else
        run_cmd chmod "$MODE" "$TARGET_PATH"
    fi
}

restic_backup_generate_password() {
    local PASSWORD_VALUE=""

    if command -v openssl >/dev/null 2>&1; then
        PASSWORD_VALUE="$(openssl rand -base64 32)"
    else
        PASSWORD_VALUE="$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 | tr -d '\n')"
    fi

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir ${RESTIC_BACKUP_PASSWORD_PATH}${NC}"
        return 0
    fi

    printf '%s\n' "$PASSWORD_VALUE" > "$RESTIC_BACKUP_PASSWORD_PATH"
    chmod 600 "$RESTIC_BACKUP_PASSWORD_PATH"
}

restic_backup_install_runtime_script() {
    local SCRIPT_DIR=""

    SCRIPT_DIR="$(dirname "$RESTIC_BACKUP_SCRIPT_PATH")"
    run_cmd mkdir -p "$SCRIPT_DIR" "$RESTIC_BACKUP_CONFIG_DIR" "$RESTIC_BACKUP_STATE_DIR" "$RESTIC_BACKUP_SYSTEM_STATE_DIR"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] generar ${RESTIC_BACKUP_SCRIPT_PATH}${NC}"
        return 0
    fi

    cat > "$RESTIC_BACKUP_SCRIPT_PATH" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/cachyos-migration-tool"
ENV_FILE="${RESTIC_BACKUP_ENV_FILE:-$CONFIG_ROOT/backup.env}"
SYSTEM_STATE_DIR="${CONFIG_ROOT}/system-state"
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/restic-backup"
RUN_STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="${STATE_ROOT}/${RUN_STAMP}.log"
LATEST_LOG="${STATE_ROOT}/latest.log"
COMMAND="${1:-run}"

mkdir -p "$STATE_ROOT" "$SYSTEM_STATE_DIR"
ln -sfn "$(basename "$LOG_FILE")" "$LATEST_LOG" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

expand_path() {
    local RAW_PATH="${1:-}"

    RAW_PATH="${RAW_PATH/#\~/$HOME}"
    RAW_PATH="${RAW_PATH//\$\{HOME\}/$HOME}"
    RAW_PATH="${RAW_PATH//\$HOME/$HOME}"

    printf '%s\n' "$RAW_PATH"
}

load_env() {
    [ -r "$ENV_FILE" ] || die "No se puede leer $ENV_FILE"

    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a

    RESTIC_PASSWORD_FILE="$(expand_path "${RESTIC_PASSWORD_FILE:-}")"
    BACKUP_EXCLUDES_FILE="$(expand_path "${BACKUP_EXCLUDES_FILE:-}")"
    BACKUP_SOURCE_HOME="$(expand_path "${BACKUP_SOURCE_HOME:-$HOME}")"
}

require_value() {
    local NAME="$1"
    local VALUE="${2:-}"

    [ -n "$VALUE" ] || die "Falta variable obligatoria: $NAME"
}

validate_requirements() {
    require_value "BACKUP_SFTP_HOST_LAN" "${BACKUP_SFTP_HOST_LAN:-}"
    require_value "BACKUP_SFTP_HOST_REMOTE" "${BACKUP_SFTP_HOST_REMOTE:-}"
    require_value "RESTIC_REPOSITORY_LAN" "${RESTIC_REPOSITORY_LAN:-}"
    require_value "RESTIC_REPOSITORY_REMOTE" "${RESTIC_REPOSITORY_REMOTE:-}"
    require_value "RESTIC_PASSWORD_FILE" "${RESTIC_PASSWORD_FILE:-}"
    require_value "BACKUP_EXCLUDES_FILE" "${BACKUP_EXCLUDES_FILE:-}"
    require_value "BACKUP_SOURCE_HOME" "${BACKUP_SOURCE_HOME:-}"

    command -v restic >/dev/null 2>&1 || die "restic no está instalado"
    command -v sftp >/dev/null 2>&1 || die "sftp no está disponible"
    command -v ssh >/dev/null 2>&1 || die "ssh no está disponible"

    [ -r "$RESTIC_PASSWORD_FILE" ] || die "No se puede leer RESTIC_PASSWORD_FILE: $RESTIC_PASSWORD_FILE"
    [ -r "$BACKUP_EXCLUDES_FILE" ] || die "No se puede leer BACKUP_EXCLUDES_FILE: $BACKUP_EXCLUDES_FILE"
    [ -d "$BACKUP_SOURCE_HOME" ] || die "No existe BACKUP_SOURCE_HOME: $BACKUP_SOURCE_HOME"
}

write_manifest() {
    local TARGET_FILE="$1"
    shift

    if "$@" > "$TARGET_FILE" 2>/dev/null; then
        return 0
    fi

    log "WARN: no se pudo generar $(basename "$TARGET_FILE")"
    return 0
}

update_system_state() {
    log "Actualizando manifiestos en $SYSTEM_STATE_DIR"
    mkdir -p "$SYSTEM_STATE_DIR"

    write_manifest "$SYSTEM_STATE_DIR/pacman-explicit.txt" pacman -Qqe
    write_manifest "$SYSTEM_STATE_DIR/aur-foreign.txt" pacman -Qqm
    write_manifest "$SYSTEM_STATE_DIR/system-enabled-units.txt" systemctl list-unit-files --state=enabled --no-pager
    write_manifest "$SYSTEM_STATE_DIR/user-enabled-units.txt" systemctl --user list-unit-files --state=enabled --no-pager
    write_manifest "$SYSTEM_STATE_DIR/mounts.txt" findmnt --real
    write_manifest "$SYSTEM_STATE_DIR/lsblk.txt" lsblk -f
    write_manifest "$SYSTEM_STATE_DIR/uname.txt" uname -a
}

probe_host() {
    local TARGET_HOST="$1"
    local CONNECT_TIMEOUT="${BACKUP_CONNECT_TIMEOUT:-8}"

    [ -n "$TARGET_HOST" ] || return 1

    printf 'pwd\nbye\n' | sftp \
        -o BatchMode=yes \
        -o ConnectTimeout="$CONNECT_TIMEOUT" \
        "$TARGET_HOST" >/dev/null 2>&1
}

choose_repository() {
    if probe_host "${BACKUP_SFTP_HOST_LAN:-}"; then
        printf '%s\n' "${RESTIC_REPOSITORY_LAN:-}"
        return 0
    fi

    if probe_host "${BACKUP_SFTP_HOST_REMOTE:-}"; then
        printf '%s\n' "${RESTIC_REPOSITORY_REMOTE:-}"
        return 0
    fi

    return 1
}

show_status() {
    local REPOSITORY=""

    log "ENV_FILE=$ENV_FILE"
    log "BACKUP_SOURCE_HOME=$BACKUP_SOURCE_HOME"
    log "BACKUP_EXCLUDES_FILE=$BACKUP_EXCLUDES_FILE"
    log "RESTIC_PASSWORD_FILE=$RESTIC_PASSWORD_FILE"
    log "LAN host=${BACKUP_SFTP_HOST_LAN:-missing}"
    log "REMOTE host=${BACKUP_SFTP_HOST_REMOTE:-missing}"

    if probe_host "${BACKUP_SFTP_HOST_LAN:-}"; then
        log "LAN probe: ok"
    else
        log "LAN probe: fail"
    fi

    if probe_host "${BACKUP_SFTP_HOST_REMOTE:-}"; then
        log "REMOTE probe: ok"
    else
        log "REMOTE probe: fail"
    fi

    if REPOSITORY="$(choose_repository)"; then
        log "Repositorio seleccionado: $REPOSITORY"
    else
        log "Repositorio seleccionado: ninguno"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user status restic-backup.service restic-backup.timer --no-pager 2>/dev/null || true
    fi
}

run_backup() {
    local REPOSITORY=""

    update_system_state

    REPOSITORY="$(choose_repository)" || die "No responde ni el destino LAN ni el remoto"
    export RESTIC_PASSWORD_FILE

    log "Usando repositorio: $REPOSITORY"
    restic -r "$REPOSITORY" backup "$BACKUP_SOURCE_HOME" \
        --exclude-file "$BACKUP_EXCLUDES_FILE" \
        --tag workstation \
        --tag automatic

    restic -r "$REPOSITORY" forget \
        --keep-hourly "${RESTIC_KEEP_HOURLY:-24}" \
        --keep-daily "${RESTIC_KEEP_DAILY:-7}" \
        --keep-weekly "${RESTIC_KEEP_WEEKLY:-4}" \
        --keep-monthly "${RESTIC_KEEP_MONTHLY:-3}" \
        --prune
}

show_snapshots() {
    local REPOSITORY=""

    REPOSITORY="$(choose_repository)" || die "No responde ni el destino LAN ni el remoto"
    export RESTIC_PASSWORD_FILE
    log "Usando repositorio: $REPOSITORY"
    restic -r "$REPOSITORY" snapshots
}

load_env
validate_requirements

case "$COMMAND" in
    run)
        run_backup
        ;;
    status)
        show_status
        ;;
    snapshots)
        show_snapshots
        ;;
    *)
        die "Subcomando no soportado: $COMMAND"
        ;;
esac
EOF

    chmod +x "$RESTIC_BACKUP_SCRIPT_PATH"
}

restic_backup_install_user_units() {
    run_cmd mkdir -p "$RESTIC_BACKUP_USER_SYSTEMD_DIR"
    run_cmd install -Dm644 "$RESTIC_BACKUP_TEMPLATE_SERVICE" "$RESTIC_BACKUP_SERVICE_PATH"
    run_cmd install -Dm644 "$RESTIC_BACKUP_TEMPLATE_TIMER" "$RESTIC_BACKUP_TIMER_PATH"
}

restic_backup_validate_init_requirements() {
    if ! command -v restic >/dev/null 2>&1; then
        log_warn "restic no está instalado. Intentando instalarlo."
        install_restic_package
    fi

    command -v restic >/dev/null 2>&1 || {
        log "${RED}restic sigue sin estar disponible. Instálalo y repite init.${NC}"
        return 1
    }

    require_command sftp
    require_command ssh
}

restic_backup_prepare_scaffold() {
    run_cmd mkdir -p "$RESTIC_BACKUP_CONFIG_DIR" "$RESTIC_BACKUP_STATE_DIR" "$RESTIC_BACKUP_SYSTEM_STATE_DIR"
    restic_backup_ensure_template_files "$RESTIC_BACKUP_TEMPLATE_ENV" "$RESTIC_BACKUP_ENV_PATH" 600
    restic_backup_ensure_template_files "$RESTIC_BACKUP_TEMPLATE_EXCLUDES" "$RESTIC_BACKUP_EXCLUDES_PATH" 600

    if [ ! -e "$RESTIC_BACKUP_PASSWORD_PATH" ]; then
        restic_backup_generate_password
    else
        run_cmd chmod 600 "$RESTIC_BACKUP_PASSWORD_PATH"
    fi

    restic_backup_install_runtime_script
    restic_backup_install_user_units
}

restic_backup_repository_probe_message() {
    if restic_backup_probe_host "${BACKUP_SFTP_HOST_LAN:-}"; then
        printf 'LAN\n'
        return 0
    fi

    if restic_backup_probe_host "${BACKUP_SFTP_HOST_REMOTE:-}"; then
        printf 'REMOTE\n'
        return 0
    fi

    return 1
}

restic_backup_repository_exists() {
    local REPOSITORY="$1"
    local OUTPUT=""
    local RC=0

    OUTPUT="$(
        RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" restic -r "$REPOSITORY" snapshots --last 1 2>&1
    )" || RC=$?

    if [ "$RC" -eq 0 ]; then
        return 0
    fi

    case "$OUTPUT" in
        *"Is there a repository at the following location?"*|*"unable to open config file"*|*"config file does not exist"*)
            return 1
            ;;
        *)
            log "${RED}${OUTPUT}${NC}"
            return 2
            ;;
    esac
}

restic_backup_run_smoke_test() {
    local REPOSITORY="$1"
    local TMP_SOURCE=""
    local TMP_RESTORE=""
    local SNAPSHOT_ID=""

    TMP_SOURCE="$(mktemp -d)"
    TMP_RESTORE="$(mktemp -d)"
    printf 'restic smoke test %s\n' "$(date '+%F %T')" > "${TMP_SOURCE}/smoke.txt"

    log_phase "Ejecutando smoke test Restic opcional"
    RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" restic -r "$REPOSITORY" backup "$TMP_SOURCE" --tag smoke-test

    SNAPSHOT_ID="$(
        RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" restic -r "$REPOSITORY" snapshots --tag smoke-test --json |
            python3 -c 'import json,sys; data=json.load(sys.stdin); print(data[-1]["short_id"] if data else "")'
    )"

    [ -n "$SNAPSHOT_ID" ] || {
        rm -rf "$TMP_SOURCE" "$TMP_RESTORE"
        log "${RED}Smoke test: no se pudo localizar snapshot recién creado.${NC}"
        return 1
    }

    RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" restic -r "$REPOSITORY" restore "$SNAPSHOT_ID" --target "$TMP_RESTORE"

    if cmp -s "${TMP_SOURCE}/smoke.txt" "${TMP_RESTORE}${TMP_SOURCE}/smoke.txt"; then
        log_success "Smoke test backup/restore correcto."
    else
        rm -rf "$TMP_SOURCE" "$TMP_RESTORE"
        log "${RED}Smoke test backup/restore falló al comparar el archivo restaurado.${NC}"
        return 1
    fi

    rm -rf "$TMP_SOURCE" "$TMP_RESTORE"
}

restic_backup_init() {
    local SELECTED_REPOSITORY=""
    local REPOSITORY_KIND=""
    local RUN_SMOKE_TEST=false
    local REPOSITORY_STATUS=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --smoke-test)
                RUN_SMOKE_TEST=true
                shift
                ;;
            *)
                log "${RED}Opción no reconocida para restic-backup init: $1${NC}"
                return 1
                ;;
        esac
    done

    restic_backup_validate_init_requirements
    restic_backup_prepare_scaffold
    restic_backup_load_local_env

    run_cmd chmod 600 "$RESTIC_BACKUP_ENV_PATH" "$RESTIC_BACKUP_PASSWORD_PATH" "$RESTIC_BACKUP_EXCLUDES_PATH"

    if restic_backup_env_uses_placeholders; then
        log_warn "Se ha preparado la estructura local, pero backup.env sigue con placeholders."
        log_info "Edita ${RESTIC_BACKUP_ENV_PATH} y vuelve a ejecutar: ./migration.sh restic-backup init"
        return 0
    fi

    REPOSITORY_KIND="$(restic_backup_repository_probe_message)" || {
        log "${RED}No responde ni el destino LAN ni el remoto. Revisa SSH/SFTP y vuelve a probar.${NC}"
        return 1
    }

    SELECTED_REPOSITORY="$(restic_backup_select_repository)"
    log_success "Destino ${REPOSITORY_KIND} accesible."

    if restic_backup_repository_exists "$SELECTED_REPOSITORY"; then
        log_info "El repositorio Restic ya existe: $SELECTED_REPOSITORY"
    else
        REPOSITORY_STATUS=$?
        case "$REPOSITORY_STATUS" in
            1)
                log_phase "Inicializando repositorio Restic en $SELECTED_REPOSITORY"
                RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" run_cmd restic -r "$SELECTED_REPOSITORY" init
                ;;
            2)
                return 1
                ;;
        esac
    fi

    if [ "$RUN_SMOKE_TEST" = true ] || confirm_action "¿Ejecutar smoke test opcional de backup/restore Restic?" "no"; then
        restic_backup_run_smoke_test "$SELECTED_REPOSITORY"
    fi

    log_success "Inicialización Restic completada."
}

restic_backup_delegate_installed_script() {
    local SUBCOMMAND="$1"

    [ -x "$RESTIC_BACKUP_SCRIPT_PATH" ] || {
        log "${RED}Falta ${RESTIC_BACKUP_SCRIPT_PATH}. Ejecuta primero: ./migration.sh restic-backup init${NC}"
        return 1
    }

    run_cmd "$RESTIC_BACKUP_SCRIPT_PATH" "$SUBCOMMAND"
}

restic_backup_install_timer() {
    restic_backup_prepare_scaffold
    if [ -r "$RESTIC_BACKUP_ENV_PATH" ]; then
        restic_backup_load_local_env
        if restic_backup_env_uses_placeholders; then
            log_warn "backup.env sigue con placeholders. El timer se instalará, pero conviene editarlo antes de confiar en las ejecuciones automáticas."
        fi
    fi
    run_cmd systemctl --user daemon-reload
    run_cmd systemctl --user enable --now restic-backup.timer
    log_success "Timer restic-backup.timer habilitado."
}

restic_backup_disable_timer() {
    run_shell "systemctl --user disable --now restic-backup.timer >/dev/null 2>&1 || true"
    run_shell "systemctl --user stop restic-backup.service >/dev/null 2>&1 || true"
    run_cmd systemctl --user daemon-reload
    log_success "Timer restic-backup.timer deshabilitado."
}

restic_backup_cli() {
    local SUBCOMMAND="${1:-status}"

    shift || true

    case "$SUBCOMMAND" in
        init)
            restic_backup_init "$@"
            ;;
        run)
            [ $# -eq 0 ] || {
                log "${RED}restic-backup run no acepta opciones extra.${NC}"
                return 1
            }
            restic_backup_delegate_installed_script run
            ;;
        status)
            [ $# -eq 0 ] || {
                log "${RED}restic-backup status no acepta opciones extra.${NC}"
                return 1
            }
            restic_backup_delegate_installed_script status
            ;;
        snapshots)
            [ $# -eq 0 ] || {
                log "${RED}restic-backup snapshots no acepta opciones extra.${NC}"
                return 1
            }
            restic_backup_delegate_installed_script snapshots
            ;;
        install-timer)
            [ $# -eq 0 ] || {
                log "${RED}restic-backup install-timer no acepta opciones extra.${NC}"
                return 1
            }
            restic_backup_install_timer
            ;;
        disable-timer)
            [ $# -eq 0 ] || {
                log "${RED}restic-backup disable-timer no acepta opciones extra.${NC}"
                return 1
            }
            restic_backup_disable_timer
            ;;
        *)
            log "${RED}Subcomando Restic no reconocido: $SUBCOMMAND${NC}"
            return 1
            ;;
    esac
}
