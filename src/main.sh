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

main_menu() {
    clear

    print_main_menu_intro

    log "${BLUE}"
    log "Linux Migration Tool v${VERSION}"
    log "${NC}"

    log "1) Backup sistema"
    log "2) Bootstrap CachyOS"
    log "3) Post-check tras reinicio"
    log "4) Restaurar backup"
    log "5) Desinstalar MBP Watch"
    log "6) Salir"
    log ""

    prompt_read "Selecciona opcion: " OPTION

    case "$OPTION" in
        1)
            backup_system
            ;;
        2)
            bootstrap_cachyos
            ;;
        3)
            post_bootstrap_checks
            ;;
        4)
            restore_system
            ;;
        5)
            uninstall_mbp_watch_diagnostics
            ;;
        6)
            exit 0
            ;;
        *)
            log "${RED}Opcion invalida.${NC}"
            ;;
    esac
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
  ./migration.sh uninstall-mbp-watch [--dry-run]
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
        postcheck)
            shift
            post_bootstrap_checks
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
