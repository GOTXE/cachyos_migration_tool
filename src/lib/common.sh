#!/usr/bin/env bash

# shellcheck disable=SC2034

VERSION="1.2.2"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATION_CONFIG_FILE="${MIGRATION_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/linux-migration-tool.conf}"

LOGFILE="${LOGFILE:-$(pwd)/linux_migration_tool_$(date +%Y-%m-%d_%H-%M-%S).log}"
DRY_MODE=false
HYPRLAND_MODE="ask"
APPLE_LAPTOP_MODE="ask"
BACKUP_TARGET=""
BACKUP_SOURCE=""
FORCE_RESTORE=false
AUTO_CONFIRM=false
[ "${AUTO_CONFIRM_ENV:-}" = "1" ] && AUTO_CONFIRM=true
MBP_PLASMOID_TARGET="${MBP_PLASMOID_TARGET:-primary}"

# Identificación de Hardware
MACBOOK_MODEL="unknown"
if [ -r /sys/devices/virtual/dmi/id/product_name ]; then
    MACBOOK_MODEL="$(cat /sys/devices/virtual/dmi/id/product_name | tr -d '[:space:]')"
fi

get_macbook_model() {
    printf '%s\n' "$MACBOOK_MODEL"
}

get_macbook_profile() {
    printf '%s\n' "$MACBOOK_MODEL"
}

get_macbook_profile_id() {
    case "$MACBOOK_MODEL" in
        MacBookPro12,1)
            printf 'mbp12_1\n'
            ;;
        MacBookPro8,1)
            printf 'mbp8_1\n'
            ;;
        *)
            printf 'generic\n'
            ;;
    esac
}

get_macbook_profile_label() {
    case "$(get_macbook_profile_id)" in
        mbp12_1)
            printf 'MacBook Pro Retina 13" 2015\n'
            ;;
        mbp8_1)
            printf 'MacBook Pro 13" Early 2011\n'
            ;;
        *)
            printf 'Perfil genérico\n'
            ;;
    esac
}

get_macbook_profile_traits() {
    case "$(get_macbook_profile_id)" in
        mbp12_1)
            printf '%s\n' 'apple mbp intel broadwell retina2015 facetimehd broadcom-bcm43602'
            ;;
        mbp8_1)
            printf '%s\n' 'apple mbp intel sandybridge retina2011'
            ;;
        *)
            printf '%s\n' 'generic'
            ;;
    esac
}

get_macbook_profile_summary() {
    case "$(get_macbook_profile_id)" in
        mbp12_1)
            printf '%s\n' 'Portátil Apple Intel, cámara FaceTime HD, Wi-Fi Broadcom BCM43602 y gráficos Broadwell.'
            ;;
        mbp8_1)
            printf '%s\n' 'Portátil Apple Intel con gráficos Sandy Bridge y soporte básico de Apple portátil.'
            ;;
        *)
            printf '%s\n' 'Perfil genérico sin extras Apple específicos.'
            ;;
    esac
}

macbook_profile_has_trait() {
    local TRAIT="$1"
    local TRAITS=" $(get_macbook_profile_traits) "

    case "$TRAITS" in
        *" $TRAIT "*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_bootstrap_context_text() {
    local PROFILE_ID=""
    local PROFILE_LABEL=""
    local PROFILE_SUMMARY=""

    PROFILE_LABEL="$(get_macbook_profile_label | tr -d '\n')"
    PROFILE_ID="$(get_macbook_profile_id)"
    PROFILE_SUMMARY="$(get_macbook_profile_summary | tr -d '\n')"

    cat <<EOF
Modelo detectado: $(get_macbook_model)
Perfil aplicado: ${PROFILE_LABEL}
Identificador: ${PROFILE_ID}
Características: ${PROFILE_SUMMARY}
EOF
}

bootstrap_context_report() {
    log_section "Bootstrap Context"
    while IFS= read -r LINE; do
        [ -n "$LINE" ] || continue
        log "$LINE"
    done < <(get_bootstrap_context_text)
}

is_macbook_model() {
    local TARGET_MODEL="$1"
    [[ "$MACBOOK_MODEL" == "$TARGET_MODEL"* ]]
}

EXTRA_CONFIG_ITEMS=()
EXTRA_REPO_SEARCH_DIRS=()
DATA_DIRS=()
SELECTED_DATA_DIRS=()
SELECTED_CONFIG_ITEMS=()
BACKUP_FS_TYPE=""
BACKUP_RSYNC_OPTIONS=()
BACKUP_ESTIMATED_BYTES=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE_BOLD='\033[1;37m'
NC='\033[0m'

log() {
    echo -e "$1"
    echo -e "$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE" 2>/dev/null || true
}

log_phase() {
    log "${YELLOW}$1${NC}"
}

log_info() {
    log "${CYAN}$1${NC}"
}

log_warn() {
    log "${YELLOW}$1${NC}"
}

log_success() {
    log "${GREEN}$1${NC}"
}

tty_available() {
    [ -r /dev/tty ] && [ -w /dev/tty ]
}

tty_log() {
    local MESSAGE="$1"

    if tty_available; then
        echo -e "$MESSAGE" > /dev/tty
    else
        echo -e "$MESSAGE"
    fi

    echo -e "$(echo -e "$MESSAGE" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOGFILE" 2>/dev/null || true
}

prompt_read() {
    local PROMPT_TEXT="$1"
    local __RESULTVAR="$2"
    local INPUT_VALUE=""

    if tty_available; then
        printf "%b" "${MAGENTA}${PROMPT_TEXT}${NC}" > /dev/tty
        read -r INPUT_VALUE < /dev/tty
    else
        printf "%b" "${MAGENTA}${PROMPT_TEXT}${NC}"
        read -r INPUT_VALUE
    fi
    printf -v "$__RESULTVAR" '%s' "$INPUT_VALUE"
}

log_block_progress() {
    local INDEX="$1"
    local TOTAL="$2"
    local LABEL="$3"

    log ""
    log "${BLUE}Bloque ${INDEX}/${TOTAL}:${NC} ${YELLOW}${LABEL}${NC}"
}

log_item_progress() {
    local INDEX="$1"
    local TOTAL="$2"
    local LABEL="$3"

    log " ${BLUE}->${NC} ${GREEN}[$INDEX/$TOTAL]${NC} ${LABEL}"
}

pause() {
    local DUMMY=""
    prompt_read "Pulsa ENTER para continuar... " DUMMY
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        log "${RED}[ERROR] Comando no encontrado: $1${NC}"
        exit 1
    }
}

