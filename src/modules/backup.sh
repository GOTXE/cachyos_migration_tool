#!/usr/bin/env bash

run_backup_rsync() {
    local LABEL="$1"
    shift
    local RC=0

    if run_cmd_quiet "$@"; then
        return 0
    else
        RC=$?
    fi
    case "$RC" in
        23|24)
            BACKUP_WARNING_COUNT=$((BACKUP_WARNING_COUNT + 1))
            log_warn "[WARN] Copia con avisos en: $LABEL (rsync code $RC)"
            if [ -n "${BACKUP_WARNING_LOG:-}" ]; then
                printf '%s | rsync code %s\n' "$LABEL" "$RC" >> "$BACKUP_WARNING_LOG"
            fi
            return 0
            ;;
        *)
            return "$RC"
            ;;
    esac
}

# Etiqueta del equipo para el nombre de la carpeta (ADR-002 D2).
backup_host_label() {
    local LABEL="${BACKUP_HOST_LABEL:-}"

    if [ -z "$LABEL" ]; then
        LABEL="$(uname -n)"
        LABEL="${LABEL%%.*}"
    fi

    LABEL="$(printf '%s' "$LABEL" | sed -E 's/[^A-Za-z0-9._-]/-/g')"
    printf '%s\n' "${LABEL:-host}"
}

backup_timestamp_label() {
    if [ -n "${BACKUP_NOW_EPOCH:-}" ]; then
        date -d "@${BACKUP_NOW_EPOCH}" +%d_%m_%Y-%H:%M
    else
        date +%d_%m_%Y-%H:%M
    fi
}

# Sistemas de ficheros cuyos nombres no admiten ':'.
backup_fs_forbids_colon() {
    case "$1" in
        exfat|vfat|msdos|ntfs|ntfs3|fuseblk|cifs|smb3) return 0 ;;
        *) return 1 ;;
    esac
}

# Uso: build_backup_name <destino>; requiere BACKUP_FS_TYPE.
build_backup_name() {
    local DEST="${1%/}"
    local NAME
    local CANDIDATE
    local SUFFIX=2

    NAME="$(backup_host_label)_$(backup_timestamp_label)"

    if backup_fs_forbids_colon "${BACKUP_FS_TYPE:-}"; then
        NAME="${NAME//:/h}"
        log_warn "El destino es ${BACKUP_FS_TYPE} y no admite ':' en nombres; se usa 'h' en la hora." >&2
    fi

    CANDIDATE="$NAME"
    while [ -e "${DEST}/${CANDIDATE}" ]; do
        CANDIDATE="${NAME}_${SUFFIX}"
        SUFFIX=$((SUFFIX + 1))
    done

    printf '%s\n' "$CANDIDATE"
}

# Metadata de sistema: user_ids, os-release, inventario, extensiones y unidades de usuario.
write_backup_system_metadata() {
    local META_DIR="$BACKUP_DIR/metadata"
    local OS_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir $META_DIR/user_ids.conf${NC}"
        log "${YELLOW}[DRY-RUN] copiar $OS_FILE a $META_DIR/os-release${NC}"
        log "${YELLOW}[DRY-RUN] inventario de paquetes en $META_DIR/packages/${NC}"
        log "${YELLOW}[DRY-RUN] extensiones de VS Code y unidades de usuario en $META_DIR${NC}"
        return 0
    fi

    {
        echo "USER=$(whoami)"
        echo "UID=$(id -u)"
        echo "GID=$(id -g)"
    } > "$META_DIR/user_ids.conf"

    if [ -r "$OS_FILE" ]; then
        cp "$OS_FILE" "$META_DIR/os-release"
    fi

    inventory_write "$META_DIR"

    if command -v code >/dev/null 2>&1; then
        code --list-extensions > "$META_DIR/vscode-extensions.txt" 2>/dev/null ||
            log_warn "No se pudo exportar la lista de extensiones de VS Code."
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if ! systemctl --user list-unit-files --state=enabled --no-pager \
            > "$META_DIR/user-enabled-units.txt" 2>/dev/null; then
            rm -f "$META_DIR/user-enabled-units.txt"
            log_warn "No se pudieron listar las unidades systemd de usuario."
        fi
    fi
}

backup_manifest_line() {
    local VALUE="${2//$'\n'/ }"
    printf '%s=%s\n' "$1" "$VALUE"
}

