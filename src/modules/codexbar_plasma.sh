#!/usr/bin/env bash

# CodexBar Plasma (Lucenx9/codexbar-plasma): widget de panel KDE 6 instalado desde una
# release de GitHub verificada con su checksum SHA-256 (ADR-001 D5).

CODEXBAR_PLASMA_ID="app.codexbar.plasma"
CODEXBAR_PLASMA_REPO="Lucenx9/codexbar-plasma"
CODEXBAR_PLASMA_ASSET="codexbar-plasma.plasmoid"
CODEXBAR_PLASMA_VERSION="${CODEXBAR_PLASMA_VERSION:-latest}"   # o vX.Y.Z

# Función aparte para poder simular el UID en los tests.
current_uid() {
    id -u
}

# Función aparte para poder simular la CLI en los tests.
codexbar_cli_available() {
    command -v codexbar >/dev/null 2>&1
}

codexbar_plasma_is_installed() {
    command -v kpackagetool6 >/dev/null 2>&1 || return 1
    kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -Fq "$CODEXBAR_PLASMA_ID"
}

codexbar_plasma_installed_version() {
    local METADATA="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/${CODEXBAR_PLASMA_ID}/metadata.json"
    local VERSION_VALUE=""

    if [ -r "$METADATA" ] && command -v python3 >/dev/null 2>&1; then
        VERSION_VALUE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["KPlugin"].get("Version", ""))' "$METADATA" 2>/dev/null || true)"
    fi
    printf '%s\n' "${VERSION_VALUE:-desconocida}"
}

# Línea informativa para el postcheck (nunca es un error).
codexbar_plasma_postcheck_line() {
    if codexbar_plasma_is_installed; then
        printf 'CodexBar Plasma: instalado (%s)\n' "$(codexbar_plasma_installed_version)"
    else
        printf 'CodexBar Plasma: no instalado\n'
    fi
}

_codexbar_plasma_cleanup() {
    local DIR="${1:-}"

    if [ -n "$DIR" ] && [ "$DIR" != "/" ] && [ "$DIR" != "$HOME" ]; then
        rm -rf -- "$DIR"
    fi
}

# Imprime "Id<TAB>Version" leyendo metadata.json del .plasmoid (zip) con la stdlib de Python.
_codexbar_plasma_read_metadata() {
    python3 - "$1" <<'PY'
import json
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = [n for n in archive.namelist() if n == "metadata.json" or n.endswith("/metadata.json")]
    if not names:
        sys.exit(1)
    name = min(names, key=lambda n: n.count("/"))
    kplugin = json.loads(archive.read(name).decode("utf-8")).get("KPlugin", {})
    print(f"{kplugin.get('Id', '')}\t{kplugin.get('Version', '')}")
PY
}