run_cmd() {
    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] $(printf '%q ' "$@")${NC}"
        return 0
    fi

    log "${CYAN}$${NC} $(printf '%q ' "$@")"
    "$@" 2>&1 | tee -a "$LOGFILE"
    return "${PIPESTATUS[0]}"
}

run_cmd_quiet() {
    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] $(printf '%q ' "$@")${NC}"
        return 0
    fi

    "$@" 2>&1 | tee -a "$LOGFILE"
    return "${PIPESTATUS[0]}"
}

run_shell() {
    local COMMAND="$1"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] $COMMAND${NC}"
        return 0
    fi

    log "${CYAN}$${NC} $COMMAND"
    bash -lc "$COMMAND" 2>&1 | tee -a "$LOGFILE"
    return "${PIPESTATUS[0]}"
}

format_bytes_human() {
    local BYTES="${1:-0}"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$BYTES"
    else
        awk -v bytes="$BYTES" '
            function human(x) {
                split("B KiB MiB GiB TiB PiB", u, " ")
                i = 1
                while (x >= 1024 && i < 6) {
                    x /= 1024
                    i++
                }
                return sprintf("%.1f%s", x, u[i])
            }
            BEGIN { print human(bytes) }
        '
    fi
}

get_mount_available_bytes() {
    local TARGET_PATH="$1"

    df -B1 --output=avail "$TARGET_PATH" 2>/dev/null | tail -n 1 | tr -d '[:space:]'
}

get_mount_available_human() {
    local TARGET_PATH="$1"
    local AVAILABLE_BYTES

    AVAILABLE_BYTES="$(get_mount_available_bytes "$TARGET_PATH")"
    [ -n "$AVAILABLE_BYTES" ] || AVAILABLE_BYTES=0
    format_bytes_human "$AVAILABLE_BYTES"
}

get_path_size_bytes() {
    local TARGET_PATH="$1"

    [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ] || {
        printf '0\n'
        return 0
    }

    du -sb "$TARGET_PATH" 2>/dev/null | awk '{print $1}'
}

get_filesystem_type() {
    local TARGET_PATH="$1"

    findmnt -n -o FSTYPE -T "$TARGET_PATH" 2>/dev/null || true
}

configure_backup_rsync_mode() {
    local TARGET_PATH="$1"

    BACKUP_FS_TYPE="$(get_filesystem_type "$TARGET_PATH")"
    BACKUP_RSYNC_OPTIONS=(-a)

    case "$BACKUP_FS_TYPE" in
        exfat|vfat|msdos|ntfs|ntfs3|fuseblk)
            BACKUP_RSYNC_OPTIONS=(-rltD --copy-links --no-perms --no-owner --no-group)
            log_phase "Destino en $BACKUP_FS_TYPE detectado. Usando modo rsync compatible sin owner/group y copiando symlinks como archivos."
            ;;
    esac
}