# manifest.env (ADR-002 D4). Se escribe con printf; nunca se hace source de él.
write_backup_manifest() {
    local NAME="$1"
    local ROOTS="$2"
    local MANIFEST="$BACKUP_DIR/metadata/manifest.env"
    local CREATED_AT
    local OS_ID
    local OS_ID_LIKE
    local OS_VERSION_ID

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir $MANIFEST${NC}"
        return 0
    fi

    if [ -n "${BACKUP_NOW_EPOCH:-}" ]; then
        CREATED_AT="$(date -d "@${BACKUP_NOW_EPOCH}" +%Y-%m-%dT%H:%M:%S%z)"
    else
        CREATED_AT="$(date +%Y-%m-%dT%H:%M:%S%z)"
    fi
    OS_ID="$(os_release_value ID)"
    OS_ID_LIKE="$(os_release_value ID_LIKE)"
    OS_VERSION_ID="$(os_release_value VERSION_ID)"

    {
        backup_manifest_line FORMAT_VERSION 2
        backup_manifest_line BACKUP_NAME "$NAME"
        backup_manifest_line CREATED_AT "$CREATED_AT"
        backup_manifest_line HOST_LABEL "$(backup_host_label)"
        backup_manifest_line TOOL_VERSION "$VERSION"
        backup_manifest_line OS_ID "$OS_ID"
        backup_manifest_line OS_ID_LIKE "$OS_ID_LIKE"
        backup_manifest_line OS_VERSION_ID "$OS_VERSION_ID"
        backup_manifest_line OS_FAMILY "$(os_family)"
        backup_manifest_line USER "$(whoami)"
        backup_manifest_line UID "$(id -u)"
        backup_manifest_line GID "$(id -g)"
        backup_manifest_line HOME "$HOME"
        backup_manifest_line PKG_MANAGERS "${INVENTORY_MANAGERS:-}"
        backup_manifest_line INVENTORY_WARNINGS "${INVENTORY_WARNINGS:-}"
        backup_manifest_line DATA_ROOTS "$ROOTS"
    } > "$MANIFEST"
}

