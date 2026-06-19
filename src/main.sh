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
# shellcheck source=modules/restic_backup.sh
source "$APP_DIR/modules/restic_backup.sh"
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
    local SUBOPTION
    local MBP_PLASMOID_TARGET

    while true; do
        clear
        print_main_menu_intro

        log "${BLUE}Linux Migration Tool v${VERSION}${NC}"
        log ""
        log "1) Backup sistema"
        log "2) Bootstrap CachyOS"
        log "3) Post-check tras reinicio"
        log "4) Restaurar backup"
        log "5) MBP Watch y plasmoid"
        log "6) Salir"
        log ""

        prompt_read "Selecciona opcion: " OPTION

        case "$OPTION" in
            1)  backup_system ;;
            2)  bootstrap_cachyos ;;
            3)  post_bootstrap_checks ;;
            4)  restore_system ;;
            5)
                while true; do
                    log ""
                    log "MBP Watch y plasmoid"
                    log "──────── MBP Watch ────────"
                    log "1) Instalar sistema MBP Watch"
                    log "2) Desinstalar sistema MBP Watch"
                    log "──────── Plasmoid MBP Watch ────────"
                    log "3) Añadir widget al escritorio"
                    log "4) Widget en pantalla..."
                    log "5) Reinstalar widget MBP Watch"
                    log "6) Quitar widget MBP Watch"
                    log "7) Atrás"
                    log ""

                    prompt_read "Selecciona opcion: " SUBOPTION

                    case "$SUBOPTION" in
                        1)
                            install_mbp_watch_diagnostics
                            ;;
                        2)
                            uninstall_mbp_watch_diagnostics
                            ;;
                        3)
                            prompt_read "Pantalla del widget [primary|screen:N]: " MBP_PLASMOID_TARGET
                            MBP_PLASMOID_TARGET="${MBP_PLASMOID_TARGET:-primary}"
                            add_mbp_plasmoid_to_desktop "$MBP_PLASMOID_TARGET"
                            ;;
                        4)
                            prompt_read "Pantalla del widget [primary|screen:N]: " MBP_PLASMOID_TARGET
                            MBP_PLASMOID_TARGET="${MBP_PLASMOID_TARGET:-primary}"
                            move_mbp_watch_plasmoid "$MBP_PLASMOID_TARGET"
                            ;;
                        5)
                            prompt_read "Pantalla del widget [primary|screen:N]: " MBP_PLASMOID_TARGET
                            MBP_PLASMOID_TARGET="${MBP_PLASMOID_TARGET:-primary}"
                            reinstall_mbp_watch_plasmoid "$MBP_PLASMOID_TARGET"
                            ;;
                        6) uninstall_mbp_watch_plasmoid ;;
                        7) break ;;
                        *) log "${RED}Opcion invalida.${NC}" ;;
                    esac
                done
                ;;
            6)  exit 0 ;;
            *)  log "${RED}Opcion invalida.${NC}" ;;
        esac
    done
}