build_broken_symlink_excludes() {
    local SOURCE_PATH="$1"
    local BROKEN_LINK
    local RELATIVE_LINK
    local EXCLUDES=()

    [ -e "$SOURCE_PATH" ] || [ -L "$SOURCE_PATH" ] || return 0
    [ -d "$SOURCE_PATH" ] || return 0

    while IFS= read -r -d '' BROKEN_LINK; do
        RELATIVE_LINK="${BROKEN_LINK#"$SOURCE_PATH"/}"

        if [ "$RELATIVE_LINK" != "$BROKEN_LINK" ] && [ -n "$RELATIVE_LINK" ]; then
            EXCLUDES+=("--exclude=$RELATIVE_LINK")
        fi
    done < <(find "$SOURCE_PATH" -xtype l -print0 2>/dev/null)

    if [ ${#EXCLUDES[@]} -gt 0 ]; then
        printf '%s\n' "${EXCLUDES[@]}"
    fi
}

resolve_xdg_dir() {
    local KEY="$1"
    local DEFAULT_PATH="$2"
    local USER_DIRS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    local RAW_VALUE=""

    if [ -r "$USER_DIRS_FILE" ]; then
        RAW_VALUE="$(
            sed -n "s/^${KEY}=\"\\(.*\\)\"$/\\1/p" "$USER_DIRS_FILE" | head -n 1
        )"
    fi

    if [ -n "$RAW_VALUE" ]; then
        RAW_VALUE="${RAW_VALUE//\$HOME/$HOME}"
        printf '%s\n' "$RAW_VALUE"
        return 0
    fi

    if [ -d "$DEFAULT_PATH" ]; then
        printf '%s\n' "$DEFAULT_PATH"
        return 0
    fi

    printf '%s\n' "$DEFAULT_PATH"
}

get_desktop_dir() {
    if [ -n "${XDG_DESKTOP_DIR:-}" ]; then
        printf '%s\n' "${XDG_DESKTOP_DIR//\$HOME/$HOME}"
        return 0
    fi

    resolve_xdg_dir "XDG_DESKTOP_DIR" "$HOME/Desktop"
}

get_documents_dir() {
    if [ -n "${XDG_DOCUMENTS_DIR:-}" ]; then
        printf '%s\n' "${XDG_DOCUMENTS_DIR//\$HOME/$HOME}"
        return 0
    fi

    resolve_xdg_dir "XDG_DOCUMENTS_DIR" "$HOME/Documents"
}

get_pictures_dir() {
    if [ -n "${XDG_PICTURES_DIR:-}" ]; then
        printf '%s\n' "${XDG_PICTURES_DIR//\$HOME/$HOME}"
        return 0
    fi

    resolve_xdg_dir "XDG_PICTURES_DIR" "$HOME/Pictures"
}

get_music_dir() {
    if [ -n "${XDG_MUSIC_DIR:-}" ]; then
        printf '%s\n' "${XDG_MUSIC_DIR//\$HOME/$HOME}"
        return 0
    fi

    resolve_xdg_dir "XDG_MUSIC_DIR" "$HOME/Music"
}

get_videos_dir() {
    if [ -n "${XDG_VIDEOS_DIR:-}" ]; then
        printf '%s\n' "${XDG_VIDEOS_DIR//\$HOME/$HOME}"
        return 0
    fi

    resolve_xdg_dir "XDG_VIDEOS_DIR" "$HOME/Videos"
}

load_user_config() {
    if [ -r "$MIGRATION_CONFIG_FILE" ]; then
        # shellcheck disable=SC1090,SC1091
        . "$MIGRATION_CONFIG_FILE"
    fi
}

append_unique_dir() {
    local ARRAY_NAME="$1"
    local CANDIDATE="$2"
    local -n TARGET_ARRAY="$ARRAY_NAME"
    local ITEM

    [ -n "$CANDIDATE" ] || return 0

    for ITEM in "${TARGET_ARRAY[@]}"; do
        if [ "$ITEM" = "$CANDIDATE" ]; then
            return 0
        fi
    done

    TARGET_ARRAY+=("$CANDIDATE")
}

get_relative_home_path() {
    local ABS_PATH="$1"

    case "$ABS_PATH" in
        "$HOME")
            printf '.\n'
            ;;
        "$HOME"/*)
            printf '%s\n' "${ABS_PATH#"$HOME"/}"
            ;;
        *)
            return 1
            ;;
    esac
}

collect_repo_dirs() {
    local SEARCH_DIRS=()
    local REPO_DIRS=()
    local DATA_DIRS=()
    local DIR
    local GIT_ENTRY
    local REPO_DIR

    mapfile -t SEARCH_DIRS < <(get_repo_search_dirs)
    mapfile -t DATA_DIRS < <(get_data_dirs)

    for DIR in "${DATA_DIRS[@]}"; do
        [ -d "$DIR" ] || continue
        append_unique_dir SEARCH_DIRS "$DIR"
    done

    for DIR in "${SEARCH_DIRS[@]}"; do
        [ -d "$DIR" ] || continue

        while IFS= read -r -d '' GIT_ENTRY; do
            REPO_DIR="$(dirname "$GIT_ENTRY")"
            append_unique_dir REPO_DIRS "$REPO_DIR"
        done < <(find "$DIR" \( -type d -name ".git" -o -type f -name ".git" \) -print0 2>/dev/null)
    done

    if [ ${#REPO_DIRS[@]} -gt 0 ]; then
        printf '%s\n' "${REPO_DIRS[@]}"
    fi
}

estimate_backup_bytes() {
    local TOTAL_BYTES=0
    local CONFIGS=()
    local REPO_DIRS=()
    local ARCHIVE_DIRS=()
    local ITEM
    local REPO_DIR
    local DATA_DIR
    local DATA_BYTES
    local EXCLUDED_BYTES

    mapfile -t CONFIGS < <(get_backup_config_items)
    for ITEM in "${CONFIGS[@]}"; do
        TOTAL_BYTES=$((TOTAL_BYTES + $(get_path_size_bytes "$HOME/$ITEM")))
    done

    mapfile -t REPO_DIRS < <(collect_repo_dirs)
    for REPO_DIR in "${REPO_DIRS[@]}"; do
        TOTAL_BYTES=$((TOTAL_BYTES + $(get_path_size_bytes "$REPO_DIR")))
    done

    mapfile -t ARCHIVE_DIRS < <(get_data_dirs)
    for DATA_DIR in "${ARCHIVE_DIRS[@]}"; do
        [ -d "$DATA_DIR" ] || continue

        DATA_BYTES="$(get_path_size_bytes "$DATA_DIR")"
        EXCLUDED_BYTES=0

        for REPO_DIR in "${REPO_DIRS[@]}"; do
            [ -d "$REPO_DIR" ] || continue

            if [[ "$REPO_DIR" == "$DATA_DIR/"* ]]; then
                EXCLUDED_BYTES=$((EXCLUDED_BYTES + $(get_path_size_bytes "$REPO_DIR")))
            fi
        done

        if [ "$DATA_BYTES" -gt "$EXCLUDED_BYTES" ]; then
            TOTAL_BYTES=$((TOTAL_BYTES + DATA_BYTES - EXCLUDED_BYTES))
        fi
    done

    TOTAL_BYTES=$((TOTAL_BYTES + 50 * 1024 * 1024))

    printf '%s\n' "$TOTAL_BYTES"
}

check_backup_space() {
    local TARGET_PATH="$1"
    local AVAILABLE_BYTES

    AVAILABLE_BYTES="$(get_mount_available_bytes "$TARGET_PATH")"
    [ -n "$AVAILABLE_BYTES" ] || AVAILABLE_BYTES=0

    if [ "$AVAILABLE_BYTES" -lt "$BACKUP_ESTIMATED_BYTES" ]; then
        log "${RED}[ERROR] Espacio insuficiente en destino.${NC}"
        log " Requerido aprox.: $(format_bytes_human "$BACKUP_ESTIMATED_BYTES")"
        log " Libre disponible : $(format_bytes_human "$AVAILABLE_BYTES")"
        exit 1
    fi
}

get_repo_search_dirs() {
    local DOCUMENTS_DIR
    local DIRS=()
    local EXTRA_DIR
    local DEFAULT_REPO_SUBDIR

    DOCUMENTS_DIR="$(get_documents_dir)"

    for DEFAULT_REPO_SUBDIR in \
        "$DOCUMENTS_DIR/GITEA" \
        "$DOCUMENTS_DIR/GITHUB" \
        "$DOCUMENTS_DIR/Prog_Local"
    do
        if [ -d "$DEFAULT_REPO_SUBDIR" ]; then
            append_unique_dir DIRS "$DEFAULT_REPO_SUBDIR"
        fi
    done

    if [ ${#DIRS[@]} -eq 0 ]; then
        append_unique_dir DIRS "$DOCUMENTS_DIR"
        append_unique_dir DIRS "$HOME/Documents"
        append_unique_dir DIRS "$HOME/Documentos"
    fi

    for EXTRA_DIR in "${EXTRA_REPO_SEARCH_DIRS[@]}"; do
        append_unique_dir DIRS "$EXTRA_DIR"
    done

    printf '%s\n' "${DIRS[@]}"
}

get_backup_config_items() {
    local ITEMS=(
        ".ssh"
        ".gnupg"
        ".gitconfig"
        ".bashrc"
        ".profile"
        ".zshrc"
        ".claude"
        ".claude.json"
        ".codex"
        ".neocoding"
        ".config/Code"
        ".vscode"
        ".mozilla"
        ".thunderbird"
        ".kde"
        ".docker"
        ".kube"
        ".npm"
        ".cargo"
        ".rustup"
        ".var/app"
        ".local/share/applications"
        ".local/share/flatpak"
        ".local/share/icons"
        ".config/BraveSoftware"
        ".config/chromium"
        ".config/google-chrome"
        ".config/kde"
        ".config/fish"
    )
    local EXTRA_ITEM
    local SELECTED_FROM_ENV=()

    if [ -n "${SELECTED_CONFIG_ITEMS_RAW:-}" ]; then
        mapfile -t SELECTED_FROM_ENV < <(
            printf '%s\n' "$SELECTED_CONFIG_ITEMS_RAW" |
            sed '/^$/d'
        )

        if [ ${#SELECTED_FROM_ENV[@]} -gt 0 ]; then
            printf '%s\n' "${SELECTED_FROM_ENV[@]}"
            return 0
        fi
    fi

    if [ ${#SELECTED_CONFIG_ITEMS[@]} -gt 0 ]; then
        printf '%s\n' "${SELECTED_CONFIG_ITEMS[@]}"
        return 0
    fi

    for EXTRA_ITEM in "${EXTRA_CONFIG_ITEMS[@]}"; do
        append_unique_dir ITEMS "$EXTRA_ITEM"
    done

    printf '%s\n' "${ITEMS[@]}"
}

backup_config_default_items() {
    printf '%s\n' \
        ".ssh" \
        ".gnupg" \
        ".gitconfig" \
        ".bashrc" \
        ".profile" \
        ".zshrc" \
        ".claude" \
        ".claude.json" \
        ".codex" \
        ".neocoding" \
        ".config/Code" \
        ".vscode"
}

get_data_dirs() {
    local DIRS=()
    local DOCUMENTS_DIR
    local EXTRA_DIR
    local SELECTED_FROM_ENV=()

    if [ -n "${SELECTED_DATA_DIRS_RAW:-}" ]; then
        mapfile -t SELECTED_FROM_ENV < <(
            printf '%s\n' "$SELECTED_DATA_DIRS_RAW" |
            sed '/^$/d'
        )

        if [ ${#SELECTED_FROM_ENV[@]} -gt 0 ]; then
            printf '%s\n' "${SELECTED_FROM_ENV[@]}"
            return 0
        fi
    fi

    if [ ${#SELECTED_DATA_DIRS[@]} -gt 0 ]; then
        printf '%s\n' "${SELECTED_DATA_DIRS[@]}"
        return 0
    fi

    DOCUMENTS_DIR="$(get_documents_dir)"
    append_unique_dir DIRS "$DOCUMENTS_DIR"

    for EXTRA_DIR in "${DATA_DIRS[@]}"; do
        append_unique_dir DIRS "$EXTRA_DIR"
    done

    printf '%s\n' "${DIRS[@]}"
}

dir_has_content() {
    local TARGET_DIR="$1"

    [ -d "$TARGET_DIR" ] || return 1
    find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
}

is_standard_home_dir() {
    local DIR_PATH="$1"
    local STANDARD_DIRS=()
    local STANDARD_DIR

    STANDARD_DIRS=(
        "$(get_desktop_dir)"
        "$(get_documents_dir)"
        "$(get_pictures_dir)"
        "$(get_music_dir)"
        "$(get_videos_dir)"
        "$HOME/Downloads"
        "$HOME/Descargas"
        "$HOME/Escritorio"
        "$HOME/Documentos"
        "$HOME/Imágenes"
        "$HOME/Música"
        "$HOME/Vídeos"
        "$HOME/Pictures"
        "$HOME/Music"
        "$HOME/Videos"
    )

    for STANDARD_DIR in "${STANDARD_DIRS[@]}"; do
        [ -n "$STANDARD_DIR" ] || continue
        if [ "$DIR_PATH" = "$STANDARD_DIR" ]; then
            return 0
        fi
    done

    return 1
}

detect_backup_data_candidates() {
    local CANDIDATES=()
    local DOCUMENTS_DIR
    local PICTURES_DIR
    local MUSIC_DIR
    local VIDEOS_DIR
    local HOME_ITEM
    local ROOT_ITEM
    local BASENAME

    DOCUMENTS_DIR="$(get_documents_dir)"
    PICTURES_DIR="$(get_pictures_dir)"
    MUSIC_DIR="$(get_music_dir)"
    VIDEOS_DIR="$(get_videos_dir)"

    for HOME_ITEM in "$DOCUMENTS_DIR" "$PICTURES_DIR" "$MUSIC_DIR" "$VIDEOS_DIR"; do
        if dir_has_content "$HOME_ITEM"; then
            append_unique_dir CANDIDATES "$HOME_ITEM"
        fi
    done

    for HOME_ITEM in "$HOME"/*; do
        [ -e "$HOME_ITEM" ] || continue
        [ -d "$HOME_ITEM" ] || continue
        BASENAME="$(basename "$HOME_ITEM")"
        [[ "$BASENAME" == .* ]] && continue

        if is_standard_home_dir "$HOME_ITEM"; then
            continue
        fi

        if dir_has_content "$HOME_ITEM"; then
            append_unique_dir CANDIDATES "$HOME_ITEM"
        fi
    done

    for ROOT_ITEM in /*; do
        [ -e "$ROOT_ITEM" ] || continue
        [ -d "$ROOT_ITEM" ] || continue

        case "$ROOT_ITEM" in
            /bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/lost+found|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
                continue
                ;;
        esac

        if [ "$(stat -c '%u' "$ROOT_ITEM" 2>/dev/null || printf '0')" != "$(id -u)" ]; then
            continue
        fi

        if dir_has_content "$ROOT_ITEM"; then
            append_unique_dir CANDIDATES "$ROOT_ITEM"
        fi
    done

    printf '%s\n' "${CANDIDATES[@]}"
}

backup_data_catalog() {
    local CANDIDATES=()
    local DEFAULT_SELECTED=()
    local CANDIDATE

    mapfile -t CANDIDATES < <(detect_backup_data_candidates)
    mapfile -t DEFAULT_SELECTED < <(get_data_dirs)

    for CANDIDATE in "${CANDIDATES[@]}"; do
        if printf '%s\n' "${DEFAULT_SELECTED[@]}" | grep -Fxq "$CANDIDATE"; then
            printf '%s|%s|ON\n' "$CANDIDATE" "$CANDIDATE"
        else
            printf '%s|%s|OFF\n' "$CANDIDATE" "$CANDIDATE"
        fi
    done
}

backup_config_catalog() {
    local CANDIDATES=()
    local CANDIDATE
    local DEFAULT_SELECTED=()

    mapfile -t CANDIDATES < <(get_backup_config_items)
    mapfile -t DEFAULT_SELECTED < <(backup_config_default_items)

    for CANDIDATE in "${CANDIDATES[@]}"; do
        if printf '%s\n' "${DEFAULT_SELECTED[@]}" | grep -Fxq "$CANDIDATE"; then
            printf '%s|%s|ON\n' "$CANDIDATE" "$CANDIDATE"
        else
            printf '%s|%s|OFF\n' "$CANDIDATE" "$CANDIDATE"
        fi
    done
}

ask_backup_data_dirs() {
    local CANDIDATES=()
    local SELECTION_RAW
    local SELECTED_INDEX
    local INDEX=1
    local CANDIDATE
    local DEFAULT_SELECTED=()
    local TOKEN

    mapfile -t CANDIDATES < <(detect_backup_data_candidates)

    if [ ${#CANDIDATES[@]} -eq 0 ]; then
        return 0
    fi

    log "${BLUE}Directorios de datos detectados para backup:${NC}"
    for CANDIDATE in "${CANDIDATES[@]}"; do
        log "${BLUE}[$INDEX]${NC} $CANDIDATE"
        INDEX=$((INDEX+1))
    done
    log ""
    log "Selecciona numeros separados por comas."
    log "ENTER = seleccion por defecto actual."

    mapfile -t DEFAULT_SELECTED < <(get_data_dirs)
    log "Por defecto:"
    for CANDIDATE in "${DEFAULT_SELECTED[@]}"; do
        log " ${GREEN}-${NC} $CANDIDATE"
    done
    log ""

    prompt_read "Directorios de datos a incluir: " SELECTION_RAW

    if [ -z "$SELECTION_RAW" ]; then
        SELECTED_DATA_DIRS=("${DEFAULT_SELECTED[@]}")
        return 0
    fi

    SELECTED_DATA_DIRS=()
    IFS=',' read -ra TOKENS <<< "$SELECTION_RAW"
    for TOKEN in "${TOKENS[@]}"; do
        TOKEN="${TOKEN//[[:space:]]/}"
        [[ "$TOKEN" =~ ^[0-9]+$ ]] || continue
        SELECTED_INDEX=$((TOKEN-1))
        if [ "$SELECTED_INDEX" -ge 0 ] && [ "$SELECTED_INDEX" -lt ${#CANDIDATES[@]} ]; then
            append_unique_dir SELECTED_DATA_DIRS "${CANDIDATES[$SELECTED_INDEX]}"
        fi
    done

    if [ ${#SELECTED_DATA_DIRS[@]} -eq 0 ]; then
        log "${RED}[ERROR] No se selecciono ningun directorio valido.${NC}"
        exit 1
    fi
}

extract_lsblk_field() {
    local LINE="$1"
    local KEY="$2"

    sed -n "s/.*${KEY}=\"\\([^\"]*\\)\".*/\\1/p" <<< "$LINE"
}

