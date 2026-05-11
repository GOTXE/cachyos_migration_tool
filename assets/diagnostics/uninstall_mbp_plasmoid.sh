#!/usr/bin/env bash
# Desinstalador standalone del plasmoid KDE MBP Watch.
# Uso: bash uninstall_mbp_plasmoid.sh [--dry-run] [--user USUARIO]

set -euo pipefail

PLUGIN_ID="io.github.gtx.mbpwatch"
PACKAGE_TYPE="Plasma/Applet"
DRY_RUN=false
TARGET_USER=""

usage() {
    cat <<EOF
Uso:
  bash uninstall_mbp_plasmoid.sh [--dry-run] [--user USUARIO]

Opciones:
  --dry-run       Muestra las acciones sin modificar Plasma.
  --user USUARIO  Usuario KDE objetivo. Por defecto: SUDO_USER o USER.
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
    local CURRENT_USER=""

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

run_as_target_plasma_session() {
    local TARGET_UID="$1"
    shift

    run_as_target_user env \
        XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
        "$@"
}

build_remove_instances_script() {
    cat <<'EOF'
var pluginId = "io.github.gtx.mbpwatch";
var removed = 0;
var failures = 0;
var allDesktops = desktops();
var result = "";

function removeWidget(widget) {
    if (!widget) {
        return;
    }

    try {
        if (typeof widget.remove === "function") {
            widget.remove();
            removed += 1;
        } else {
            failures += 1;
        }
    } catch (error) {
        failures += 1;
    }
}

for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
    var desktop = allDesktops[desktopIndex];
    if (!desktop) {
        continue;
    }

    var typedWidgets = desktop.widgets(pluginId);
    if (typedWidgets) {
        for (var typedIndex = 0; typedIndex < typedWidgets.length; typedIndex += 1) {
            removeWidget(typedWidgets[typedIndex]);
        }
    }

    var ids = desktop.widgetIds || [];
    for (var idIndex = 0; idIndex < ids.length; idIndex += 1) {
        var widget = desktop.widgetById(ids[idIndex]);
        if (widget && widget.type === pluginId) {
            removeWidget(widget);
        }
    }
}

if (failures > 0) {
    result = "ERROR:remove-failed:" + failures;
} else if (removed > 0) {
    result = "OK:removed:" + removed;
} else {
    result = "OK:not-present";
}

result;
EOF
}

is_package_installed() {
    run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" --list 2>/dev/null \
        | grep -Fq "$PLUGIN_ID"
}

TARGET_USER="$(resolve_target_user)"
[ -n "$TARGET_USER" ] || die "No se pudo resolver el usuario KDE objetivo"
id "$TARGET_USER" >/dev/null 2>&1 || die "Usuario no valido: $TARGET_USER"
TARGET_UID="$(id -u "$TARGET_USER")"

log "Desinstalando plasmoid MBP Watch para $TARGET_USER (uid $TARGET_UID)."

if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] si hay sesion Plasma: qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '<remove $PLUGIN_ID>'"
    log "[DRY-RUN] kpackagetool6 --type $PACKAGE_TYPE --remove $PLUGIN_ID"
    log "[DRY-RUN] no se editarian archivos internos de configuracion de Plasma."
    exit 0
fi

if command -v qdbus6 >/dev/null 2>&1 && [ -S "/run/user/$TARGET_UID/bus" ]; then
    REMOVE_SCRIPT="$(build_remove_instances_script)"
    REMOVE_RESULT="$(
        run_as_target_plasma_session "$TARGET_UID" \
            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$REMOVE_SCRIPT" \
            2>/dev/null || true
    )"

    case "$REMOVE_RESULT" in
        *"OK:removed:"*)
            log "Instancias del escritorio eliminadas: $REMOVE_RESULT"
            ;;
        *"OK:not-present"*)
            log "No habia instancias activas del plasmoid en el escritorio."
            ;;
        *"ERROR:remove-failed:"*)
            warn "Plasma no pudo eliminar alguna instancia automaticamente: $REMOVE_RESULT"
            ;;
        *)
            warn "No se pudo confirmar la eliminacion de instancias activas via qdbus6."
            ;;
    esac
else
    warn "No hay qdbus6 o bus de sesion Plasma activo; se omite la eliminacion de instancias del escritorio."
fi

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    warn "kpackagetool6 no esta disponible; no se puede desinstalar el paquete del plasmoid."
    exit 0
fi

if is_package_installed; then
    run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" --remove "$PLUGIN_ID"
    log "Paquete del plasmoid eliminado: $PLUGIN_ID"
else
    log "El paquete del plasmoid no aparece instalado para $TARGET_USER."
fi

log "No se han editado archivos internos de configuracion de Plasma."
log "Desinstalacion del plasmoid MBP Watch finalizada."
