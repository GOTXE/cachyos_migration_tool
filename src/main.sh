#!/usr/bin/env bash

# shellcheck disable=SC2034

set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
# shellcheck source=lib/common.sh
source "$APP_DIR/lib/common.sh"
# shellcheck disable=SC1091
# shellcheck source=modules/backup.sh
source "$APP_DIR/modules/backup.sh"
# shellcheck disable=SC1091
# shellcheck source=modules/restore.sh
source "$APP_DIR/modules/restore.sh"
# shellcheck disable=SC1091
# shellcheck source=modules/bootstrap.sh
source "$APP_DIR/modules/bootstrap.sh"
# shellcheck disable=SC1091
# shellcheck source=lib/tui.sh
source "$APP_DIR/lib/tui.sh"

main_menu() {
    case "${TUI_BACKEND:-auto}" in
        python)
            python3 "$APP_DIR/lib/tui.py" "$PROJECT_ROOT" "$VERSION"
            return ;;
        whiptail)
            tui_main_menu
            return ;;
        text)
            : ;;  # cae al menú de texto
        auto|*)
            if command -v python3 >/dev/null 2>&1 && python3 -c "import curses" 2>/dev/null; then
                python3 "$APP_DIR/lib/tui.py" "$PROJECT_ROOT" "$VERSION"
                return
            fi
            if command -v whiptail >/dev/null 2>&1; then
                tui_main_menu
                return
            fi ;;
    esac

    local OPTION

    while true; do
        clear
        print_main_menu_intro

        log "${BLUE}Linux Migration Tool v${VERSION}${NC}"
        log ""
        log "1) Backup sistema"
        log "2) Bootstrap CachyOS"
        log "3) Post-check tras reinicio"
        log "4) Restaurar backup"
        log "5) Desinstalar MBP Watch"
        log "6) Desinstalar plasmoid MBP Watch"
        log "7) Reinstalar plasmoid MBP Watch"
        log "8) Mover plasmoid MBP Watch"
        log "9) Instalar YouTube Force H264"
        log "10) Configurar VA-API Brave/Chromium (Intel Broadwell)"
        log "11) Salir"
        log ""

        prompt_read "Selecciona opcion: " OPTION

        case "$OPTION" in
            1)  backup_system ;;
            2)  bootstrap_cachyos ;;
            3)  post_bootstrap_checks ;;
            4)  restore_system ;;
            5)  uninstall_mbp_watch_diagnostics ;;
            6)  uninstall_mbp_watch_plasmoid ;;
            7)  reinstall_mbp_watch_plasmoid ;;
            8)
                prompt_read "Destino del plasmoid [primary|screen:N]: " MBP_PLASMOID_TARGET
                MBP_PLASMOID_TARGET="${MBP_PLASMOID_TARGET:-primary}"
                move_mbp_watch_plasmoid "$MBP_PLASMOID_TARGET"
                ;;
            9)  install_youtube_force_h264_package ;;
            10) configure_vaapi_brave_broadwell ;;
            11) exit 0 ;;
            *)  log "${RED}Opcion invalida.${NC}" ;;
        esac
    done
}

usage() {
    cat <<'EOF'
Uso recomendado tras instalar CachyOS:
  1) ./migration.sh bootstrap
  2) Reiniciar sistema
  3) ./migration.sh postcheck
  4) ./migration.sh restore --source RUTA_BACKUP

Comandos:
  ./migration.sh
  ./migration.sh backup [--target RUTA] [--dry-run]
  ./migration.sh bootstrap [--dry-run] [--hyprland yes|no] [--apple-laptop yes|no]
  ./migration.sh postcheck
  ./migration.sh restore [--source RUTA] [--force] [--dry-run]
  ./migration.sh add-mbp-plasmoid [--target primary|screen:N] [--dry-run]
  ./migration.sh move-mbp-plasmoid [--target primary|screen:N] [--dry-run]
  ./migration.sh uninstall-mbp-watch [--dry-run]
  ./migration.sh uninstall-mbp-plasmoid [--dry-run]
  ./migration.sh reinstall-mbp-plasmoid [--target primary|screen:N] [--dry-run]
  ./migration.sh install-youtube-force-h264 [--dry-run]
  ./migration.sh configure-vaapi-brave [--dry-run]