parse_user_ids() {
    local FILE="$1"

    OLD_UID=""
    OLD_GID=""

    while IFS='=' read -r KEY VALUE; do
        case "$KEY" in
            UID)
                OLD_UID="$VALUE"
                ;;
            GID)
                OLD_GID="$VALUE"
                ;;
        esac
    done < "$FILE"

    if [ -z "$OLD_UID" ] || [ -z "$OLD_GID" ]; then
        log "${RED}Metadata de UID/GID invalida.${NC}"
        exit 1
    fi
}

log_section() {
    log ""
    log "${BLUE}=================================${NC}"
    log "${BLUE}$1${NC}"
    log "${BLUE}=================================${NC}"
}

show_log_location() {
    log ""
    log "Log de esta ejecucion:"
    log "$LOGFILE"
}

confirm_action() {
    local PROMPT="$1"
    local DEFAULT_ANSWER="${2:-no}"
    local RESPONSE
    local HINT="s/n"

    if [ "$AUTO_CONFIRM" = true ]; then
        log "${CYAN}[auto] $PROMPT → sí${NC}"
        return 0
    fi

    case "$DEFAULT_ANSWER" in
        yes|s|S)
            HINT="S/n"
            ;;
        no|n|N)
            HINT="s/N"
            ;;
    esac

    while true; do
        prompt_read "$PROMPT [$HINT]: " RESPONSE
        RESPONSE="${RESPONSE:-$DEFAULT_ANSWER}"
        case "$RESPONSE" in
            s|S|si|SI|sí|Sí|yes|YES|y|Y)
                return 0
                ;;
            n|N|no|NO)
                return 1
                ;;
            *)
                log_warn "Respuesta no valida. Escribe 's' para si o 'n' para no."
                ;;
        esac
    done
}

