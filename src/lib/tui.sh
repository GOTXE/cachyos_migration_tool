#!/usr/bin/env bash

# shellcheck disable=SC2034

export NEWT_COLORS='
  root=white,black
  border=cyan,black
  title=cyan,black
  roottext=white,black
  window=white,black
  textbox=white,black
  button=black,cyan
  actbutton=white,blue
  checkbox=white,black
  actcheckbox=black,green
  listbox=white,black
  actlistbox=black,cyan
  sellistbox=black,cyan
  actsellistbox=black,cyan
  label=white,black
  compactbutton=white,black
'

tui_main_menu() {
    local OPTION
    local TUI_TARGET

    while true; do
        OPTION=$(whiptail \
            --title " Linux Migration Tool v${VERSION} " \
            --menu "\nSelecciona una operación:" \
            23 64 12 \
            "1"  "Backup sistema" \
            "2"  "Bootstrap CachyOS" \
            "3"  "Post-check tras reinicio" \
            "4"  "Restaurar backup" \
            "5"  "Desinstalar MBP Watch" \
            "6"  "Desinstalar plasmoid MBP Watch" \
            "7"  "Reinstalar plasmoid MBP Watch" \
            "8"  "Mover plasmoid MBP Watch" \
            "9"  "Instalar YouTube Force H264" \
            "10" "VA-API Brave/Chromium (Intel Broadwell)" \
            "11" "Salir" \
            3>&1 1>&2 2>&3) || break

        case "$OPTION" in
            1)
                backup_system
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            2)
                tui_bootstrap
                ;;
            3)
                post_bootstrap_checks
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            4)
                restore_system
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            5)
                uninstall_mbp_watch_diagnostics
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            6)
                uninstall_mbp_watch_plasmoid
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            7)
                reinstall_mbp_watch_plasmoid
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            8)
                TUI_TARGET=$(whiptail \
                    --title " Mover plasmoid MBP Watch " \
                    --inputbox "\nDestino del plasmoid:" \
                    9 52 "primary" \
                    3>&1 1>&2 2>&3) || continue
                MBP_PLASMOID_TARGET="${TUI_TARGET:-primary}"
                move_mbp_watch_plasmoid "$MBP_PLASMOID_TARGET"
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            9)
                install_youtube_force_h264_package
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            10)
                configure_vaapi_brave_broadwell
                whiptail --title " Operación completada " \
                    --msgbox "\nLog guardado en:\n$LOGFILE" 9 60
                ;;
            11)
                break
                ;;
        esac
    done
}

tui_bootstrap() {
    local APPLE_DEFAULT="OFF"
    local FACETIME_DEFAULT="OFF"
    local SELECTED

    is_apple_laptop 2>/dev/null && APPLE_DEFAULT="ON"
    [ "$(detect_facetimehd_camera 2>/dev/null)" = "yes" ] && FACETIME_DEFAULT="ON"

    SELECTED=$(whiptail \
        --title " Bootstrap CachyOS " \
        --checklist \
        "Space=marcar/desmarcar   Flechas=navegar   Enter=confirmar" \
        28 72 16 \
        "base"       "Paquetes base + KDE"                        ON  \
        "zsh"        "Oh My Zsh + Powerlevel10k"                  ON  \
        "node"       "Node / pnpm / bun"                          ON  \
        "ai"         "Herramientas IA — Codex + Claude Code"      OFF \
        "mbpwatch"   "MBP Watch diagnóstico (systemd)"            ON  \
        "plasmoid"   "Plasmoid KDE MBP Watch"                     ON  \
        "youtube"    "YouTube Force H264"                          OFF \
        "apple"      "Apple laptop extras (thermald, lm_sensors)" "$APPLE_DEFAULT" \
        "facetime"   "FaceTime HD camera (driver AUR)"            "$FACETIME_DEFAULT" \
        "iwd"        "iwd backend para NetworkManager"            OFF \
        "hyprland"   "Hyprland"                                    OFF \
        "wifi"       "Configurar país/región Wi-Fi"               OFF \
        "globalmenu" "Global Menu KDE (GTK + VS Code)"            OFF \
        "hwaccel"    "Aceleración HW Chromium/Brave"              OFF \
        "vaapi"      "VA-API Brave/Chromium Intel Broadwell"      OFF \
        "btrfs"      "Snapshots BTRFS (Snapper)"                  OFF \
        3>&1 1>&2 2>&3) || return 0

    if [ -z "$SELECTED" ]; then
        whiptail --title " Bootstrap " \
            --msgbox "\nNo se seleccionó ningún bloque." \
            8 44
        return 0
    fi

    whiptail --title " Bootstrap CachyOS " \
        --yesno "\nSe ejecutarán los bloques seleccionados.\n¿Continuar?" \
        9 52 || return 0

    tui_bootstrap_run "$SELECTED"

    whiptail --title " Bootstrap completado " \
        --msgbox "\nBootstrap completado.\n\nRecomendado: reiniciar el sistema.\n\nLog guardado en:\n$LOGFILE" \
        13 60
}

tui_bootstrap_run() {
    local SELECTED="$1"

    log_section "Bootstrap CachyOS (TUI)"
    show_log_location

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}DRY RUN ACTIVADO por flag --dry-run.${NC}"
    fi

    AUTO_CONFIRM=true

    [[ "$SELECTED" == *'"base"'* ]]       && install_packages
    [[ "$SELECTED" == *'"zsh"'* ]]        && { install_ohmyzsh; install_powerlevel10k; }
    [[ "$SELECTED" == *'"node"'* ]]       && install_node_stack
    [[ "$SELECTED" == *'"ai"'* ]]         && install_ai_tools
    [[ "$SELECTED" == *'"mbpwatch"'* ]]   && install_mbp_watch_diagnostics
    [[ "$SELECTED" == *'"plasmoid"'* ]]   && install_mbp_plasmoid_if_accepted
    [[ "$SELECTED" == *'"youtube"'* ]]    && install_youtube_force_h264_package
    [[ "$SELECTED" == *'"apple"'* ]]      && install_apple_laptop_extras
    [[ "$SELECTED" == *'"facetime"'* ]]   && configure_facetimehd_camera
    [[ "$SELECTED" == *'"iwd"'* ]]        && configure_networkmanager_iwd_backend
    [[ "$SELECTED" == *'"hyprland"'* ]]   && install_hyprland
    [[ "$SELECTED" == *'"wifi"'* ]]       && configure_wifi_regulatory_domain
    [[ "$SELECTED" == *'"globalmenu"'* ]] && configure_global_menu_support
    [[ "$SELECTED" == *'"hwaccel"'* ]]    && configure_chromium_hw_acceleration
    [[ "$SELECTED" == *'"vaapi"'* ]]      && configure_vaapi_brave_broadwell
    [[ "$SELECTED" == *'"btrfs"'* ]]      && configure_btrfs_snapshots

    AUTO_CONFIRM=false

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}BOOTSTRAP COMPLETADO${NC}"
    log "${GREEN}=================================${NC}"
    show_log_location
}
