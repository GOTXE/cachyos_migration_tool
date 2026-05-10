#!/usr/bin/env bash

verify_rsync_restored_tree() {
    local SOURCE_DIR="$1"
    local TARGET_DIR="$2"
    local LABEL="$3"
    local TMP_DIFF
    local CHANGE_COUNT=0

    [ -d "$SOURCE_DIR" ] || return 0

    log " ${BLUE}->${NC} Verificando $LABEL"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] rsync -a --dry-run --checksum --itemize-changes '$SOURCE_DIR/' '$TARGET_DIR/'${NC}"
        return 0
    fi

    TMP_DIFF="$(mktemp)"
    rsync -a --dry-run --checksum --itemize-changes "$SOURCE_DIR/" "$TARGET_DIR/" > "$TMP_DIFF" || true
    CHANGE_COUNT="$(grep -vc '^\.d' "$TMP_DIFF" 2>/dev/null || true)"

    if [ "${CHANGE_COUNT:-0}" -eq 0 ]; then
        log "    ${GREEN}OK:${NC} $LABEL no muestra diferencias pendientes desde el backup hacia destino."
    else
        log "    ${YELLOW}AVISO:${NC} $LABEL muestra $CHANGE_COUNT diferencias pendientes."
        log "    Primeras diferencias:"
        sed -n '1,20p' "$TMP_DIFF" | while IFS= read -r LINE; do
            log "      $LINE"
        done
        log "    Revisa el log completo: $LOGFILE"
    fi

    rm -f "$TMP_DIFF"
}

restore_system() {
    local CURRENT_UID
    local CURRENT_GID
    local DATA_COPY
    local DATA_INDEX=0
    local TOTAL_DATA_DIRS=0
    local TOTAL_BLOCKS=5

    log_section "Restauracion de backup"
    show_log_location

    if [ -n "$BACKUP_SOURCE" ]; then
        BACKUP_DIR="$BACKUP_SOURCE"
    else
        prompt_read "Ruta completa del backup a restaurar: " BACKUP_DIR
    fi

    if [ ! -d "$BACKUP_DIR" ]; then
        log "${RED}Backup no encontrado.${NC}"
        exit 1
    fi

    if [ ! -f "$BACKUP_DIR/metadata/user_ids.conf" ]; then
        log "${RED}No se encontro metadata/user_ids.conf${NC}"
        exit 1
    fi

    parse_user_ids "$BACKUP_DIR/metadata/user_ids.conf"

    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)

    log ""
    log "${BLUE}UID/GID antiguos:${NC} UID=$OLD_UID GID=$OLD_GID"
    log "${BLUE}UID/GID actuales:${NC} UID=$CURRENT_UID GID=$CURRENT_GID"

    if [ "$OLD_UID" != "$CURRENT_UID" ] || [ "$OLD_GID" != "$CURRENT_GID" ]; then
        log "${YELLOW}AVISO:${NC} UID/GID distintos. Se corregira ownership de rutas criticas, pero conviene revisar permisos en repos/datos."
    fi

    log_block_progress 1 "$TOTAL_BLOCKS" "Configuraciones"

    if restore_conflicts_exist && [ "$FORCE_RESTORE" != true ]; then
        log "Se han detectado configuraciones existentes en tu HOME que tambien estan en el backup."
        log "Si respondes si, el contenido del backup se copiara encima de esas rutas. No se borraran ficheros extra del destino."
        if ! confirm_action "Sobrescribir configuraciones existentes durante la restauracion" "no"; then
            log "${RED}Restauracion cancelada por el usuario.${NC}"
            exit 1
        fi
    fi

    if [ -d "$BACKUP_DIR/configs" ]; then
        run_cmd rsync -a --info=progress2 \
            "$BACKUP_DIR/configs/" \
            "$HOME/"
    else
        log "${YELLOW}No existe bloque configs en el backup. Se omite.${NC}"
    fi

    log_block_progress 2 "$TOTAL_BLOCKS" "Repositorios Git"

    if [ -d "$BACKUP_DIR/repos" ]; then
        run_cmd rsync -a --info=progress2 \
            "$BACKUP_DIR/repos/" \
            "$HOME/"
    else
        log "${YELLOW}No existe bloque repos en el backup. Se omite.${NC}"
    fi

    log_block_progress 3 "$TOTAL_BLOCKS" "Datos de usuario"

    if [ -d "$BACKUP_DIR/data" ]; then
        TOTAL_DATA_DIRS="$(find "$BACKUP_DIR/data" -mindepth 1 -maxdepth 1 -type d | wc -l)"

        while IFS= read -r -d '' DATA_COPY; do
            local DATA_NAME
            local TARGET_PARENT

            DATA_INDEX=$((DATA_INDEX+1))
            DATA_NAME="$(basename "$DATA_COPY")"
            TARGET_PARENT="$HOME"

            if [ "$DATA_NAME" = "$(basename "$(get_documents_dir)")" ]; then
                TARGET_PARENT="$(dirname "$(get_documents_dir)")"
            fi

            log_item_progress "$DATA_INDEX" "$TOTAL_DATA_DIRS" "$DATA_NAME -> $TARGET_PARENT/$DATA_NAME"
            run_cmd mkdir -p "$TARGET_PARENT"
            run_cmd rsync -a --info=progress2 \
                "$DATA_COPY/" \
                "$TARGET_PARENT/$DATA_NAME/"
        done < <(find "$BACKUP_DIR/data" -mindepth 1 -maxdepth 1 -type d -print0)
    else
        log "${YELLOW}No existe bloque data en el backup. Se omite.${NC}"
    fi

    log_block_progress 4 "$TOTAL_BLOCKS" "Permisos"

    run_cmd sudo chown -R "$(whoami)":"$(whoami)" "$HOME/.ssh" || true
    run_cmd sudo chown -R "$(whoami)":"$(whoami)" "$HOME/.codex" || true
    run_cmd sudo chown -R "$(whoami)":"$(whoami)" "$HOME/.claude" || true

    if [ -d "$HOME/.ssh" ]; then
        run_cmd chmod 700 "$HOME/.ssh"
        run_shell "find \"$HOME/.ssh\" -type f \\( -name 'id_*' -o -name 'authorized_keys' -o -name 'known_hosts' -o -name 'config' \\) -exec chmod 600 {} +"
        run_shell "find \"$HOME/.ssh\" -type f -name '*.pub' -exec chmod 644 {} +"
    fi

    log_block_progress 5 "$TOTAL_BLOCKS" "Verificacion"

    verify_rsync_restored_tree "$BACKUP_DIR/configs" "$HOME" "configuraciones"
    verify_rsync_restored_tree "$BACKUP_DIR/repos" "$HOME" "repositorios"

    if [ -d "$BACKUP_DIR/data" ]; then
        while IFS= read -r -d '' DATA_COPY; do
            local DATA_NAME
            local TARGET_PARENT

            DATA_NAME="$(basename "$DATA_COPY")"
            TARGET_PARENT="$HOME"
            if [ "$DATA_NAME" = "$(basename "$(get_documents_dir)")" ]; then
                TARGET_PARENT="$(dirname "$(get_documents_dir)")"
            fi
            verify_rsync_restored_tree "$DATA_COPY" "$TARGET_PARENT/$DATA_NAME" "datos/$DATA_NAME"
        done < <(find "$BACKUP_DIR/data" -mindepth 1 -maxdepth 1 -type d -print0)
    fi

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}RESTAURACION COMPLETADA${NC}"
    log "${GREEN}=================================${NC}"
    log "Backup restaurado desde: $BACKUP_DIR"
    show_log_location
    log ""
}