restore_conflicts_exist() {
    [ -d "$BACKUP_DIR/configs" ] || return 1

    while IFS= read -r -d '' ITEM; do
        local RELATIVE

        RELATIVE="${ITEM#"$BACKUP_DIR/configs/"}"

        if [ -e "$HOME/$RELATIVE" ]; then
            return 0
        fi
    done < <(find "$BACKUP_DIR/configs" -mindepth 1 -maxdepth 1 -print0)

    return 1
}

is_apple_laptop() {
    local SYS_VENDOR=""

    [ -r /sys/devices/virtual/dmi/id/sys_vendor ] &&
        SYS_VENDOR="$(< /sys/devices/virtual/dmi/id/sys_vendor)"

    [[ "$SYS_VENDOR" == "Apple Inc." ]] &&
        [[ "$MACBOOK_MODEL" == MacBook* ]]
}

get_bootstrap_checklist_items() {
    local APPLE_DEFAULT="OFF"
    local FACETIME_DEFAULT="OFF"
    local HWACCEL_VISIBLE=false
    local VAAPI_VISIBLE=false
    local VAAPI_LABEL="VA-API Brave/Chromium (Intel)"
    local GPU_PROFILE=""

    if macbook_profile_has_trait apple; then
        APPLE_DEFAULT="ON"
    fi

    if command -v detect_facetimehd_camera >/dev/null 2>&1 \
        && [ "$(detect_facetimehd_camera 2>/dev/null || true)" = "yes" ]; then
        FACETIME_DEFAULT="ON"
    fi

    if command -v detect_gpu_profile >/dev/null 2>&1; then
        GPU_PROFILE="$(detect_gpu_profile 2>/dev/null || true)"
        case "$GPU_PROFILE" in
            amd|nvidia)
                HWACCEL_VISIBLE=true
                ;;
            intel*)
                VAAPI_VISIBLE=true
                ;;
        esac
    fi

    case "$(get_macbook_profile_id)" in
        mbp12_1)
            VAAPI_VISIBLE=true
            VAAPI_LABEL="VA-API Brave/Chromium (Intel Broadwell)"
            ;;
        mbp8_1)
            VAAPI_VISIBLE=true
            VAAPI_LABEL="VA-API Brave/Chromium (Intel Sandy Bridge)"
            ;;
    esac

    cat <<EOF