install_codexbar_plasma() {
    local VERSION_ARG="$CODEXBAR_PLASMA_VERSION"
    local WITH_CLI=false
    local BASE_URL=""
    local ASSET_URL=""
    local SUM_URL=""
    local TMP_DIR=""
    local SUM_LINE=""
    local METADATA=""
    local PLUGIN_ID=""
    local PLUGIN_VERSION=""
    local ACTION="-i"

    while [ $# -gt 0 ]; do
        case "$1" in
            --version)
                [ $# -ge 2 ] || {
                    log "${RED}[ERROR] Falta valor para --version${NC}"
                    return 2
                }
                VERSION_ARG="$2"
                shift 2
                ;;
            --with-cli)
                WITH_CLI=true
                shift
                ;;
            *)
                log "${RED}[ERROR] Opción no reconocida para CodexBar Plasma: $1${NC}"
                return 2
                ;;
        esac
    done

    if ! [[ "$VERSION_ARG" =~ ^(latest|v[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        log "${RED}[ERROR] Versión de CodexBar Plasma no válida: ${VERSION_ARG} (usa 'latest' o 'vX.Y.Z').${NC}"
        return 2
    fi

    if [ "$(current_uid)" = "0" ]; then
        log "${RED}[ERROR] Instala CodexBar Plasma como tu usuario de escritorio, no como root.${NC}"
        return 1
    fi

    require_commands kpackagetool6 curl sha256sum python3 || return 1

    if [ "$VERSION_ARG" = "latest" ]; then
        BASE_URL="https://github.com/${CODEXBAR_PLASMA_REPO}/releases/latest/download"
    else
        BASE_URL="https://github.com/${CODEXBAR_PLASMA_REPO}/releases/download/${VERSION_ARG}"
    fi
    ASSET_URL="${BASE_URL}/${CODEXBAR_PLASMA_ASSET}"
    SUM_URL="${ASSET_URL}.sha256"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] descargar ${ASSET_URL}${NC}"
        log "${YELLOW}[DRY-RUN] descargar ${SUM_URL}${NC}"
        log "${YELLOW}[DRY-RUN] verificar SHA-256 (sha256sum --check --strict) y el Id ${CODEXBAR_PLASMA_ID} del metadata.json${NC}"
        log "${YELLOW}[DRY-RUN] kpackagetool6 -t Plasma/Applet -i|-u ${CODEXBAR_PLASMA_ASSET}${NC}"
        return 0
    fi

    TMP_DIR="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "_codexbar_plasma_cleanup '$TMP_DIR'; trap - RETURN" RETURN

    log_phase "Descargando CodexBar Plasma (${VERSION_ARG})..."
    local CURL_OPTIONS=(-fsSL --proto '=https' --tlsv1.2 --max-time 120)
    run_cmd curl "${CURL_OPTIONS[@]}" -o "$TMP_DIR/$CODEXBAR_PLASMA_ASSET" "$ASSET_URL" || {
        log "${RED}[ERROR] No se pudo descargar ${ASSET_URL}${NC}"
        return 1
    }
    run_cmd curl "${CURL_OPTIONS[@]}" -o "$TMP_DIR/$CODEXBAR_PLASMA_ASSET.sha256" "$SUM_URL" || {
        log "${RED}[ERROR] No se pudo descargar ${SUM_URL}${NC}"
        return 1
    }

    SUM_LINE="$(cat "$TMP_DIR/$CODEXBAR_PLASMA_ASSET.sha256")"
    if ! [[ "$SUM_LINE" =~ ^[0-9a-f]{64}[[:space:]][\ \*]codexbar-plasma\.plasmoid$ ]] ||
       ! (cd "$TMP_DIR" && sha256sum --check --strict --status "$CODEXBAR_PLASMA_ASSET.sha256"); then
        log "${RED}[ERROR] Checksum de CodexBar Plasma no válido; no se instala.${NC}"
        return 1
    fi
    log_success "Checksum SHA-256 verificado."

    if ! METADATA="$(_codexbar_plasma_read_metadata "$TMP_DIR/$CODEXBAR_PLASMA_ASSET")"; then
        log "${RED}[ERROR] No se pudo leer metadata.json del paquete de CodexBar Plasma.${NC}"
        return 1
    fi
    PLUGIN_ID="${METADATA%%$'\t'*}"
    PLUGIN_VERSION="${METADATA#*$'\t'}"
    if [ "$PLUGIN_ID" != "$CODEXBAR_PLASMA_ID" ]; then
        log "${RED}[ERROR] El paquete descargado tiene Id '${PLUGIN_ID}', se esperaba '${CODEXBAR_PLASMA_ID}'; no se instala.${NC}"
        return 1
    fi
    log_info "Paquete verificado: ${PLUGIN_ID} ${PLUGIN_VERSION}"

    if codexbar_plasma_is_installed; then
        ACTION="-u"
    fi
    run_cmd kpackagetool6 -t Plasma/Applet "$ACTION" "$TMP_DIR/$CODEXBAR_PLASMA_ASSET" || {
        log "${RED}[ERROR] kpackagetool6 no pudo instalar CodexBar Plasma.${NC}"
        return 1
    }

    if ! codexbar_plasma_is_installed; then
        log "${RED}[ERROR] CodexBar Plasma no aparece en kpackagetool6 tras la instalación.${NC}"
        return 1
    fi

    if codexbar_cli_available; then
        log_success "codexbar CLI disponible en PATH."
    elif [ "$WITH_CLI" = true ] && [ "$(os_family)" = "arch" ]; then
        install_codexbar_cli
    else
        log_warn "El widget necesita la CLI 'codexbar'. Puedes usar General → Managed CLI → Use managed CLI desde la configuración del widget."
    fi

    if [ "$(systemctl --user is-enabled codexbar-tray.service 2>/dev/null || true)" = "enabled" ]; then
        log_info "codexbar-tray.service está habilitado: tendrás dos indicadores de CodexBar (no se desactiva nada)."
    fi

    log_success 'Añade "CodexBar" desde Añadir widgets del panel.'
    if [ "$ACTION" = "-u" ]; then
        log "Para recargarlo: systemctl --user restart plasma-plasmashell.service"
    fi
}

uninstall_codexbar_plasma() {
    require_commands kpackagetool6 || return 1

    if codexbar_plasma_is_installed; then
        run_cmd kpackagetool6 -t Plasma/Applet -r "$CODEXBAR_PLASMA_ID"
        log_success "CodexBar Plasma desinstalado (la CLI codexbar no se toca)."
    else
        log_info "CodexBar Plasma no está instalado."
    fi
}
