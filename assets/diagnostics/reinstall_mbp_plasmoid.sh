#!/usr/bin/env bash
# Reinstalador standalone del plasmoid KDE MBP Watch.
# Uso: bash reinstall_mbp_plasmoid.sh [--dry-run] [--user USUARIO]

set -euo pipefail

PLUGIN_ID="io.github.gtx.mbpwatch"
PACKAGE_TYPE="Plasma/Applet"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/assets/plasmoids/mbp-watch"
UNINSTALL_SCRIPT="$SCRIPT_DIR/uninstall_mbp_plasmoid.sh"
DRY_RUN=false
TARGET_USER=""
TARGET_SPEC="primary"

usage() {
    cat <<EOF
Uso:
  bash reinstall_mbp_plasmoid.sh [--dry-run] [--user USUARIO] [--target primary|screen:N]

Opciones:
  --dry-run          Muestra las acciones sin modificar Plasma.
  --user USUARIO     Usuario KDE objetivo. Por defecto: SUDO_USER o USER.
  --target           Destino del plasmoid tras reinstalarlo.
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
        --target)
            [ $# -ge 2 ] || die "Falta valor para --target"
            TARGET_SPEC="$2"
            shift 2
            ;;
        --restart-plasma)
            die "La opcion --restart-plasma esta deshabilitada temporalmente por inestabilidad en esta sesion Plasma"
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

wait_for_plasmashell() {
    local TARGET_USER="$1"
    local ATTEMPTS=30
    local I=0

    while [ "$I" -lt "$ATTEMPTS" ]; do
        if pgrep -u "$TARGET_USER" -x plasmashell >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        I=$((I + 1))
    done

    return 1
}

wait_for_session_bus() {
    local TARGET_UID="$1"
    local ATTEMPTS=20
    local I=0

    while [ "$I" -lt "$ATTEMPTS" ]; do
        if [ -S "/run/user/$TARGET_UID/bus" ]; then
            return 0
        fi
        sleep 1
        I=$((I + 1))
    done

    return 1
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

build_presence_script() {
    cat <<'EOF'
var pluginId = "io.github.gtx.mbpwatch";
var allDesktops = desktops();
var present = false;

for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
    var desktop = allDesktops[desktopIndex];
    if (!desktop) {
        continue;
    }

    var typedWidgets = desktop.widgets(pluginId);
    if (typedWidgets && typedWidgets.length > 0) {
        present = true;
        break;
    }

    var ids = desktop.widgetIds || [];
    for (var idIndex = 0; idIndex < ids.length; idIndex += 1) {
        var widget = desktop.widgetById(ids[idIndex]);
        if (widget && widget.type === pluginId) {
            present = true;
            break;
        }
    }

    if (present) {
        break;
    }
}

present ? "OK:present" : "OK:not-present";
EOF
}

query_plasmoid_presence() {
    local TARGET_USER="$1"
    local TARGET_UID="$2"
    local SCRIPT=""

    SCRIPT="$(build_presence_script)"
    run_as_target_plasma_session "$TARGET_UID" \
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$SCRIPT" \
        2>/dev/null || true
}

wait_for_plasmashell_service() {
    local TARGET_USER="$1"
    local TARGET_UID="$2"
    local ATTEMPTS="${3:-20}"
    local I=0

    while [ "$I" -lt "$ATTEMPTS" ]; do
        if [ "$(query_plasmoid_presence "$TARGET_USER" "$TARGET_UID")" = "OK:not-present" ] \
            || [ "$(query_plasmoid_presence "$TARGET_USER" "$TARGET_UID")" = "OK:present" ]; then
            return 0
        fi
        sleep 1
        I=$((I + 1))
    done

    return 1
}

