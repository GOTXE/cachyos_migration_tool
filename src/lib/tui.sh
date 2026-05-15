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

# Ejecuta "$@" en modo "pantalla de ejecución":
# limpia la pantalla, muestra cabecera, deja correr el output en el terminal
# y espera ENTER antes de volver al menú whiptail.
# Sin dependencias externas: solo bash + ANSI.
_tui_run_with_output() {
    local TITLE="$1"
    shift
    local COLS
    COLS="$(tput cols 2>/dev/null || echo 78)"
    local LINE
    printf -v LINE '%*s' "$COLS" ''
    LINE="${LINE// /━}"

    clear
    printf '\033[1;36m%s\033[0m\n' "$LINE"
    printf '\033[1;36m  %s\033[0m\n' "$TITLE"
    printf '\033[1;36m%s\033[0m\n\n' "$LINE"

    ("$@") 2>&1 || true

    printf '\n\033[1;36m%s\033[0m\n' "$LINE"
    printf '\033[1;32m  Operación completada. Pulsa ENTER para volver al menú.\033[0m\n'
    printf '\033[1;36m%s\033[0m\n' "$LINE"
    read -r _ < /dev/tty
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

bootstrap_checklist_catalog() {
    local -n OUT_ITEMS="$1"
    local -n OUT_DEFAULTS="$2"
    local CATALOG=()
    local LINE=""
    local TAG=""
    local LABEL=""
    local DEFAULT=""
    local STATUS="OFF"
    local INDEX=1

    mapfile -t CATALOG < <(get_bootstrap_checklist_items)

    for LINE in "${CATALOG[@]}"; do
        IFS='|' read -r TAG LABEL DEFAULT <<< "$LINE"
        [ -n "$TAG" ] || continue
        [ "$DEFAULT" = "ON" ] && STATUS="ON" || STATUS="OFF"
        OUT_ITEMS+=("$TAG" "${INDEX}. ${LABEL}" "$STATUS")
        [ "$DEFAULT" = "ON" ] && OUT_DEFAULTS+=("$TAG")
        INDEX=$((INDEX + 1))
    done
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

_tui_is_backup_dir() {
    local PATH_TO_CHECK="$1"
    [ -d "$PATH_TO_CHECK" ] && [ -f "$PATH_TO_CHECK/metadata/user_ids.conf" ]
}

_tui_effective_user() {
    printf '%s\n' "${SUDO_USER:-${USER:-$(id -un 2>/dev/null || true)}}"
}

tui_collect_restore_roots() {
    local USER_NAME
    USER_NAME="$(_tui_effective_user)"

    {
        [ -d "/run/media/$USER_NAME" ] && printf '%s\n' "/run/media/$USER_NAME"
        [ -d "/media/$USER_NAME" ] && printf '%s\n' "/media/$USER_NAME"
        [ -d "/mnt" ] && printf '%s\n' "/mnt"
        [ -d "/run/media" ] && printf '%s\n' "/run/media"
        [ -d "/media" ] && printf '%s\n' "/media"

        lsblk -P -o MOUNTPOINT 2>/dev/null | while IFS= read -r LINE; do
            local MP
            MP="$(extract_lsblk_field "$LINE" "MOUNTPOINT")"
            if [ -n "$MP" ] && [ "$MP" != "/" ] && [[ ! "$MP" =~ ^/boot ]]; then
                printf '%s\n' "$MP"
            fi
        done
    } | awk 'NF && !seen[$0]++'
}

tui_find_restore_backups() {
    local ROOTS=()
    local ROOT

    mapfile -t ROOTS < <(tui_collect_restore_roots)

    for ROOT in "${ROOTS[@]}"; do
        [ -d "$ROOT" ] || continue
        find "$ROOT" -maxdepth 5 -type f -path "*/metadata/user_ids.conf" 2>/dev/null | while IFS= read -r FILE; do
            dirname "$(dirname "$FILE")"
        done
    done | awk 'NF && !seen[$0]++' | sort -r
}

tui_browse_directory() {
    local TITLE="$1"
    local START_PATH="$2"
    local CURRENT="${START_PATH:-/}"
    local START="$CURRENT"
    local CHOICE=""
    local MANUAL=""
    local PARENT=""
    local MENU_ARGS=()
    local ENTRY=""

    while true; do
        CURRENT="$(realpath -m "$CURRENT")"
        PARENT="$(dirname "${CURRENT%/}")"
        [ -n "$PARENT" ] || PARENT="/"
        [ "$CURRENT" = "/" ] && PARENT="/"

        MENU_ARGS=()
        MENU_ARGS+=("__use__" "[*] Usar esta ruta: $CURRENT")
        if [ "$CURRENT" != "/" ]; then
            MENU_ARGS+=("__up__" "../")
        fi

        while IFS= read -r ENTRY; do
            [ -n "$ENTRY" ] || continue
            MENU_ARGS+=("$ENTRY" "$(basename "$ENTRY")/")
        done < <(
            find "$CURRENT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
        )

        MENU_ARGS+=("__manual__" "Escribir ruta manualmente")

        CHOICE=$(wt \
            --title "$TITLE" \
            --menu "Ruta actual: $CURRENT\n\nENTER abre carpeta   ESC vuelve atrás/cancela" \
            22 78 14 \
            "${MENU_ARGS[@]}" \
            3>&1 1>&2 2>&3) || {
                if [ "$CURRENT" != "$START" ]; then
                    CURRENT="$PARENT"
                    continue
                fi
                return 1
            }

        case "$CHOICE" in
            __use__)
                printf '%s\n' "$CURRENT"
                return 0
                ;;
            __up__)
                CURRENT="$PARENT"
                ;;
            __manual__)
                MANUAL=$(wt \
                    --title "$TITLE" \
                    --inputbox "\nEscribe la ruta:" \
                    9 64 "$CURRENT" \
                    3>&1 1>&2 2>&3) || continue
                MANUAL="$(realpath -m "$MANUAL")"
                if [ -d "$MANUAL" ]; then
                    CURRENT="$MANUAL"
                else
                    wt --title "$TITLE" \
                        --msgbox "\nLa ruta no existe o no es un directorio:\n$MANUAL" \
                        10 68
                fi
                ;;
            *)
                if [ -d "$CHOICE" ]; then
                    CURRENT="$CHOICE"
                else
                    wt --title "$TITLE" \
                        --msgbox "\nNo es un directorio válido:\n$CHOICE" \
                        10 68
                fi
                ;;
        esac
    done
}

