#!/usr/bin/env bash

# Inventario de paquetes multi-distro (ADR-002 D5).
# shellcheck disable=SC2034
# Autónomo: se puede cargar con `source` sin common.sh (lo reutiliza el runner de
# Restic). No usa log, run_cmd ni colores; los avisos van por stderr.

INVENTORY_MANAGERS=""
INVENTORY_WARNINGS=""

_inventory_add() {
    local -n _INV_TARGET="$1"
    local ITEM="$2"

    case ",${_INV_TARGET}," in
        *",${ITEM},"*) return 0 ;;
    esac
    _INV_TARGET="${_INV_TARGET:+${_INV_TARGET},}${ITEM}"
}

# _inventory_capture <id> <gestor> <fichero> <vacío_ok> <comando> [args...]
# Escribe el fichero solo si el comando termina con 0 (o con 1 y salida vacía
# cuando <vacío_ok> es 1, p. ej. `pacman -Qqem` sin paquetes foráneos).
_inventory_capture() {
    local ID="$1"
    local MANAGER="$2"
    local OUT="$3"
    local EMPTY_OK="$4"
    local TMP_FILE
    local RC=0

    shift 4

    if ! TMP_FILE="$(mktemp "${OUT}.XXXXXX")"; then
        printf 'inventory: no se pudo crear temporal para %s\n' "$ID" >&2
        _inventory_add INVENTORY_WARNINGS "$ID"
        return 0
    fi

    LC_ALL=C "$@" >"$TMP_FILE" 2>/dev/null || RC=$?

    if [ "$RC" -ne 0 ]; then
        if ! { [ "$EMPTY_OK" = "1" ] && [ "$RC" -eq 1 ] && [ ! -s "$TMP_FILE" ]; }; then
            rm -f "$TMP_FILE"
            printf 'inventory: %s falló (código %s); se omite\n' "$ID" "$RC" >&2
            _inventory_add INVENTORY_WARNINGS "$ID"
            return 0
        fi
    fi

    chmod 644 "$TMP_FILE"
    mv -f "$TMP_FILE" "$OUT"
    _inventory_add INVENTORY_MANAGERS "$MANAGER"
    return 0
}

# inventory_write <dir_metadata>
inventory_write() {
    local META_DIR="$1"
    local PKG_DIR="$META_DIR/packages"

    INVENTORY_MANAGERS=""
    INVENTORY_WARNINGS=""

    mkdir -p "$PKG_DIR"

    if command -v pacman >/dev/null 2>&1; then
        _inventory_capture pacman-native-explicit pacman "$PKG_DIR/pacman-native-explicit.txt" 0 pacman -Qqen
        _inventory_capture pacman-foreign pacman "$PKG_DIR/pacman-foreign.txt" 1 pacman -Qqem
    fi

    if command -v apt-mark >/dev/null 2>&1; then
        _inventory_capture apt-manual apt "$PKG_DIR/apt-manual.txt" 0 apt-mark showmanual
    fi

    if command -v dpkg >/dev/null 2>&1; then
        _inventory_capture dpkg-selections dpkg "$PKG_DIR/dpkg-selections.txt" 0 dpkg --get-selections
    fi

    if command -v rpm >/dev/null 2>&1; then
        _inventory_capture rpm-names rpm "$PKG_DIR/rpm-names.txt" 0 rpm -qa --qf '%{NAME}\n'
        if [ -s "$PKG_DIR/rpm-names.txt" ]; then
            LC_ALL=C sort -u -o "$PKG_DIR/rpm-names.txt" "$PKG_DIR/rpm-names.txt"
        fi
    fi

    if command -v dnf >/dev/null 2>&1; then
        _inventory_capture dnf-userinstalled dnf "$PKG_DIR/dnf-userinstalled.txt" 0 dnf repoquery --userinstalled
    fi

    if command -v zypper >/dev/null 2>&1; then
        _inventory_capture zypper-installed zypper "$PKG_DIR/zypper-installed.txt" 0 \
            zypper --non-interactive --quiet search --installed-only --type package
    fi

    if command -v flatpak >/dev/null 2>&1; then
        _inventory_capture flatpak-apps flatpak "$META_DIR/flatpak-apps.txt" 0 \
            flatpak list --app --columns=application,origin
    fi

    if command -v snap >/dev/null 2>&1; then
        _inventory_capture snap-list snap "$META_DIR/snap-list.txt" 0 snap list
    fi

    return 0
}