wait_for_plasmoid_on_desktop() {
    local TARGET_USER="$1"
    local TARGET_UID="$2"
    local ATTEMPTS="${3:-12}"
    local I=0
    local RESULT=""

    while [ "$I" -lt "$ATTEMPTS" ]; do
        RESULT="$(query_plasmoid_presence "$TARGET_USER" "$TARGET_UID")"
        if [ "$RESULT" = "OK:present" ]; then
            return 0
        fi
        sleep 1
        I=$((I + 1))
    done

    return 1
}

build_autoload_script() {
    local TARGET_SCREEN_INDEX="$1"

    cat <<EOF
var pluginId = "io.github.gtx.mbpwatch";
var preferredScreen = ${TARGET_SCREEN_INDEX};
var widgetWidth = 360;
var widgetMargin = 24;
var widgetTop = 24;
var widgetMinHeight = 480;
var widgetMaxHeight = 920;
var result = "";

function widgetAlreadyPresent(allDesktops, expectedPluginId) {
    for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
        var desktop = allDesktops[desktopIndex];
        if (!desktop) {
            continue;
        }

        var typedWidgets = desktop.widgets(expectedPluginId);
        if (typedWidgets && typedWidgets.length > 0) {
            return true;
        }

        var ids = desktop.widgetIds || [];
        for (var idIndex = 0; idIndex < ids.length; idIndex += 1) {
            var widget = desktop.widgetById(ids[idIndex]);
            if (widget && widget.type === expectedPluginId) {
                return true;
            }
        }
    }

    return false;
}

if (!knownWidgetTypes || knownWidgetTypes.indexOf(pluginId) === -1) {
    result = "ERROR:plasmoid-not-installed";
} else {
    var allDesktops = desktops();

    if (widgetAlreadyPresent(allDesktops, pluginId)) {
        result = "OK:already-present";
    } else {
        var targetDesktop = null;

        if (typeof desktopForScreen === "function") {
            targetDesktop = desktopForScreen(preferredScreen);
        }

        if (!targetDesktop) {
            for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
                var desktopCandidate = allDesktops[desktopIndex];
                if (desktopCandidate && desktopCandidate.screen === preferredScreen) {
                    targetDesktop = desktopCandidate;
                    break;
                }
            }
        }

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
                result = "OK:created";
            }
        }
    }
}

result;
EOF
}

auto_add_plasmoid() {
    local TARGET_USER="$1"
    local TARGET_UID="$2"
    local NORMALIZED_TARGET=""
    local TARGET_SCREEN_INDEX=""
    local SCRIPT=""
    local RESULT=""
    local STATUS=0

    if ! NORMALIZED_TARGET="$(normalize_target_spec "$TARGET_SPEC" 2>/dev/null)"; then
        printf 'ERROR:bad-target\n'
        return 1
    fi
    TARGET_SCREEN_INDEX="${NORMALIZED_TARGET#screen:}"

    if [ "$(query_plasmoid_presence "$TARGET_USER" "$TARGET_UID")" = "OK:present" ]; then
        printf 'OK:already-present\n'
        return 0
    fi

    SCRIPT="$(build_autoload_script "$TARGET_SCREEN_INDEX")"
    set +e
    RESULT="$(
        run_as_target_plasma_session "$TARGET_UID" \
            qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$SCRIPT" \
            2>/dev/null
    )"
    STATUS=$?
    set -e

    if [ "$STATUS" -ne 0 ]; then
        printf 'ERROR:qdbus-failed\n'
        return 1
    fi

    case "$RESULT" in
        *"ERROR:plasmoid-not-installed"*)
            printf 'ERROR:plasmoid-not-installed\n'
            return 1
            ;;
        *"ERROR:no-desktop"*)
            printf 'ERROR:no-desktop\n'
            return 1
            ;;
        *"ERROR:create-failed"*)
            printf 'ERROR:create-failed\n'
            return 1
            ;;
    esac

    if wait_for_plasmoid_on_desktop "$TARGET_USER" "$TARGET_UID" 12; then
        printf 'OK:created\n'
        return 0
    fi

    printf 'OK:created\n'
    return 0
}