tui_choose_restore_source() {
    local DETECTED=()
    local ROOTS=()
    local MENU_ARGS=()
    local CHOICE=""
    local SRC=""
    local INDEX=0

    mapfile -t DETECTED < <(tui_find_restore_backups)
    mapfile -t ROOTS < <(tui_collect_restore_roots)

    while true; do
        MENU_ARGS=()
        for INDEX in "${!DETECTED[@]}"; do
            MENU_ARGS+=("b$INDEX" "Backup detectado: $(basename "${DETECTED[$INDEX]}")  [${DETECTED[$INDEX]}]")
        done
        MENU_ARGS+=("manual" "Escribir ruta manualmente")
        for INDEX in "${!ROOTS[@]}"; do
            MENU_ARGS+=("r$INDEX" "Explorar ${ROOTS[$INDEX]}")
        done
        MENU_ARGS+=("root" "Navegar desde /")

        CHOICE=$(wt \
            --title " Selecciona el origen del backup " \
            --menu "\nSelecciona dónde está la copia a restaurar:" \
            24 92 16 \
            "${MENU_ARGS[@]}" \
            3>&1 1>&2 2>&3) || return 1

        case "$CHOICE" in
            b*)
                INDEX="${CHOICE#b}"
                SRC="${DETECTED[$INDEX]}"
                ;;
            manual)
                SRC=$(wt \
                    --title " Selecciona el origen del backup " \
                    --inputbox "\nRuta del backup a restaurar:" \
                    9 64 "" \
                    3>&1 1>&2 2>&3) || continue
                SRC="$(realpath -m "$SRC")"
                ;;
            r*)
                INDEX="${CHOICE#r}"
                SRC="$(tui_browse_directory " Selecciona el origen del backup " "${ROOTS[$INDEX]}")" || continue
                ;;
            root)
                SRC="$(tui_browse_directory " Selecciona el origen del backup " "/")" || continue
                ;;
            *)
                continue
                ;;
        esac

        if _tui_is_backup_dir "$SRC"; then
            printf '%s\n' "$SRC"
            return 0
        fi

        wt --title " Selecciona el origen del backup " \
            --msgbox "\nLa ruta seleccionada no parece una copia válida.\n\nDebe contener:\nmetadata/user_ids.conf\n\nRuta:\n$SRC" \
            14 72
    done
}

