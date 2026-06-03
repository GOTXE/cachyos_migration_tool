#!/usr/bin/env bash

MBP_PLASMOID_ID="io.github.cachyosmigrationtool.mbpwatch"
MBP_PLASMOID_PACKAGE_TYPE="Plasma/Applet"
MBP_PLASMOID_RELATIVE_DIR="assets/plasmoids/mbp-watch"
MBP_PLASMOID_WEB_URL="http://127.0.0.1:7070/report.html"
MBP_PLASMOID_POPUP_TTL_MS="30000"

get_installed_package_version() {
    local PACKAGE_NAME="$1"

    pacman -Q "$PACKAGE_NAME" 2>/dev/null | awk '{print $2}'
}

get_repo_package_status() {
    local PACKAGE_NAME="$1"
    local INSTALLED_VERSION=""
    local UPDATE_LINE=""
    local TARGET_VERSION=""

    INSTALLED_VERSION="$(get_installed_package_version "$PACKAGE_NAME")"

    if [ -z "$INSTALLED_VERSION" ]; then
        printf 'pendiente||\n'
        return 0
    fi

    UPDATE_LINE="$(pacman -Qu "$PACKAGE_NAME" 2>/dev/null || true)"
    if [ -n "$UPDATE_LINE" ]; then
        TARGET_VERSION="$(printf '%s\n' "$UPDATE_LINE" | awk '{print $4}')"
        printf 'desactualizado|%s|%s\n' "$INSTALLED_VERSION" "$TARGET_VERSION"
        return 0
    fi

    printf 'instalado|%s|\n' "$INSTALLED_VERSION"
}

get_aur_package_status() {
    local PACKAGE_NAME="$1"
    local INSTALLED_VERSION=""
    local UPDATE_LINE=""
    local TARGET_VERSION=""

    INSTALLED_VERSION="$(get_installed_package_version "$PACKAGE_NAME")"

    if [ -z "$INSTALLED_VERSION" ]; then
        printf 'pendiente||\n'
        return 0
    fi

    UPDATE_LINE="$(yay -Qua "$PACKAGE_NAME" 2>/dev/null || true)"
    if [ -n "$UPDATE_LINE" ]; then
        TARGET_VERSION="$(printf '%s\n' "$UPDATE_LINE" | awk '{print $4}')"
        printf 'desactualizado|%s|%s\n' "$INSTALLED_VERSION" "$TARGET_VERSION"
        return 0
    fi

    printf 'instalado|%s|\n' "$INSTALLED_VERSION"
}

log_package_batch_state() {
    local CHANNEL_LABEL="$1"
    local STATUS_MODE="${2:-repo}"
    shift 2
    local STATUS_LINE=""
    local STATUS_LABEL=""
    local PACKAGE_NAME=""
    local INSTALLED_VERSION=""
    local TARGET_VERSION=""

    log "${YELLOW}Comprobando estado previo de paquetes ${CHANNEL_LABEL}...${NC}"

    for PACKAGE_NAME in "$@"; do
        case "$STATUS_MODE" in
            aur)
                STATUS_LINE="$(get_aur_package_status "$PACKAGE_NAME")"
                ;;
            *)
                STATUS_LINE="$(get_repo_package_status "$PACKAGE_NAME")"
                ;;
        esac

        IFS='|' read -r STATUS_LABEL INSTALLED_VERSION TARGET_VERSION <<< "$STATUS_LINE"

        case "$STATUS_LABEL" in
            instalado)
                log_success " - $PACKAGE_NAME: instalado ($INSTALLED_VERSION)"
                ;;
            desactualizado)
                log_warn " - $PACKAGE_NAME: desactualizado ($INSTALLED_VERSION -> $TARGET_VERSION)"
                ;;
            *)
                log_info " - $PACKAGE_NAME: pendiente de instalar"
                ;;
        esac
    done
}

get_npm_global_status() {
    local PACKAGE_NAME="$1"
    local PACKAGE_BIN="$2"
    local INSTALLED_VERSION=""
    local OUTDATED_JSON=""
    local LATEST_VERSION=""

    if ! command -v "$PACKAGE_BIN" >/dev/null 2>&1; then
        printf 'pendiente||\n'
        return 0
    fi

    INSTALLED_VERSION="$(npm list -g "$PACKAGE_NAME" --depth=0 --json 2>/dev/null | node -e '
let data = "";
process.stdin.on("data", chunk => data += chunk);
process.stdin.on("end", () => {
  try {
    const parsed = JSON.parse(data || "{}");
    const version = parsed.dependencies?.["'"$PACKAGE_NAME"'"]?.version || "";
    process.stdout.write(version);
  } catch {
    process.stdout.write("");
  }
});
')"

    OUTDATED_JSON="$(npm outdated -g "$PACKAGE_NAME" --depth=0 --json 2>/dev/null || true)"
    if [ -n "$OUTDATED_JSON" ] && [ "$OUTDATED_JSON" != "{}" ]; then
        LATEST_VERSION="$(printf '%s' "$OUTDATED_JSON" | node -e '
let data = "";
process.stdin.on("data", chunk => data += chunk);
process.stdin.on("end", () => {
  try {
    const parsed = JSON.parse(data || "{}");
    const latest = parsed["'"$PACKAGE_NAME"'"]?.latest || "";
    process.stdout.write(latest);
  } catch {
    process.stdout.write("");
  }
});
')"
        printf 'desactualizado|%s|%s\n' "$INSTALLED_VERSION" "$LATEST_VERSION"
        return 0
    fi

    printf 'instalado|%s|\n' "$INSTALLED_VERSION"
}

log_npm_tool_status() {
    local LABEL="$1"
    local PACKAGE_NAME="$2"
    local PACKAGE_BIN="$3"
    local STATUS_LINE=""
    local STATUS_LABEL=""
    local INSTALLED_VERSION=""
    local TARGET_VERSION=""

    STATUS_LINE="$(get_npm_global_status "$PACKAGE_NAME" "$PACKAGE_BIN")"
    IFS='|' read -r STATUS_LABEL INSTALLED_VERSION TARGET_VERSION <<< "$STATUS_LINE"

    case "$STATUS_LABEL" in
        instalado)
            log_success "$LABEL: instalado ($INSTALLED_VERSION)"
            ;;
        desactualizado)
            log_warn "$LABEL: desactualizado ($INSTALLED_VERSION -> $TARGET_VERSION)"
            ;;
        *)
            log_info "$LABEL: pendiente de instalar"
            ;;
    esac
}

log_claude_tool_status() {
    if command -v claude >/dev/null 2>&1; then
        log_info "Claude Code CLI: instalado; la comprobacion de actualizaciones se hara con: claude update"
    else
        log_info "Claude Code CLI: pendiente de instalar"
    fi
}

install_yay() {
    if command -v yay >/dev/null 2>&1; then
        log "${GREEN}yay ya instalado.${NC}"
        return
    fi

    log "${YELLOW}3. Instalando yay (requiere compilador Go)...${NC}"

    # Instalamos go aquí porque es necesario para compilar yay
    run_cmd sudo pacman -S --needed --noconfirm go

    local YAY_TMP
    YAY_TMP="$(mktemp -d /tmp/yay-build.XXXXXX)"

    run_cmd git clone https://aur.archlinux.org/yay.git "$YAY_TMP"
    run_shell "cd \"$YAY_TMP\" && makepkg -si --noconfirm"
}