sync|Sincronización y actualización sistema|ON
base_dev|Herramientas base desarrollo (git, go)|OFF
yay|AUR helper (yay)|ON
flatpak|Soporte Flatpak + Flathub|ON
official|Paquetes oficiales de repositorio|ON
kde|Aplicaciones base KDE Plasma|ON
aur|Paquetes adicionales desde AUR|ON
handy|Handy (speech-to-text offline, AUR)|OFF
docker_svc|Configuración servicio Docker|OFF
zsh|Oh My Zsh + Powerlevel10k|ON
node|Stack Node / pnpm / bun|ON
ai_codex|Codex CLI (@openai/codex)|OFF
ai_claude|Claude Code CLI (nativo)|OFF
ai_gemini|Gemini CLI (@google/gemini-cli)|OFF
ai_opencode|OpenCode CLI|OFF
youtube|YouTube Force H264|OFF
iwd|iwd backend para NetworkManager|OFF
hyprland|Hyprland|OFF
wifi|Configurar país/región Wi-Fi|OFF
globalmenu|Global Menu KDE (GTK + VS Code)|OFF
EOF

    if macbook_profile_has_trait apple; then
        printf '%s\n' "mbpwatch|MBP Watch diagnóstico (systemd)|OFF"
        printf '%s\n' "plasmoid|Plasmoid KDE MBP Watch|OFF"
        printf '%s\n' "apple|Apple laptop extras|${APPLE_DEFAULT}"
    fi

    if macbook_profile_has_trait apple && macbook_profile_has_trait facetimehd && [ "$FACETIME_DEFAULT" = "ON" ]; then
        printf '%s\n' "facetime|FaceTime HD camera (AUR)|${FACETIME_DEFAULT}"
    fi

    if [ "$HWACCEL_VISIBLE" = true ]; then
        printf '%s\n' "hwaccel|Aceleración HW Chromium/Brave|OFF"
    fi

    if [ "$VAAPI_VISIBLE" = true ]; then
        printf '%s\n' "vaapi|${VAAPI_LABEL}|OFF"
    fi

    cat <<'EOF'