tui_restore() {
    local SRC=""

    SRC="$(tui_choose_restore_source)" || return 0

    wt --title " Restaurar backup " \
        --yesno "\nFuente : $SRC\n\n¿Iniciar restauración?" \
        10 60 || return 0

    BACKUP_SOURCE="$SRC"
    _tui_run_with_output "Restaurar backup" restore_system

    _tui_log_msgbox "Restore completado" "\nRestore completado.\n\n" 11
}

tui_watch_plasmoid_menu() {
    local OPTION
    local TUI_TARGET

    while true; do
        OPTION=$(wt \
            --title " MBP Watch y plasmoid " \
            --menu "\nSelecciona una operación:" \
            22 72 10 \
            "s1" "──────── MBP Watch ────────" \
            "1" "Instalar sistema MBP Watch" \
            "2" "Desinstalar sistema MBP Watch" \
            "s2" "──────── Plasmoid MBP Watch ────────" \
            "3" "Añadir widget al escritorio" \
            "4" "Widget en pantalla..." \
            "5" "Reinstalar widget MBP Watch" \
            "6" "Quitar widget MBP Watch" \
            "7" "Atrás" \
            3>&1 1>&2 2>&3) || return 0

        case "$OPTION" in
            s1|s2) continue ;;
            1)
                tui_op "Sistema MBP Watch instalado" install_mbp_watch_diagnostics
                ;;
            2)
                tui_op "Sistema MBP Watch desinstalado" uninstall_mbp_watch_diagnostics
                ;;
            3)
                TUI_TARGET=$(wt \
                    --title " Añadir widget al escritorio " \
                    --inputbox "\nPantalla del widget [primary|screen:N]:" \
                    9 58 "primary" \
                    3>&1 1>&2 2>&3) || continue
                tui_op "Widget añadido" add_mbp_plasmoid_to_desktop "${TUI_TARGET:-primary}"
                ;;
            4)
                TUI_TARGET=$(wt \
                    --title " Widget en pantalla... " \
                    --inputbox "\nPantalla del widget [primary|screen:N]:" \
                    9 58 "primary" \
                    3>&1 1>&2 2>&3) || continue
                tui_op "Widget movido" move_mbp_watch_plasmoid "${TUI_TARGET:-primary}"
                ;;
            5)
                TUI_TARGET=$(wt \
                    --title " Reinstalar widget MBP Watch " \
                    --inputbox "\nPantalla del widget [primary|screen:N]:" \
                    9 58 "primary" \
                    3>&1 1>&2 2>&3) || continue
                tui_op "Widget reinstalado" reinstall_mbp_watch_plasmoid "${TUI_TARGET:-primary}"
                ;;
            6) tui_op "Widget quitado" uninstall_mbp_watch_plasmoid ;;
            7) return 0 ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Menú principal
# ---------------------------------------------------------------------------

tui_main_menu() {
    local OPTION
    local TUI_TARGET

    while true; do
        OPTION=$(wt \
            --title " Linux Migration Tool v${VERSION}  [whiptail] " \
            --menu "\nSelecciona una operación:" \
            18 64 9 \
            "1"  "Backup sistema" \
            "2"  "Bootstrap CachyOS" \
            "3"  "Post-check tras reinicio" \
            "4"  "Restaurar backup" \
            "5"  "MBP Watch y plasmoid" \
            "6"  "Salir" \
            3>&1 1>&2 2>&3) || break

        case "$OPTION" in
            1)  tui_backup ;;
            2)  tui_bootstrap ;;
            3)  tui_op "Post-check completado"  post_bootstrap_checks ;;
            4)  tui_restore ;;
            5)  tui_watch_plasmoid_menu ;;
            6) break ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