install_flatpak() {
    log "${YELLOW}Instalando Flatpak y configurando Flathub...${NC}"
    run_cmd sudo pacman -S --needed --noconfirm flatpak flatpak-kcm
    run_cmd flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

update_system_repos() {
    log "${YELLOW}1. Sincronizando repositorios y actualizando sistema...${NC}"
    run_cmd sudo pacman -Syyu --noconfirm
}

install_base_devel() {
    local BASE_DEV_PACKAGES=(
        base-devel
        git
    )
    log "${YELLOW}2. Instalando herramientas base de desarrollo (git, base-devel)...${NC}"
    run_cmd sudo pacman -S --needed --noconfirm "${BASE_DEV_PACKAGES[@]}"
}

install_official_packages() {
    local COMMON_PACKAGES=(
        curl
        wget
        unzip
        zip
        jq
        yq
        ripgrep
        fd
        bat
        eza
        btop
        fastfetch
        fzf
        tree
        tmux
        zsh
        kitty
        neovim
        python
        python-pip
        docker
        docker-compose
        iwd
        lazydocker
        github-cli
        opencode
        shellcheck
        shfmt
        direnv
        nmap
        wireshark-qt
        mtr
        bind
        inetutils
        ffmpeg
        yt-dlp
        firefox
        syncthing
        kdeconnect
        solaar
        piper
        libratbag
        wl-clipboard
        noto-fonts
        noto-fonts-emoji
    )
    log "${YELLOW}5. Instalando paquetes oficiales de repositorio...${NC}"
    log_package_batch_state "repo" "repo" "${COMMON_PACKAGES[@]}"
    run_cmd sudo pacman -S --needed --noconfirm "${COMMON_PACKAGES[@]}"
}

install_kde_packages() {
    local KDE_PACKAGES=(
        spectacle
        dolphin
        ark
        gwenview
        kate
        kcalc
        filelight
        plasma-systemmonitor
    )
    log "${YELLOW}6. Instalando base KDE Plasma...${NC}"
    log_package_batch_state "repo" "repo" "${KDE_PACKAGES[@]}"
    run_cmd sudo pacman -S --needed --noconfirm "${KDE_PACKAGES[@]}"
}

install_aur_packages() {
    log "${YELLOW}7. Instalando paquetes desde AUR...${NC}"
    install_base_devel
    install_yay
    log_package_batch_state "AUR" "aur" \
        visual-studio-code-bin \
        brave-bin \
        opencode-desktop-bin \
        ttf-jetbrains-mono-nerd \
        pamac-aur \
        webapp-manager
    run_cmd yay -S --needed --noconfirm \
        visual-studio-code-bin \
        brave-bin \
        opencode-desktop-bin \
        ttf-jetbrains-mono-nerd \
        pamac-aur \
        webapp-manager
}

install_handy_package() {
    log "${YELLOW}Instalando Handy desde AUR...${NC}"
    install_base_devel
    install_yay
    log_package_batch_state "AUR" "aur" handy-bin
    run_cmd yay -S --needed --noconfirm handy-bin
}

find_repo_dir_by_name() {
    local OVERRIDE_DIR="$1"
    local SEARCH_PATTERN="$2"
    local SEARCH_DIRS=()
    local CANDIDATES=()
    local SEARCH_DIR=""
    local MATCH=""

    if [ -n "$OVERRIDE_DIR" ]; then
        if [ -d "$OVERRIDE_DIR" ]; then
            printf '%s\n' "$OVERRIDE_DIR"
            return 0
        fi

        log_warn "Ruta configurada no encontrada: $OVERRIDE_DIR"
        return 1
    fi

    mapfile -t SEARCH_DIRS < <(get_repo_search_dirs)
    for SEARCH_DIR in "${SEARCH_DIRS[@]}"; do
        [ -d "$SEARCH_DIR" ] || continue
        while IFS= read -r -d '' MATCH; do
            if [ -d "$MATCH/.git" ] || [ -f "$MATCH/.git" ]; then
                CANDIDATES+=("$MATCH")
            fi
        done < <(find "$SEARCH_DIR" -mindepth 1 -maxdepth 3 -type d -iname "$SEARCH_PATTERN" -print0 2>/dev/null)
    done

    if [ ${#CANDIDATES[@]} -eq 0 ]; then
        return 1
    fi

    printf '%s\n' "${CANDIDATES[0]}"
}

find_codexbar_tray_repo_dir() {
    find_repo_dir_by_name "$CODEXBAR_TRAY_REPO_DIR" "codexbar-tray*"
}

get_talk2ai_repo_url() {
    printf '%s\n' "https://github.com/GOTXE/talk2ai.git"
}

get_talk2ai_managed_dir() {
    local DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    printf '%s\n' "$DATA_HOME/linux-migration-tool/repos/talk2ai"
}

sync_talk2ai_repo() {
    local REPO_URL=""
    local TARGET_DIR=""

    REPO_URL="$(get_talk2ai_repo_url)"
    TARGET_DIR="$(get_talk2ai_managed_dir)"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] preparar checkout gestionado de talk2ai en $TARGET_DIR${NC}"
        log "${YELLOW}[DRY-RUN] git clone --depth=1 $REPO_URL $TARGET_DIR${NC}"
        log "${YELLOW}[DRY-RUN] o git -C $TARGET_DIR pull --ff-only${NC}"
        printf '%s\n' "$TARGET_DIR"
        return 0
    fi

    run_cmd mkdir -p "$(dirname "$TARGET_DIR")"

    if [ -d "$TARGET_DIR/.git" ]; then
        log_info "Actualizando checkout gestionado de talk2ai..."
        run_cmd git -C "$TARGET_DIR" fetch --depth=1 origin
        run_shell "cd \"$TARGET_DIR\" && git pull --ff-only"
    else
        log_info "Clonando talk2ai desde GitHub..."
        run_cmd git clone --depth=1 "$REPO_URL" "$TARGET_DIR"
    fi

    printf '%s\n' "$TARGET_DIR"
}

install_talk2ai_from_github() {
    local REPO_DIR=""

    install_handy_package

    REPO_DIR="$(sync_talk2ai_repo)"

    if [ ! -f "$REPO_DIR/install.sh" ]; then
        log_warn "El checkout gestionado de talk2ai no contiene install.sh: $REPO_DIR"
        return 1
    fi

    log "${YELLOW}Instalando/actualizando talk2ai desde GitHub...${NC}"
    log_info "Checkout gestionado: $REPO_DIR"
    log_info "Se respondera 'no' al contexto opcional del instalador para mantener el flujo no interactivo."
    run_shell "cd \"$REPO_DIR\" && printf 'n\n' | bash ./install.sh"
}

install_talk2ai_if_accepted() {
    log_info "talk2ai se descargara o actualizara desde GitHub en un checkout gestionado por el instalador."
    if confirm_action "¿Instalar/actualizar talk2ai desde GitHub?"; then
        install_talk2ai_from_github
    else
        log_info "Instalacion de talk2ai omitida por decision del usuario."
    fi
}

install_obsidian_package() {
    log "${YELLOW}Instalando Obsidian desde repositorio oficial...${NC}"
    log_package_batch_state "repo" "repo" obsidian
    run_cmd sudo pacman -S --needed --noconfirm obsidian
}

install_markdownpart_package() {
    log "${YELLOW}Instalando markdownpart desde repositorio oficial...${NC}"
    log_package_batch_state "repo" "repo" markdownpart
    run_cmd sudo pacman -S --needed --noconfirm markdownpart
}

install_markdownpart_if_accepted() {
    if confirm_action "¿Instalar MarkdownPart para vista previa Markdown en Kate?"; then
        install_markdownpart_package
    else
        log_info "Instalacion de MarkdownPart omitida por decision del usuario."
    fi
}

install_libreoffice_package() {
    log "${YELLOW}Instalando LibreOffice Fresh ES desde repositorio oficial...${NC}"
    log_package_batch_state "repo" "repo" libreoffice-fresh-es
    run_cmd sudo pacman -S --needed --noconfirm libreoffice-fresh-es
}

install_libreoffice_if_accepted() {
    if confirm_action "¿Instalar LibreOffice Fresh ES como suite ofimatica opcional?"; then
        install_libreoffice_package
    else
        log_info "Instalacion de LibreOffice Fresh ES omitida por decision del usuario."
    fi
}

install_filezilla_package() {
    log "${YELLOW}Instalando FileZilla desde repositorio oficial...${NC}"
    log_package_batch_state "repo" "repo" filezilla
    run_cmd sudo pacman -S --needed --noconfirm filezilla
}

install_restic_package() {
    log "${YELLOW}Instalando Restic desde repositorio oficial...${NC}"
    log_package_batch_state "repo" "repo" restic
    run_cmd sudo pacman -S --needed --noconfirm restic
}

install_sshpass_package() {
    log "${YELLOW}Instalando sshpass desde repositorio oficial...${NC}"
    log_package_batch_state "repo" "repo" sshpass
    run_cmd sudo pacman -S --needed --noconfirm sshpass
}

install_ipscan_package() {
    log "${YELLOW}Instalando Angry IP Scanner desde AUR...${NC}"
    install_base_devel
    install_yay
    log_package_batch_state "AUR" "aur" angryipscanner
    run_cmd yay -S --needed --noconfirm angryipscanner
}

install_ipscan_if_accepted() {
    if confirm_action "¿Instalar Angry IP Scanner desde AUR como herramienta de red opcional?"; then
        install_ipscan_package
    else
        log_info "Instalacion de Angry IP Scanner omitida por decision del usuario."
    fi
}

install_filezilla_if_accepted() {
    if confirm_action "¿Instalar FileZilla como cliente SFTP/FTP opcional?"; then
        install_filezilla_package
    else
        log_info "Instalacion de FileZilla omitida por decision del usuario."
    fi
}

install_restic_if_accepted() {
    log_info "Restic puede usarse para backups/restores contra repositorios SFTP/SSH."
    if confirm_action "¿Instalar Restic como herramienta de backup/restore?" "yes"; then
        install_restic_package
    else
        log_info "Instalacion de Restic omitida por decision del usuario."
    fi
}

install_codexbar_tray_dependencies() {
    log "${YELLOW}Preparando dependencias de codexBar Tray...${NC}"
    log_package_batch_state "repo" "repo" python-pyqt6
    run_cmd sudo pacman -S --needed --noconfirm python-pyqt6

    if command -v codexbar >/dev/null 2>&1; then
        log_success "codexbar CLI ya disponible en PATH."
        return 0
    fi

    log_info "codexbar CLI no detectado. Se intentara instalar desde AUR (codexbar-cli)."
    install_base_devel
    install_yay
    log_package_batch_state "AUR" "aur" codexbar-cli
    run_cmd yay -S --needed --noconfirm codexbar-cli
}

install_codexbar_tray_from_local_repo() {
    local REPO_DIR=""

    REPO_DIR="$(find_codexbar_tray_repo_dir 2>/dev/null || true)"
    if [ -z "$REPO_DIR" ]; then
        log_warn "No se encontro un repo local de codexBar Tray en las rutas de repos configuradas."
        log_warn "Puedes fijarlo en tu config con CODEXBAR_TRAY_REPO_DIR."
        return 1
    fi

    if [ ! -f "$REPO_DIR/scripts/install_systemd_user_service.sh" ]; then
        log_warn "El repo detectado de codexBar Tray no contiene el instalador esperado: $REPO_DIR"
        return 1
    fi

    install_codexbar_tray_dependencies

    log "${YELLOW}Instalando codexBar Tray desde repo local detectado...${NC}"
    log_info "Repo detectado: $(basename "$REPO_DIR")"
    run_shell "cd \"$REPO_DIR\" && bash ./scripts/install_desktop_entry.sh --autostart"
    run_shell "cd \"$REPO_DIR\" && bash ./scripts/install_systemd_user_service.sh"
}

install_codexbar_tray_if_accepted() {
    local REPO_DIR=""

    REPO_DIR="$(find_codexbar_tray_repo_dir 2>/dev/null || true)"
    [ -n "$REPO_DIR" ] || return 0

    log_info "Repo local de codexBar Tray detectado: $(basename "$REPO_DIR")"
    log_info "Se instalara desde el repo restaurado y, si hace falta, intentara preparar codexbar-cli."
    if confirm_action "¿Instalar codexBar Tray desde el repo local detectado?"; then
        install_codexbar_tray_from_local_repo
    else
        log_info "Instalacion de codexBar Tray omitida por decision del usuario."
    fi
}

setup_docker() {
    log "${YELLOW}8. Configurando servicios finales (Docker)...${NC}"
    run_cmd sudo systemctl enable docker
    run_cmd sudo systemctl start docker
    run_cmd sudo usermod -aG docker "$USER"
}

install_packages() {
    update_system_repos
    install_base_devel
    install_yay
    install_flatpak
    install_official_packages
    install_kde_packages
    install_aur_packages
    setup_docker
}

install_ohmyzsh() {
    if [ -d "$HOME/.oh-my-zsh" ]; then
        log "${GREEN}Oh My Zsh ya instalado.${NC}"
        return
    fi

    log "${YELLOW}Instalando Oh My Zsh...${NC}"
    run_shell "RUNZSH=no CHSH=no sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
}

install_powerlevel10k() {
    if [ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
        return
    fi

    log "${YELLOW}Instalando Powerlevel10k...${NC}"

    run_cmd git clone --depth=1 \
        https://github.com/romkatv/powerlevel10k.git \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

    run_cmd sed -i \
        's/ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' \
        "$HOME/.zshrc"
}

install_node_stack() {
    if [ ! -d "$HOME/.nvm" ]; then
        log "${YELLOW}Instalando NVM...${NC}"
        run_shell "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash"
    fi

    export NVM_DIR="$HOME/.nvm"

    # shellcheck disable=SC1090,SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    log "${YELLOW}Instalando Node LTS...${NC}"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] nvm install --lts${NC}"
    else
        nvm install --lts
    fi

    log "${YELLOW}Instalando pnpm y bun...${NC}"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] npm install -g pnpm${NC}"
    else
        npm install -g pnpm
    fi

    run_shell "curl -fsSL https://bun.sh/install | bash"
}

log_gemini_tool_status() {
    log_npm_tool_status "Gemini CLI" "@google/gemini-cli" "gemini"
}

log_opencode_tool_status() {
    if command -v opencode >/dev/null 2>&1; then
        log_success "OpenCode CLI: instalado"
    else
        log_info "OpenCode CLI: pendiente de instalar"
    fi
}

install_codex_cli() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1090,SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    log "${YELLOW}Instalando/Actualizando Codex CLI...${NC}"
    log_npm_tool_status "Codex CLI" "@openai/codex" "codex"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] npm install -g @openai/codex@latest${NC}"
    else
        npm install -g @openai/codex@latest 2>&1 | tee -a "$LOGFILE"
    fi
    link_npm_global_binaries
}

install_claude_cli() {
    log "${YELLOW}Instalando/Actualizando Claude Code CLI...${NC}"
    log_claude_tool_status

    if command -v claude >/dev/null 2>&1; then
        if [ "$DRY_MODE" = true ]; then
            log "${YELLOW}[DRY-RUN] claude update${NC}"
        else
            claude update 2>&1 | tee -a "$LOGFILE" || true
        fi
    else
        run_shell "curl -fsSL https://claude.ai/install.sh | bash"
    fi
}

install_gemini_cli() {
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1090,SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    log "${YELLOW}Instalando/Actualizando Gemini CLI...${NC}"
    log_gemini_tool_status

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] npm install -g @google/gemini-cli@latest${NC}"
    else
        npm install -g @google/gemini-cli@latest 2>&1 | tee -a "$LOGFILE"
    fi
    link_npm_global_binaries
}

install_opencode_cli() {
    log "${YELLOW}Instalando OpenCode CLI...${NC}"
    log_opencode_tool_status
    # OpenCode suele venir con el paquete de repositorio o AUR ya configurado en install_packages/install_aur_packages
    # Aquí aseguramos que esté presente o damos instrucciones
    if ! command -v opencode >/dev/null 2>&1; then
        run_cmd sudo pacman -S --needed --noconfirm opencode || yay -S --needed --noconfirm opencode-desktop-bin
    fi
}

install_ai_tools() {
    install_codex_cli
    install_claude_cli
    install_gemini_cli
    install_opencode_cli
    
    configure_shell_paths
    verify_ai_tools
}

link_npm_global_binaries() {
    local NPM_BIN_DIR=""
    local BIN_NAME

    [ "$DRY_MODE" = true ] && return 0
    command -v npm >/dev/null 2>&1 || return 0

    NPM_BIN_DIR="$(npm prefix -g 2>/dev/null)/bin"
    [ -d "$NPM_BIN_DIR" ] || return 0

    run_cmd mkdir -p "$HOME/.local/bin"

    for BIN_NAME in codex gemini pnpm bun; do
        if [ -x "$NPM_BIN_DIR/$BIN_NAME" ]; then
            run_cmd ln -sf "$NPM_BIN_DIR/$BIN_NAME" "$HOME/.local/bin/$BIN_NAME"
        fi
    done
}

configure_shell_paths() {
    local FISH_DIR="$HOME/.config/fish/conf.d"
    local FISH_FILE="$FISH_DIR/linux-migration-tool-paths.fish"
    local ZSH_MARKER="# linux-migration-tool PATH"

    log "${YELLOW}Configurando PATH de usuario para shells habituales...${NC}"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] configurar PATH en fish/zsh/bash para ~/.local/bin, ~/.bun/bin y npm global via nvm${NC}"
        return 0
    fi

    mkdir -p "$HOME/.local/bin" "$FISH_DIR"

    cat > "$FISH_FILE" <<'EOF_FISH'