EOF
}

parse_backup_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --target)
                [ $# -ge 2 ] || {
                    log "${RED}Falta valor para --target${NC}"
                    exit 1
                }
                BACKUP_TARGET="$2"
                shift 2
                ;;
            --dry-run)
                DRY_MODE=true
                shift
                ;;
            *)
                log "${RED}Opcion no reconocida para backup: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

parse_restore_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --source)
                [ $# -ge 2 ] || {
                    log "${RED}Falta valor para --source${NC}"
                    exit 1
                }
                BACKUP_SOURCE="$2"
                shift 2
                ;;
            --force)
                FORCE_RESTORE=true
                shift
                ;;
            --dry-run)
                DRY_MODE=true
                shift
                ;;
            *)
                log "${RED}Opcion no reconocida para restore: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

parse_bootstrap_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DRY_MODE=true
                shift
                ;;
            --hyprland)
                [ $# -ge 2 ] || {
                    log "${RED}Falta valor para --hyprland${NC}"
                    exit 1
                }
                case "$2" in
                    yes|no)
                        HYPRLAND_MODE="$2"
                        ;;
                    *)
                        log "${RED}Valor invalido para --hyprland: $2${NC}"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --apple-laptop)
                [ $# -ge 2 ] || {
                    log "${RED}Falta valor para --apple-laptop${NC}"
                    exit 1
                }
                case "$2" in
                    yes|no)
                        APPLE_LAPTOP_MODE="$2"
                        ;;
                    *)
                        log "${RED}Valor invalido para --apple-laptop: $2${NC}"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            *)
                log "${RED}Opcion no reconocida para bootstrap: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done
}

main() {
    local REQUESTED_PLASMOID_TARGET=""

    if [ $# -eq 0 ]; then
        main_menu
        return
    fi

    case "$1" in
        backup)
            shift
            parse_backup_args "$@"
            backup_system
            ;;
        restore)
            shift
            parse_restore_args "$@"
            restore_system
            ;;
        bootstrap)
            shift
            parse_bootstrap_args "$@"
            bootstrap_cachyos
            ;;
        install-youtube-force-h264)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            install_youtube_force_h264_package
            ;;
        configure-vaapi-brave)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            configure_vaapi_brave_broadwell
            ;;
        postcheck)
            shift
            post_bootstrap_checks
            ;;
        add-mbp-plasmoid)
            shift
            REQUESTED_PLASMOID_TARGET=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    --target)
                        [ $# -ge 2 ] || {
                            log "${RED}Falta valor para --target${NC}"
                            usage
                            exit 1
                        }
                        REQUESTED_PLASMOID_TARGET="$2"
                        shift 2
                        ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            add_mbp_plasmoid_to_desktop "$REQUESTED_PLASMOID_TARGET"
            ;;
        move-mbp-plasmoid)
            shift
            MBP_PLASMOID_TARGET="primary"
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    --target)
                        [ $# -ge 2 ] || {
                            log "${RED}Falta valor para --target${NC}"
                            usage
                            exit 1
                        }
                        MBP_PLASMOID_TARGET="$2"
                        shift 2
                        ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            move_mbp_watch_plasmoid "$MBP_PLASMOID_TARGET"
            ;;
        uninstall-mbp-watch)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            uninstall_mbp_watch_diagnostics
            ;;
        uninstall-mbp-plasmoid)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            uninstall_mbp_watch_plasmoid
            ;;
        reinstall-mbp-plasmoid)
            shift
            REQUESTED_PLASMOID_TARGET=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    --target)
                        [ $# -ge 2 ] || {
                            log "${RED}Falta valor para --target${NC}"
                            usage
                            exit 1
                        }
                        REQUESTED_PLASMOID_TARGET="$2"
                        shift 2
                        ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            reinstall_mbp_watch_plasmoid "$REQUESTED_PLASMOID_TARGET"
            ;;
        tui-bootstrap-run)
            shift
            tui_bootstrap_run "${1:-}" "${2:-}" "${3:-}"
            ;;
        -h|--help)
            usage
            ;;
        *)
            log "${RED}Comando no reconocido: $1${NC}"
            usage
            exit 1
            ;;
    esac
}

main "$@"
