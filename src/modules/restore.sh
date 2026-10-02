#!/usr/bin/env bash

restore_rsync() {
    local SOURCE_DIR="$1"
    local TARGET_DIR="$2"
    local LABEL="$3"
    local RSYNC_OPTIONS=()

    if [ "${RESTORE_PRESERVE_PERMISSIONS:-false}" = true ]; then
        RSYNC_OPTIONS=(-a)
    else
        # shellcheck disable=SC2054
        RSYNC_OPTIONS=(-rltD --no-perms --no-owner --no-group --chmod=F644,D755)
    fi

    log "Restaurando $LABEL con política de permisos: ${RESTORE_PRESERVE_PERMISSIONS:-false}."
    run_cmd rsync "${RSYNC_OPTIONS[@]}" --info=progress2 \
        "$SOURCE_DIR" \
        "$TARGET_DIR"
}

normalize_restored_git_repository_permissions() {
    local BACKUP_REPOS_DIR="$1"
    local TARGET_HOME="$2"
    local SOURCE_GIT_DIR=""
    local RELATIVE_REPO=""
    local TARGET_REPO=""
    local ENTRY=""
    local MODE=""
    local RELATIVE_FILE=""
    local TARGET_FILE=""

    [ "${RESTORE_PRESERVE_PERMISSIONS:-false}" = true ] && return 0
    [ -d "$BACKUP_REPOS_DIR" ] || return 0

    while IFS= read -r -d '' SOURCE_GIT_DIR; do
        RELATIVE_REPO="${SOURCE_GIT_DIR#"$BACKUP_REPOS_DIR/"}"
        RELATIVE_REPO="${RELATIVE_REPO%/.git}"
        TARGET_REPO="$TARGET_HOME/$RELATIVE_REPO"

        [ -e "$TARGET_REPO" ] || continue
        log "Normalizando permisos Git: $RELATIVE_REPO"

        while IFS= read -r -d '' ENTRY; do
            MODE="${ENTRY%% *}"
            RELATIVE_FILE="${ENTRY#*$'\t'}"
            TARGET_FILE="$TARGET_REPO/$RELATIVE_FILE"

            [ -e "$TARGET_FILE" ] || [ -L "$TARGET_FILE" ] || continue
            case "$MODE" in
                100755)
                    [ -L "$TARGET_FILE" ] || chmod a+x "$TARGET_FILE"
                    ;;
                100644)
                    [ -L "$TARGET_FILE" ] || chmod a-x "$TARGET_FILE"
                    ;;
            esac
        done < <(git -C "$TARGET_REPO" ls-files -s -z 2>/dev/null || true)
    done < <(find "$BACKUP_REPOS_DIR" \( -type d -o -type f \) -name .git -print0 2>/dev/null)
}

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
    # Restoration normalizes ownership and SSH permissions, while Codex keeps
    # changing its history, SQLite journals and caches during an active session.
    # Do not report those expected runtime differences as restore failures.
    rsync -r --dry-run --checksum --itemize-changes \
        --no-perms --no-owner --no-group --omit-dir-times \
        --exclude='.codex/history.jsonl' \
        --exclude='.codex/logs_*.sqlite*' \
        --exclude='.codex/state_*.sqlite*' \
        --exclude='.codex/*-journal' \
        --exclude='.codex/cache/' \
        --exclude='.codex/plugins/cache/' \
        --exclude='.codex/models_cache.json' \
        "$SOURCE_DIR/" "$TARGET_DIR/" > "$TMP_DIFF" || true
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

# Lee metadata/manifest.env (formato v2) sin hacer source y rellena BM_<CLAVE>.
# Sin manifest pero con user_ids.conf el backup es v1. Devuelve 1 si no es un backup.
read_backup_manifest() {
    local DIR="$1"
    local MANIFEST="$DIR/metadata/manifest.env"
    local KEY
    local VALUE
    local VAR

    for VAR in $(compgen -A variable BM_); do
        unset "$VAR"
    done

    if [ -f "$MANIFEST" ]; then
        while IFS='=' read -r KEY VALUE || [ -n "$KEY" ]; do
            [[ "$KEY" =~ ^[A-Z][A-Z0-9_]*$ ]] || continue
            printf -v "BM_${KEY}" '%s' "$VALUE"
        done < "$MANIFEST"
        BM_FORMAT_VERSION="${BM_FORMAT_VERSION:-}"
        return 0
    fi

    if [ -f "$DIR/metadata/user_ids.conf" ]; then
        BM_FORMAT_VERSION=1
        return 0
    fi

    return 1
}