# linux-migration-tool PATH
fish_add_path -m "$HOME/.local/bin"
fish_add_path -m "$HOME/.bun/bin"
for node_bin in "$HOME"/.nvm/versions/node/*/bin
    if test -d "$node_bin"
        fish_add_path -m "$node_bin"
    end
end
EOF_FISH

    for SHELL_RC in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
        touch "$SHELL_RC"
        if ! grep -q "$ZSH_MARKER" "$SHELL_RC"; then
            cat >> "$SHELL_RC" <<'EOF_SH'

# linux-migration-tool PATH
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
EOF_SH
        fi
    done

    log "PATH configurado. Abre una terminal nueva o ejecuta: source ~/.config/fish/conf.d/linux-migration-tool-paths.fish"
}

verify_ai_tools() {
    log "${YELLOW}Verificando herramientas IA...${NC}"

    for TOOL in codex claude gemini opencode; do
        if command -v "$TOOL" >/dev/null 2>&1; then
            log "$TOOL detectado en: $(command -v "$TOOL")"
            "$TOOL" --version 2>&1 | head -n 1 | tee -a "$LOGFILE" || true
        else
            log "${YELLOW}$TOOL no esta en PATH de esta sesion.${NC}"
        fi
    done
}

install_hyprland() {
    local HYPRLAND_PACKAGES=(
        hyprland
        waybar
        rofi-wayland
        hyprpaper
        grim
        slurp
        mako
    )

    if [ "$HYPRLAND_MODE" = "ask" ]; then
        if confirm_action "¿Instalar Hyprland opcional?"; then
            HYPRLAND_MODE="yes"
        else
            HYPRLAND_MODE="no"
        fi
    fi

    if [ "$HYPRLAND_MODE" = "yes" ]; then
        run_cmd sudo pacman -S --needed --noconfirm "${HYPRLAND_PACKAGES[@]}"
    fi
}

install_apple_laptop_extras() {
    local APPLE_LAPTOP_PACKAGES=(
        thermald
        powertop
        lm_sensors
    )
    local MISSING_APPLE_PACKAGES=()
    local PACKAGE_NAME=""
    local PACKAGE_SUMMARY=""

    collect_missing_packages() {
        local PACKAGE

        for PACKAGE in "$@"; do
            if pacman -Q "$PACKAGE" >/dev/null 2>&1; then
                log "${GREEN}Ya presente por defecto o instalado previamente:${NC} $PACKAGE"
            else
                MISSING_APPLE_PACKAGES+=("$PACKAGE")
            fi
        done
    }

    if [ "$APPLE_LAPTOP_MODE" = "ask" ]; then
        if is_apple_laptop; then
            log "${YELLOW}Equipo Apple Intel detectado.${NC} Revisando extras especificos para MBP 2015 frente a lo que ya trae CachyOS..."
            collect_missing_packages "${APPLE_LAPTOP_PACKAGES[@]}"

            if [ "${#MISSING_APPLE_PACKAGES[@]}" -eq 0 ]; then
                log "${GREEN}No hay extras Apple pendientes.${NC} CachyOS ya tiene los paquetes previstos para este bloque."
                APPLE_LAPTOP_MODE="no"
            else
                log "Se van a instalar estos extras Apple que no estan presentes ahora mismo:"
                for PACKAGE_NAME in "${MISSING_APPLE_PACKAGES[@]}"; do
                    log " - $PACKAGE_NAME"
                done

                PACKAGE_SUMMARY="${MISSING_APPLE_PACKAGES[*]}"

                if confirm_action "Equipo Apple detectado. Se instalaran estos extras no presentes (${PACKAGE_SUMMARY}). ¿Continuar con la instalacion para Apple laptop Intel (MBP 2015)?"; then
                    APPLE_LAPTOP_MODE="yes"
                else
                    APPLE_LAPTOP_MODE="no"
                fi
            fi
        else
            APPLE_LAPTOP_MODE="no"
        fi
    fi

    if [ "$APPLE_LAPTOP_MODE" = "yes" ]; then
        log "${YELLOW}Instalando extras de portatil Apple Intel...${NC}"
        if [ "${#MISSING_APPLE_PACKAGES[@]}" -eq 0 ]; then
            collect_missing_packages "${APPLE_LAPTOP_PACKAGES[@]}"
        fi

        if [ "${#MISSING_APPLE_PACKAGES[@]}" -eq 0 ]; then
            log "${GREEN}No hay paquetes Apple extra pendientes de instalar.${NC}"
        else
            run_cmd sudo pacman -S --needed --noconfirm "${MISSING_APPLE_PACKAGES[@]}"
        fi
        run_cmd sudo systemctl enable thermald
        run_cmd sudo systemctl start thermald
    fi
}

install_mbp_watch_diagnostics() {
    local SOURCE_SCRIPT="$PROJECT_ROOT/assets/diagnostics/mbp_watch.sh"
    local SOURCE_SERVICE="$PROJECT_ROOT/assets/diagnostics/mbp-watch.service"
    local SOURCE_UNINSTALL="$PROJECT_ROOT/assets/diagnostics/uninstall_mbp_watch.sh"
    local SOURCE_WEB_DIR="$PROJECT_ROOT/assets/diagnostics/web"
    local TARGET_BIN="/usr/local/bin/mbp_watch.sh"
    local TARGET_UNINSTALL="/usr/local/sbin/uninstall_mbp_watch.sh"
    local TARGET_SERVICE="/etc/systemd/system/mbp-watch.service"
    local TARGET_CONFIG="/etc/mbp-watch.conf"
    local DESKTOP_DIR
    local REPORT_DESKTOP
    local REPORT_PATH="/var/lib/mbp-watch/report.html"
    local REPORT_TEXT="/var/lib/mbp-watch/report.txt"

    DESKTOP_DIR="$(get_desktop_dir)"
    REPORT_DESKTOP="$DESKTOP_DIR/MBP-Watch-Report.desktop"

    log "${YELLOW}Instalando diagnostico MBP Watch...${NC}"

    run_cmd mkdir -p "$DESKTOP_DIR"
    run_cmd sudo mkdir -p /usr/local/bin /usr/local/sbin /etc/systemd/system /var/lib/mbp-watch
    run_cmd sudo cp "$SOURCE_SCRIPT" "$TARGET_BIN"
    run_cmd sudo chmod +x "$TARGET_BIN"
    run_cmd sudo cp "$SOURCE_UNINSTALL" "$TARGET_UNINSTALL"
    run_cmd sudo chmod +x "$TARGET_UNINSTALL"
    run_cmd sudo cp "$SOURCE_SERVICE" "$TARGET_SERVICE"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] copiar archivos web estaticos a /var/lib/mbp-watch${NC}"
    else
        for WEB_FILE in report.html report.css report.js; do
            if [ -f "$SOURCE_WEB_DIR/$WEB_FILE" ]; then
                sudo cp "$SOURCE_WEB_DIR/$WEB_FILE" "/var/lib/mbp-watch/$WEB_FILE"
            else
                log "${YELLOW}AVISO: no encontrado $SOURCE_WEB_DIR/$WEB_FILE${NC}"
            fi
        done
    fi

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir $TARGET_CONFIG${NC}"
        log "${YELLOW}[DRY-RUN] instalar lanzador Desktop: $REPORT_DESKTOP${NC}"
    else
        printf 'MBP_WATCH_DIR=/var/lib/mbp-watch\nMBP_WATCH_INTERVAL=5\nMBP_WATCH_PORT=7070\n' \
            | sudo tee "$TARGET_CONFIG" >/dev/null

        cat > "$REPORT_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=MBP Watch Report
Comment=Open the MBP diagnostics report
Exec=xdg-open "http://localhost:7070/report.html"
Terminal=false
Icon=utilities-system-monitor
Categories=System;Monitor;
EOF
        chmod +x "$REPORT_DESKTOP"
    fi

    run_cmd sudo systemctl daemon-reload
    run_cmd sudo systemctl enable --now mbp-watch.service

    if [ "$DRY_MODE" = false ]; then
        "$TARGET_BIN" report >/dev/null 2>&1 || true
    fi

    log "Lanzador Desktop:"
    log "$REPORT_DESKTOP"
    log "Datos persistentes:"
    log "$REPORT_PATH"
    log "AI digest (report.txt para analisis IA):"
    log "$REPORT_TEXT"
    log "Desinstalador:"
    log "$TARGET_UNINSTALL"
}

is_kde_plasma_session() {
    local DESKTOP_HINTS=""
    local TARGET_USER=""

    DESKTOP_HINTS="$(printf '%s %s %s\n' \
        "${XDG_CURRENT_DESKTOP:-}" \
        "${DESKTOP_SESSION:-}" \
        "${KDE_FULL_SESSION:-}")"

    if printf '%s\n' "$DESKTOP_HINTS" | grep -Eiq 'kde|plasma'; then
        return 0
    fi

    TARGET_USER="$(resolve_desktop_target_user 2>/dev/null || true)"
    if [ -n "$TARGET_USER" ] && pgrep -u "$TARGET_USER" -x plasmashell >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

resolve_desktop_target_user() {
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
        return 0
    fi

    if [ -n "${USER:-}" ] && [ "${USER}" != "root" ]; then
        printf '%s\n' "$USER"
        return 0
    fi

    return 1
}

resolve_desktop_target_uid() {
    local TARGET_USER="$1"

    id -u "$TARGET_USER" 2>/dev/null
}

has_plasma_session_bus() {
    local TARGET_UID="$1"

    [ -S "/run/user/$TARGET_UID/bus" ]
}

has_required_plasmoid_tools() {
    command -v kpackagetool6 >/dev/null 2>&1 || return 1
    command -v qdbus6 >/dev/null 2>&1 || return 1
}

list_mbp_plasmoid_outputs() {
    local RAW_OUTPUT=""

    command -v kscreen-doctor >/dev/null 2>&1 || return 0

    RAW_OUTPUT="$(kscreen-doctor -o 2>/dev/null || true)"
    if [ -n "$RAW_OUTPUT" ]; then
        printf '%s\n' "$RAW_OUTPUT" | awk '/^Output:/ { print $2 "|" $3 }'
        return 0
    fi

    if command -v script >/dev/null 2>&1; then
        RAW_OUTPUT="$(
            env SHELL=/bin/bash script -qfc "kscreen-doctor -o" /dev/null 2>/dev/null \
                | sed 's/\r$//' \
            || true
        )"
        if [ -n "$RAW_OUTPUT" ]; then
            printf '%s\n' "$RAW_OUTPUT" | awk '/^Output:/ { print $2 "|" $3 }'
            return 0
        fi
    fi
}

normalize_mbp_plasmoid_target() {
    local REQUESTED_TARGET="${1:-primary}"
    local OUTPUTS=()
    local ENTRY=""
    local OUTPUT_ID=""
    local OUTPUT_NAME=""

    case "$REQUESTED_TARGET" in
        screen:[0-9]*)
            printf '%s\n' "$REQUESTED_TARGET"
            return 0
            ;;
        primary|"")
            mapfile -t OUTPUTS < <(list_mbp_plasmoid_outputs)

            for ENTRY in "${OUTPUTS[@]}"; do
                OUTPUT_ID="${ENTRY%%|*}"
                OUTPUT_NAME="${ENTRY#*|}"
                if printf '%s\n' "$OUTPUT_NAME" | grep -Eiq '^(eDP|LVDS|DSI)'; then
                    printf 'screen:%s\n' "$OUTPUT_ID"
                    return 0
                fi
            done

            if [ ${#OUTPUTS[@]} -gt 0 ]; then
                OUTPUT_ID="${OUTPUTS[0]%%|*}"
                printf 'screen:%s\n' "$OUTPUT_ID"
                return 0
            fi

            printf 'screen:0\n'
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

log_mbp_plasmoid_outputs() {
    local OUTPUTS=()
    local ENTRY=""
    local OUTPUT_ID=""
    local OUTPUT_NAME=""

    mapfile -t OUTPUTS < <(list_mbp_plasmoid_outputs)
    if [ ${#OUTPUTS[@]} -eq 0 ]; then
        tty_log "${CYAN}No se pudieron enumerar salidas de Plasma con kscreen-doctor; se usara el fallback interno.${NC}"
        return 0
    fi

    tty_log "${CYAN}Salidas KDE detectadas para el plasmoid:${NC}"
    for ENTRY in "${OUTPUTS[@]}"; do
        OUTPUT_ID="${ENTRY%%|*}"
        OUTPUT_NAME="${ENTRY#*|}"
        tty_log " - screen:${OUTPUT_ID} -> ${OUTPUT_NAME}"
    done
}

prompt_mbp_plasmoid_target() {
    local DEFAULT_TARGET="${1:-$MBP_PLASMOID_TARGET}"
    local NORMALIZED_DEFAULT_TARGET=""
    local OUTPUTS=()
    local ENTRY=""
    local OUTPUT_ID=""
    local OUTPUT_NAME=""
    local OPTION_INDEX=1
    local DEFAULT_OPTION_INDEX=""
    local TARGET_VALUE=""

    if ! NORMALIZED_DEFAULT_TARGET="$(normalize_mbp_plasmoid_target "$DEFAULT_TARGET" 2>/dev/null)"; then
        NORMALIZED_DEFAULT_TARGET="screen:1"
    fi

    mapfile -t OUTPUTS < <(list_mbp_plasmoid_outputs)
    if [ ${#OUTPUTS[@]} -eq 0 ]; then
        tty_log "${CYAN}No se pudieron enumerar salidas de Plasma con kscreen-doctor; se usara el fallback interno.${NC}"
        prompt_read "Destino del plasmoid [primary|screen:N] (default: ${DEFAULT_TARGET}): " TARGET_VALUE
        if [ -z "$TARGET_VALUE" ]; then
            TARGET_VALUE="$DEFAULT_TARGET"
        fi
        printf '%s\n' "$TARGET_VALUE"
        return 0
    fi

    tty_log "${CYAN}Pantallas KDE detectadas para el plasmoid:${NC}"
    for ENTRY in "${OUTPUTS[@]}"; do
        OUTPUT_ID="${ENTRY%%|*}"
        OUTPUT_NAME="${ENTRY#*|}"
        if [ "screen:${OUTPUT_ID}" = "$NORMALIZED_DEFAULT_TARGET" ]; then
            DEFAULT_OPTION_INDEX="$OPTION_INDEX"
            tty_log " ${GREEN}${OPTION_INDEX})${NC} ${OUTPUT_NAME} (${YELLOW}screen:${OUTPUT_ID}${NC}, por defecto)"
        else
            tty_log " ${GREEN}${OPTION_INDEX})${NC} ${OUTPUT_NAME} (${YELLOW}screen:${OUTPUT_ID}${NC})"
        fi
        OPTION_INDEX=$((OPTION_INDEX + 1))
    done
    tty_log " ${GREEN}p)${NC} principal automatica (${YELLOW}primary${NC})"

    if [ -n "$DEFAULT_OPTION_INDEX" ]; then
        prompt_read "Selecciona pantalla [1-${#OUTPUTS[@]}|p] (default: ${DEFAULT_OPTION_INDEX}): " TARGET_VALUE
    else
        prompt_read "Selecciona pantalla [1-${#OUTPUTS[@]}|p] (default: primary): " TARGET_VALUE
    fi

    if [ -z "$TARGET_VALUE" ]; then
        if [ -n "$DEFAULT_OPTION_INDEX" ]; then
            TARGET_VALUE="$DEFAULT_OPTION_INDEX"
        else
            TARGET_VALUE="primary"
        fi
    fi

    if [[ "$TARGET_VALUE" =~ ^[Pp]$ ]]; then
        printf 'primary\n'
        return 0
    fi

    if [[ "$TARGET_VALUE" =~ ^[0-9]+$ ]] && [ "$TARGET_VALUE" -ge 1 ] && [ "$TARGET_VALUE" -le ${#OUTPUTS[@]} ]; then
        ENTRY="${OUTPUTS[$((TARGET_VALUE - 1))]}"
        OUTPUT_ID="${ENTRY%%|*}"
        printf 'screen:%s\n' "$OUTPUT_ID"
        return 0
    fi

    printf '%s\n' "$TARGET_VALUE"
}

resolve_mbp_plasmoid_target() {
    local REQUESTED_TARGET="${1:-}"
    local DEFAULT_TARGET="${MBP_PLASMOID_TARGET:-primary}"

    if [ -n "$REQUESTED_TARGET" ]; then
        printf '%s\n' "$REQUESTED_TARGET"
        return 0
    fi

    if [ -t 0 ]; then
        prompt_mbp_plasmoid_target "$DEFAULT_TARGET"
        return 0
    fi

    printf '%s\n' "$DEFAULT_TARGET"
}

get_mbp_plasmoid_source_dir() {
    printf '%s/%s\n' "$PROJECT_ROOT" "$MBP_PLASMOID_RELATIVE_DIR"
}

is_mbp_plasmoid_installed() {
    local TARGET_USER="$1"

    sudo -u "$TARGET_USER" \
        kpackagetool6 --type "$MBP_PLASMOID_PACKAGE_TYPE" --list 2>/dev/null \
        | grep -Fq "$MBP_PLASMOID_ID"
}

install_or_upgrade_mbp_plasmoid() {
    local TARGET_USER="$1"
    local SOURCE_DIR="$2"
    local ACTION="--install"

    if is_mbp_plasmoid_installed "$TARGET_USER"; then
        ACTION="--upgrade"
        log_info "Plasmoid MBP Watch ya instalado para $TARGET_USER; aplicando upgrade."
    else
        log_info "Instalando plasmoid MBP Watch para $TARGET_USER."
    fi

    run_cmd sudo -u "$TARGET_USER" \
        kpackagetool6 --type "$MBP_PLASMOID_PACKAGE_TYPE" "$ACTION" "$SOURCE_DIR"
}

build_mbp_plasmoid_autoload_script() {
    local TARGET_SCREEN_INDEX="$1"

    cat <<EOF
var pluginId = "io.github.cachyosmigrationtool.mbpwatch";
var preferredScreen = ${TARGET_SCREEN_INDEX};
var widgetWidth = 360;
var widgetMargin = 24;
var widgetTop = 24;
var widgetMinHeight = 480;
var widgetMaxHeight = 920;
var result = "";

function widgetAlreadyPresent(allDesktops, expectedPluginId) {
    for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
        var desktop = allDesktops[desktopIndex];
        if (!desktop) {
            continue;
        }

        var typedWidgets = desktop.widgets(expectedPluginId);
        if (typedWidgets && typedWidgets.length > 0) {
            return true;
        }

        var ids = desktop.widgetIds || [];
        for (var idIndex = 0; idIndex < ids.length; idIndex += 1) {
            var widget = desktop.widgetById(ids[idIndex]);
            if (widget && widget.type === expectedPluginId) {
                return true;
            }
        }
    }

    return false;
}

if (!knownWidgetTypes || knownWidgetTypes.indexOf(pluginId) === -1) {
    result = "ERROR:plasmoid-not-installed";
} else {
    var allDesktops = desktops();

    if (widgetAlreadyPresent(allDesktops, pluginId)) {
        result = "OK:already-present";
    } else {
        var targetDesktop = null;

        if (typeof desktopForScreen === "function") {
            targetDesktop = desktopForScreen(preferredScreen);
        }

        if (!targetDesktop) {
            for (var desktopIndex = 0; desktopIndex < allDesktops.length; desktopIndex += 1) {
                var desktopCandidate = allDesktops[desktopIndex];
                if (desktopCandidate && desktopCandidate.screen === preferredScreen) {
                    targetDesktop = desktopCandidate;
                    break;
                }
            }
        }

        if (!targetDesktop && allDesktops.length > 0) {
            targetDesktop = allDesktops[0];
        }

        if (!targetDesktop) {
            result = "ERROR:no-desktop";
        } else {
            var targetScreen = targetDesktop.screen >= 0 ? targetDesktop.screen : 0;
            var geom = screenGeometry(targetScreen);
            var widgetHeight = Math.min(Math.max(geom.height - 48, widgetMinHeight), widgetMaxHeight);
            var widgetX = geom.x + geom.width - widgetWidth - widgetMargin;
            var widgetY = geom.y + widgetTop;

            var widget = targetDesktop.addWidget(
                pluginId,
                widgetX,
                widgetY,
                widgetWidth,
                widgetHeight
            );

            if (!widget) {
                result = "ERROR:create-failed";
            } else {
                result = "OK:created";
            }
        }
    }
}

result;
EOF
}

is_mbp_plasmoid_on_desktop() {
    local TARGET_USER="$1"
    local PLASMA_CFG=""

    PLASMA_CFG="$(eval echo "~$TARGET_USER")/.config/plasma-org.kde.plasma.desktop-appletsrc"
    [ -f "$PLASMA_CFG" ] && grep -Fq "plugin=$MBP_PLASMOID_ID" "$PLASMA_CFG"
}

auto_add_mbp_plasmoid_to_desktop() {
    local TARGET_USER="$1"
    local TARGET_UID="$2"
    local TARGET_SPEC="${3:-$MBP_PLASMOID_TARGET}"
    local SCRIPT=""
    local NORMALIZED_TARGET=""
    local TARGET_SCREEN_INDEX=""

    if ! NORMALIZED_TARGET="$(normalize_mbp_plasmoid_target "$TARGET_SPEC" 2>/dev/null)"; then
        printf 'ERROR:bad-target\n'
        return 1
    fi
    TARGET_SCREEN_INDEX="${NORMALIZED_TARGET#screen:}"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] auto-add KDE plasmoid via qdbus6 para $TARGET_USER en ${NORMALIZED_TARGET}${NC}"
        printf 'OK:created\n'
        return 0
    fi

    # qdbus6 no imprime el valor de retorno de evaluateScript a stdout;
    # el check de presencia se hace leyendo el config de Plasma directamente.
    if is_mbp_plasmoid_on_desktop "$TARGET_USER"; then
        printf 'OK:already-present\n'
        return 0
    fi

    SCRIPT="$(build_mbp_plasmoid_autoload_script "$TARGET_SCREEN_INDEX")"

    if sudo -u "$TARGET_USER" env \
        XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
        qdbus6 org.kde.plasmashell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript "$SCRIPT" >/dev/null 2>&1; then
        printf 'OK:created\n'
    else
        printf 'ERROR:create-failed\n'
    fi
}

log_mbp_plasmoid_auto_add_result() {
    local AUTO_ADD_RESULT="$1"

    case "$AUTO_ADD_RESULT" in
        *"OK:created"*)
            log_success "Plasmoid MBP Watch añadido automaticamente al escritorio KDE."
            ;;
        *"OK:already-present"*)
            log_success "La instancia del plasmoid MBP Watch ya existia en el escritorio."
            ;;
        *"ERROR:plasmoid-not-installed"*)
            log_warn "El auto-add no encontro el plasmoid instalado en Plasma. Verifica con: kpackagetool6 --type $MBP_PLASMOID_PACKAGE_TYPE --list"
            ;;
        *"ERROR:no-desktop"*)
            log_warn "Plasma no devolvio un desktop valido para auto-add."
            ;;
        *"ERROR:create-failed"*)
            log_warn "La creacion automatica de la instancia en el escritorio fallo."
            ;;
        *)
            log_warn "El auto-add no pudo completarse automaticamente."
            if [ -n "$AUTO_ADD_RESULT" ]; then
                log_warn "Salida de auto-add: $AUTO_ADD_RESULT"
            fi
            ;;
    esac
}

add_mbp_plasmoid_to_desktop() {
    local TARGET_USER=""
    local TARGET_UID=""
    local REQUESTED_TARGET="${1:-}"
    local NORMALIZED_TARGET=""
    local AUTO_ADD_RESULT=""

    if ! has_required_plasmoid_tools; then
        log_warn "Faltan herramientas requeridas para el plasmoid (kpackagetool6 y/o qdbus6)."
        return 0
    fi

    TARGET_USER="$(resolve_desktop_target_user 2>/dev/null || true)"
    if [ -z "$TARGET_USER" ]; then
        log_warn "No se pudo resolver un usuario de escritorio valido para el plasmoid."
        return 0
    fi

    TARGET_UID="$(resolve_desktop_target_uid "$TARGET_USER" 2>/dev/null || true)"
    if [ -z "$TARGET_UID" ]; then
        log_warn "No se pudo resolver el UID del usuario objetivo ($TARGET_USER)."
        return 0
    fi

    REQUESTED_TARGET="$(resolve_mbp_plasmoid_target "$REQUESTED_TARGET")"
    if ! NORMALIZED_TARGET="$(normalize_mbp_plasmoid_target "$REQUESTED_TARGET" 2>/dev/null)"; then
        log_warn "Target de plasmoid no valido: $REQUESTED_TARGET"
        return 0
    fi

    if ! is_mbp_plasmoid_installed "$TARGET_USER"; then
        log_warn "El plasmoid MBP Watch no aparece instalado para $TARGET_USER."
        log_warn "Instalalo primero desde bootstrap o con: kpackagetool6 --type $MBP_PLASMOID_PACKAGE_TYPE --install $(get_mbp_plasmoid_source_dir)"
        return 0
    fi

    if ! has_plasma_session_bus "$TARGET_UID"; then
        log_warn "No se detecto bus de sesion Plasma en /run/user/$TARGET_UID/bus."
        log_warn "Recuperacion manual: plasmawindowed $MBP_PLASMOID_ID o anadir el widget desde Plasma."
        return 0
    fi

    log_info "Reintentando auto-add del plasmoid MBP Watch para $TARGET_USER en ${NORMALIZED_TARGET}."
    AUTO_ADD_RESULT="$(auto_add_mbp_plasmoid_to_desktop "$TARGET_USER" "$TARGET_UID" "$NORMALIZED_TARGET" 2>&1 || true)"
    log_mbp_plasmoid_auto_add_result "$AUTO_ADD_RESULT"

    if [[ "$AUTO_ADD_RESULT" != *"OK:created"* && "$AUTO_ADD_RESULT" != *"OK:already-present"* ]]; then
        log_warn "Recuperacion manual recomendada: plasmawindowed $MBP_PLASMOID_ID o añadir el widget manualmente desde Plasma."
    fi
}

move_mbp_watch_plasmoid() {
    local MOVE_SCRIPT="$PROJECT_ROOT/assets/diagnostics/move_mbp_plasmoid.sh"
    local TARGET_SPEC="${1:-primary}"
    local NORMALIZED_TARGET=""
    local TARGET_USER=""
    local COMMAND_ARGS=()

    if [ ! -f "$MOVE_SCRIPT" ]; then
        log_warn "No se encontro el script de move del plasmoid: $MOVE_SCRIPT"
        return 0
    fi

    TARGET_USER="$(resolve_desktop_target_user 2>/dev/null || true)"
    if [ -z "$TARGET_USER" ]; then
        log_warn "No se pudo resolver un usuario KDE objetivo para el plasmoid."
        return 0
    fi

    if ! NORMALIZED_TARGET="$(normalize_mbp_plasmoid_target "$TARGET_SPEC" 2>/dev/null)"; then
        log_warn "Target de plasmoid no valido: $TARGET_SPEC"
        return 0
    fi

    log "${YELLOW}Se va a mover el plasmoid KDE MBP Watch para el usuario: $TARGET_USER${NC}"
    log " - Destino solicitado: $TARGET_SPEC"
    log " - Destino resuelto: $NORMALIZED_TARGET"
    log " - Se quitara la instancia activa y se recreara en la pantalla objetivo."
    log ""

    if ! confirm_action "¿Continuar con el movimiento del plasmoid KDE MBP Watch?"; then
        log_info "Movimiento del plasmoid cancelado por el usuario."
        return 0
    fi

    COMMAND_ARGS=(--user "$TARGET_USER" --target "$NORMALIZED_TARGET")
    if [ "$DRY_MODE" = true ]; then
        COMMAND_ARGS+=(--dry-run)
        bash "$MOVE_SCRIPT" "${COMMAND_ARGS[@]}" 2>&1 | tee -a "$LOGFILE"
        return "${PIPESTATUS[0]}"
    fi

    run_cmd bash "$MOVE_SCRIPT" "${COMMAND_ARGS[@]}"
}

install_mbp_plasmoid_if_accepted() {
    local TARGET_USER=""
    local TARGET_UID=""
    local SOURCE_DIR=""
    local REQUESTED_TARGET=""
    local NORMALIZED_TARGET=""
    local AUTO_ADD_RESULT=""

    if ! is_kde_plasma_session; then
        log_info "Entorno KDE Plasma no detectado. Se omite el plasmoid MBP Watch."
        return 0
    fi

    log_info "KDE Plasma detectado. El plasmoid MBP Watch instala un overlay de escritorio, usa popup temporal de ${MBP_PLASMOID_POPUP_TTL_MS} ms, abre la web completa cuando haya avisos o clic del usuario y se añadira automaticamente al escritorio si la sesion Plasma esta activa."
    if ! confirm_action "¿Instalar el plasmoid KDE de MBP Watch (overlay, avisos y acceso rapido a ${MBP_PLASMOID_WEB_URL})?"; then
        log_info "Instalacion del plasmoid MBP Watch omitida por decision del usuario."
        return 0
    fi

    if ! has_required_plasmoid_tools; then
        log_warn "Faltan herramientas requeridas para el plasmoid (kpackagetool6 y/o qdbus6). Se omite este bloque."
        return 0
    fi

    TARGET_USER="$(resolve_desktop_target_user 2>/dev/null || true)"
    if [ -z "$TARGET_USER" ]; then
        log_warn "No se pudo resolver un usuario de escritorio valido para instalar el plasmoid."
        return 0
    fi

    TARGET_UID="$(resolve_desktop_target_uid "$TARGET_USER" 2>/dev/null || true)"
    if [ -z "$TARGET_UID" ]; then
        log_warn "No se pudo resolver el UID del usuario objetivo ($TARGET_USER)."
        return 0
    fi

    SOURCE_DIR="$(get_mbp_plasmoid_source_dir)"
    if [ ! -d "$SOURCE_DIR" ] || [ ! -f "$SOURCE_DIR/metadata.json" ]; then
        log_warn "No se encontro el paquete del plasmoid en: $SOURCE_DIR"
        return 0
    fi

    REQUESTED_TARGET="$(prompt_mbp_plasmoid_target "$MBP_PLASMOID_TARGET")"
    if ! NORMALIZED_TARGET="$(normalize_mbp_plasmoid_target "$REQUESTED_TARGET" 2>/dev/null)"; then
        log_warn "Target de plasmoid no valido: $REQUESTED_TARGET"
        return 0
    fi

    log_info "Usuario objetivo del plasmoid: $TARGET_USER (uid $TARGET_UID)"
    log_info "Destino elegido para el plasmoid: $REQUESTED_TARGET -> $NORMALIZED_TARGET"
    if ! install_or_upgrade_mbp_plasmoid "$TARGET_USER" "$SOURCE_DIR"; then
        log_warn "No se pudo instalar o actualizar el plasmoid MBP Watch. El bootstrap continuara."
        return 0
    fi

    if ! has_plasma_session_bus "$TARGET_UID"; then
        log_warn "Plasmoid instalado para $TARGET_USER, pero no se detecto bus de sesion Plasma en /run/user/$TARGET_UID/bus."
        log_warn "Recuperacion manual: plasmawindowed $MBP_PLASMOID_ID o anadir el widget desde Plasma."
        return 0
    fi

    AUTO_ADD_RESULT="$(auto_add_mbp_plasmoid_to_desktop "$TARGET_USER" "$TARGET_UID" "$NORMALIZED_TARGET" 2>&1 || true)"
    log_mbp_plasmoid_auto_add_result "$AUTO_ADD_RESULT"

    if [[ "$AUTO_ADD_RESULT" != *"OK:created"* && "$AUTO_ADD_RESULT" != *"OK:already-present"* ]]; then
        log_warn "Recuperacion manual recomendada: plasmawindowed $MBP_PLASMOID_ID o añadir el widget manualmente desde Plasma."
    fi

    return 0
}

uninstall_mbp_watch_diagnostics() {
    local SERVICE_NAME="mbp-watch.service"
    local BIN_PATH="/usr/local/bin/mbp_watch.sh"
    local UNINSTALL_PATH="/usr/local/sbin/uninstall_mbp_watch.sh"
    local CONFIG_PATH="/etc/mbp-watch.conf"
    local SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
    local STATE_DIR="/var/lib/mbp-watch"
    local DESKTOP_DIR
    local DESKTOP_FILE

    DESKTOP_DIR="$(get_desktop_dir)"
    DESKTOP_FILE="$DESKTOP_DIR/MBP-Watch-Report.desktop"

    local INSTALLED=false
    for CHECK_PATH in "$BIN_PATH" "$SERVICE_PATH" "$CONFIG_PATH"; do
        if [ -f "$CHECK_PATH" ]; then
            INSTALLED=true
            break
        fi
    done

    if [ "$INSTALLED" = false ]; then
        log "${YELLOW}MBP Watch no parece estar instalado (no se encontraron archivos del sistema).${NC}"
        return 0
    fi

    log "${YELLOW}Se van a eliminar los siguientes archivos:${NC}"
    log " - $BIN_PATH"
    log " - $UNINSTALL_PATH"
    log " - $CONFIG_PATH"
    log " - $SERVICE_PATH"
    [ -f "$DESKTOP_FILE" ] && log " - $DESKTOP_FILE"
    log ""

    local PURGE_STATE=false
    if confirm_action "¿Eliminar también los datos de estado ($STATE_DIR logs, reportes)?"; then
        PURGE_STATE=true
    fi

    log "${YELLOW}Desinstalando MBP Watch...${NC}"

    run_cmd sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    run_cmd sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    run_cmd sudo systemctl daemon-reload

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] rm -f $BIN_PATH $UNINSTALL_PATH $CONFIG_PATH $SERVICE_PATH${NC}"
        [ -f "$DESKTOP_FILE" ] && log "${YELLOW}[DRY-RUN] rm -f $DESKTOP_FILE${NC}"
        [ "$PURGE_STATE" = true ] && log "${YELLOW}[DRY-RUN] rm -rf $STATE_DIR${NC}"
    else
        sudo rm -f "$BIN_PATH" "$UNINSTALL_PATH" "$CONFIG_PATH" "$SERVICE_PATH"
        [ -f "$DESKTOP_FILE" ] && rm -f "$DESKTOP_FILE" && log "Lanzador eliminado: $DESKTOP_FILE"
        if [ "$PURGE_STATE" = true ]; then
            sudo rm -rf "$STATE_DIR"
            log "Datos de estado eliminados: $STATE_DIR"
        else
            log "Datos de estado conservados en: $STATE_DIR"
            log "Para eliminarlos: sudo rm -rf $STATE_DIR"
        fi
    fi

    log_success "MBP Watch desinstalado."
}

uninstall_mbp_watch_plasmoid() {
    local UNINSTALL_SCRIPT="$PROJECT_ROOT/assets/diagnostics/uninstall_mbp_plasmoid.sh"
    local TARGET_USER=""
    local COMMAND_ARGS=()

    if [ ! -f "$UNINSTALL_SCRIPT" ]; then
        log_warn "No se encontro el desinstalador del plasmoid: $UNINSTALL_SCRIPT"
        return 0
    fi

    TARGET_USER="$(resolve_desktop_target_user 2>/dev/null || true)"
    if [ -z "$TARGET_USER" ]; then
        log_warn "No se pudo resolver un usuario KDE objetivo para el plasmoid."
        return 0
    fi

    log "${YELLOW}Se va a desinstalar el plasmoid KDE MBP Watch para el usuario: $TARGET_USER${NC}"
    log " - Se intentara quitar la instancia activa del escritorio via qdbus6."
    log " - Se eliminara el paquete Plasma con kpackagetool6 --remove."
    log " - No se editaran archivos internos de configuracion de Plasma."
    log ""

    if ! confirm_action "¿Continuar con la desinstalacion del plasmoid KDE MBP Watch?"; then
        log_info "Desinstalacion del plasmoid cancelada por el usuario."
        return 0
    fi

    COMMAND_ARGS=(--user "$TARGET_USER")
    if [ "$DRY_MODE" = true ]; then
        COMMAND_ARGS+=(--dry-run)
        bash "$UNINSTALL_SCRIPT" "${COMMAND_ARGS[@]}" 2>&1 | tee -a "$LOGFILE"
        return "${PIPESTATUS[0]}"
    fi

    run_cmd bash "$UNINSTALL_SCRIPT" "${COMMAND_ARGS[@]}"
}

reinstall_mbp_watch_plasmoid() {
    local REINSTALL_SCRIPT="$PROJECT_ROOT/assets/diagnostics/reinstall_mbp_plasmoid.sh"
    local REQUESTED_TARGET="${1:-}"
    local NORMALIZED_TARGET=""
    local TARGET_USER=""
    local COMMAND_ARGS=()

    if [ ! -f "$REINSTALL_SCRIPT" ]; then
        log_warn "No se encontro el reinstalador del plasmoid: $REINSTALL_SCRIPT"
        return 0
    fi

    TARGET_USER="$(resolve_desktop_target_user 2>/dev/null || true)"
    if [ -z "$TARGET_USER" ]; then
        log_warn "No se pudo resolver un usuario KDE objetivo para el plasmoid."
        return 0
    fi

    REQUESTED_TARGET="$(resolve_mbp_plasmoid_target "$REQUESTED_TARGET")"
    if ! NORMALIZED_TARGET="$(normalize_mbp_plasmoid_target "$REQUESTED_TARGET" 2>/dev/null)"; then
        log_warn "Target de plasmoid no valido: $REQUESTED_TARGET"
        return 0
    fi

    log "${YELLOW}Se va a reinstalar el plasmoid KDE MBP Watch para el usuario: $TARGET_USER${NC}"
    log " - Se quitara la instancia actual del escritorio y el paquete Plasma."
    log " - Se reinstalara el paquete desde el repo actual."
    log " - No se reiniciara plasmashell; se reutilizara la sesion activa."
    log " - Destino solicitado: $REQUESTED_TARGET"
    log " - Destino resuelto: $NORMALIZED_TARGET"
    log ""

    if ! confirm_action "¿Continuar con la reinstalacion del plasmoid KDE MBP Watch?"; then
        log_info "Reinstalacion del plasmoid cancelada por el usuario."
        return 0
    fi

    COMMAND_ARGS=(--user "$TARGET_USER" --target "$NORMALIZED_TARGET")
    if [ "$DRY_MODE" = true ]; then
        COMMAND_ARGS+=(--dry-run)
        bash "$REINSTALL_SCRIPT" "${COMMAND_ARGS[@]}" 2>&1 | tee -a "$LOGFILE"
        return "${PIPESTATUS[0]}"
    fi

    run_cmd bash "$REINSTALL_SCRIPT" "${COMMAND_ARGS[@]}"
}

install_youtube_force_h264_package() {
    local SOURCE_DIR="$PROJECT_ROOT/assets/youtube-force-h264"
    local TARGET_PARENT="$HOME/extensions"
    local TARGET_DIR="$TARGET_PARENT/youtube-force-h264"
    local TARGET_DOC_DIR="/usr/local/share/doc/linux-migration-tool"
    local TARGET_DOC_GUIDE="$TARGET_DOC_DIR/youtube-force-h264-chromium-brave.md"
    local SOURCE_DOC_GUIDE="$PROJECT_ROOT/docs/youtube-force-h264.md"

    if [ ! -f "$SOURCE_DIR/manifest.json" ] || [ ! -f "$SOURCE_DIR/content.js" ] || [ ! -f "$SOURCE_DIR/inject.js" ]; then
        log_warn "Paquete YouTube H264 incompleto en: $SOURCE_DIR"
        return
    fi

    if [ ! -f "$SOURCE_DOC_GUIDE" ]; then
        log_warn "Guia YouTube H264 no encontrada en: $SOURCE_DOC_GUIDE"
        return
    fi

    log "${YELLOW}Instalando paquete YouTube Force H264...${NC}"
    run_cmd mkdir -p "$TARGET_PARENT"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] copiar $SOURCE_DIR -> $TARGET_DIR${NC}"
        log "${YELLOW}[DRY-RUN] copiar guia de referencia -> $TARGET_DOC_GUIDE${NC}"
    else
        run_cmd rm -rf "$TARGET_DIR"
        run_cmd cp -R "$SOURCE_DIR" "$TARGET_PARENT/"
        run_cmd sudo mkdir -p "$TARGET_DOC_DIR"
        run_cmd sudo cp "$SOURCE_DOC_GUIDE" "$TARGET_DOC_GUIDE"
    fi

    log "Paquete listo para cargar como extension descomprimida:"
    log "$TARGET_DIR"
    log ""
    log "Importante:"
    log " - ~/extensions no es una carpeta estandar del sistema."
    log " - Se usa aqui como ubicacion local para extensiones descomprimidas."
    log " - Esta accion no instala nada desde la tienda del navegador."
    log ""
    log "Navegadores compatibles previstos:"
    log " - Brave"
    log " - Google Chrome"
    log " - Chromium"
    log ""
    log "Para activarla manualmente:"
    log " 1. Abre brave://extensions, chrome://extensions o chromium://extensions"
    log " 2. Activa Modo desarrollador"
    log " 3. Usa Cargar descomprimida"
    log " 4. Selecciona: $TARGET_DIR"
    log "Guia de referencia:"
    log "$TARGET_DOC_GUIDE"
}

detect_gpu_vendor() {
    local LINE=""

    if command -v lspci >/dev/null 2>&1; then
        LINE="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n 1 || true)"
    fi

    if [[ "$LINE" =~ [Nn][Vv][Ii][Dd][Ii][Aa] ]]; then
        printf 'nvidia\n'
        return 0
    fi

    if [[ "$LINE" =~ [Aa][Mm][Dd]|[Aa][Tt][Ii]|Radeon ]]; then
        printf 'amd\n'
        return 0
    fi

    if [[ "$LINE" =~ [Ii]ntel ]]; then
        printf 'intel\n'
        return 0
    fi

    printf 'unknown\n'
}

detect_gpu_profile() {
    local GPU_LINES=""
    local HAS_INTEL=false
    local HAS_AMD=false
    local HAS_NVIDIA=false

    if command -v lspci >/dev/null 2>&1; then
        GPU_LINES="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
    fi

    [[ "$GPU_LINES" =~ [Ii]ntel ]] && HAS_INTEL=true
    [[ "$GPU_LINES" =~ [Aa][Mm][Dd]|[Aa][Tt][Ii]|Radeon ]] && HAS_AMD=true
    [[ "$GPU_LINES" =~ [Nn][Vv][Ii][Dd][Ii][Aa] ]] && HAS_NVIDIA=true

    if [ "$HAS_INTEL" = true ] && [ "$HAS_AMD" = false ] && [ "$HAS_NVIDIA" = false ]; then
        printf 'intel-only\n'
        return 0
    fi

    if [ "$HAS_INTEL" = true ] && [ "$HAS_AMD" = true ]; then
        printf 'intel+amd\n'
        return 0
    fi

    if [ "$HAS_INTEL" = true ] && [ "$HAS_NVIDIA" = true ]; then
        printf 'intel+nvidia\n'
        return 0
    fi

    if [ "$HAS_AMD" = true ] && [ "$HAS_INTEL" = false ] && [ "$HAS_NVIDIA" = false ]; then
        printf 'amd-only\n'
        return 0
    fi

    if [ "$HAS_NVIDIA" = true ] && [ "$HAS_INTEL" = false ] && [ "$HAS_AMD" = false ]; then
        printf 'nvidia-only\n'
        return 0
    fi

    printf 'unknown\n'
}

detect_broadcom_wifi_profile() {
    local BROADCOM_LINES=""
    local HAS_BCM43602=false

    if command -v lspci >/dev/null 2>&1; then
        BROADCOM_LINES="$(lspci -nn 2>/dev/null | grep -Ei 'network|wireless' | grep -i '14e4:' || true)"
    fi

    [[ "$BROADCOM_LINES" =~ 14e4:43ba ]] && HAS_BCM43602=true

    if [ "$HAS_BCM43602" = true ] && is_apple_laptop; then
        printf 'apple-bcm43602\n'
        return 0
    fi

    if [ "$HAS_BCM43602" = true ]; then
        printf 'bcm43602\n'
        return 0
    fi

    printf 'unknown\n'
}

report_broadcom_bundle_status() {
    local LOCAL_FW_DIR="$1"
    local REQUIRED_FILES=(
        "brcmfmac43602-pcie.bin"
        "brcmfmac43602-pcie.bin.zst"
        "brcmfmac43602-pcie.clm_blob"
        "brcmfmac43602-pcie.clm_blob.zst"
        "brcmfmac43602-pcie.txcap_blob"
        "brcmfmac43602-pcie.txcap_blob.zst"
        "brcmfmac43602-pcie.txt"
        "brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt"
    )
    local FILE_NAME=""
    local HAS_BIN=false
    local HAS_CLM=false
    local HAS_TXCAP=false
    local HAS_TXT=false
    local HAS_APPLE_TXT=false

    [ -d "$LOCAL_FW_DIR" ] || return 0

    for FILE_NAME in "${REQUIRED_FILES[@]}"; do
        [ -f "$LOCAL_FW_DIR/$FILE_NAME" ] || continue

        case "$FILE_NAME" in
            brcmfmac43602-pcie.bin|brcmfmac43602-pcie.bin.zst)
                HAS_BIN=true
                ;;
            brcmfmac43602-pcie.clm_blob|brcmfmac43602-pcie.clm_blob.zst)
                HAS_CLM=true
                ;;
            brcmfmac43602-pcie.txcap_blob|brcmfmac43602-pcie.txcap_blob.zst)
                HAS_TXCAP=true
                ;;
            brcmfmac43602-pcie.txt)
                HAS_TXT=true
                ;;
            brcmfmac43602-pcie.Apple\ Inc.-MacBookPro12,1.txt)
                HAS_APPLE_TXT=true
                ;;
        esac
    done

    log "Estado bundle Broadcom local:"
    log " - bin       : $HAS_BIN"
    log " - clm_blob  : $HAS_CLM"
    log " - txcap_blob: $HAS_TXCAP"
    log " - txt       : $HAS_TXT"
    log " - apple txt : $HAS_APPLE_TXT"

    if [ "$HAS_CLM" = false ] || [ "$HAS_TXCAP" = false ]; then
        log "${YELLOW}Faltan blobs auxiliares Broadcom (${NC}clm_blob/txcap_blob${YELLOW}).${NC}"
        log "El workaround se puede aplicar igual, pero el Wi-Fi puede quedar limitado."
    fi
}

write_browser_flags_file() {
    local TARGET_FILE="$1"
    local FLAGS_CONTENT="$2"
    local TARGET_DIR

    TARGET_DIR="$(dirname "$TARGET_FILE")"
    run_cmd mkdir -p "$TARGET_DIR"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir flags en $TARGET_FILE${NC}"
        return 0
    fi

    printf '%s\n' "$FLAGS_CONTENT" > "$TARGET_FILE"
}

configure_apple_broadcom_wifi() {
    local WIFI_PROFILE=""
    local LOCAL_FW_DIR="$PROJECT_ROOT/firmware/brcm"
    local TARGET_FW_DIR="/usr/lib/firmware/brcm"
    local TARGET_CONF="/etc/modprobe.d/brcmfmac-apple-bcm43602.conf"
    local LOCAL_FW_INSTALLED=false
    local FIRMWARE_FILE=""

    WIFI_PROFILE="$(detect_broadcom_wifi_profile)"

    if [ "$WIFI_PROFILE" != "apple-bcm43602" ]; then
        return
    fi

    log "${YELLOW}Broadcom BCM43602 detectada en equipo Apple.${NC}"
    log "Caso compatible con MBP 2015 usando brcmfmac."
    log "Cambios que puede aplicar este bloque:"
    log " - Copiar firmware local desde $LOCAL_FW_DIR a $TARGET_FW_DIR si existe bundle en el repo"
    log " - Crear $TARGET_CONF con options brcmfmac feature_disable=0x82000"
    log " - Recargar el modulo Wi-Fi: modprobe -r brcmfmac && modprobe brcmfmac"

    if ! confirm_action "¿Aplicar ahora este ajuste Broadcom BCM43602 para Wi-Fi en Apple MBP 2015?"; then
        return
    fi

    if [ -d "$LOCAL_FW_DIR" ]; then
        while IFS= read -r FIRMWARE_FILE; do
            [ -n "$FIRMWARE_FILE" ] || continue
            LOCAL_FW_INSTALLED=true
            break
        done < <(find "$LOCAL_FW_DIR" -maxdepth 1 -type f | sort)
    fi

    if [ "$LOCAL_FW_INSTALLED" = true ]; then
        log "${YELLOW}Instalando firmware Broadcom local desde el repo...${NC}"
        log "Se aceptan ficheros sin comprimir y .zst."
        report_broadcom_bundle_status "$LOCAL_FW_DIR"

        if [ "$DRY_MODE" = true ]; then
            log "${YELLOW}[DRY-RUN] copiar $LOCAL_FW_DIR/* a $TARGET_FW_DIR/${NC}"
        else
            run_cmd sudo mkdir -p "$TARGET_FW_DIR"
            run_cmd sudo cp "$LOCAL_FW_DIR"/* "$TARGET_FW_DIR"/
        fi
    else
        log "${YELLOW}No hay bundle local de firmware Broadcom en el repo.${NC}"
        log "Ruta esperada: $LOCAL_FW_DIR"
        log "El script aplicara igualmente el workaround de brcmfmac si decides seguir."
    fi

    log "${YELLOW}Aplicando configuracion de brcmfmac para BCM43602...${NC}"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] verificar ficheros en $TARGET_FW_DIR${NC}"
        log "${YELLOW}[DRY-RUN] escribir $TARGET_CONF${NC}"
        log "${YELLOW}[DRY-RUN] modprobe -r brcmfmac && modprobe brcmfmac${NC}"
        log "Si sigue fallando, revisar dmesg por errores de backplane/runtime PM."
        return
    fi

    run_shell "printf '%s\n' 'options brcmfmac feature_disable=0x82000' | sudo tee \"$TARGET_CONF\" >/dev/null"
    run_cmd sudo modprobe -r brcmfmac
    run_cmd sudo modprobe brcmfmac

    log "Workaround aplicado en $TARGET_CONF"
    log "Firmware local esperado en: $TARGET_FW_DIR"
    log "Verifica Wi-Fi y revisa logs con: dmesg | grep -i brcmfmac"
    log "Si aparece 'backplane type 15 is not supported', revisa manualmente PCI runtime power management."
}

configure_wifi_regulatory_domain() {
    local WIFI_COUNTRY="${TUI_WIFI_COUNTRY:-}"
    local TMP_FILE=""

    if [ -z "$WIFI_COUNTRY" ]; then
        if ! confirm_action "¿Configurar pais/región del Wi-Fi para ajustar canales y potencia legales?"; then
            return
        fi
        prompt_read "Codigo del pais para Wi-Fi (ej. ES para España): " WIFI_COUNTRY
    fi
    WIFI_COUNTRY="$(printf '%s' "$WIFI_COUNTRY" | tr '[:lower:]' '[:upper:]')"

    if [[ ! "$WIFI_COUNTRY" =~ ^[A-Z]{2}$ ]]; then
        log "${RED}Codigo de pais Wi-Fi invalido. Se omite configuracion.${NC}"
        return
    fi

    log "${YELLOW}Configurando pais/región Wi-Fi: $WIFI_COUNTRY${NC}"
    run_cmd sudo pacman -S --needed --noconfirm wireless-regdb iw

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] actualizar /etc/conf.d/wireless-regdom a $WIFI_COUNTRY${NC}"
        log_warn "Verificacion posterior: iw reg get"
        return
    fi

    TMP_FILE="$(mktemp)"
    if [ -r /etc/conf.d/wireless-regdom ]; then
        cp /etc/conf.d/wireless-regdom "$TMP_FILE"
    fi

    if grep -q '^WIRELESS_REGDOM=' "$TMP_FILE" 2>/dev/null; then
        sed -i "s/^WIRELESS_REGDOM=.*/WIRELESS_REGDOM=\"$WIFI_COUNTRY\"/" "$TMP_FILE"
    else
        printf 'WIRELESS_REGDOM="%s"\n' "$WIFI_COUNTRY" >> "$TMP_FILE"
    fi

    run_cmd sudo cp "$TMP_FILE" /etc/conf.d/wireless-regdom
    rm -f "$TMP_FILE"

    log_warn "Pais/región Wi-Fi configurado. Reinicia y valida con: iw reg get"
}