tui_bootstrap() {
    local CHECKLIST_ITEMS=()
    local CHECKLIST_DEFAULTS=()
    local SELECTED
    local TUI_WIFI_COUNTRY=""
    local TUI_BROWSER=""
    local BOOTSTRAP_CONTEXT=""

    bootstrap_checklist_catalog CHECKLIST_ITEMS CHECKLIST_DEFAULTS
    BOOTSTRAP_CONTEXT="$(get_bootstrap_context_text)"

    wt --title " Bootstrap CachyOS " \
        --msgbox "\n${BOOTSTRAP_CONTEXT}\n\nEl listado se filtrará según este perfil.\n\nENTER = Aceptar   ESC = Cancelar" \
        11 64

    SELECTED=$(wt \
        --title " Bootstrap CachyOS " \
        --checklist \
        "Space=marcar/desmarcar   Flechas=navegar   Enter=confirmar   ESC=Atrás" \
        28 72 18 \
        "${CHECKLIST_ITEMS[@]}" \
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

    [[ "$SELECTED" == *'"sync"'* ]]        && update_system_repos
    [[ "$SELECTED" == *'"base_dev"'* ]]    && install_base_devel
    [[ "$SELECTED" == *'"yay"'* ]]         && install_yay
    [[ "$SELECTED" == *'"flatpak"'* ]]     && install_flatpak
    [[ "$SELECTED" == *'"official"'* ]]    && install_official_packages
    [[ "$SELECTED" == *'"kde"'* ]]         && install_kde_packages
    [[ "$SELECTED" == *'"aur"'* ]]         && install_aur_packages
    [[ "$SELECTED" == *'"docker_svc"'* ]]  && setup_docker
    [[ "$SELECTED" == *'"zsh"'* ]]         && { install_ohmyzsh; install_powerlevel10k; }
    [[ "$SELECTED" == *'"node"'* ]]        && install_node_stack
    [[ "$SELECTED" == *'"ai_codex"'* ]]    && install_codex_cli
    [[ "$SELECTED" == *'"ai_claude"'* ]]   && install_claude_cli
    [[ "$SELECTED" == *'"ai_gemini"'* ]]   && install_gemini_cli
    [[ "$SELECTED" == *'"ai_opencode"'* ]] && install_opencode_cli

    if [[ "$SELECTED" == *'"ai_codex"'* || "$SELECTED" == *'"ai_claude"'* || "$SELECTED" == *'"ai_gemini"'* || "$SELECTED" == *'"ai_opencode"'* ]]; then
        configure_shell_paths
        verify_ai_tools
    fi

    [[ "$SELECTED" == *'"mbpwatch"'* ]]    && install_mbp_watch_diagnostics
    [[ "$SELECTED" == *'"plasmoid"'* ]]    && install_mbp_plasmoid_if_accepted
    [[ "$SELECTED" == *'"youtube"'* ]]     && install_youtube_force_h264_package
    [[ "$SELECTED" == *'"apple"'* ]]       && install_apple_laptop_extras
    [[ "$SELECTED" == *'"facetime"'* ]]    && configure_facetimehd_camera
    [[ "$SELECTED" == *'"iwd"'* ]]         && configure_networkmanager_iwd_backend
    [[ "$SELECTED" == *'"hyprland"'* ]]    && install_hyprland
    [[ "$SELECTED" == *'"wifi"'* ]]        && configure_wifi_regulatory_domain
    [[ "$SELECTED" == *'"globalmenu"'* ]]  && configure_global_menu_support
    [[ "$SELECTED" == *'"hwaccel"'* ]]     && configure_chromium_hw_acceleration
    [[ "$SELECTED" == *'"vaapi"'* ]]       && configure_vaapi_brave_broadwell
    [[ "$SELECTED" == *'"btrfs"'* ]]       && configure_btrfs_snapshots

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}BOOTSTRAP COMPLETADO${NC}"
    log "${GREEN}=================================${NC}"
    show_log_location
}
