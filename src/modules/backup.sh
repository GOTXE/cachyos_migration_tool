#!/usr/bin/env bash

backup_system() {
    local DATE
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

    require_command rsync
    extract_broadcom_bundle_silent

    DATE="$(date +%Y-%m-%d_%H-%M-%S)"
    BACKUP_NAME="linux_backup_${DATE}"

    if [ -n "$BACKUP_TARGET" ]; then
        DISK_MOUNT="$BACKUP_TARGET"
        # Se actualiza el global para reutilizarlo en la validacion de espacio.
        # shellcheck disable=SC2034
        BACKUP_ESTIMATED_BYTES="$(estimate_backup_bytes)"
    else
        ask_backup_data_dirs
        select_disk
    fi

    if [ ! -d "$DISK_MOUNT" ]; then
        log "${RED}Ruta destino invalida: $DISK_MOUNT${NC}"
        exit 1
    fi

    if [ -n "$BACKUP_TARGET" ]; then
        check_backup_space "$DISK_MOUNT"
    fi

    BACKUP_DIR="${DISK_MOUNT%/}/${BACKUP_NAME}"
    configure_backup_rsync_mode "$DISK_MOUNT"

    run_cmd mkdir -p \
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

    log_phase "Exportando paquetes..."

    if command -v dpkg >/dev/null 2>&1; then
        if [ "$DRY_MODE" = true ]; then
            log "${YELLOW}[DRY-RUN] dpkg --get-selections > $BACKUP_DIR/metadata/dpkg_packages.txt${NC}"
        else
            dpkg --get-selections > "$BACKUP_DIR/metadata/dpkg_packages.txt"
        fi
    fi

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] flatpak list > $BACKUP_DIR/metadata/flatpak_packages.txt${NC}"
    else
        flatpak list > "$BACKUP_DIR/metadata/flatpak_packages.txt" 2>/dev/null || true
    fi

    if command -v code >/dev/null 2>&1; then
        if [ "$DRY_MODE" = true ]; then
            log "${YELLOW}[DRY-RUN] code --list-extensions > $BACKUP_DIR/metadata/vscode_extensions.txt${NC}"
        else
            code --list-extensions > "$BACKUP_DIR/metadata/vscode_extensions.txt"
        fi
    fi

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
                mapfile -t BROKEN_LINK_EXCLUDES < <(build_broken_symlink_excludes "$CONFIG_SOURCE")
            fi

            run_cmd rsync "${BACKUP_RSYNC_OPTIONS[@]}" --info=progress2 \
                "${BROKEN_LINK_EXCLUDES[@]}" \
                "$CONFIG_SOURCE" \
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

        run_cmd mkdir -p "$REPO_TARGET_PARENT"

        if [[ " ${BACKUP_RSYNC_OPTIONS[*]} " == *" --copy-links "* ]]; then
            mapfile -t BROKEN_LINK_EXCLUDES < <(build_broken_symlink_excludes "$DIR")
        fi

        run_cmd rsync "${BACKUP_RSYNC_OPTIONS[@]}" --info=progress2 \
            "${BROKEN_LINK_EXCLUDES[@]}" \
            --exclude='venv' \
            --exclude='.venv' \
            --exclude='__pycache__' \
            --exclude='.cache' \
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
        local DATA_NAME
        local REL_REPO_DIR
        local RSYNC_EXCLUDES=()
        local BROKEN_LINK_EXCLUDES=()
        local REPO_DIR

        [ -d "$DATA_DIR" ] || continue

        DATA_NAME="$(basename "$DATA_DIR")"
        DATA_INDEX=$((DATA_INDEX+1))
        log_item_progress "$DATA_INDEX" "$TOTAL_DATA_DIRS" "$DATA_DIR"

        for REPO_DIR in "${REPO_DIRS[@]}"; do
            [ -d "$REPO_DIR" ] || continue

            if [[ "$REPO_DIR" == "$DATA_DIR/"* ]]; then
                REL_REPO_DIR="${REPO_DIR#"$DATA_DIR"/}"

                if [ -n "$REL_REPO_DIR" ]; then
                    RSYNC_EXCLUDES+=("--exclude=$REL_REPO_DIR")
                fi
            fi
        done

        if [[ " ${BACKUP_RSYNC_OPTIONS[*]} " == *" --copy-links "* ]]; then
            mapfile -t BROKEN_LINK_EXCLUDES < <(build_broken_symlink_excludes "$DATA_DIR")
        fi

        run_cmd rsync "${BACKUP_RSYNC_OPTIONS[@]}" --info=progress2 \
            "${BROKEN_LINK_EXCLUDES[@]}" \
            "${RSYNC_EXCLUDES[@]}" \
            "$DATA_DIR/" \
            "$BACKUP_DIR/data/$DATA_NAME/"
    done

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}BACKUP COMPLETADO${NC}"
    log "${GREEN}=================================${NC}"
    log ""
    log "Destino:"
    log "$BACKUP_DIR"
    log ""
}