configure_networkmanager_iwd_backend() {
    if ! systemctl list-unit-files --type=service 2>/dev/null | grep -q '^NetworkManager\.service'; then
        return 0
    fi

    if ! confirm_action "¿Configurar NetworkManager para usar iwd como backend Wi-Fi? Suele mejorar estabilidad y evitar caidas de senal" "yes"; then
        return 0
    fi

    log "${YELLOW}Aplicando backend Wi-Fi iwd para NetworkManager...${NC}"
    log "Cambios a aplicar:"
    log " - Instalar iwd"
    log " - Habilitar servicio iwd"
    log " - Escribir /etc/NetworkManager/conf.d/wifi_backend.conf"
    log " - Reiniciar NetworkManager"

    run_cmd sudo pacman -S --needed --noconfirm iwd
    run_cmd sudo systemctl enable --now iwd

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] crear /etc/NetworkManager/conf.d${NC}"
        log "${YELLOW}[DRY-RUN] escribir /etc/NetworkManager/conf.d/wifi_backend.conf${NC}"
    else
        run_cmd sudo mkdir -p /etc/NetworkManager/conf.d
        run_shell "sudo tee /etc/NetworkManager/conf.d/wifi_backend.conf > /dev/null <<'EOF'
[device]
wifi.backend=iwd
EOF"
    fi

    run_cmd sudo systemctl restart NetworkManager
    run_cmd sleep 2
    run_cmd sudo systemctl restart iwd
    log_warn "Backend iwd aplicado. Validacion posterior: iw dev, iw reg get, nmcli device wifi list."
}