# Imprime los items de CONFIG_ITEMS: de logs/backup_selection.txt (uno por línea).
backup_selection_config_items() {
    local FILE="$1/logs/backup_selection.txt"

    [ -f "$FILE" ] || return 1
    grep -q '^CONFIG_ITEMS:$' "$FILE" || return 1

    awk '/^CONFIG_ITEMS:$/ { in_items = 1; next } /^$/ { in_items = 0 } /^[A-Z_]+:$/ { in_items = 0 } in_items { print }' "$FILE"
}

# Origen de un item de configuración dentro del backup según el formato.
backup_config_source_path() {
    local ITEM="$1"

    if [ "${BM_FORMAT_VERSION:-1}" -ge 2 ]; then
        printf '%s/configs/%s\n' "$BACKUP_DIR" "$ITEM"
    else
        printf '%s/configs/%s\n' "$BACKUP_DIR" "$(basename "$ITEM")"
    fi
}

restore_conflicts_exist() {
    local ITEM
    local SOURCE
    local RELATIVE
    local ITEMS=()

    [ -d "$BACKUP_DIR/configs" ] || return 1

    if mapfile -t ITEMS < <(backup_selection_config_items "$BACKUP_DIR") && [ "${#ITEMS[@]}" -gt 0 ]; then
        for ITEM in "${ITEMS[@]}"; do
            SOURCE="$(backup_config_source_path "$ITEM")"
            if { [ -e "$SOURCE" ] || [ -L "$SOURCE" ]; } && [ -e "$HOME/$ITEM" ]; then
                return 0
            fi
        done
        return 1
    fi

    while IFS= read -r -d '' ITEM; do
        RELATIVE="${ITEM#"$BACKUP_DIR/configs/"}"

        if [ -e "$HOME/$RELATIVE" ]; then
            return 0
        fi
    done < <(find "$BACKUP_DIR/configs" -mindepth 1 -maxdepth 1 -print0)

    return 1
}

# Inversa de manifest_path_encode (backup.sh): %0A, %2C y, al final, %25.
manifest_path_decode() {
    local VALUE="$1"

    VALUE="${VALUE//%0A/$'\n'}"
    VALUE="${VALUE//%2C/,}"
    VALUE="${VALUE//%25/%}"
    printf '%s\n' "$VALUE"
}

# Raíces externas (external:<ruta absoluta>) de DATA_ROOTS, una por línea.
# Las rutas vienen codificadas con manifest_path_encode; los manifests escritos
# antes de la codificación nunca llegaron a publicarse (v2 se publica en 1.12.0 ya codificado).
backup_external_roots() {
    local ROOTS="${BM_DATA_ROOTS:-}"
    local ENTRY

    [ -n "$ROOTS" ] || return 0
    while IFS= read -r ENTRY; do
        case "$ENTRY" in
            external:/?*) manifest_path_decode "${ENTRY#external:}" ;;
        esac
    done < <(printf '%s\n' "${ROOTS//,/$'\n'}")
}

# Destino de una raíz externa: ruta original (si se pidió y es posible) o restored-external.
external_restore_destination() {
    local ROOT_PATH="$1"
    local PARENT

    if [ "$EXTERNAL_TO_ORIGINAL" = true ]; then
        PARENT="$(dirname "$ROOT_PATH")"
        if [ -d "$PARENT" ] && [ -w "$PARENT" ]; then
            printf '%s\n' "$ROOT_PATH"
            return 0
        fi
        log_warn "No se puede restaurar en $ROOT_PATH (el directorio padre no existe o no es escribible); se usa $HOME/restored-external/${ROOT_PATH#/}." >&2
    fi

    printf '%s\n' "$HOME/restored-external/${ROOT_PATH#/}"
}

# Avisa (o corrige con --fix-ownership) de ficheros que no son del usuario actual.
check_restored_ownership() {
    local DIR
    local FOREIGN
    local CURRENT_USER
    local CURRENT_GROUP
    local PENDING=()

    CURRENT_USER="$(id -un)"
    CURRENT_GROUP="$(id -gn)"

    for DIR in "$HOME/.ssh" "$HOME/.codex" "$HOME/.claude"; do
        [ -e "$DIR" ] || continue
        FOREIGN="$(find "$DIR" ! -user "$(id -u)" -print -quit 2>/dev/null || true)"
        [ -n "$FOREIGN" ] && PENDING+=("$DIR")
    done

    [ "${#PENDING[@]}" -gt 0 ] || return 0

    if [ "$FIX_OWNERSHIP" = true ]; then
        ensure_sudo_session || return 1
        for DIR in "${PENDING[@]}"; do
            run_cmd sudo chown -R "$CURRENT_USER:$CURRENT_GROUP" "$DIR"
        done
        return 0
    fi

    for DIR in "${PENDING[@]}"; do
        log_warn "Hay ficheros que no son tuyos en $DIR. Corrígelo con: sudo chown -R \"\$(id -un):\$(id -gn)\" \"$DIR\" (o ejecuta restore con --fix-ownership)."
    done
}