usage() {
    cat <<EOF
Linux Migration Tool v${VERSION} - Herramienta de migración y configuración para CachyOS

USO:
  ./migration.sh [comando] [opciones]

COMANDOS PRINCIPALES:
  (sin comando)              Lanza el menú interactivo (TUI)
  bootstrap                  Configuración inicial del sistema (paquetes, AUR, IA, Apple, navegador, etc.)
                             Opciones: [--dry-run] [--hyprland yes|no] [--apple-laptop yes|no]
  backup                     Realiza copia de seguridad del sistema y datos
                             Opciones: [--target RUTA] [--dry-run]
  restore                    Restaura una copia de seguridad previa
                             Opciones: [--source RUTA] [--force] [--dry-run]
  restic-backup              Gestiona backup permanente Restic por SFTP/SSH
                             Subcomandos: init [--smoke-test] | run | status | snapshots |
                                          install-timer | disable-timer
  postcheck                  Verifica el estado del sistema tras el reinicio post-bootstrap
                             y genera contexto local para analisis con IA
  post-restore-fixups        Normaliza un HOME restaurado en una máquina nueva
                             (CLI npm/NVM, talk2ai deps, codexBar autostart, locks de Brave, etc.)
  test                       Ejecuta pruebas locales y reportes de preflight
                             Opciones: [profiles|catalog|syntax|all]

HERRAMIENTAS Y AJUSTES:
  configure-vaapi-brave      Configura VA-API Intel según el modelo detectado
                             Nota: normalmente se usa desde el bloque VA-API del bootstrap
  bootstrap-context          Muestra el modelo Apple detectado y el perfil aplicado
  bootstrap-catalog          Imprime el catálogo de bloques compatibles para la TUI
  backup-config-catalog      Imprime la configuración importante detectada para la TUI
  backup-data-catalog        Imprime los directorios de datos detectados para la TUI
  export-ai-context          Exporta un resumen post-instalacion para analisis con IA
                             Salidas: ~/.local/state/linux-migration-tool/{postinstall-ai-context.txt,postinstall-ai-context.redacted.txt}
  install-talk2ai            Instala o actualiza talk2ai descargandolo desde GitHub
  install-codexbar-tray      Instala codexBar Tray desde un repo local restaurado/detectado
  install-youtube-force-h264 Prepara la extensión local YouTube Force H264 para carga manual
                             Nota: normalmente se usa desde el bloque YouTube Force H264 del bootstrap

MBP WATCH (Diagnóstico y Overlay):
  install-mbp-watch          Instala o actualiza el daemon de diagnóstico y servicio systemd
  add-mbp-plasmoid           Añade el widget MBP Watch al escritorio KDE
  move-mbp-plasmoid          Mueve el widget a otra pantalla [--target primary|screen:N]
  reinstall-mbp-plasmoid     Reinstala el paquete del widget y la instancia
  uninstall-mbp-watch        Desinstala el daemon de diagnóstico y servicio systemd
  uninstall-mbp-plasmoid     Elimina el widget del escritorio y desinstala el paquete

OPCIONES GLOBALES (Variables de Entorno):
  TUI_BACKEND=[python|whiptail|text]  Fuerza el motor de interfaz
  DRY_MODE=true                       Equivalente a pasar --dry-run
  TUI_WIFI_COUNTRY=ES                 Pre-configura el país para el Wi-Fi
  TUI_BROWSER=brave                   Pre-configura el navegador para aceleración HW
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
    local TEST_MODE=""

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
        restic-backup)
            shift
            restic_backup_cli "$@"
            ;;
        bootstrap)
            shift
            parse_bootstrap_args "$@"
            bootstrap_cachyos
            ;;
        bootstrap-context)
            get_bootstrap_context_text
            ;;
        bootstrap-catalog)
            get_bootstrap_checklist_items
            ;;
        backup-config-catalog)
            backup_config_catalog
            ;;
        backup-data-catalog)
            backup_data_catalog
            ;;
        export-ai-context)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            export_postinstall_ai_context
            ;;
        test)
            shift
            TEST_MODE="${1:-all}"
            case "$TEST_MODE" in
                profiles)
                    bash "$APP_DIR/../tests/test_bootstrap_profiles.sh"
                    ;;
                catalog)
                    bash "$APP_DIR/../tests/test_bootstrap_catalog.sh"
                    ;;
                syntax)
                    bash -n \
                        "$APP_DIR/../migration.sh" \
                        "$APP_DIR/main.sh" \
                        "$APP_DIR/lib/common.sh" \
                        "$APP_DIR/modules"/*.sh \
                        "$APP_DIR/tools"/*.sh \
                        "$APP_DIR/lib/tui.sh"
                    ;;
                all)
                    bash "$APP_DIR/../tests/run.sh"
                    ;;
                *)
                    log "${RED}Modo de test no reconocido: $TEST_MODE${NC}"
                    usage
                    exit 1
                    ;;
            esac
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
        install-talk2ai)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            install_talk2ai_from_github
            ;;
        install-codexbar-tray)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            install_codexbar_tray_from_local_repo
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
        post-restore-fixups)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            post_restore_fixups
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
        install-mbp-watch)
            shift
            while [ $# -gt 0 ]; do
                case "$1" in
                    --dry-run) DRY_MODE=true; shift ;;
                    *) log "${RED}Opcion no reconocida: $1${NC}"; usage; exit 1 ;;
                esac
            done
            install_mbp_watch_diagnostics
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