configure_global_menu_support() {
    if ! confirm_action "¿Activar menu global en KDE para apps GTK y VS Code, de forma que el menu aparezca en la barra superior/panel?"; then
        return
    fi

    log "${YELLOW}Instalando soporte Global Menu...${NC}"
    run_cmd sudo pacman -S --needed --noconfirm appmenu-gtk-module libdbusmenu-glib
    log_warn "Reinicia las apps afectadas para aplicar el cambio."
}

configure_chromium_hw_acceleration() {
    local GPU_VENDOR=""
    local GPU_PROFILE=""
    local BROWSER="${TUI_BROWSER:-}"
    local TARGET_FILE=""
    local FLAGS_CONTENT=""

    if ! confirm_action "¿Configurar aceleracion hardware en navegador Chromium?"; then
        return
    fi

    GPU_VENDOR="$(detect_gpu_vendor)"
    GPU_PROFILE="$(detect_gpu_profile)"

    log "GPU detectada: $GPU_VENDOR"
    log "Perfil GPU detectado: $GPU_PROFILE"

    if [ "$GPU_PROFILE" = "intel-only" ]; then
        if is_apple_laptop; then
            log "${YELLOW}Equipo Apple con GPU Intel detectado.${NC}"
            log "Caso esperado para MBP Retina 13\" 2015."
        else
            log "${YELLOW}Equipo con GPU Intel-only detectado.${NC}"
        fi

        log "No se aplican flags automaticos de Chromium para Intel con la plantilla actual."
        log_warn "Verifica manualmente la aceleracion en brave://gpu o chrome://gpu."
        log "Referencia:"
        log "https://wiki.cachyos.org/configuration/enabling_hardware_acceleration_in_google_chrome/"
        return
    fi

    if [ -z "$BROWSER" ]; then
        log "Navegadores soportados en automatizacion: brave, chrome"
        prompt_read "Navegador a configurar [brave/chrome]: " BROWSER
    fi
    BROWSER="$(printf '%s' "$BROWSER" | tr '[:upper:]' '[:lower:]')"

    case "$BROWSER" in
        brave)
            TARGET_FILE="$HOME/.config/brave-flags.conf"
            ;;
        chrome)
            TARGET_FILE="$HOME/.config/chrome-flags.conf"
            ;;
        *)
            log "${RED}Navegador no soportado para configuracion automatica.${NC}"
            return
            ;;
    esac

    case "$GPU_VENDOR:$BROWSER" in
        amd:brave)
            FLAGS_CONTENT='--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-zero-copy
