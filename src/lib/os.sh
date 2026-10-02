#!/usr/bin/env bash

# Detección de distribución y utilidades de preflight portables (ADR-002 D1).

# shellcheck disable=SC2034

_os_error() {
    if declare -F log >/dev/null 2>&1; then
        log "${RED:-}$1${NC:-}"
    else
        printf '%s\n' "$1" >&2
    fi
}

# Lee una clave de os-release sin ejecutar el fichero.
os_release_value() {
    local KEY="$1"
    local FILE="${OS_RELEASE_FILE:-/etc/os-release}"
    local K
    local V

    [ -r "$FILE" ] || return 0

    while IFS='=' read -r K V || [ -n "$K" ]; do
        if [ "$K" = "$KEY" ]; then
            V="${V%\"}"
            V="${V#\"}"
            V="${V%\'}"
            V="${V#\'}"
            printf '%s\n' "$V"
            return 0
        fi
    done < "$FILE"
    return 0
}

_os_family_from_id() {
    case "$1" in
        arch|cachyos|endeavouros|manjaro) printf 'arch\n' ;;
        debian|ubuntu) printf 'debian\n' ;;
        fedora|rhel|centos|rocky|almalinux) printf 'fedora\n' ;;
        opensuse*|sles) printf 'suse\n' ;;
    esac
}

# arch | debian | fedora | suse | unknown
os_family() {
    local ID
    local ID_LIKE
    local FAMILY=""
    local WORD

    ID="$(os_release_value ID)"
    ID_LIKE="$(os_release_value ID_LIKE)"

    FAMILY="$(_os_family_from_id "$ID")"
    if [ -z "$FAMILY" ]; then
        for WORD in $ID_LIKE; do
            case "$WORD" in
                arch) FAMILY="arch"; break ;;
            esac
        done
    fi
    if [ -z "$FAMILY" ]; then
        for WORD in $ID_LIKE; do
            case "$WORD" in
                debian|ubuntu) FAMILY="debian"; break ;;
            esac
        done
    fi
    if [ -z "$FAMILY" ]; then
        for WORD in $ID_LIKE; do
            case "$WORD" in
                fedora|rhel) FAMILY="fedora"; break ;;
            esac
        done
    fi
    if [ -z "$FAMILY" ]; then
        for WORD in $ID_LIKE; do
            case "$WORD" in
                suse|opensuse*) FAMILY="suse"; break ;;
            esac
        done
    fi

    printf '%s\n' "${FAMILY:-unknown}"
}

# Comando sugerido para instalar un paquete (vacío si la familia es desconocida).
os_pkg_install_cmd() {
    local PACKAGE="$1"

    case "$(os_family)" in
        arch) printf 'sudo pacman -S --needed %s\n' "$PACKAGE" ;;
        debian) printf 'sudo apt-get install -y %s\n' "$PACKAGE" ;;
        fedora) printf 'sudo dnf install -y %s\n' "$PACKAGE" ;;
        suse) printf 'sudo zypper --non-interactive install %s\n' "$PACKAGE" ;;
        *) printf '\n' ;;
    esac
}

require_commands() {
    local CMD
    local HINT
    local MISSING=0

    for CMD in "$@"; do
        command -v "$CMD" >/dev/null 2>&1 && continue
        MISSING=1
        HINT="$(os_pkg_install_cmd "$CMD")"
        if [ -n "$HINT" ]; then
            _os_error "[ERROR] Falta ${CMD}. Instálalo con: ${HINT}"
        else
            _os_error "[ERROR] Falta ${CMD}. Instálalo con el gestor de paquetes de tu distribución."
        fi
    done

    [ "$MISSING" -eq 0 ]
}

# bash_version_at_least <req_major> <req_minor> <have_major> <have_minor>
bash_version_at_least() {
    local REQ_MAJOR="$1"
    local REQ_MINOR="$2"
    local HAVE_MAJOR="$3"
    local HAVE_MINOR="$4"

    [ "$HAVE_MAJOR" -gt "$REQ_MAJOR" ] && return 0
    [ "$HAVE_MAJOR" -eq "$REQ_MAJOR" ] && [ "$HAVE_MINOR" -ge "$REQ_MINOR" ]
}

_os_report_old_bash() {
    _os_error "[ERROR] Se necesita Bash >= 4.4 (detectado: ${1}.${2})."
    return 1
}

require_bash_44() {
    bash_version_at_least 4 4 "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}" ||
        _os_report_old_bash "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"
}
