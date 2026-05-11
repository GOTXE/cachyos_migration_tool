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

# Limpia la pantalla antes de cada diálogo para eliminar el glitch entre ventanas.
wt() {
    clear
    whiptail "$@"
}

# Muestra un msgbox con el path del log ajustando el ancho al tamaño del path.
# Uso: _tui_log_msgbox "Título" "Texto extra\n\n" <filas>
_tui_log_msgbox() {
    local TITLE="$1"
    local BODY="$2"
    local ROWS="${3:-9}"
    local SHORT="${LOGFILE/#$HOME/\~}"
    local COLS=$(( ${#SHORT} + 6 ))
    local MAXCOLS=$(( $(tput cols 2>/dev/null || echo 80) - 2 ))
    (( COLS > MAXCOLS )) && COLS=$MAXCOLS
    (( COLS < 50 ))      && COLS=50
    wt --title " $TITLE " \
        --msgbox "${BODY}Log guardado en:\n${SHORT}" "$ROWS" "$COLS"
}

# Ejecuta "$@" en subshell mostrando su salida en un terminal embebido
# (dialog --programbox) si dialog está disponible, o redirigiendo al log.
# Los códigos ANSI de color se eliminan antes de pasarlos a dialog.
_tui_run_with_output() {
    local TITLE="$1"
    shift
    if command -v dialog >/dev/null 2>&1; then
        ("$@") 2>&1 \
            | sed 's/\033\[[0-9;]*[a-zA-Z]//g' \
            | dialog --title " $TITLE " \
                     --programbox "  ↑↓ para desplazar — se cierra al terminar  " \
                     22 78
    else
        ("$@") >> "$LOGFILE" 2>&1 || true
    fi
}

_tui_op_run() {
    AUTO_CONFIRM=true
    "$@"
}

# Ejecuta una función en subshell (con AUTO_CONFIRM=true) mostrando su salida
# en terminal embebido, y al terminar muestra un msgbox con la ruta del log.
tui_op() {
    local TITLE="$1"
    shift
    _tui_run_with_output "$TITLE" _tui_op_run "$@"
    _tui_log_msgbox "$TITLE" "\n" 9
}

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

tui_backup_select_dirs() {
    local CANDIDATES=()
    local DEFAULTS=()
    local CHECKLIST_ARGS=()
    local SELECTED_RAW
    local DEFAULT_DIR
    local STATUS
    local i

    mapfile -t CANDIDATES < <(detect_backup_data_candidates)
    if [ ${#CANDIDATES[@]} -eq 0 ]; then
        return 0
    fi

    mapfile -t DEFAULTS < <(get_data_dirs)

    for i in "${!CANDIDATES[@]}"; do
        STATUS="OFF"
        for DEFAULT_DIR in "${DEFAULTS[@]}"; do
            [ "${CANDIDATES[$i]}" = "$DEFAULT_DIR" ] && STATUS="ON" && break
        done
        CHECKLIST_ARGS+=("$i" "${CANDIDATES[$i]}" "$STATUS")
    done

    SELECTED_RAW=$(wt \
        --title " Directorios de datos para backup " \
        --checklist "Space=marcar/desmarcar   Enter=confirmar" \
        22 74 12 \
        "${CHECKLIST_ARGS[@]}" \
        3>&1 1>&2 2>&3) || return 1

    SELECTED_DATA_DIRS=()
    for TOKEN in $SELECTED_RAW; do
        TOKEN="${TOKEN//\"/}"
        [[ "$TOKEN" =~ ^[0-9]+$ ]] || continue
        SELECTED_DATA_DIRS+=("${CANDIDATES[$TOKEN]}")
    done

    if [ ${#SELECTED_DATA_DIRS[@]} -eq 0 ]; then
        SELECTED_DATA_DIRS=("${DEFAULTS[@]}")
    fi
}

tui_backup_select_disk() {
    local DISKS=()
    local LINE
    local RADIOLIST_ARGS=()
    local FIRST=true
    local NAME SIZE FS LABEL MOUNT AVAILABLE
    local STATUS
    local DISK_SELECTED
    local AVAILABLE_BYTES

    BACKUP_ESTIMATED_BYTES="$(estimate_backup_bytes)"
    local REQUIRED_HUMAN
    REQUIRED_HUMAN="$(format_bytes_human "$BACKUP_ESTIMATED_BYTES")"

    mapfile -t DISKS < <(
        lsblk -P -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,TRAN |
        while IFS= read -r LINE; do
            local MP
            MP="$(extract_lsblk_field "$LINE" "MOUNTPOINT")"
            if [ -n "$MP" ] && [ "$MP" != "/" ] && [[ ! "$MP" =~ ^/boot ]]; then
                printf '%s\n' "$LINE"
            fi
        done
    )

    if [ ${#DISKS[@]} -eq 0 ]; then
        wt --title " Error " \
            --msgbox "\nNo se encontraron discos montados." 8 44
        return 1
    fi

    for LINE in "${DISKS[@]}"; do
        NAME="$(extract_lsblk_field "$LINE" "NAME")"
        SIZE="$(extract_lsblk_field "$LINE" "SIZE")"
        FS="$(extract_lsblk_field  "$LINE" "FSTYPE")"
        LABEL="$(extract_lsblk_field "$LINE" "LABEL")"
        MOUNT="$(extract_lsblk_field "$LINE" "MOUNTPOINT")"
        AVAILABLE="$(get_mount_available_human "$MOUNT")"

        STATUS="OFF"
        $FIRST && STATUS="ON" && FIRST=false

        RADIOLIST_ARGS+=("$MOUNT" "${NAME}  ${SIZE}  libre:${AVAILABLE}  ${FS}  ${LABEL}" "$STATUS")
    done

    DISK_SELECTED=$(wt \
        --title " Seleccionar disco destino " \
        --radiolist \
        "Espacio necesario aprox.: ${REQUIRED_HUMAN}\nSpace=seleccionar   Enter=confirmar" \
        18 74 8 \
        "${RADIOLIST_ARGS[@]}" \
        3>&1 1>&2 2>&3) || return 1

    DISK_MOUNT="$DISK_SELECTED"

    AVAILABLE_BYTES="$(get_mount_available_bytes "$DISK_MOUNT")"
    AVAILABLE_BYTES="${AVAILABLE_BYTES:-0}"
    if [ "$AVAILABLE_BYTES" -lt "$BACKUP_ESTIMATED_BYTES" ]; then
        wt --title " Espacio insuficiente " \
            --msgbox "\nEspacio insuficiente en el disco seleccionado.\n\nNecesario : ${REQUIRED_HUMAN}\nDisponible: $(format_bytes_human "$AVAILABLE_BYTES")" \
            11 56
        return 1
    fi
}

tui_backup() {
    tui_backup_select_dirs || return 0
    tui_backup_select_disk || return 0

    wt --title " Backup CachyOS " \
        --yesno "\nDestino : $DISK_MOUNT\nNecesario: $(format_bytes_human "$BACKUP_ESTIMATED_BYTES")\n\n¿Iniciar backup?" \
        11 60 || return 0

    BACKUP_TARGET="$DISK_MOUNT"
    _tui_run_with_output "Backup CachyOS" backup_system

    _tui_log_msgbox "Backup completado" "\nBackup completado.\n\n" 11
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------

tui_restore() {
    local SRC=""

    while true; do
        SRC=$(wt \
            --title " Restaurar backup " \
            --inputbox "\nRuta completa del backup a restaurar:" \
            9 64 "$SRC" \
            3>&1 1>&2 2>&3) || return 0

        if [ -z "$SRC" ]; then
            wt --title " Restaurar backup " \
                --msgbox "\nDebes indicar una ruta." 8 44
            continue
        fi

        if [ ! -d "$SRC" ]; then
            wt --title " Restaurar backup " \
                --msgbox "\nRuta no encontrada:\n$SRC\n\nRevisa la ruta e inténtalo de nuevo." \
                11 64
            continue
        fi

        break
    done

    wt --title " Restaurar backup " \
        --yesno "\nFuente : $SRC\n\n¿Iniciar restauración?" \
        10 60 || return 0

    BACKUP_SOURCE="$SRC"
    _tui_run_with_output "Restaurar backup" restore_system

    _tui_log_msgbox "Restore completado" "\nRestore completado.\n\n" 11
}

# ---------------------------------------------------------------------------
# Menú principal
# ---------------------------------------------------------------------------

tui_main_menu() {
    local OPTION
    local TUI_TARGET

    while true; do
        OPTION=$(wt \
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
            1)  tui_backup ;;
            2)  tui_bootstrap ;;
            3)  tui_op "Post-check completado"  post_bootstrap_checks ;;
            4)  tui_restore ;;
            5)  tui_op "MBP Watch desinstalado" uninstall_mbp_watch_diagnostics ;;
            6)  tui_op "Plasmoid desinstalado"  uninstall_mbp_watch_plasmoid ;;
            7)
                TUI_TARGET=$(wt \
                    --title " Reinstalar plasmoid MBP Watch " \
                    --inputbox "\nDestino del plasmoid:" \
                    9 52 "primary" \
                    3>&1 1>&2 2>&3) || continue
                tui_op "Plasmoid reinstalado" reinstall_mbp_watch_plasmoid "${TUI_TARGET:-primary}"
                ;;
            8)
                TUI_TARGET=$(wt \
                    --title " Mover plasmoid MBP Watch " \
                    --inputbox "\nDestino del plasmoid:" \
                    9 52 "primary" \
                    3>&1 1>&2 2>&3) || continue
                tui_op "Plasmoid movido" move_mbp_watch_plasmoid "${TUI_TARGET:-primary}"
                ;;
            9)  tui_op "YouTube H264 instalado" install_youtube_force_h264_package ;;
            10) tui_op "VA-API configurado"     configure_vaapi_brave_broadwell ;;
            11) break ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

tui_bootstrap() {
    local APPLE_DEFAULT="OFF"
    local FACETIME_DEFAULT="OFF"
    local SELECTED
    local TUI_WIFI_COUNTRY=""
    local TUI_BROWSER=""

    is_apple_laptop 2>/dev/null && APPLE_DEFAULT="ON"
    [ "$(detect_facetimehd_camera 2>/dev/null)" = "yes" ] && FACETIME_DEFAULT="ON"

    SELECTED=$(wt \
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
        wt --title " Bootstrap " \
            --msgbox "\nNo se seleccionó ningún bloque." \
            8 44
        return 0
    fi

    # Recoger entradas adicionales antes de empezar, para que el run
    # no necesite llamar a whiptail mientras está siendo piped a dialog.
    if [[ "$SELECTED" == *'"wifi"'* ]]; then
        TUI_WIFI_COUNTRY=$(wt \
            --title " Configurar Wi-Fi " \
            --inputbox "\nCódigo de país para Wi-Fi (ej. ES para España):" \
            9 56 "ES" \
            3>&1 1>&2 2>&3) || return 0
        TUI_WIFI_COUNTRY="$(printf '%s' "$TUI_WIFI_COUNTRY" | tr '[:lower:]' '[:upper:]')"
    fi

    if [[ "$SELECTED" == *'"hwaccel"'* ]]; then
        TUI_BROWSER=$(wt \
            --title " Aceleración HW navegador " \
            --radiolist "Selecciona el navegador a configurar:" \
            10 56 2 \
            "brave"  "Brave Browser"  ON \
            "chrome" "Google Chrome"  OFF \
            3>&1 1>&2 2>&3) || return 0
    fi

    wt --title " Bootstrap CachyOS " \
        --yesno "\nSe ejecutarán los bloques seleccionados.\n¿Continuar?" \
        9 52 || return 0

    _tui_run_with_output "Bootstrap CachyOS" \
        tui_bootstrap_run "$SELECTED" "$TUI_WIFI_COUNTRY" "$TUI_BROWSER"

    _tui_log_msgbox "Bootstrap completado" "\nBootstrap completado.\n\nRecomendado: reiniciar el sistema.\n\n" 13
}

tui_bootstrap_run() {
    local SELECTED="$1"
    TUI_WIFI_COUNTRY="${2:-}"
    TUI_BROWSER="${3:-}"

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

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}BOOTSTRAP COMPLETADO${NC}"
    log "${GREEN}=================================${NC}"
    show_log_location
}