--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,CanvasOopRasterization,VaapiIgnoreDriverChecks,UseMultiPlaneFormatForHardwareVideo
--ozone-platform-hint=auto'
            ;;
        amd:chrome)
            FLAGS_CONTENT='--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-zero-copy
--ozone-platform-hint=auto
--use-gl=angle
--use-angle=vulkan
--enable-features=VaapiVideoDecoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,VaapiIgnoreDriverChecks,UseMultiPlaneFormatForHardwareVideo,Vulkan,VulkanFromANGLE,DefaultANGLEVulkan'
            ;;
        nvidia:brave)
            FLAGS_CONTENT='--enable-features=VaapiVideoDecoder,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,VaapiIgnoreDriverChecks'
            ;;
        *)
            log "${YELLOW}No hay plantilla automatica fiable para ${GPU_VENDOR}/${BROWSER}.${NC}"
            log "Revisa manualmente:"
            log "https://wiki.cachyos.org/configuration/enabling_hardware_acceleration_in_google_chrome/"
            return
            ;;
    esac

    log "${YELLOW}Escribiendo flags en $TARGET_FILE...${NC}"
    write_browser_flags_file "$TARGET_FILE" "$FLAGS_CONTENT"
    log_warn "Reinicia el navegador y valida en:"
    log " - brave://gpu"
    log " - chrome://gpu"
}