restore_configs_v1_mapped() {
    local ITEMS=("$@")
    local ITEM
    local SOURCE
    local TARGET

    for ITEM in "${ITEMS[@]}"; do
        SOURCE="$(backup_config_source_path "$ITEM")"
        TARGET="$HOME/$ITEM"

        if [ ! -e "$SOURCE" ] && [ ! -L "$SOURCE" ]; then
            log "    (sin copia en el backup para $ITEM; se omite)"
            continue
        fi

        run_cmd mkdir -p "$(dirname "$TARGET")"
        if [ -d "$SOURCE" ]; then
            restore_rsync "$SOURCE/" "$TARGET/" "configuración $ITEM"
        else
            restore_rsync "$SOURCE" "$TARGET" "configuración $ITEM"
        fi
    done
}

restore_data_v1() {
    local DATA_COPY
    local DATA_INDEX=0
    local TOTAL_DATA_DIRS

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
        restore_rsync \
            "$DATA_COPY/" \
            "$TARGET_PARENT/$DATA_NAME/" \
            "datos/$DATA_NAME"
    done < <(find "$BACKUP_DIR/data" -mindepth 1 -maxdepth 1 -type d -print0)
}

restore_data_v2() {
    local ROOT_PATH
    local DEST
    local ROOTS=()

    if [ -d "$BACKUP_DIR/data/home" ]; then
        restore_rsync "$BACKUP_DIR/data/home/" "$HOME/" "datos (home)"
    fi

    [ -d "$BACKUP_DIR/data/external" ] || return 0

    mapfile -t ROOTS < <(backup_external_roots)

    if [ "${#ROOTS[@]}" -eq 0 ]; then
        log_warn "El manifest no lista DATA_ROOTS externos; se restaura data/external/ completo en $HOME/restored-external."
        run_cmd mkdir -p "$HOME/restored-external"
        restore_rsync "$BACKUP_DIR/data/external/" "$HOME/restored-external/" "datos externos"
        return 0
    fi

    for ROOT_PATH in "${ROOTS[@]}"; do
        [ -d "$BACKUP_DIR/data/external/${ROOT_PATH#/}" ] || continue
        DEST="$(external_restore_destination "$ROOT_PATH")"
        log_item_progress 1 "${#ROOTS[@]}" "$ROOT_PATH -> $DEST"
        run_cmd mkdir -p "$DEST"
        restore_rsync "$BACKUP_DIR/data/external/${ROOT_PATH#/}/" "$DEST/" "datos externos $ROOT_PATH"
    done
}

verify_restored_data_v2() {
    local ROOT_PATH
    local ROOTS=()

    verify_rsync_restored_tree "$BACKUP_DIR/data/home" "$HOME" "datos (home)"

    [ -d "$BACKUP_DIR/data/external" ] || return 0
    mapfile -t ROOTS < <(backup_external_roots)
    for ROOT_PATH in "${ROOTS[@]}"; do
        verify_rsync_restored_tree "$BACKUP_DIR/data/external/${ROOT_PATH#/}" \
            "$(external_restore_destination "$ROOT_PATH" 2>/dev/null)" "datos externos $ROOT_PATH"
    done
}

