#!/usr/bin/env bash
# Recoloca el plasmoid KDE MBP Watch en una pantalla objetivo.
# Uso: bash move_mbp_plasmoid.sh [--dry-run] [--user USUARIO] [--target primary|screen:N]

set -euo pipefail

PLUGIN_ID="io.github.cachyosmigrationtool.mbpwatch"
PACKAGE_TYPE="Plasma/Applet"
DRY_RUN=false
TARGET_USER=""
TARGET_SPEC="primary"

usage() {
    cat <<EOF
Uso:
  bash move_mbp_plasmoid.sh [--dry-run] [--user USUARIO] [--target primary|screen:N]

Opciones:
  --dry-run               Muestra las acciones sin modificar Plasma.
  --user USUARIO          Usuario KDE objetivo. Por defecto: SUDO_USER o USER.
  --target primary        Usa la pantalla principal/logica por defecto de Plasma.
  --target screen:N       Fuerza la pantalla con indice N.
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

validate_target_spec() {
    local VALUE="$1"

    case "$VALUE" in
        primary)
            return 0
            ;;
        screen:[0-9]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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
        --target)
            [ $# -ge 2 ] || die "Falta valor para --target"
            TARGET_SPEC="$2"
            validate_target_spec "$TARGET_SPEC" || die "Target no valido: $TARGET_SPEC"
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

has_plasma_session_bus() {
    local TARGET_UID="$1"
    [ -S "/run/user/$TARGET_UID/bus" ]
}

list_plasma_outputs() {
    command -v kscreen-doctor >/dev/null 2>&1 || return 0
    kscreen-doctor -o 2>/dev/null | awk '/^Output:/ { print $2 "|" $3 }'
}

normalize_target_spec() {
    local REQUESTED_TARGET="${1:-primary}"
    local OUTPUTS=()
    local ENTRY=""
    local OUTPUT_ID=""
    local OUTPUT_NAME=""

    case "$REQUESTED_TARGET" in
        screen:[0-9]*)
            printf '%s\n' "$REQUESTED_TARGET"
            return 0
            ;;
        primary|"")
            mapfile -t OUTPUTS < <(list_plasma_outputs)

            for ENTRY in "${OUTPUTS[@]}"; do
                OUTPUT_ID="${ENTRY%%|*}"
                OUTPUT_NAME="${ENTRY#*|}"
                if printf '%s\n' "$OUTPUT_NAME" | grep -Eiq '^(eDP|LVDS|DSI)'; then
                    printf 'screen:%s\n' "$OUTPUT_ID"
                    return 0
                fi
            done

            if [ ${#OUTPUTS[@]} -gt 0 ]; then
                OUTPUT_ID="${OUTPUTS[0]%%|*}"
                printf 'screen:%s\n' "$OUTPUT_ID"
                return 0
            fi

            printf 'screen:0\n'
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_package_installed() {
    run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" --list 2>/dev/null \
        | grep -Fq "$PLUGIN_ID"
}

build_move_script() {
    local TARGET_SPEC="$1"

    cat <<EOF
var pluginId = "io.github.cachyosmigrationtool.mbpwatch";
var targetSpec = ${TARGET_SPEC@Q};
var widgetWidth = 360;
var widgetMargin = 24;
var widgetTop = 24;
var widgetMinHeight = 480;
var widgetMaxHeight = 920;
var result = "";
var allDesktops = desktops();
var removed = 0;

function removeWidget(widget) {
    if (!widget) {
        return;
    }

    try {
        if (typeof widget.remove === "function") {
            widget.remove();
            removed += 1;
        }
    } catch (error) {
    }
}

function findDesktopByScreen(screenIndex) {
    if (typeof desktopForScreen === "function") {
        var byScreen = desktopForScreen(screenIndex);
        if (byScreen) {
            return byScreen;
        }
    }

    for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
        var desktop = allDesktops[desktopIndex];
        if (desktop && desktop.screen === screenIndex) {
            return desktop;
        }
    }

    return null;
}

function removeExistingWidgets() {
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
}

if (!knownWidgetTypes || knownWidgetTypes.indexOf(pluginId) === -1) {
    result = "ERROR:plasmoid-not-installed";
} else {
    removeExistingWidgets();

    var targetDesktop = null;

    if (targetSpec === "primary") {
        targetDesktop = findDesktopByScreen(0);
    } else if (targetSpec.indexOf("screen:") === 0) {
        var screenIndex = parseInt(targetSpec.slice(7), 10);
        if (!isFinite(screenIndex) || screenIndex < 0) {
            result = "ERROR:bad-target";
        } else {
            targetDesktop = findDesktopByScreen(screenIndex);
            if (!targetDesktop) {
                result = "ERROR:no-desktop-for-screen:" + screenIndex;
            }
        }
    } else {
        result = "ERROR:bad-target";
    }

    if (!result) {
        if (!targetDesktop && allDesktops.length > 0) {
            targetDesktop = allDesktops[0];
        }

        if (!targetDesktop) {
            result = "ERROR:no-desktop";
        } else {
            var targetScreen = targetDesktop.screen >= 0 ? targetDesktop.screen : 0;
            var geom = screenGeometry(targetScreen);
            var widgetHeight = Math.min(Math.max(geom.height - 48, widgetMinHeight), widgetMaxHeight);
            var widgetX = geom.x + geom.width - widgetWidth - widgetMargin;
            var widgetY = geom.y + widgetTop;

            var widget = targetDesktop.addWidget(
                pluginId,
                widgetX,
                widgetY,
                widgetWidth,
                widgetHeight
            );

            if (!widget) {
                result = "ERROR:create-failed";
            } else {
                result = "OK:moved:screen:" + targetScreen + ":removed:" + removed;
            }
        }
    }
}

result;
EOF
}

TARGET_USER="$(resolve_target_user)"
[ -n "$TARGET_USER" ] || die "No se pudo resolver el usuario KDE objetivo"
id "$TARGET_USER" >/dev/null 2>&1 || die "Usuario no valido: $TARGET_USER"
TARGET_UID="$(id -u "$TARGET_USER")"
NORMALIZED_TARGET="$(normalize_target_spec "$TARGET_SPEC" 2>/dev/null)" || die "Target no valido: $TARGET_SPEC"

command -v kpackagetool6 >/dev/null 2>&1 || die "kpackagetool6 no esta disponible"
command -v qdbus6 >/dev/null 2>&1 || die "qdbus6 no esta disponible"

if ! is_package_installed; then
    die "El paquete del plasmoid no aparece instalado para $TARGET_USER"
fi

if ! has_plasma_session_bus "$TARGET_UID"; then
    die "No se detecto bus de sesion Plasma en /run/user/$TARGET_UID/bus"
fi

log "Moviendo plasmoid MBP Watch para $TARGET_USER (uid $TARGET_UID)."
log " - Destino solicitado: $TARGET_SPEC"
log " - Destino resuelto: $NORMALIZED_TARGET"

if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] usuario $TARGET_USER: qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '<move $PLUGIN_ID to $TARGET_SPEC>'"
    exit 0