configure_vaapi_intel() {
    local GPU_PROFILE=""
    local MODEL=""
    local PROMPT_LABEL=""

    GPU_PROFILE="$(detect_gpu_profile)"
    MODEL="$(get_macbook_model)"

    if [[ "$GPU_PROFILE" != intel* ]]; then
        return
    fi

    log "${YELLOW}GPU Intel detectada.${NC}"

    case "$MODEL" in
        MacBookPro12,1)
            # MacBook Pro 13" Retina 2015 (Broadwell / Iris 6100)
            log "Configurando corrección VA-API para Intel Broadwell (2015):"
            log " - Instala libva-intel-driver-irql (AUR) para corregir el fallo de frame pool."
            log " - Configura LIBVA_DRIVER_NAME=i965"
            PROMPT_LABEL="Intel Broadwell (2015)"

            if ! confirm_action "¿Aplicar corrección VA-API para $PROMPT_LABEL?"; then
                return
            fi

            log "${YELLOW}Instalando libva-intel-driver-irql (AUR)...${NC}"
            log_package_batch_state "AUR" "aur" libva-intel-driver-irql
            run_cmd yay -S --needed --noconfirm libva-intel-driver-irql
            ;;
        MacBookPro8,1)
            # MacBook Pro 13" Early 2011 (Sandy Bridge / HD Graphics 3000)
            log "Configurando corrección VA-API para Intel Sandy Bridge (2011):"
            log " - Instala libva-intel-driver estándar."
            log " - Configura LIBVA_DRIVER_NAME=i965"
            log " - Nota: Decodificación por HW limitada (sin soporte VP9/AV1)."
            PROMPT_LABEL="Intel Sandy Bridge (2011)"

            if ! confirm_action "¿Aplicar configuración VA-API para $PROMPT_LABEL?"; then
                return
            fi

            log "${YELLOW}Instalando libva-intel-driver...${NC}"
            run_cmd sudo pacman -S --needed --noconfirm libva-intel-driver
            ;;
        *)
            log "${YELLOW}No hay perfil específico para el modelo $MODEL.${NC}"
            log "Se intentará la configuración genérica para Intel."
            PROMPT_LABEL="Intel genérico"

            if ! confirm_action "¿Continuar con la configuración genérica de $PROMPT_LABEL?"; then
                return
            fi
            run_cmd sudo pacman -S --needed --noconfirm libva-intel-driver
            ;;
    esac

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] crear ~/.config/environment.d/vaapi.conf${NC}"
        log "${YELLOW}[DRY-RUN] escribir ~/.config/brave-flags.conf${NC}"
    else
        run_cmd mkdir -p "$HOME/.config/environment.d"
        printf 'LIBVA_DRIVER_NAME=i965\n' > "$HOME/.config/environment.d/vaapi.conf"
        write_browser_flags_file "$HOME/.config/brave-flags.conf" \
'--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL
--ozone-platform-hint=x11'
    fi

    log_warn "Reinicia la sesión para aplicar los cambios de VA-API."
}

configure_vaapi_brave_broadwell() {
    configure_vaapi_intel "$@"
}

configure_btrfs_snapshots() {
    log "${YELLOW}Configurando Snapper...${NC}"

    run_cmd sudo pacman -S --needed --noconfirm \
        snapper \
        grub-btrfs \
        snap-pac

    log "${YELLOW}"
    log "IMPORTANTE:"
    log "Configura manualmente subvolumenes BTRFS."
    log "Este script NO modifica particiones."
    log "${NC}"
}

extract_broadcom_bundle_menu() {
    local APPLE_MODEL="MacBookPro12,1"
    local EXTRACTOR="$PROJECT_ROOT/src/tools/extract_bcm43602_bundle.sh"

    if [ ! -x "$EXTRACTOR" ]; then
        run_cmd chmod +x "$EXTRACTOR"
    fi

    log "${YELLOW}Extraccion de firmware Broadcom BCM43602${NC}"
    log "Origen: sistema actual"
    log "Destino: $PROJECT_ROOT/firmware/brcm"
    log "Modelo Apple asumido: $APPLE_MODEL"

    run_cmd bash "$EXTRACTOR" "$APPLE_MODEL"
}

extract_broadcom_bundle_silent() {
    local APPLE_MODEL="MacBookPro12,1"
    local EXTRACTOR="$PROJECT_ROOT/src/tools/extract_bcm43602_bundle.sh"

    [ -x "$EXTRACTOR" ] || chmod +x "$EXTRACTOR" 2>/dev/null || true

    if [ "$DRY_MODE" = true ]; then
        return 0
    fi

    bash "$EXTRACTOR" "$APPLE_MODEL" >/dev/null 2>&1 || true
}

detect_facetimehd_camera() {
    command -v lspci >/dev/null 2>&1 || { printf 'no\n'; return 0; }
    lspci -nn 2>/dev/null | grep -qi '14e4:1570' && printf 'yes\n' || printf 'no\n'
}

configure_facetimehd_camera() {
    if [ "$(detect_facetimehd_camera)" != "yes" ] || ! is_apple_laptop; then
        return
    fi

    log "${YELLOW}Cámara FaceTime HD PCIe detectada (14e4:1570).${NC}"
    log "Requiere driver facetimehd (AUR) en lugar de uvcvideo."
    log "Cambios a aplicar:"
    log " - yay -S facetimehd-dkms facetimehd-firmware"
    log " - modprobe -r bdc_pci && modprobe facetimehd"
    log " - /etc/modules-load.d/facetimehd.conf  (carga persistente)"
    log " - /etc/modprobe.d/facetimehd.conf       (blacklist bdc_pci)"

    if ! confirm_action "¿Instalar y configurar driver facetimehd para la cámara FaceTime HD?"; then
        return
    fi

    log "${YELLOW}Instalando facetimehd-dkms y facetimehd-firmware...${NC}"
    log_package_batch_state "AUR" "aur" facetimehd-dkms facetimehd-firmware
    run_cmd yay -S --needed --noconfirm facetimehd-dkms facetimehd-firmware

    log "${YELLOW}Configurando módulo...${NC}"
    if grep -q '^bdc_pci ' /proc/modules 2>/dev/null; then
        run_cmd sudo modprobe -r bdc_pci
    else
        log "bdc_pci no está cargado, omitiendo descarga."
    fi
    run_cmd sudo modprobe facetimehd

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] escribir /etc/modules-load.d/facetimehd.conf${NC}"
        log "${YELLOW}[DRY-RUN] escribir /etc/modprobe.d/facetimehd.conf${NC}"
    else
        run_shell "printf 'facetimehd\n' | sudo tee /etc/modules-load.d/facetimehd.conf >/dev/null"
        run_shell "printf 'blacklist bdc_pci\n' | sudo tee /etc/modprobe.d/facetimehd.conf >/dev/null"
    fi

    log_warn "Driver configurado. Verifica con: ls /dev/video*"
    log "Si /dev/video* no aparece, instala el kernel Zen y reinicia:"
    log "  sudo pacman -S linux-cachyos-zen linux-cachyos-zen-headers"
}

bootstrap_cachyos() {
    log_section "Bootstrap CachyOS"
    show_log_location
    bootstrap_context_report

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}DRY RUN ACTIVADO por flag --dry-run.${NC}"
        log "${YELLOW}Dry-run actualmente informativo.${NC}"
    fi

    install_packages
    install_ohmyzsh
    install_powerlevel10k
    install_node_stack
    install_ai_tools
    install_restic_if_accepted
    install_filezilla_if_accepted
    install_markdownpart_if_accepted
    install_libreoffice_if_accepted
    install_ipscan_if_accepted
    install_talk2ai_if_accepted || true
    install_codexbar_tray_if_accepted || true
    install_mbp_watch_diagnostics
    install_mbp_plasmoid_if_accepted
    install_youtube_force_h264_package
    install_apple_laptop_extras
    configure_facetimehd_camera
    configure_networkmanager_iwd_backend
    install_hyprland
    configure_wifi_regulatory_domain
    configure_global_menu_support
    configure_chromium_hw_acceleration
    configure_vaapi_intel
    configure_btrfs_snapshots

    log ""
    log "${GREEN}=================================${NC}"
    log "${GREEN}BOOTSTRAP COMPLETADO${NC}"
    log "${GREEN}=================================${NC}"
    log ""

    log "Recomendado:"
    log "- Reiniciar sistema para asegurar PATH, grupos, servicios y firmware recien aplicados."
    log "- Tras reiniciar, ejecuta: ./migration.sh postcheck"
    show_log_location
    log ""
}

get_ai_context_state_dir() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/linux-migration-tool"
}

get_ai_context_raw_file() {
    printf '%s\n' "$(get_ai_context_state_dir)/postinstall-ai-context.txt"
}