btrfs|Snapshots BTRFS (Snapper)|OFF
EOF
}

bootstrap_test_report() {
    local CHECKLIST_LINE=""

    bootstrap_context_report
    log "Bloques visibles:"

    while IFS= read -r CHECKLIST_LINE; do
        [ -n "$CHECKLIST_LINE" ] || continue
        log " - ${CHECKLIST_LINE#*|}"
    done < <(get_bootstrap_checklist_items)
}

print_main_menu_intro() {
    log "${BLUE}=================================${NC}"
    log "${BLUE}Informacion rapida${NC}"
    log "${BLUE}=================================${NC}"
    log "${RED}IMPORTANTE:${NC} antes de instalar CachyOS o tocar particiones,"
    log "${RED}haz una imagen completa del disco con Rescuezilla o Clonezilla.${NC}"
    log "${RED}Este script hace backup selectivo de datos y configuracion,${NC}"
    log "${RED}pero no sustituye un backup completo para volver atras.${NC}"
    log ""
    log "${YELLOW}Comportamiento general:${NC}"
    log " - Backup detecta directorios con contenido en tu home."
    log " - Los directorios estandar XDG suelen aparecer por defecto."
    log " - Directorios extra conviene fijarlos en config."
    log ""
    log "${YELLOW}Configuracion recomendada:${NC}"
    log " - Archivo: ${GREEN}${MIGRATION_CONFIG_FILE}${NC}"
    log " - Ejemplo base: ${GREEN}$PROJECT_ROOT/linux-migration-tool.conf.example${NC}"
    log " - Variables utiles: ${GREEN}DATA_DIRS${NC}, ${GREEN}EXTRA_REPO_SEARCH_DIRS${NC}, ${GREEN}EXTRA_CONFIG_ITEMS${NC}"
    log ""
    log "${YELLOW}Ejemplos de uso por CLI:${NC}"
    log " - ${GREEN}./migration.sh backup --dry-run${NC}"
    log " - ${GREEN}./migration.sh backup --target /ruta/al/disco${NC}"
    log " - ${GREEN}./migration.sh restore --source /ruta/al/backup --dry-run${NC}"
    log " - ${GREEN}./migration.sh bootstrap --dry-run${NC}"
    log ""
}