fi

MOVE_SCRIPT="$(build_move_script "$NORMALIZED_TARGET")"
set +e
MOVE_RESULT="$(
    run_as_target_plasma_session "$TARGET_UID" \
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$MOVE_SCRIPT" \
        2>/dev/null
)"
MOVE_STATUS=$?
set -e

if [ "$MOVE_STATUS" -ne 0 ]; then
    die "qdbus6 no pudo hablar con org.kde.plasmashell en la sesion activa"
fi

case "$MOVE_RESULT" in
    *"OK:moved:screen:"*)
        log "Resultado de move: $MOVE_RESULT"
        ;;
    "")
        log "Movimiento enviado a Plasma sin salida textual; se asume aceptado."
        ;;
    *"ERROR:plasmoid-not-installed"*)
        die "Plasma no reconoce el plasmoid como instalado en la sesion activa"
        ;;
    *"ERROR:no-desktop-for-screen:"*)
        die "No existe un desktop valido para el target pedido: $TARGET_SPEC"
        ;;
    *"ERROR:no-desktop"*)
        die "Plasma no devolvio un desktop valido para recolocar el plasmoid"
        ;;
    *"ERROR:bad-target"*)
        die "El target pedido no es valido: $TARGET_SPEC"
        ;;
    *"ERROR:create-failed"*)
        die "Plasma no pudo crear la nueva instancia del plasmoid"
        ;;
    *)
        log "Salida de move no estandar: $MOVE_RESULT"
        ;;
esac

log "Movimiento del plasmoid MBP Watch finalizado."
