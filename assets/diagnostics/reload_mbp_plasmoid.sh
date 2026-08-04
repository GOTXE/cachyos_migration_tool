#!/usr/bin/env bash
# Recargador standalone del plasmoid KDE MBP Watch.
# Uso: bash reload_mbp_plasmoid.sh [--dry-run] [--user USUARIO] [--soft|--hard]

set -euo pipefail

PLUGIN_ID="io.github.cachyosmigrationtool.mbpwatch"
LEGACY_PLUGIN_ID="io.github.gtx.mbpwatch"
PACKAGE_TYPE="Plasma/Applet"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/assets/plasmoids/mbp-watch"
DRY_RUN=false
TARGET_USER=""
MODE="soft"

usage() {
    cat <<EOF
Uso:
  bash reload_mbp_plasmoid.sh [--dry-run] [--user USUARIO] [--soft|--hard]

Opciones:
  --dry-run       Muestra las acciones sin modificar Plasma.
  --user USUARIO  Usuario KDE objetivo. Por defecto: SUDO_USER o USER.
  --soft          Reinstala/actualiza el paquete del plasmoid (por defecto).
  --hard          Actualiza el paquete y reinicia plasmashell si es posible.
EOF
}

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'AVISO: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --user)
            [ $# -ge 2 ] || die "Falta valor para --user"
            TARGET_USER="$2"
            shift 2
            ;;
        --soft)
            MODE="soft"
            shift
            ;;
        --hard)
            MODE="hard"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Opcion no reconocida: $1"
            ;;
    esac
done

resolve_target_user() {
    if [ -n "$TARGET_USER" ]; then
        printf '%s\n' "$TARGET_USER"
        return 0
    fi

    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
        return 0
    fi

    if [ -n "${USER:-}" ] && [ "$USER" != "root" ]; then
        printf '%s\n' "$USER"
        return 0
    fi

    if command -v logname >/dev/null 2>&1; then
        logname 2>/dev/null || true
        return 0
    fi

    return 1
}

run_as_target_user() {
    local CURRENT_USER
    CURRENT_USER="$(id -un)"

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] usuario $TARGET_USER: $(printf '%q ' "$@")"
        return 0
    fi

    if [ "$CURRENT_USER" = "$TARGET_USER" ]; then
        "$@"
        return $?
    fi

    if [ "$(id -u)" -eq 0 ]; then
        sudo -u "$TARGET_USER" "$@"
        return $?
    fi

    die "Ejecuta como $TARGET_USER o con sudo para operar sobre ese usuario"
}

is_plasmoid_installed() {
    run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" --list 2>/dev/null \
        | grep -Eq "$PLUGIN_ID|$LEGACY_PLUGIN_ID"
}

restart_plasmashell() {
    local TARGET_UID="$1"

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] reiniciar plasmashell para uid $TARGET_UID"
        return 0
    fi

    if [ -x /usr/bin/plasmashell ]; then
        run_as_target_user env \
            XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
            sh -c 'kquitapp6 plasmashell >/dev/null 2>&1 || true; sleep 2; kstart6 plasmashell >/dev/null 2>&1 || plasmashell >/dev/null 2>&1 &' || true
    else
        warn "plasmashell no está disponible para reiniciar."
    fi
}

TARGET_USER="$(resolve_target_user)"
[ -n "$TARGET_USER" ] || die "No se pudo resolver el usuario KDE objetivo"
id "$TARGET_USER" >/dev/null 2>&1 || die "Usuario no valido: $TARGET_USER"
TARGET_UID="$(id -u "$TARGET_USER")"

log "Recargando plasmoid MBP Watch para $TARGET_USER (uid $TARGET_UID) en modo $MODE."

if [ ! -d "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/metadata.json" ]; then
    die "No se encontro el paquete del plasmoid en: $SOURCE_DIR"
fi

command -v kpackagetool6 >/dev/null 2>&1 || die "kpackagetool6 no esta disponible"

if [ "$MODE" = "hard" ]; then
    warn "Modo hard: reintentará la actualización del paquete."
fi

if is_plasmoid_installed; then
    ACTION="--upgrade"
else
    ACTION="--install"
    warn "El plasmoid no aparece instalado para $TARGET_USER; se hará instalación en lugar de upgrade."
fi

if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] kpackagetool6 --type $PACKAGE_TYPE $ACTION $SOURCE_DIR"
else
    run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" "$ACTION" "$SOURCE_DIR"
fi

if [ "$MODE" = "hard" ]; then
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] repetir la actualización del paquete y reiniciar plasmashell para uid $TARGET_UID"
    else
        sleep 2
        run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" "$ACTION" "$SOURCE_DIR" || true
        restart_plasmashell "$TARGET_UID"
    fi
fi

log "Recarga completada."