TARGET_USER="$(resolve_target_user)"
[ -n "$TARGET_USER" ] || die "No se pudo resolver el usuario KDE objetivo"
id "$TARGET_USER" >/dev/null 2>&1 || die "Usuario no valido: $TARGET_USER"
TARGET_UID="$(id -u "$TARGET_USER")"

[ -d "$SOURCE_DIR" ] || die "No se encontro el paquete del plasmoid en: $SOURCE_DIR"
[ -f "$SOURCE_DIR/metadata.json" ] || die "Falta metadata.json en: $SOURCE_DIR"
[ -f "$UNINSTALL_SCRIPT" ] || die "No se encontro el desinstalador: $UNINSTALL_SCRIPT"
command -v kpackagetool6 >/dev/null 2>&1 || die "kpackagetool6 no esta disponible"
command -v qdbus6 >/dev/null 2>&1 || die "qdbus6 no esta disponible"

log "Reinstalando plasmoid MBP Watch para $TARGET_USER (uid $TARGET_UID)."
log " - Se quitara la instancia actual del escritorio y el paquete Plasma."
log " - Se reinstalara el paquete desde: $SOURCE_DIR"
log " - Destino solicitado: $TARGET_SPEC"
log " - No se reiniciara plasmashell; se reintentara el auto-add sobre la sesion activa."

if ! wait_for_session_bus "$TARGET_UID"; then
    warn "No se detecto bus de sesion Plasma en /run/user/$TARGET_UID/bus."
    if [ "$DRY_RUN" != true ]; then
        die "Abre una sesion KDE Plasma activa antes de reinstalar el plasmoid"
    fi
fi

log ""
log "1) Desinstalando instancia y paquete actuales..."
UNINSTALL_ARGS=(--user "$TARGET_USER")
if [ "$DRY_RUN" = true ]; then
    UNINSTALL_ARGS=(--dry-run "${UNINSTALL_ARGS[@]}")
fi
bash "$UNINSTALL_SCRIPT" "${UNINSTALL_ARGS[@]}"

log ""
log "2) Instalando paquete del plasmoid..."
run_as_target_user kpackagetool6 --type "$PACKAGE_TYPE" --install "$SOURCE_DIR"

log ""
log "3) Se omite el reinicio de plasmashell."

log ""
log "4) Añadiendo el plasmoid al escritorio..."
if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] usuario $TARGET_USER: qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '<auto-add $PLUGIN_ID>'"
else
    AUTO_ADD_RESULT=""
    ATTEMPT=1

    while [ "$ATTEMPT" -le 3 ]; do
        AUTO_ADD_RESULT="$(auto_add_plasmoid "$TARGET_USER" "$TARGET_UID" 2>&1 || true)"

        case "$AUTO_ADD_RESULT" in
            *"OK:created"*)
                log "Plasmoid MBP Watch añadido al escritorio tras reinstalar."
                break
                ;;
            *"OK:already-present"*)
                log "La instancia del plasmoid MBP Watch ya estaba presente tras reinstalar."
                break
                ;;
            *)
                warn "Intento $ATTEMPT/3 de auto-add sin confirmacion: ${AUTO_ADD_RESULT:-sin salida}"
                if [ "$ATTEMPT" -lt 3 ]; then
                    sleep 2
                fi
                ;;
        esac

        ATTEMPT=$((ATTEMPT + 1))
    done

    if [ "$(query_plasmoid_presence "$TARGET_USER" "$TARGET_UID")" != "OK:present" ]; then
        warn "El plasmoid se reinstalo, pero Plasma no reflejo la instancia en el escritorio."
        warn "Reintento manual recomendado: bash migration.sh add-mbp-plasmoid"
        exit 1
    fi
fi

log ""
log "Reinstalacion del plasmoid MBP Watch finalizada."
