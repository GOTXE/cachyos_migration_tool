#!/usr/bin/env bash

# Registro único de bloques de bootstrap (ADR-001 D2).
# Etiquetas, valores por defecto y visibilidad salen de get_bootstrap_checklist_items.

# shellcheck disable=SC2034

# El orden de BLOCK_IDS es el orden de ejecución.
BLOCK_IDS=( sync base_dev yay flatpak official kde aur talk2ai restic appimage \
            filezilla markdownpart libreoffice androidstudio ipscan tea obsidian \
            sshpass codexbar_tray docker_svc zsh node ai_codex ai_engram ai_claude \
            ai_gemini ai_opencode ai_antigravity mbpwatch plasmoid youtube apple \
            facetime iwd hyprland wifi globalmenu hwaccel vaapi btrfs )

declare -gA BLOCK_FN=(
    [sync]=update_system_repos [base_dev]=install_base_devel [yay]=install_yay
    [flatpak]=install_flatpak [official]=install_official_packages [kde]=install_kde_packages
    [aur]=install_aur_packages [talk2ai]=install_talk2ai_from_github [restic]=install_restic_package
    [appimage]=install_appimage_support_package [filezilla]=install_filezilla_package
    [markdownpart]=install_markdownpart_package [libreoffice]=install_libreoffice_package
    [androidstudio]=install_android_studio_package [ipscan]=install_ipscan_package
    [tea]=install_tea_package [obsidian]=install_obsidian_package [sshpass]=install_sshpass_package
    [codexbar_tray]=install_codexbar_tray_from_local_repo [docker_svc]=setup_docker
    [zsh]=block_zsh [node]=install_node_stack [ai_codex]=install_codex_cli
    [ai_engram]=install_engram_for_codex [ai_claude]=install_claude_cli
    [ai_gemini]=install_gemini_cli [ai_opencode]=install_opencode_cli
    [ai_antigravity]=install_antigravity [youtube]=install_youtube_force_h264_package
    [iwd]=configure_networkmanager_iwd_backend [hyprland]=install_hyprland
    [wifi]=configure_wifi_regulatory_domain [globalmenu]=configure_global_menu_support
    [mbpwatch]=install_mbp_watch_diagnostics [plasmoid]=install_mbp_plasmoid_if_accepted
    [apple]=install_apple_laptop_extras [facetime]=configure_facetimehd_camera
    [hwaccel]=configure_chromium_hw_acceleration [vaapi]=configure_vaapi_intel
    [btrfs]=configure_btrfs_snapshots
)

block_zsh() {
    install_ohmyzsh
    install_powerlevel10k
}

# ids visibles, en el orden del catálogo
block_catalog_visible_ids() {
    get_bootstrap_checklist_items | awk -F'|' 'NF >= 3 && $1 != "" { print $1 }'
}

# ids visibles con valor por defecto ON
block_catalog_default_ids() {
    get_bootstrap_checklist_items | awk -F'|' 'NF >= 3 && $1 != "" && $NF == "ON" { print $1 }'
}

block_is_visible() {
    local ID="$1"
    block_catalog_visible_ids | grep -Fxq -- "$ID"
}

# id<TAB>ON|OFF<TAB>etiqueta de los bloques visibles
list_bootstrap_blocks() {
    get_bootstrap_checklist_items | awk -F'|' 'NF >= 3 && $1 != "" { printf "%s\t%s\t%s\n", $1, $NF, $2 }'
}

block_label() {
    local ID="$1"
    get_bootstrap_checklist_items | awk -F'|' -v id="$ID" '$1 == id { print $2; exit }'
}