select_disk() {
    local REQUIRED_HUMAN
    local DISKS=()
    local LINE
    local MOUNTPOINT
    local INDEX=1
    local DISK
    local AVAILABLE_HUMAN

    BACKUP_ESTIMATED_BYTES="$(estimate_backup_bytes)"
    REQUIRED_HUMAN="$(format_bytes_human "$BACKUP_ESTIMATED_BYTES")"

    mapfile -t DISKS < <(
        lsblk -P -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,TRAN |
        while IFS= read -r LINE; do
            local FSTYPE
            MOUNTPOINT="$(extract_lsblk_field "$LINE" "MOUNTPOINT")"
            FSTYPE="$(extract_lsblk_field "$LINE" "FSTYPE")"

            if [ -n "$MOUNTPOINT" ] &&
               [ "$MOUNTPOINT" != "/" ] &&
               [[ ! "$MOUNTPOINT" =~ ^/boot ]] &&
               [ "${FSTYPE,,}" != "swap" ]; then
                printf '%s\n' "$LINE"
            fi
        done
    )

    if [ ${#DISKS[@]} -eq 0 ]; then
        log "${RED}No se encontraron discos montados.${NC}"
        exit 1
    fi

    log "${BLUE}Discos disponibles:${NC}"
    log "Espacio estimado necesario: ${GREEN}${REQUIRED_HUMAN}${NC}"
    log ""

    for DISK in "${DISKS[@]}"; do
        NAME="$(extract_lsblk_field "$DISK" "NAME")"
        SIZE="$(extract_lsblk_field "$DISK" "SIZE")"
        FS="$(extract_lsblk_field "$DISK" "FSTYPE")"
        LABEL="$(extract_lsblk_field "$DISK" "LABEL")"
        MOUNT="$(extract_lsblk_field "$DISK" "MOUNTPOINT")"
        TRAN="$(extract_lsblk_field "$DISK" "TRAN")"
        AVAILABLE_HUMAN="$(get_mount_available_human "$MOUNT")"

        log "${BLUE}[$INDEX]${NC}"
        log " ${YELLOW}Device${NC} : $NAME"
        log " ${YELLOW}Size${NC}   : $SIZE"
        log " ${GREEN}Free${NC}   : $AVAILABLE_HUMAN"
        log " ${YELLOW}FS${NC}     : $FS"
        log " ${YELLOW}Label${NC}  : $LABEL"
        log " ${YELLOW}Mount${NC}  : $MOUNT"
        log " ${YELLOW}Type${NC}   : $TRAN"
        log ""

        INDEX=$((INDEX+1))
    done

    prompt_read "Selecciona disco destino: " SELECTION

    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
        log "${RED}Seleccion invalida.${NC}"
        exit 1
    fi

    SELECTED="${DISKS[$((SELECTION-1))]}"

    if [ -z "${SELECTED:-}" ]; then
        log "${RED}Seleccion invalida.${NC}"
        exit 1
    fi

    DISK_MOUNT="$(extract_lsblk_field "$SELECTED" "MOUNTPOINT")"
    check_backup_space "$DISK_MOUNT"
}

load_user_config