backup_system() {
    local BACKUP_NAME
    local CONFIGS=()
    local EXISTING_CONFIGS=()
    local REPO_DIRS=()
    local ARCHIVE_DIRS=()
    local EXISTING_ARCHIVE_DIRS=()
    local ITEM
    local DIR
    local CONFIG_INDEX=0
    local REPO_INDEX=0
    local DATA_INDEX=0
    local TOTAL_CONFIGS=0
    local TOTAL_REPOS=0
    local TOTAL_DATA_DIRS=0
    local TOTAL_BLOCKS=4
    local BACKUP_WARNING_COUNT=0
    local DATA_ROOTS=""
    local PREFLIGHT_COMMANDS=(rsync find du df findmnt stat)

    require_bash_44 || exit 1
    [ -n "$BACKUP_TARGET" ] || PREFLIGHT_COMMANDS+=(lsblk)
    require_commands "${PREFLIGHT_COMMANDS[@]}" || exit 1

    if [ -n "$BACKUP_TARGET" ]; then
        DISK_MOUNT="$BACKUP_TARGET"
        if [ "${BACKUP_SELECTION_FROM_TUI:-0}" != "1" ] &&
           [ -z "${SELECTED_DATA_DIRS_RAW:-}" ] &&
           [ ${#SELECTED_DATA_DIRS[@]} -eq 0 ]; then
            ask_backup_data_dirs
        fi
        # Se actualiza el global para reutilizarlo en la validacion de espacio.
        # shellcheck disable=SC2034
        BACKUP_ESTIMATED_BYTES="$(estimate_backup_bytes)"
    else
        ask_backup_data_dirs
        select_disk || exit 1
    fi

    if [ ! -d "$DISK_MOUNT" ]; then
        log "${RED}Ruta destino invalida: $DISK_MOUNT${NC}"
        exit 1
    fi

    if [ -n "$BACKUP_TARGET" ]; then
        check_backup_space "$DISK_MOUNT"
    fi

    configure_backup_rsync_mode "$DISK_MOUNT"
    BACKUP_NAME="$(build_backup_name "$DISK_MOUNT")"
    BACKUP_DIR="${DISK_MOUNT%/}/${BACKUP_NAME}"
    BACKUP_WARNING_LOG="$BACKUP_DIR/logs/rsync_warnings.txt"

    run_cmd_quiet mkdir -p \
        "$BACKUP_DIR/configs" \
        "$BACKUP_DIR/repos" \
        "$BACKUP_DIR/data" \
        "$BACKUP_DIR/metadata" \
        "$BACKUP_DIR/logs"

    log_block_progress 1 "$TOTAL_BLOCKS" "Metadata y exportes"
    log_phase "Guardando UID/GID..."

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir $BACKUP_DIR/metadata/user_ids.conf${NC}"
    else
        {
            echo "USER=$(whoami)"
            echo "UID=$(id -u)"
            echo "GID=$(id -g)"
        } > "$BACKUP_DIR/metadata/user_ids.conf"
    fi

    log_phase "Exportando inventario del sistema..."
    write_backup_system_metadata

    log_block_progress 2 "$TOTAL_BLOCKS" "Configuraciones"
    log_phase "Copiando configuraciones..."

    mapfile -t CONFIGS < <(get_backup_config_items)

    for ITEM in "${CONFIGS[@]}"; do
        local CONFIG_SOURCE

        CONFIG_SOURCE="$HOME/$ITEM"
        if [ -e "$CONFIG_SOURCE" ] || [ -L "$CONFIG_SOURCE" ]; then
            EXISTING_CONFIGS+=("$ITEM")
        fi
    done

    TOTAL_CONFIGS=${#EXISTING_CONFIGS[@]}

    for ITEM in "${EXISTING_CONFIGS[@]}"; do
        local CONFIG_SOURCE
        local BROKEN_LINK_EXCLUDES=()

        CONFIG_SOURCE="$HOME/$ITEM"

        if [ -e "$CONFIG_SOURCE" ] || [ -L "$CONFIG_SOURCE" ]; then
            CONFIG_INDEX=$((CONFIG_INDEX+1))

            log_item_progress "$CONFIG_INDEX" "$TOTAL_CONFIGS" "$ITEM"

            if [ "$BACKUP_FS_TYPE" != "" ] && [ "${#BACKUP_RSYNC_OPTIONS[@]}" -gt 0 ] &&
               [[ " ${BACKUP_RSYNC_OPTIONS[*]} " == *" --copy-links "* ]]; then
                local EXCLUDE_LINE
                while IFS= read -r EXCLUDE_LINE; do
                    [ -n "$EXCLUDE_LINE" ] || continue
                    # Con -R la raíz de transferencia es $HOME: se ancla cada exclusión al item.
                    BROKEN_LINK_EXCLUDES+=("--exclude=/${ITEM}/${EXCLUDE_LINE#--exclude=}")
                done < <(build_broken_symlink_excludes "$CONFIG_SOURCE")
            fi

            # -R + "/./" conserva la ruta relativa a $HOME (configs/.config/Code/...).
            run_backup_rsync "$ITEM" rsync "${BACKUP_RSYNC_OPTIONS[@]}" -R \
                "${BROKEN_LINK_EXCLUDES[@]}" \
                "$HOME/./$ITEM" \
                "$BACKUP_DIR/configs/"
        fi
    done

    log_block_progress 3 "$TOTAL_BLOCKS" "Repositorios Git"
    log_phase "Buscando repositorios Git..."

    mapfile -t REPO_DIRS < <(collect_repo_dirs)

    TOTAL_REPOS=${#REPO_DIRS[@]}

    for DIR in "${REPO_DIRS[@]}"; do
        local BROKEN_LINK_EXCLUDES=()
        local REPO_NAME
        local REPO_RELATIVE_PATH
        local REPO_TARGET_PARENT

        REPO_NAME="$(basename "$DIR")"
        REPO_INDEX=$((REPO_INDEX+1))

        log_item_progress "$REPO_INDEX" "$TOTAL_REPOS" "$REPO_NAME"

        if ! REPO_RELATIVE_PATH="$(get_relative_home_path "$DIR")"; then
            log "${RED}[ERROR] No se pudo calcular la ruta relativa del repo: $DIR${NC}"
            exit 1
        fi

        REPO_TARGET_PARENT="$BACKUP_DIR/repos"
        if [ "$REPO_RELATIVE_PATH" != "." ]; then
            REPO_TARGET_PARENT="$BACKUP_DIR/repos/$(dirname "$REPO_RELATIVE_PATH")"
        fi

        run_cmd_quiet mkdir -p "$REPO_TARGET_PARENT"

        if [[ " ${BACKUP_RSYNC_OPTIONS[*]} " == *" --copy-links "* ]]; then
            mapfile -t BROKEN_LINK_EXCLUDES < <(build_broken_symlink_excludes "$DIR")
        fi

        run_backup_rsync "$REPO_NAME" rsync "${BACKUP_RSYNC_OPTIONS[@]}" \
            "${BROKEN_LINK_EXCLUDES[@]}" \
            --exclude='venv' \
            --exclude='.venv' \
            --exclude='__pycache__' \
            --exclude='.cache' \
            --exclude='node_modules' \
            --exclude='.pnpm-store' \
            --exclude='.tox' \
            --exclude='.mypy_cache' \
            --exclude='.pytest_cache' \
            --exclude='.ruff_cache' \
            "$DIR" \
            "$REPO_TARGET_PARENT/"
    done

    log_block_progress 4 "$TOTAL_BLOCKS" "Datos de usuario"
    log_phase "Copiando datos de usuario..."

    mapfile -t ARCHIVE_DIRS < <(get_data_dirs)

    for DIR in "${ARCHIVE_DIRS[@]}"; do
        [ -d "$DIR" ] && EXISTING_ARCHIVE_DIRS+=("$DIR")
    done

    TOTAL_DATA_DIRS=${#EXISTING_ARCHIVE_DIRS[@]}

    for DATA_DIR in "${EXISTING_ARCHIVE_DIRS[@]}"; do
        local DATA_DEST
        local DATA_REL
        local REL_REPO_DIR
        local RSYNC_EXCLUDES=()
        local BROKEN_LINK_EXCLUDES=()
        local REPO_DIR

        [ -d "$DATA_DIR" ] || continue

        if [ "$DATA_DIR" = "$HOME" ]; then
            DATA_REL="."
            DATA_DEST="$BACKUP_DIR/data/home"
            DATA_ROOTS="${DATA_ROOTS:+${DATA_ROOTS},}home:."
        elif [[ "$DATA_DIR" == "$HOME/"* ]]; then
            DATA_REL="${DATA_DIR#"$HOME"/}"
            DATA_DEST="$BACKUP_DIR/data/home/$DATA_REL"
            DATA_ROOTS="${DATA_ROOTS:+${DATA_ROOTS},}home:${DATA_REL}"
        else
            DATA_REL="${DATA_DIR#/}"
            DATA_DEST="$BACKUP_DIR/data/external/$DATA_REL"
            DATA_ROOTS="${DATA_ROOTS:+${DATA_ROOTS},}external:${DATA_DIR}"
        fi
        DATA_INDEX=$((DATA_INDEX+1))
        log_item_progress "$DATA_INDEX" "$TOTAL_DATA_DIRS" "$DATA_DIR"

        for REPO_DIR in "${REPO_DIRS[@]}"; do
            [ -d "$REPO_DIR" ] || continue

            if [[ "$REPO_DIR" == "$DATA_DIR/"* ]]; then
                REL_REPO_DIR="${REPO_DIR#"$DATA_DIR"/}"

                if [ -n "$REL_REPO_DIR" ]; then
                    RSYNC_EXCLUDES+=("--exclude=/$REL_REPO_DIR")
                fi
            fi
        done

        if [[ " ${BACKUP_RSYNC_OPTIONS[*]} " == *" --copy-links "* ]]; then
            mapfile -t BROKEN_LINK_EXCLUDES < <(build_broken_symlink_excludes "$DATA_DIR")
        fi

        run_cmd_quiet mkdir -p "$DATA_DEST"

        run_backup_rsync "$DATA_DIR" rsync "${BACKUP_RSYNC_OPTIONS[@]}" \
            "${BROKEN_LINK_EXCLUDES[@]}" \
            "${RSYNC_EXCLUDES[@]}" \
            "$DATA_DIR/" \
            "$DATA_DEST/"
    done

    write_backup_manifest "$BACKUP_NAME" "$DATA_ROOTS"

    if [ "$DRY_MODE" != true ]; then
        find "$BACKUP_DIR" -type f | sort > "$BACKUP_DIR/logs/copied_files.txt" 2>/dev/null || true
        {
            echo "CONFIG_ITEMS:"
            printf '%s\n' "${EXISTING_CONFIGS[@]}"
            echo ""
            echo "DATA_DIRS:"
            printf '%s\n' "${EXISTING_ARCHIVE_DIRS[@]}"
        } > "$BACKUP_DIR/logs/backup_selection.txt"
    fi
    log ""
    log "${GREEN}=================================${NC}"
    if [ "$BACKUP_WARNING_COUNT" -gt 0 ]; then
        log "${YELLOW}BACKUP COMPLETADO CON AVISOS${NC}"
    else
        log "${GREEN}BACKUP COMPLETADO${NC}"
    fi
    log "${GREEN}=================================${NC}"
    log ""
    if [ "$BACKUP_WARNING_COUNT" -gt 0 ]; then
        log "Avisos detectados: $BACKUP_WARNING_COUNT"
        log "Detalle de avisos:"
        log "$BACKUP_WARNING_LOG"
        log ""
    fi
    log "Registro de archivos copiados:"
    log "$BACKUP_DIR/logs/copied_files.txt"
    log ""
    log "Destino:"
    log "$BACKUP_DIR"
    log ""
}