# Las herramientas instaladas por bloques (subshell) dejan sus binarios en rutas
# que el proceso padre no ve; se añaden antes de verify_ai_tools.
refresh_bootstrap_path() {
    local DIR
    local EXTRA=("$HOME/.local/bin" "$HOME/.bun/bin" "${GOBIN:-$HOME/go/bin}")

    for DIR in "$HOME"/.nvm/versions/node/*/bin; do
        [ -d "$DIR" ] && EXTRA+=("$DIR")
    done

    for DIR in "${EXTRA[@]}"; do
        [ -d "$DIR" ] || continue
        case ":$PATH:" in
            *":$DIR:"*) ;;
            *) PATH="$DIR:$PATH" ;;
        esac
    done
    export PATH
}

# Uso: set +e; run_bootstrap_blocks <id>...; rc=$?; set -e
# Debe llamarse siempre como sentencia simple (nunca dentro de if/&&/||): bash
# ignora `set -e` en esos contextos, incluidas las subshells de cada bloque.
run_bootstrap_blocks() {
    local -A WANTED=()
    local VISIBLE_IDS
    local ID
    local LAST_AI=""
    local TOTAL=0
    local INDEX=0
    local RC=0
    local ERREXIT=false
    local FAILED=()
    local LABEL

    VISIBLE_IDS="$(block_catalog_visible_ids)"

    for ID in "$@"; do
        if [ -z "${BLOCK_FN[$ID]:-}" ] || ! printf '%s\n' "$VISIBLE_IDS" | grep -Fxq -- "$ID"; then
            log "${RED}[ERROR] Bloque desconocido o no compatible con este equipo: ${ID}${NC}"
            return 2
        fi
        WANTED[$ID]=1
    done

    if [ "$DRY_MODE" != true ]; then
        ensure_sudo_session || return 1
    fi

    AUTO_CONFIRM=true

    # Seleccionar un bloque equivale a aceptar sus preguntas internas.
    if [ -n "${WANTED[hyprland]:-}" ] && [ "$HYPRLAND_MODE" = "ask" ]; then
        HYPRLAND_MODE="yes"
    fi
    if [ -n "${WANTED[apple]:-}" ] && [ "$APPLE_LAPTOP_MODE" = "ask" ]; then
        APPLE_LAPTOP_MODE="yes"
    fi

    for ID in "${BLOCK_IDS[@]}"; do
        [ -n "${WANTED[$ID]:-}" ] || continue
        TOTAL=$((TOTAL + 1))
        case "$ID" in
            ai_*) LAST_AI="$ID" ;;
        esac
    done

    case "$-" in
        *e*) ERREXIT=true ;;
    esac

    for ID in "${BLOCK_IDS[@]}"; do
        [ -n "${WANTED[$ID]:-}" ] || continue
        INDEX=$((INDEX + 1))
        LABEL="$(block_label "$ID")"
        log_block_progress "$INDEX" "$TOTAL" "${LABEL:-$ID}"

        set +e
        ( set -e; "${BLOCK_FN[$ID]}" )
        RC=$?
        [ "$ERREXIT" = true ] && set -e

        if [ "$RC" -ne 0 ]; then
            log_warn "Bloque ${ID} falló (código ${RC}); se continúa con los siguientes."
            FAILED+=("$ID")
        fi

        if [ "$ID" = "$LAST_AI" ]; then
            refresh_bootstrap_path
            set +e
            ( set -e; configure_shell_paths )
            RC=$?
            [ "$ERREXIT" = true ] && set -e
            if [ "$RC" -ne 0 ]; then
                log_warn "configure_shell_paths falló (código ${RC})."
                FAILED+=("shell_paths")
            fi
            set +e
            ( set -e; verify_ai_tools )
            RC=$?
            [ "$ERREXIT" = true ] && set -e
            if [ "$RC" -ne 0 ]; then
                log_warn "verify_ai_tools falló (código ${RC})."
                FAILED+=("verify_ai_tools")
            fi
        fi
    done

    log ""
    if [ "${#FAILED[@]}" -eq 0 ]; then
        log "${GREEN}=================================${NC}"
        log "${GREEN}BOOTSTRAP COMPLETADO${NC}"
        log "${GREEN}=================================${NC}"
        return 0
    fi

    log "${RED}=================================${NC}"
    log "${RED}BOOTSTRAP COMPLETADO CON ERRORES: ${FAILED[*]}${NC}"
    log "${RED}=================================${NC}"
    return 1
}
