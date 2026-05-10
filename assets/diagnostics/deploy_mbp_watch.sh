#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# mbp_watch
SOURCE_SCRIPT="$SCRIPT_DIR/mbp_watch.sh"
WEB_DIR="$SCRIPT_DIR/web"
TARGET_BIN="/usr/local/bin/mbp_watch.sh"
SERVICE="mbp-watch.service"
MBP_WATCH_PORT="${MBP_WATCH_PORT:-7070}"
STATE_DIR="${MBP_WATCH_DIR:-/var/lib/mbp-watch}"

DO_CLEAN=false

usage() {
    cat <<EOF
Uso: $0 [deploy|desktop] [--clean]

  deploy   instala/actualiza el watcher y lo arranca
  desktop  crea solo el lanzador de escritorio
  --clean  archiva el estado anterior en vez de reutilizarlo
EOF
}

archive_state_dir() {
    local BACKUP_DIR

    [ -d "$STATE_DIR" ] || return 0

    BACKUP_DIR="${STATE_DIR}.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$STATE_DIR" "$BACKUP_DIR"
    echo "Estado anterior archivado en: $BACKUP_DIR"
}

install_desktop() {
    local XDG_DESKTOP
    local DESKTOP_FILE

    XDG_DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    DESKTOP_FILE="$XDG_DESKTOP/MBP-Watch-Report.desktop"

    mkdir -p "$XDG_DESKTOP"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=MBP Watch Report
Comment=Open the MBP diagnostics report
Exec=xdg-open "http://localhost:${MBP_WATCH_PORT}/report.html"
Terminal=false
Icon=utilities-system-monitor
Categories=System;Monitor;
EOF
    chmod +x "$DESKTOP_FILE"
    echo "Lanzador creado: $DESKTOP_FILE"
}

MODE="deploy"
for ARG in "$@"; do
    case "$ARG" in
        deploy|desktop)
            MODE="$ARG"
            ;;
        --clean)
            DO_CLEAN=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: argumento desconocido: $ARG"
            usage
            exit 1
            ;;
    esac
done

if [ "$MODE" = "desktop" ]; then
    install_desktop
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi

if [ ! -f "$SOURCE_SCRIPT" ]; then
    echo "ERROR: no encontrado $SOURCE_SCRIPT"
    exit 1
fi

bash -n "$SOURCE_SCRIPT" || { echo "ERROR: sintaxis invalida en $SOURCE_SCRIPT"; exit 1; }

echo "=== Instalando mbp_watch ==="
echo "Parando $SERVICE..."
systemctl stop "$SERVICE" 2>/dev/null || true

if [ "$DO_CLEAN" = true ]; then
    archive_state_dir
fi

echo "Copiando $SOURCE_SCRIPT -> $TARGET_BIN"
cp "$SOURCE_SCRIPT" "$TARGET_BIN"
chmod +x "$TARGET_BIN"

echo "Copiando archivos web estaticos..."
for F in report.html report.css report.js; do
    if [ -f "$WEB_DIR/$F" ]; then
        cp "$WEB_DIR/$F" "$STATE_DIR/$F"
    else
        echo "AVISO: no encontrado $WEB_DIR/$F"
    fi
done

echo "Arrancando $SERVICE..."
systemctl start "$SERVICE"

sleep 2
systemctl is-active --quiet "$SERVICE" \
    && echo "OK: $SERVICE activo" \
    || echo "AVISO: $SERVICE no esta activo, revisa: journalctl -u $SERVICE -n 20"

echo ""
"$TARGET_BIN" status

echo ""
echo "=== Retirando wifi_monitor legado ==="
systemctl disable --now wifi-monitor.service 2>/dev/null || true
rm -f /etc/systemd/system/wifi-monitor.service 2>/dev/null || true
systemctl daemon-reload

echo ""
echo "=== Instalación completada ==="
echo "mbp_watch:     http://localhost:${MBP_WATCH_PORT}/report.html"
echo "wifi:          integrado como modal en http://localhost:${MBP_WATCH_PORT}/report.html"