get_ai_context_redacted_file() {
    printf '%s\n' "$(get_ai_context_state_dir)/postinstall-ai-context.redacted.txt"
}

collect_default_route() {
    ip route show default 2>/dev/null | head -n 1
}

collect_default_gateway() {
    collect_default_route | awk '{for (i = 1; i <= NF; i++) if ($i == "via") { print $(i+1); exit }}'
}

collect_default_interface() {
    collect_default_route | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i+1); exit }}'
}

collect_dns_servers() {
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl dns 2>/dev/null |
            awk '{$1=""; sub(/^ /, ""); print}' |
            tr ' ' '\n' |
            sed '/^$/d' |
            sort -u
        return 0
    fi

    sed -n 's/^nameserver[[:space:]]\+//p' /etc/resolv.conf 2>/dev/null | sort -u
}

collect_current_wifi_ssid() {
    nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1 == "yes" {print $2; exit}'
}

collect_saved_wifi_profiles() {
    nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: '$2 == "802-11-wireless" {print $1}'
}

collect_service_state() {
    local SCOPE="$1"
    local SERVICE_NAME="$2"

    case "$SCOPE" in
        user)
            if systemctl --user list-unit-files --type=service 2>/dev/null | grep -q "^${SERVICE_NAME}[[:space:]]"; then
                if systemctl --user is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
                    printf 'enabled\n'
                else
                    printf 'installed-disabled\n'
                fi
            else
                printf 'not-installed\n'
            fi
            ;;
        *)
            if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${SERVICE_NAME}[[:space:]]"; then
                if systemctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
                    printf 'enabled\n'
                else
                    printf 'installed-disabled\n'
                fi
            else
                printf 'not-installed\n'
            fi
            ;;
    esac
}

collect_package_state() {
    local PACKAGE_NAME="$1"

    if pacman -Q "$PACKAGE_NAME" >/dev/null 2>&1; then
        printf 'installed\n'
    else
        printf 'missing\n'
    fi
}

collect_single_line_file() {
    local FILE_PATH="$1"

    if [ -r "$FILE_PATH" ]; then
        tr '\n' ' ' < "$FILE_PATH" | sed 's/[[:space:]]\+/ /g; s/[[:space:]]$//'
    else
        printf 'not-present\n'
    fi
}

render_ai_context_value() {
    local MODE="$1"
    local KEY="$2"
    local VALUE="$3"

    case "$MODE:$KEY" in
        redacted:hostname|redacted:pretty_hostname|redacted:transient_hostname|redacted:default_route|redacted:default_gateway|redacted:dns_servers|redacted:current_ssid|redacted:saved_wifi_profiles)
            printf '<redacted>\n'
            ;;
        *)
            printf '%s\n' "$VALUE"
            ;;
    esac
}

write_postinstall_ai_context_file() {
    local OUTPUT_PATH="$1"
    local MODE="$2"
    local STATE_DIR=""
    local DNS_JOINED=""
    local WIFI_PROFILES_JOINED=""
    local DEFAULT_ROUTE=""
    local DEFAULT_GATEWAY=""
    local DEFAULT_INTERFACE=""
    local CURRENT_SSID=""
    local HOSTNAME_VALUE=""
    local PRETTY_HOSTNAME=""
    local TRANSIENT_HOSTNAME=""
    local KERNEL_VALUE=""
    local SESSION_TYPE_VALUE=""
    local DOCKER_SERVICE_STATE=""
    local SYNCTHING_SERVICE_STATE=""
    local TALK2AI_SERVICE_STATE=""
    local CODEXBAR_TRAY_SERVICE_STATE=""
    local IWD_BACKEND_CONF=""
    local WIRELESS_REGDOM_CONF=""
    local BRAVE_FLAGS=""
    local VAAPI_CONF=""

    STATE_DIR="$(dirname "$OUTPUT_PATH")"
    mkdir -p "$STATE_DIR"

    DEFAULT_ROUTE="$(collect_default_route)"
    DEFAULT_GATEWAY="$(collect_default_gateway)"
    DEFAULT_INTERFACE="$(collect_default_interface)"
    CURRENT_SSID="$(collect_current_wifi_ssid)"
    HOSTNAME_VALUE="$(hostnamectl --static 2>/dev/null || hostname 2>/dev/null || printf 'unknown\n')"
    PRETTY_HOSTNAME="$(hostnamectl --pretty 2>/dev/null || printf '\n')"
    TRANSIENT_HOSTNAME="$(hostnamectl --transient 2>/dev/null || printf '\n')"
    KERNEL_VALUE="$(uname -r)"
    SESSION_TYPE_VALUE="${XDG_SESSION_TYPE:-unknown}"
    DOCKER_SERVICE_STATE="$(collect_service_state system docker.service)"
    SYNCTHING_SERVICE_STATE="$(collect_service_state user syncthing.service)"
    TALK2AI_SERVICE_STATE="$(collect_service_state user talk2ai.service)"
    CODEXBAR_TRAY_SERVICE_STATE="$(collect_service_state user codexbar-tray.service)"
    IWD_BACKEND_CONF="$(collect_single_line_file /etc/NetworkManager/conf.d/wifi_backend.conf)"
    WIRELESS_REGDOM_CONF="$(collect_single_line_file /etc/conf.d/wireless-regdom)"
    BRAVE_FLAGS="$(collect_single_line_file "$HOME/.config/brave-flags.conf")"
    VAAPI_CONF="$(collect_single_line_file "$HOME/.config/environment.d/vaapi.conf")"

    DNS_JOINED="$(collect_dns_servers | paste -sd ',' - | sed 's/,/, /g')"
    WIFI_PROFILES_JOINED="$(collect_saved_wifi_profiles | paste -sd ',' - | sed 's/,/, /g')"
    [ -n "$DNS_JOINED" ] || DNS_JOINED="none"
    [ -n "$WIFI_PROFILES_JOINED" ] || WIFI_PROFILES_JOINED="none"
    [ -n "$CURRENT_SSID" ] || CURRENT_SSID="not-connected"
    [ -n "$DEFAULT_ROUTE" ] || DEFAULT_ROUTE="none"
    [ -n "$DEFAULT_GATEWAY" ] || DEFAULT_GATEWAY="none"
    [ -n "$DEFAULT_INTERFACE" ] || DEFAULT_INTERFACE="none"
    [ -n "$PRETTY_HOSTNAME" ] || PRETTY_HOSTNAME="not-set"
    [ -n "$TRANSIENT_HOSTNAME" ] || TRANSIENT_HOSTNAME="not-set"

    {
        printf '# Linux Migration Tool - Post-install AI Context (%s)\n' "$MODE"
        printf 'generated_at: %s\n' "$(date --iso-8601=seconds)"
        printf 'tool_version: %s\n' "$VERSION"
        printf 'macbook_model: %s\n' "$(get_macbook_model)"
        printf 'profile_id: %s\n' "$(get_macbook_profile_id)"
        printf '\n[system]\n'
        printf 'hostname: %s\n' "$(render_ai_context_value "$MODE" hostname "$HOSTNAME_VALUE")"
        printf 'pretty_hostname: %s\n' "$(render_ai_context_value "$MODE" pretty_hostname "$PRETTY_HOSTNAME")"
        printf 'transient_hostname: %s\n' "$(render_ai_context_value "$MODE" transient_hostname "$TRANSIENT_HOSTNAME")"
        printf 'kernel: %s\n' "$KERNEL_VALUE"
        printf 'session_type: %s\n' "$SESSION_TYPE_VALUE"
        printf '\n[network]\n'
        printf 'default_route: %s\n' "$(render_ai_context_value "$MODE" default_route "$DEFAULT_ROUTE")"
        printf 'default_gateway: %s\n' "$(render_ai_context_value "$MODE" default_gateway "$DEFAULT_GATEWAY")"
        printf 'default_interface: %s\n' "$DEFAULT_INTERFACE"
        printf 'dns_servers: %s\n' "$(render_ai_context_value "$MODE" dns_servers "$DNS_JOINED")"
        printf 'current_ssid: %s\n' "$(render_ai_context_value "$MODE" current_ssid "$CURRENT_SSID")"
        printf 'saved_wifi_profiles: %s\n' "$(render_ai_context_value "$MODE" saved_wifi_profiles "$WIFI_PROFILES_JOINED")"
        printf '\n[services]\n'
        printf 'docker_service: %s\n' "$DOCKER_SERVICE_STATE"
        printf 'syncthing_user_service: %s\n' "$SYNCTHING_SERVICE_STATE"
        printf 'talk2ai_user_service: %s\n' "$TALK2AI_SERVICE_STATE"
        printf 'codexbar_tray_user_service: %s\n' "$CODEXBAR_TRAY_SERVICE_STATE"
        printf '\n[packages]\n'
        printf 'markdownpart: %s\n' "$(collect_package_state markdownpart)"
        printf 'filezilla: %s\n' "$(collect_package_state filezilla)"
        printf 'handy_bin: %s\n' "$(collect_package_state handy-bin)"
        printf '\n[config_files]\n'
        printf 'networkmanager_wifi_backend_conf: %s\n' "$IWD_BACKEND_CONF"
        printf 'wireless_regdom_conf: %s\n' "$WIRELESS_REGDOM_CONF"
        printf 'brave_flags_conf: %s\n' "$BRAVE_FLAGS"
        printf 'vaapi_conf: %s\n' "$VAAPI_CONF"
    } > "$OUTPUT_PATH"
}

export_postinstall_ai_context() {
    local RAW_FILE=""
    local REDACTED_FILE=""

    RAW_FILE="$(get_ai_context_raw_file)"
    REDACTED_FILE="$(get_ai_context_redacted_file)"

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] exportar contexto IA post-instalacion en:${NC}"
        log "${YELLOW}[DRY-RUN] - $RAW_FILE${NC}"
        log "${YELLOW}[DRY-RUN] - $REDACTED_FILE${NC}"
        return 0
    fi

    write_postinstall_ai_context_file "$RAW_FILE" raw
    write_postinstall_ai_context_file "$REDACTED_FILE" redacted

    log_success "Contexto IA post-instalacion exportado."
    log " - Completo: $RAW_FILE"
    log " - Saneado:  $REDACTED_FILE"
}

post_bootstrap_checks() {
    local REG_LINE=""

    log_section "Post-Check Tras Reinicio"
    show_log_location

    log "${YELLOW}Comprobaciones automatizadas${NC}"

    if groups | tr ' ' '\n' | grep -q '^docker$'; then
        log_success "Docker group: OK"
    else
        log_warn "Docker group: pendiente. Falta relogin/reinicio o revisar usermod."
    fi

    if systemctl is-active --quiet docker; then
        log_success "Docker service: activo"
    else
        log_warn "Docker service: no activo"
    fi

    if [ -f "$HOME/.p10k.zsh" ]; then
        log_success "Powerlevel10k: ya configurado (~/.p10k.zsh presente)"
    else
        log_warn "Powerlevel10k: pendiente. Ejecuta: p10k configure"
    fi

    if systemctl --user is-enabled syncthing.service >/dev/null 2>&1; then
        log_success "Syncthing user service: habilitado"
    else
        log_warn "Syncthing user service: no habilitado. Ejecuta: systemctl --user enable --now syncthing.service"
    fi

    if command -v codex >/dev/null 2>&1; then
        log_success "Codex CLI detectado en: $(command -v codex)"
        codex --version 2>&1 | tee -a "$LOGFILE" || true
    else
        log_warn "Codex CLI no detectado en PATH"
    fi

    if command -v claude >/dev/null 2>&1; then
        log_success "Claude Code CLI detectado en: $(command -v claude)"
        claude --version 2>&1 | tee -a "$LOGFILE" || true
    else
        log_warn "Claude Code CLI no detectado en PATH"
    fi

    if command -v iw >/dev/null 2>&1; then
        REG_LINE="$(iw reg get 2>/dev/null | head -n 1 || true)"
        if [ -n "$REG_LINE" ]; then
            log_success "Wi-Fi regulatorio: $REG_LINE"
        else
            log_warn "Wi-Fi regulatorio: no se pudo leer con iw reg get"
        fi
    else
        log_warn "iw no disponible para validar pais/región Wi-Fi"
    fi

    export_postinstall_ai_context

    log ""
    log "${YELLOW}Pendiente manual${NC}"
    log "- KDE Connect: abre KDE Connect Settings, empareja el movil y valida red local/firewall."
    log "- Navegador Chromium: abre brave://gpu o chrome://gpu y revisa Video Decode / Rasterization."
    log "- Extension YouTube H264: carga ~/extensions/youtube-force-h264 en brave://extensions o chrome://extensions."
    log "- Broadcom Apple: solo si con iwd sigue fallando el Wi-Fi, valorar workaround manual adicional."
    if [ "$(detect_facetimehd_camera)" = "yes" ]; then
        if ls /dev/video* >/dev/null 2>&1; then
            log_success "Cámara FaceTime HD: /dev/video* presente."
        else
            log_warn "Cámara FaceTime HD: /dev/video* no encontrado. Si facetimehd está instalado, prueba con el kernel Zen: sudo pacman -S linux-cachyos-zen linux-cachyos-zen-headers"
        fi
    fi

    log ""
}