restore_system() {
    local CURRENT_UID
    local CURRENT_GID
    local DATA_COPY
    local TOTAL_BLOCKS=5
    local SELECTION_ITEMS=()
    local MAPPED_V1=false

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

    if ! read_backup_manifest "$BACKUP_DIR"; then
        log "${RED}No se encontro metadata/manifest.env ni metadata/user_ids.conf${NC}"
        exit 1
    fi

    if ! [[ "$BM_FORMAT_VERSION" =~ ^[0-9]+$ ]] || [ "$BM_FORMAT_VERSION" -gt 2 ]; then
        log "${RED}[ERROR] Formato de backup no soportado: ${BM_FORMAT_VERSION:-desconocido}${NC}"
        exit 1
    fi

    if [ -f "$BACKUP_DIR/metadata/user_ids.conf" ]; then
        parse_user_ids "$BACKUP_DIR/metadata/user_ids.conf"
    else
        OLD_UID="${BM_UID:-}"
        OLD_GID="${BM_GID:-}"
    fi

    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)

    log ""
    log "Formato de backup: v${BM_FORMAT_VERSION}${BM_HOST_LABEL:+ (equipo: ${BM_HOST_LABEL})}"
    log "${BLUE}UID/GID antiguos:${NC} UID=${OLD_UID:-?} GID=${OLD_GID:-?}"
    log "${BLUE}UID/GID actuales:${NC} UID=$CURRENT_UID GID=$CURRENT_GID"

    if [ "${OLD_UID:-}" != "$CURRENT_UID" ] || [ "${OLD_GID:-}" != "$CURRENT_GID" ]; then
        log "${YELLOW}AVISO:${NC} UID/GID distintos. Revisa permisos en repos/datos; usa --fix-ownership si hay ficheros ajenos."
    fi

    if [ "$BM_FORMAT_VERSION" -lt 2 ]; then
        log_warn "Backup en formato v1: las rutas de datos se restauran por nombre de directorio."
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
        if [ "$BM_FORMAT_VERSION" -ge 2 ]; then
            restore_rsync \
                "$BACKUP_DIR/configs/" \
                "$HOME/" \
                "configuraciones"
        elif mapfile -t SELECTION_ITEMS < <(backup_selection_config_items "$BACKUP_DIR") &&
             [ "${#SELECTION_ITEMS[@]}" -gt 0 ]; then
            MAPPED_V1=true
            restore_configs_v1_mapped "${SELECTION_ITEMS[@]}"
        else
            log_warn "Backup v1 sin logs/backup_selection.txt: se restaura configs/ directamente en \$HOME y las rutas anidadas (p. ej. .config/Code) pueden quedar en el sitio equivocado."
            restore_rsync \
                "$BACKUP_DIR/configs/" \
                "$HOME/" \
                "configuraciones"
        fi
    else
        log "${YELLOW}No existe bloque configs en el backup. Se omite.${NC}"
    fi

    log_block_progress 2 "$TOTAL_BLOCKS" "Repositorios Git"

    if [ -d "$BACKUP_DIR/repos" ]; then
        restore_rsync \
            "$BACKUP_DIR/repos/" \
            "$HOME/" \
            "repositorios"
        normalize_restored_git_repository_permissions "$BACKUP_DIR/repos" "$HOME"
    else
        log "${YELLOW}No existe bloque repos en el backup. Se omite.${NC}"
    fi

    log_block_progress 3 "$TOTAL_BLOCKS" "Datos de usuario"

    if [ -d "$BACKUP_DIR/data" ]; then
        if [ "$BM_FORMAT_VERSION" -ge 2 ]; then
            restore_data_v2
        else
            log_warn "Backup v1: los datos se restauran por nombre de directorio (sin información de la ruta original)."
            restore_data_v1
        fi
    else
        log "${YELLOW}No existe bloque data en el backup. Se omite.${NC}"
    fi

    log_block_progress 4 "$TOTAL_BLOCKS" "Permisos"

    check_restored_ownership

    if [ -d "$HOME/.ssh" ]; then
        run_cmd chmod 700 "$HOME/.ssh"
        run_shell "find \"$HOME/.ssh\" -type f \\( -name 'id_*' -o -name 'authorized_keys' -o -name 'known_hosts' -o -name 'config' \\) -exec chmod 600 {} +"
        run_shell "find \"$HOME/.ssh\" -type f -name '*.pub' -exec chmod 644 {} +"
    fi

    log_block_progress 5 "$TOTAL_BLOCKS" "Verificacion"

    if [ "$MAPPED_V1" = true ]; then
        local V1_ITEM
        for V1_ITEM in "${SELECTION_ITEMS[@]}"; do
            DATA_COPY="$(backup_config_source_path "$V1_ITEM")"
            [ -d "$DATA_COPY" ] && verify_rsync_restored_tree "$DATA_COPY" "$HOME/$V1_ITEM" "configuración $V1_ITEM"
        done
    else
        verify_rsync_restored_tree "$BACKUP_DIR/configs" "$HOME" "configuraciones"
    fi
    verify_rsync_restored_tree "$BACKUP_DIR/repos" "$HOME" "repositorios"

    if [ -d "$BACKUP_DIR/data" ]; then
        if [ "$BM_FORMAT_VERSION" -ge 2 ]; then
            verify_restored_data_v2
        else
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
    fi

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}RESTAURACION COMPLETADA${NC}"
    log "${GREEN}=================================${NC}"
    log "Backup restaurado desde: $BACKUP_DIR"
    show_log_location
    log ""
}
