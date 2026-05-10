#!/usr/bin/env bash

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

    log "${YELLOW}Instalando yay...${NC}"

    run_cmd sudo pacman -S --needed --noconfirm git base-devel

    local YAY_TMP
    YAY_TMP="$(mktemp -d /tmp/yay-build.XXXXXX)"

    run_cmd git clone https://aur.archlinux.org/yay.git "$YAY_TMP"
    run_shell "cd \"$YAY_TMP\" && makepkg -si --noconfirm"
}

install_packages() {
    local COMMON_PACKAGES=(
        git
        base-devel
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

    log "${YELLOW}Actualizando sistema...${NC}"
    run_cmd sudo pacman -Syu --noconfirm

    log "${YELLOW}Instalando paquetes comunes de desarrollo...${NC}"
    log_package_batch_state "repo" "repo" "${COMMON_PACKAGES[@]}"
    run_cmd sudo pacman -S --needed --noconfirm "${COMMON_PACKAGES[@]}"

    log "${YELLOW}Instalando base KDE Plasma...${NC}"
    log_package_batch_state "repo" "repo" "${KDE_PACKAGES[@]}"
    run_cmd sudo pacman -S --needed --noconfirm "${KDE_PACKAGES[@]}"

    install_yay

    log "${YELLOW}Instalando paquetes AUR...${NC}"
    log_package_batch_state "AUR" "aur" \
        visual-studio-code-bin \
        brave-bin \
        opencode-desktop-bin \
        ttf-jetbrains-mono-nerd \
        angryipscanner
    run_cmd yay -S --needed --noconfirm \
        visual-studio-code-bin \
        brave-bin \
        opencode-desktop-bin \
        ttf-jetbrains-mono-nerd \
        angryipscanner

    log "${YELLOW}Habilitando Docker...${NC}"
    run_cmd sudo systemctl enable docker
    run_cmd sudo systemctl start docker
    run_cmd sudo usermod -aG docker "$USER"
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

install_ai_tools() {
    export NVM_DIR="$HOME/.nvm"

    # shellcheck disable=SC1090,SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

    log "${YELLOW}Comprobando estado previo de CLIs de IA...${NC}"
    log_npm_tool_status "Codex CLI" "@openai/codex" "codex"
    log_claude_tool_status

    if command -v codex >/dev/null 2>&1; then
        log "Codex CLI ya detectado en: $(command -v codex)"
        codex --version 2>&1 | tee -a "$LOGFILE" || true
        log "${YELLOW}Actualizando Codex CLI mediante npm oficial (@openai/codex)...${NC}"
    else
        log "${YELLOW}Instalando Codex CLI mediante npm oficial (@openai/codex)...${NC}"
    fi

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}[DRY-RUN] npm install -g @openai/codex@latest${NC}"
    else
        npm install -g @openai/codex@latest 2>&1 | tee -a "$LOGFILE"
    fi

    link_npm_global_binaries

    if command -v claude >/dev/null 2>&1; then
        log "Claude Code CLI ya detectado en: $(command -v claude)"
        if [ "$DRY_MODE" = true ]; then
            log "${YELLOW}[DRY-RUN] claude update${NC}"
        else
            log "${YELLOW}Comprobando/actualizando Claude Code CLI a la ultima version disponible...${NC}"
            claude update 2>&1 | tee -a "$LOGFILE" || true
        fi
    else
        log "${YELLOW}Instalando Claude Code CLI nativo...${NC}"
        run_shell "curl -fsSL https://claude.ai/install.sh | bash"
    fi

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

    for BIN_NAME in codex pnpm bun; do
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

    if command -v codex >/dev/null 2>&1; then
        log "codex detectado en: $(command -v codex)"
        codex --version 2>&1 | tee -a "$LOGFILE" || true
    else
        log "${YELLOW}codex no esta en PATH de esta sesion.${NC} Reabre terminal y ejecuta: command -v codex && codex --version"
    fi

    if command -v claude >/dev/null 2>&1; then
        log "claude detectado en: $(command -v claude)"
        claude --version 2>&1 | tee -a "$LOGFILE" || true
    else
        log "${YELLOW}claude no esta en PATH de esta sesion.${NC} Reabre terminal y ejecuta: command -v claude && claude --version"
        log "Claude Code nativo suele instalar el binario en ~/.local/bin/claude."
    fi
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

install_youtube_force_h264_package() {
    local SOURCE_DIR="$PROJECT_ROOT/assets/youtube-force-h264"
    local TARGET_PARENT="$HOME/extensions"
    local TARGET_DIR="$TARGET_PARENT/youtube-force-h264"
    local TARGET_DOC_DIR="/usr/local/share/doc/linux-migration-tool"
    local TARGET_DOC_GUIDE="$TARGET_DOC_DIR/youtube-force-h264-chromium-brave.md"

    if [ ! -f "$SOURCE_DIR/manifest.json" ] || [ ! -f "$SOURCE_DIR/content.js" ] || [ ! -f "$SOURCE_DIR/inject.js" ]; then
        log_warn "Paquete YouTube H264 incompleto en: $SOURCE_DIR"
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
        run_cmd sudo cp "$PROJECT_ROOT/youtube-force-h264-chromium-brave.md" "$TARGET_DOC_GUIDE"
    fi

    log "Paquete listo para cargar como extension descomprimida:"
    log "$TARGET_DIR"
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
    local WIFI_COUNTRY=""
    local TMP_FILE=""

    if ! confirm_action "¿Configurar pais/región del Wi-Fi para ajustar canales y potencia legales?"; then
        return
    fi

    prompt_read "Codigo del pais para Wi-Fi (ej. ES para España): " WIFI_COUNTRY
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
    local BROWSER=""
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

    log "Navegadores soportados en automatizacion: brave, chrome"
    prompt_read "Navegador a configurar [brave/chrome]: " BROWSER
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

    if [ "$DRY_MODE" = true ]; then
        log "${YELLOW}DRY RUN ACTIVADO por flag --dry-run.${NC}"
        log "${YELLOW}Dry-run actualmente informativo.${NC}"
    fi

    install_packages
    install_ohmyzsh
    install_powerlevel10k
    install_node_stack
    install_ai_tools
    install_mbp_watch_diagnostics
    install_youtube_force_h264_package
    install_apple_laptop_extras
    configure_facetimehd_camera
    configure_networkmanager_iwd_backend
    install_hyprland
    configure_wifi_regulatory_domain
    configure_global_menu_support
    configure_chromium_hw_acceleration
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
