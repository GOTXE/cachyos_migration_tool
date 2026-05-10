#!/usr/bin/env bash
# Desinstalador standalone de MBP Watch.
# Uso: sudo bash uninstall_mbp_watch.sh [--purge]
#   --purge  elimina también el directorio de estado (/var/lib/mbp-watch)

set -euo pipefail

SERVICE_NAME="mbp-watch.service"
BIN_PATH="/usr/local/bin/mbp_watch.sh"
UNINSTALL_PATH="/usr/local/sbin/uninstall_mbp_watch.sh"
CONFIG_PATH="/etc/mbp-watch.conf"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
STATE_DIR="/var/lib/mbp-watch"

PURGE_STATE=false
for ARG in "$@"; do
    case "$ARG" in
        --purge) PURGE_STATE=true ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Ejecuta como root: sudo bash $0 [--purge]"
    exit 1
fi

# Detectar el lanzador de escritorio del usuario real (invocado via sudo)
DESKTOP_FILE=""
REAL_USER="${SUDO_USER:-}"
if [ -n "$REAL_USER" ]; then
    REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 || true)"
    if [ -n "$REAL_HOME" ]; then
        for CANDIDATE in \
            "$REAL_HOME/Desktop/MBP-Watch-Report.desktop" \
            "$REAL_HOME/Escritorio/MBP-Watch-Report.desktop"
        do
            if [ -f "$CANDIDATE" ]; then
                DESKTOP_FILE="$CANDIDATE"
                break
            fi
        done
        # Fallback: buscar en XDG_DESKTOP_DIR del usuario
        if [ -z "$DESKTOP_FILE" ]; then
            USER_DIRS_FILE="$REAL_HOME/.config/user-dirs.dirs"
            if [ -r "$USER_DIRS_FILE" ]; then
                RAW_DESKTOP="$(sed -n 's/^XDG_DESKTOP_DIR="\([^"]*\)"$/\1/p' "$USER_DIRS_FILE" | head -1 || true)"
                if [ -n "$RAW_DESKTOP" ]; then
                    XDG_DESKTOP="${RAW_DESKTOP//\$HOME/$REAL_HOME}"
                    CANDIDATE="$XDG_DESKTOP/MBP-Watch-Report.desktop"
                    [ -f "$CANDIDATE" ] && DESKTOP_FILE="$CANDIDATE"
                fi
            fi
        fi
    fi
fi

echo "Parando y deshabilitando $SERVICE_NAME..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

echo "Eliminando archivos del sistema..."
rm -f "$BIN_PATH" "$CONFIG_PATH" "$SERVICE_PATH"

if [ -n "$DESKTOP_FILE" ] && [ -f "$DESKTOP_FILE" ]; then
    rm -f "$DESKTOP_FILE"
    echo "Lanzador de escritorio eliminado: $DESKTOP_FILE"
fi

if [ "$PURGE_STATE" = true ]; then
    rm -rf "$STATE_DIR"
    echo "Datos de estado eliminados: $STATE_DIR"
else
    echo "Datos de estado conservados en: $STATE_DIR"
    echo "Para eliminarlos manualmente: sudo rm -rf $STATE_DIR"
fi

# Eliminarse a si mismo al final para no dejar huella
rm -f "$UNINSTALL_PATH"

echo "MBP Watch desinstalado correctamente."
