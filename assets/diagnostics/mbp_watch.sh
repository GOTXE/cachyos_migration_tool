#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="${MBP_WATCH_CONFIG_FILE:-/etc/mbp-watch.conf}"

# shellcheck disable=SC1090,SC1091
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"

DEFAULT_STATE_DIR="/var/lib/mbp-watch"

resolve_default_desktop_dir() {
    local HOME_DIR="${HOME:-/root}"
    local USER_DIRS_FILE="${XDG_CONFIG_HOME:-$HOME_DIR/.config}/user-dirs.dirs"
    local RAW_VALUE=""

    if [ -r "$USER_DIRS_FILE" ]; then
        RAW_VALUE="$(
            sed -n 's/^XDG_DESKTOP_DIR="\([^"]*\)"$/\1/p' "$USER_DIRS_FILE" | head -n 1
        )"
    fi

    if [ -n "$RAW_VALUE" ]; then
        printf '%s\n' "${RAW_VALUE//\$HOME/$HOME_DIR}"
        return 0
    fi

    printf '%s\n' "$HOME_DIR/Desktop"
}

BASE_DIR="${MBP_WATCH_DIR:-$DEFAULT_STATE_DIR}"
EVENTS_LOG="$BASE_DIR/events.log"
SNAPSHOTS_LOG="$BASE_DIR/snapshots.log"
INVENTORY_LOG="$BASE_DIR/inventory.log"
DAILY_LOG="$BASE_DIR/daily_errors.log"
STATUS_LOG="$BASE_DIR/status.log"
REPORT_HTML="$BASE_DIR/report.html"
REPORT_TEXT="$BASE_DIR/report.txt"
JOURNAL_PID_FILE="$BASE_DIR/journal.pid"
SNAPSHOT_PID_FILE="$BASE_DIR/snapshot.pid"
SERVE_PID_FILE="$BASE_DIR/serve.pid"
DRIVER_HEALTH_LOG="$BASE_DIR/driver_health.log"
INTERVAL_SECONDS="${MBP_WATCH_INTERVAL:-5}"
MBP_WATCH_PORT="${MBP_WATCH_PORT:-7070}"
RESUME_CONTEXT_WINDOW_MINUTES="${MBP_WATCH_RESUME_WINDOW_MINUTES:-15}"
WIFI_PING_TARGET="${MBP_WATCH_WIFI_PING_TARGET:-8.8.8.8}"
WIFI_SCAN_CACHE_TTL="${MBP_WATCH_WIFI_SCAN_CACHE_TTL:-120}"
WIFI_SIGNAL_WARN_DBM="${MBP_WATCH_WIFI_SIGNAL_WARN_DBM:--72}"
WIFI_INTERFERENCE_SIGNAL_DBM="${MBP_WATCH_WIFI_INTERFERENCE_SIGNAL_DBM:--75}"

# MBP-specific subsystems added: i915 (Intel Iris), applesmc (sensors/fans),
# snd_hda_intel (audio), thunderbolt, PM suspend/resume errors
FAILURE_EVENT_REGEX='brcmf.*(fail|error|timeout|unknown frame|crashed)|wpa_supplicant.*(fail|error|timeout)|dhcp4 .* (failed|timeout)|device .*Activation: failed|NetworkManager.*(failed|error|timed out|activation failed)|bluetoothd.*(fail|error)|iwlwifi.*(fail|error|timeout)|mt76.*(fail|error|timeout)|ath.*(fail|error|timeout)|rtl.*(fail|error|timeout)|rtw.*(fail|error|timeout)|i915.*(error|fail|hang|reset|gpu hang)|applesmc.*(error|fail)|snd_hda_intel.*(error|fail)|thunderbolt.*(error|fail|timeout)|PM: .*(error|fail)|PM: suspend.*failed|PM: resume.*fail|cpu.*throttl|thermal.*throttl|CPU.*max.*freq|turbo.*disabled'

NOISY_EVENT_REGEX='brave\[[0-9]+\]: .*ERROR:gpu/command_buffer/|brave\[[0-9]+\]: .*SharedImageManager::ProduceSkia|brcmf_inetaddr_changed: fail to get arp ip table|brcmf_cfg80211_get_station: GET STA INFO failed|brcmf_p2p_send_action_frame: Unknown Frame|brcmfmac.*Direct firmware load for brcm/brcmfmac43602.*failed with error -2|iwd-manager.*(if_nametoindex failed|is not a Wifi device)'

MAX_EVENT_LINES=10000
MAX_SNAPSHOT_LINES=500
MAX_STATUS_LINES=2000
COUNT_WINDOW_LINES=500

if ! mkdir -p "$BASE_DIR" 2>/dev/null; then
    BASE_DIR="${PWD}/.mbp-watch"
    mkdir -p "$BASE_DIR"
fi

EVENTS_LOG="$BASE_DIR/events.log"
SNAPSHOTS_LOG="$BASE_DIR/snapshots.log"
INVENTORY_LOG="$BASE_DIR/inventory.log"
DAILY_LOG="$BASE_DIR/daily_errors.log"
STATUS_LOG="$BASE_DIR/status.log"
REPORT_HTML="$BASE_DIR/report.html"
REPORT_TEXT="$BASE_DIR/report.txt"
JOURNAL_PID_FILE="$BASE_DIR/journal.pid"
SNAPSHOT_PID_FILE="$BASE_DIR/snapshot.pid"
SERVE_PID_FILE="$BASE_DIR/serve.pid"
DRIVER_HEALTH_LOG="$BASE_DIR/driver_health.log"
WIFI_SCAN_CACHE_FILE="$BASE_DIR/wifi_scan.cache"

timestamp() {
    date --iso-8601=seconds
}

timestamp_display() {
    date '+%-d %b %Y  %H:%M:%S'
}

capture_energy_mode() {
    local MODE

    if command -v powerprofilesctl >/dev/null 2>&1; then
        MODE="$(powerprofilesctl get 2>/dev/null || true)"
        case "$MODE" in
            performance|balanced|power-saver)
                printf '%s\n' "$MODE"
                return 0
                ;;
        esac
    fi

    if [ -r /sys/firmware/acpi/platform_profile ]; then
        MODE="$(tr -d '[:space:]' < /sys/firmware/acpi/platform_profile 2>/dev/null || true)"
        case "$MODE" in
            performance|balanced|power-saver|low-power|quiet)
                printf '%s\n' "$MODE"
                return 0
                ;;
        esac
    fi

    printf 'unknown\n'
}

log_status() {
    printf '[%s] %s\n' "$(timestamp)" "$1" >> "$STATUS_LOG"
}

prune_log_file() {
    local FILE_PATH="$1"
    local MAX_LINES="$2"
    local CURRENT_LINES
    local TMP_FILE

    [ -f "$FILE_PATH" ] || return 0

    CURRENT_LINES="$(wc -l < "$FILE_PATH" 2>/dev/null || printf '0')"
    if [ "$CURRENT_LINES" -le "$MAX_LINES" ]; then
        return 0
    fi

    TMP_FILE="$(mktemp "${FILE_PATH}.XXXXXX")"
    tail -n "$MAX_LINES" "$FILE_PATH" > "$TMP_FILE"
    mv "$TMP_FILE" "$FILE_PATH"
    chmod 644 "$FILE_PATH"
}


is_running_pid() {
    local PID_FILE="$1"

    [ -f "$PID_FILE" ] || return 1

    local PID
    local CMDLINE
    PID="$(< "$PID_FILE")"

    [ -n "$PID" ] || return 1
    kill -0 "$PID" 2>/dev/null || return 1
    CMDLINE="$(ps -p "$PID" -o args= 2>/dev/null || true)"
    [ -n "$CMDLINE" ] || return 1

    case "$PID_FILE" in
        "$SERVE_PID_FILE")
            printf '%s\n' "$CMDLINE" | grep -Eq 'python3 .*http\.server|mbp_watch\.sh _serve_loop' || return 1
            ;;
        *)
            printf '%s\n' "$CMDLINE" | grep -q 'mbp_watch\.sh' || return 1
            ;;
    esac

    return 0
}

cleanup_stale_pid_file() {
    local PID_FILE="$1"

    if [ -f "$PID_FILE" ] && ! is_running_pid "$PID_FILE"; then
        rm -f "$PID_FILE"
    fi
}

# Captures static hardware inventory once at startup.
# Does not repeat in the snapshot loop since GPU/WiFi chip do not change.
capture_hardware_inventory() {
    {
        printf '=== HARDWARE INVENTORY %s ===\n' "$(timestamp)"

        printf '\n[cpu]\n'
        if command -v lscpu >/dev/null 2>&1; then
            lscpu 2>/dev/null | awk -F: '
                BEGIN {
                    want["Architecture"] = 1
                    want["Model name"] = 1
                    want["CPU(s)"] = 1
                    want["Thread(s) per core"] = 1
                    want["Core(s) per socket"] = 1
                    want["Socket(s)"] = 1
                    want["CPU max MHz"] = 1
                    want["CPU min MHz"] = 1
                    want["CPU(s) scaling MHz"] = 1
                }
                {
                    key = $1
                    gsub(/^[ \t]+|[ \t]+$/, "", key)
                    if (want[key]) {
                        value = $2
                        gsub(/^[ \t]+|[ \t]+$/, "", value)
                        if (length(value) > 0) print key ": " value
                    }
                }
            '
            awk -F: '
                /^cpu MHz/ {
                    gsub(/^[ \t]+|[ \t]+$/, "", $2)
                    if (length($2) > 0) {
                        print "Current MHz: " $2
                        seen = 1
                        exit
                    }
                }
                END {
                    if (!seen) {
                        print "Current MHz: unknown"
                    }
                }
            ' /proc/cpuinfo 2>/dev/null
        else
            awk -F: '
                BEGIN {
                    printed = 0
                }
                /^model name/ {
                    gsub(/^[ \t]+|[ \t]+$/, "", $2)
                    if (!printed) {
                        print "Model name: " $2
                        printed = 1
                    }
                }
                /^processor/ {
                    cpus++
                }
                END {
                    if (!printed) print "model name not available"
                    print "CPU(s): " (cpus > 0 ? cpus : "unknown")
                    print "Current MHz: unknown"
                }
            ' /proc/cpuinfo 2>/dev/null
        fi

        printf '\n[apple_model]\n'
        cat /sys/class/dmi/id/product_name 2>/dev/null || printf 'unknown\n'
        cat /sys/class/dmi/id/board_name 2>/dev/null || true

        printf '\n[kernel]\n'
        uname -r

        printf '\n[gpu]\n'
        lspci 2>/dev/null | grep -Ei 'vga|3d|display' || printf 'unknown\n'

        printf '\n[wifi_chip]\n'
        lspci -nn 2>/dev/null | grep -Ei 'network|wireless' || printf 'unknown\n'

        printf '\n[wifi_firmware]\n'
        dmesg 2>/dev/null | grep -i 'brcmfmac.*firmware\|brcmfmac.*version\|brcmfmac.*loaded\|brcmfmac.*nvram' \
            | tail -5 || printf 'no brcmfmac log found\n'

        printf '\n[bluetooth_chip]\n'
        lspci -nn 2>/dev/null | grep -Ei 'bluetooth' \
            || lsusb 2>/dev/null | grep -Ei 'bluetooth' \
            || printf 'not found via lspci/lsusb\n'

        printf '\n[audio_card]\n'
        aplay -l 2>/dev/null | grep -v '^\*\*' | head -6 || printf 'aplay not available\n'

        printf '\n[camera]\n'
        ls /dev/video* 2>/dev/null || printf 'no /dev/video* found\n'

        printf '\n[thunderbolt_ports]\n'
        ls /sys/bus/thunderbolt/devices/ 2>/dev/null \
            || lspci 2>/dev/null | grep -i thunderbolt | head -2 \
            || printf 'not found\n'
    } > "$INVENTORY_LOG" 2>&1
}

# Checks that each hardware driver is loaded and functional.
# Writes NAME|STATUS|DETAIL|FIX lines to DRIVER_HEALTH_LOG.
# STATUS: OK | WARN | ERROR
capture_driver_health() {
    {
        printf '=== DRIVER HEALTH %s ===\n' "$(timestamp)"

        # ── Camera ────────────────────────────────────────────────────────
        # MBP 2013+ usa PCIe (14e4:1570, driver: facetimehd).
        # MBP anteriores usan USB (driver: uvcvideo).
        local CAM_S="OK" CAM_D="" CAM_F=""
        local CAM_PCIE CAM_DEV_NODES
        CAM_PCIE="$(lspci -nn 2>/dev/null | grep -i '14e4:1570\|1570.*apple\|apple.*1570' | head -1 | tr '|' ';' || true)"
        CAM_DEV_NODES="$(ls /dev/video* 2>/dev/null | tr '\n' ' ' | tr '|' ';' | sed 's/ $//' || true)"

        if [ -n "$CAM_PCIE" ]; then
            # PCIe camera (MBP 2013+) — necesita facetimehd
            if grep -q '^facetimehd ' /proc/modules 2>/dev/null; then
                CAM_D="facetimehd loaded (PCIe)"
                if [ -n "$CAM_DEV_NODES" ]; then
                    CAM_D="${CAM_D}; ${CAM_DEV_NODES}"
                else
                    CAM_S="WARN"
                    CAM_D="${CAM_D}; no /dev/video* — puede faltar firmware o requiere kernel Zen"
                    CAM_F="yay -S facetimehd-firmware && sudo modprobe -r facetimehd && sudo modprobe facetimehd  (si persiste: instala linux-cachyos-zen y reinicia)"
                fi
            else
                CAM_S="ERROR"
                CAM_D="cámara PCIe detectada pero facetimehd no cargado"
                CAM_F="yay -S facetimehd-dkms facetimehd-firmware && sudo modprobe -r bdc_pci 2>/dev/null; sudo modprobe facetimehd && echo facetimehd | sudo tee /etc/modules-load.d/facetimehd.conf && echo 'blacklist bdc_pci' | sudo tee /etc/modprobe.d/facetimehd.conf"
            fi
        elif grep -q '^uvcvideo ' /proc/modules 2>/dev/null; then
            # USB camera — uvcvideo
            CAM_D="uvcvideo loaded"
            if [ -n "$CAM_DEV_NODES" ]; then
                CAM_D="${CAM_D}; ${CAM_DEV_NODES}"
            else
                CAM_S="WARN"
                CAM_D="${CAM_D}; no /dev/video* — cámara USB no enumerada"
                CAM_F="lsusb | grep -i apple  (si no aparece, problema de hardware USB)"
            fi
        else
            CAM_S="WARN"
            CAM_D="no se detecta cámara PCIe (14e4:1570) ni módulo uvcvideo"
            CAM_F="lspci | grep -i apple  y  lsusb | grep -i apple  para identificar el tipo de cámara"
        fi
        printf 'camera|%s|%s|%s\n' "$CAM_S" "$CAM_D" "$CAM_F"

        # ── Wi-Fi (brcmfmac) ──────────────────────────────────────────────
        local WIFI_S="OK" WIFI_D="" WIFI_F=""
        if grep -q '^brcmfmac ' /proc/modules 2>/dev/null; then
            WIFI_D="brcmfmac loaded"
            local WLAN_IF
            local RESUME_CONTEXT
            WLAN_IF="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}' || true)"
            if [ -n "$WLAN_IF" ]; then
                WIFI_D="${WIFI_D}; interface: ${WLAN_IF}"
            else
                WIFI_S="WARN"
                WIFI_D="${WIFI_D}; no wireless interface found"
                WIFI_F="sudo modprobe -r brcmfmac && sudo modprobe brcmfmac"
                if recent_suspend_resume_context && current_wifi_is_connected; then
                    WIFI_S="OK"
                    WIFI_D="${WIFI_D}; link restored after suspend/resume"
                    WIFI_F="Interface discovery still settling; recheck only if it persists fuera de la reanudación"
                fi
            fi
            local FW_WARN
            RESUME_CONTEXT=false
            if recent_suspend_resume_context; then
                RESUME_CONTEXT=true
            fi
            FW_WARN="$(dmesg 2>/dev/null \
                | grep -i 'brcmfmac.*fail\|brcmfmac.*error\|brcmfmac.*no such\|brcmfmac.*unable' \
                | tail -1 | tr '|' ';' || true)"
            if [ -n "$FW_WARN" ]; then
                WIFI_D="${WIFI_D}; firmware warning in dmesg"
                if current_wifi_is_connected; then
                    WIFI_S="OK"
                    if [ "$RESUME_CONTEXT" = true ]; then
                        WIFI_D="${WIFI_D}; warning detected after suspend/resume and link is up"
                        WIFI_F="Posible ruido transitorio tras reanudar; revisa firmware solo si vuelve a fallar en frio"
                    else
                        WIFI_D="${WIFI_D}; link is up"
                        local FW_BLOB_ONLY=false
                        if printf '%s\n' "$FW_WARN" | grep -qE 'txcap_blob|clm_blob|Apple Inc\.-MacBookPro'; then
                            if ! dmesg 2>/dev/null \
                                | grep -iE 'brcmfmac.*(fail|error|no such|unable)' \
                                | grep -qvE 'txcap_blob|clm_blob|Apple Inc\.-MacBookPro'; then
                                FW_BLOB_ONLY=true
                            fi
                        fi
                        if [ "$FW_BLOB_ONLY" = true ]; then
                            WIFI_F="Optional calibration blobs unavailable for BCM43602 (txcap_blob, clm_blob, device .bin) — not required for operation"
                        else
                            WIFI_F="Firmware warning present but wifi is connected; monitor for disconnections. Check: dmesg | grep brcmfmac"
                        fi
                    fi
                else
                    WIFI_S="WARN"
                    WIFI_F="Verifica: ls /lib/firmware/brcm/brcmfmac43602* — si falta: sudo pacman -S linux-firmware"
                fi
            fi
        else
            WIFI_S="ERROR"
            WIFI_D="brcmfmac not loaded"
            if ls /lib/firmware/brcm/brcmfmac43602-pcie.bin >/dev/null 2>&1; then
                WIFI_F="sudo modprobe brcmfmac (firmware present, module not loaded)"
            else
                WIFI_F="sudo pacman -S linux-firmware && reboot (firmware missing: /lib/firmware/brcm/brcmfmac43602-pcie.bin)"
            fi
            if recent_suspend_resume_context && current_wifi_is_connected; then
                WIFI_S="OK"
                WIFI_D="${WIFI_D}; wifi link restored after suspend/resume"
                WIFI_F="Módulo no visible todavía; revalida solo si se mantiene fuera de la reanudación"
            elif recent_suspend_resume_context; then
                WIFI_S="WARN"
                WIFI_D="${WIFI_D}; likely transient after suspend/resume"
                WIFI_F="Revisar solo si el módulo sigue ausente fuera de la ventana de reanudación"
            fi
        fi
        printf 'wifi|%s|%s|%s\n' "$WIFI_S" "$WIFI_D" "$WIFI_F"

        # ── Bluetooth (btusb) ─────────────────────────────────────────────
        local BT_S="OK" BT_D="" BT_F=""
        if grep -q '^btusb ' /proc/modules 2>/dev/null; then
            BT_D="btusb loaded"
            local HCI_DEV
            HCI_DEV="$(ls /sys/class/bluetooth/ 2>/dev/null | head -1 || true)"
            if [ -n "$HCI_DEV" ]; then
                BT_D="${BT_D}; ${HCI_DEV} present"
            else
                BT_S="WARN"
                BT_D="${BT_D}; no hci device found"
                BT_F="sudo systemctl start bluetooth && sudo rfkill unblock bluetooth"
            fi
        else
            BT_S="ERROR"
            BT_D="btusb not loaded"
            BT_F="sudo modprobe btusb && sudo systemctl start bluetooth"
        fi
        printf 'bluetooth|%s|%s|%s\n' "$BT_S" "$BT_D" "$BT_F"

        # ── GPU (i915) ────────────────────────────────────────────────────
        local GPU_S="OK" GPU_D="" GPU_F=""
        if grep -q '^i915 ' /proc/modules 2>/dev/null; then
            GPU_D="i915 loaded"
            local DRI_DEV
            DRI_DEV="$(ls /dev/dri/card* 2>/dev/null | head -1 || true)"
            if [ -n "$DRI_DEV" ]; then
                GPU_D="${GPU_D}; ${DRI_DEV}"
            else
                GPU_S="WARN"
                GPU_D="${GPU_D}; no /dev/dri/card*"
                GPU_F="sudo pacman -S mesa libva-intel-driver && reboot"
            fi
        else
            GPU_S="ERROR"
            GPU_D="i915 not loaded"
            GPU_F="sudo pacman -S mesa libva-intel-driver xf86-video-intel && reboot"
        fi
        printf 'gpu|%s|%s|%s\n' "$GPU_S" "$GPU_D" "$GPU_F"

        # ── Audio (snd_hda_intel) ─────────────────────────────────────────
        local AUD_S="OK" AUD_D="" AUD_F=""
        if grep -q '^snd_hda_intel ' /proc/modules 2>/dev/null; then
            AUD_D="snd_hda_intel loaded"
            local ALSA_CARD
            ALSA_CARD="$(aplay -l 2>/dev/null | grep '^card' | head -1 | tr '|' ';' || true)"
            if [ -n "$ALSA_CARD" ]; then
                AUD_D="${AUD_D}; ${ALSA_CARD}"
            else
                AUD_S="WARN"
                AUD_D="${AUD_D}; no ALSA cards detected"
                AUD_F="sudo pacman -S alsa-utils pipewire pipewire-alsa && systemctl --user restart pipewire"
            fi
        else
            AUD_S="ERROR"
            AUD_D="snd_hda_intel not loaded"
            AUD_F="sudo modprobe snd_hda_intel (si falta el módulo: sudo pacman -S alsa-utils)"
        fi
        printf 'audio|%s|%s|%s\n' "$AUD_S" "$AUD_D" "$AUD_F"

        # ── AppleSMC (fans / sensors) ─────────────────────────────────────
        local SMC_S="OK" SMC_D="" SMC_F=""
        if grep -q '^applesmc ' /proc/modules 2>/dev/null; then
            SMC_D="applesmc loaded"
            if ls /sys/devices/platform/applesmc.768/temp1_input >/dev/null 2>&1; then
                SMC_D="${SMC_D}; sysfs sensors ok"
            else
                SMC_S="WARN"
                SMC_D="${SMC_D}; sysfs path not found"
                SMC_F="Verifica: ls /sys/devices/platform/applesmc*/temp* — puede estar en otra ruta"
            fi
        else
            SMC_S="ERROR"
            SMC_D="applesmc not loaded"
            SMC_F="sudo modprobe applesmc (sin él no hay datos de temperatura ni ventiladores)"
        fi
        printf 'applesmc|%s|%s|%s\n' "$SMC_S" "$SMC_D" "$SMC_F"

        # ── Thunderbolt ───────────────────────────────────────────────────
        local TB_S="OK" TB_D="" TB_F=""
        if grep -q '^thunderbolt ' /proc/modules 2>/dev/null; then
            TB_D="thunderbolt loaded"
            local TB_COUNT
            TB_COUNT="$(ls /sys/bus/thunderbolt/devices/ 2>/dev/null | wc -l || printf '0')"
            TB_D="${TB_D}; ${TB_COUNT} device(s) on bus"
        else
            TB_S="WARN"
            TB_D="thunderbolt module not loaded"
            TB_F="sudo modprobe thunderbolt (necesario para puertos Thunderbolt/USB-C)"
        fi
        printf 'thunderbolt|%s|%s|%s\n' "$TB_S" "$TB_D" "$TB_F"

    } > "$DRIVER_HEALTH_LOG" 2>&1
}

capture_snapshot() {
    # flock garantiza que solo un snapshot escribe al log a la vez
    local _SNAP_LOCK="${BASE_DIR}/snapshot.lock"
    exec 9>>"$_SNAP_LOCK"
    if ! flock -n 9; then
        return 0  # ya hay un snapshot en curso, saltar esta iteración
    fi

    local BAT_PATH=""
    local WIFI_IF=""

    WIFI_IF="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}' || true)"

    {
        printf '\n=== SNAPSHOT %s ===\n' "$(timestamp)"

        printf '\n[system]\n'
        uname -a || true
        uptime || true

        printf '\n[memory]\n'
        free -h || true

        printf '\n[memory_parsed]\n'
        awk '
            /^MemTotal:/     { mem_total=$2; printf "mem_total_kb: %s\n", $2 }
            /^MemFree:/      { mem_free=$2 }
            /^Buffers:/      { buffers=$2 }
            /^Cached:/       { cached=$2 }
            /^MemAvailable:/ { printf "mem_available_kb: %s\n", $2 }
            /^SwapTotal:/    { swap_total=$2; printf "swap_total_kb: %s\n", $2 }
            /^SwapFree:/     { printf "swap_used_kb: %s\n", swap_total - $2 }
            END { printf "mem_used_kb: %s\n", mem_total - mem_free - buffers - cached }
        ' /proc/meminfo 2>/dev/null || true

        printf '\n[temperature_fans]\n'
        if command -v sensors >/dev/null 2>&1; then
            local FAN_SUMMARY=""
            local APPSMC_FAN_PATH
            FAN_SUMMARY="$(
                sensors 2>/dev/null \
                    | awk -F: '
                        tolower($1) ~ /^fan[0-9]+$/ {
                            gsub(/^[ \t]+|[ \t]+$/, "", $2)
                            if (length($2) > 0) {
                                if (out != "") out = out "; "
                                out = out $1 ": " $2
                            }
                        }
                        END {
                            if (out != "") print out
                        }
                    ' || true
            )"
            if [ -z "$FAN_SUMMARY" ]; then
                for APPSMC_FAN_PATH in /sys/devices/platform/applesmc*/fan*_input; do
                    [ -r "$APPSMC_FAN_PATH" ] || continue
                    if [ -n "$FAN_SUMMARY" ]; then
                        FAN_SUMMARY="${FAN_SUMMARY}; "
                    fi
                    FAN_SUMMARY="${FAN_SUMMARY}$(basename "${APPSMC_FAN_PATH%_input}"): $(cat "$APPSMC_FAN_PATH") RPM"
                done
            fi
            if [ -n "$FAN_SUMMARY" ]; then
                printf 'fan speed: %s\n' "$FAN_SUMMARY"
            fi
            sensors 2>/dev/null | grep -E 'Core |fan[0-9]|Fan|Package id' || true
        else
            printf 'sensors not installed (pacman -S lm_sensors)\n'
        fi

        printf '\n[cpu_perf]\n'
        local CORE_FREQS="" CORE_USAGES="" CORE_N=0 FREQ_KHZ_FILE FREQ_KHZ FREQ_MHZ

        # Capturar estado de /proc/stat antes y después para calcular uso de CPU
        local STAT_BEFORE STAT_AFTER
        STAT_BEFORE=$(cat /proc/stat 2>/dev/null)
        sleep 0.1
        STAT_AFTER=$(cat /proc/stat 2>/dev/null)

        for FREQ_KHZ_FILE in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
            [ -r "$FREQ_KHZ_FILE" ] || continue
            FREQ_KHZ="$(cat "$FREQ_KHZ_FILE" 2>/dev/null || printf '0')"
            FREQ_MHZ=$(( FREQ_KHZ / 1000 ))
            CORE_FREQS="${CORE_FREQS}core${CORE_N}=${FREQ_MHZ}MHz "
            CORE_N=$((CORE_N + 1))
        done
        printf 'current_freq: %s\n' "${CORE_FREQS% }"

        # Calcular uso de CPU por core
        CORE_USAGES="$(
            awk -v BEFORE="$STAT_BEFORE" -v AFTER="$STAT_AFTER" '
            BEGIN {
                split(BEFORE, before_lines, "\n")
                split(AFTER, after_lines, "\n")

                for (i in before_lines) {
                    if (before_lines[i] ~ /^cpu[0-9]/) {
                        core_match = match(before_lines[i], /^cpu([0-9]+)/)
                        if (core_match) {
                            core_id = substr(before_lines[i], RSTART+3, RLENGTH-3)
                            split(before_lines[i], b_fields)

                            # Buscar la línea correspondiente en AFTER
                            for (j in after_lines) {
                                if (after_lines[j] ~ /^cpu[0-9]+ /) {
                                    after_core = match(after_lines[j], /^cpu([0-9]+)/)
                                    if (after_core && substr(after_lines[j], RSTART+3, RLENGTH-3) == core_id) {
                                        split(after_lines[j], a_fields)

                                        # Calcular delta
                                        b_total = b_fields[2] + b_fields[3] + b_fields[4] + b_fields[5]
                                        a_total = a_fields[2] + a_fields[3] + a_fields[4] + a_fields[5]

                                        b_idle = b_fields[5]
                                        a_idle = a_fields[5]

                                        delta_total = a_total - b_total
                                        delta_idle = a_idle - b_idle

                                        if (delta_total > 0) {
                                            usage = int(100 * (delta_total - delta_idle) / delta_total)
                                        } else {
                                            usage = 0
                                        }

                                        if (first++) printf " "
                                        printf "core%s=%d%%", core_id, usage
                                        break
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ' 2>/dev/null || printf ''
        )"
        if [ -n "$CORE_USAGES" ]; then
            printf 'cpu_usage: %s\n' "$CORE_USAGES"
        fi

        local MAX_FREQ_KHZ MAX_FREQ_MHZ
        MAX_FREQ_KHZ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || printf '0')"
        MAX_FREQ_MHZ=$(( MAX_FREQ_KHZ / 1000 ))
        printf 'max_freq_mhz: %s\n' "$MAX_FREQ_MHZ"

        # Base clock: sysfs no lo expone en Broadwell, usar 88% del turbo max (da 2904 ≈ 2900 real)
        # rdmsr evitado en el hot path — bloquea bajo carga 100%
        local BASE_FREQ_KHZ BASE_FREQ_MHZ
        BASE_FREQ_KHZ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>/dev/null || printf '0')"
        if [ "$BASE_FREQ_KHZ" -eq 0 ] && [ "$MAX_FREQ_KHZ" -gt 0 ]; then
            BASE_FREQ_KHZ=$(( MAX_FREQ_KHZ * 88 / 100 ))
        fi
        BASE_FREQ_MHZ=$(( BASE_FREQ_KHZ / 1000 ))
        printf 'base_freq_mhz: %s\n' "$BASE_FREQ_MHZ"

        local GOV
        GOV="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || printf 'unknown')"
        printf 'governor: %s\n' "$GOV"

        local ENERGY_MODE
        ENERGY_MODE="$(capture_energy_mode)"
        printf 'energy_mode: %s\n' "$ENERGY_MODE"

        local CUR0_KHZ FREQ_RATIO FREQ_HEADROOM FREQ_STATE
        CUR0_KHZ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || printf '0')"
        if [ "$BASE_FREQ_KHZ" -gt 0 ] && [ "$MAX_FREQ_KHZ" -gt 0 ]; then
            # Ratio contra turbo max (para el display), throttle contra base clock
            FREQ_RATIO=$(( CUR0_KHZ * 100 / MAX_FREQ_KHZ ))
            FREQ_HEADROOM=$(( 100 - FREQ_RATIO ))
            # Throttling real = por debajo del base clock bajo carga
            if [ "$CUR0_KHZ" -lt "$BASE_FREQ_KHZ" ]; then
                FREQ_STATE="low"
            else
                FREQ_STATE="ok"
            fi
            printf 'freq_ratio: %s\n' "$FREQ_RATIO"
            printf 'freq_headroom: %s\n' "$FREQ_HEADROOM"
            printf 'freq_state: %s\n' "$FREQ_STATE"
        else
            printf 'freq_ratio: unknown\n'
            printf 'freq_headroom: unknown\n'
            printf 'freq_state: unknown\n'
        fi
        printf 'throttle_status: freq_state=%s ratio=%s%% headroom=%s%%\n' \
            "${FREQ_STATE:-unknown}" "${FREQ_RATIO:-0}" "${FREQ_HEADROOM:-0}"

        # PROCHOT: se determina por delta del counter del kernel (ver más abajo)
        local PROCHOT="false"
        local ALARM_CHK
        for ALARM_CHK in /sys/class/hwmon/hwmon*/temp*_alarm; do
            [ -r "$ALARM_CHK" ] || continue
            [ "$(cat "$ALARM_CHK" 2>/dev/null)" = "1" ] && PROCHOT="true" && break
        done

        local THERM_ALARM=""
        local ALARM_FILE
        for ALARM_FILE in /sys/class/hwmon/hwmon*/temp*_crit_alarm; do
            [ -r "$ALARM_FILE" ] || continue
            local VAL
            VAL="$(cat "$ALARM_FILE" 2>/dev/null || printf '0')"
            if [ "$VAL" = "1" ]; then
                THERM_ALARM="${THERM_ALARM}$(basename "$(dirname "$ALARM_FILE")")/$(basename "$ALARM_FILE") "
            fi
        done
        printf 'thermal_alarm: %s\n' "${THERM_ALARM:-none}"

        # Contador acumulativo de throttle del kernel (más fiable que frecuencia instantánea)
        local PKG_THROTTLE_NOW PKG_THROTTLE_PREV PKG_THROTTLE_DELTA
        PKG_THROTTLE_NOW="$(cat /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count 2>/dev/null || printf '0')"
        local _THROTTLE_STATE_FILE="${BASE_DIR}/throttle_count_prev.dat"
        PKG_THROTTLE_PREV="$(cat "$_THROTTLE_STATE_FILE" 2>/dev/null || printf '0')"
        if [ "$PKG_THROTTLE_NOW" -ge "$PKG_THROTTLE_PREV" ] 2>/dev/null; then
            PKG_THROTTLE_DELTA=$(( PKG_THROTTLE_NOW - PKG_THROTTLE_PREV ))
        else
            PKG_THROTTLE_DELTA=0
        fi
        printf '%s\n' "$PKG_THROTTLE_NOW" > "$_THROTTLE_STATE_FILE"
        printf 'throttle_count_now: %s\n' "$PKG_THROTTLE_NOW"
        printf 'throttle_count_delta: %s\n' "$PKG_THROTTLE_DELTA"
        [ "$PKG_THROTTLE_DELTA" -gt 0 ] && PROCHOT="true"
        printf 'prochot: %s\n' "$PROCHOT"

        printf '\n[load_and_processes]\n'
        uptime 2>/dev/null | sed 's/.*load average: /load_average: /' || true

        awk '/^ctxt / { print "context_switches: " $2 }' /proc/stat 2>/dev/null || true
        awk '/^processes / { print "procs_created: " $2 }' /proc/stat 2>/dev/null || true

        printf '\n[top_cpu_processes]\n'
        ps aux --sort=-%cpu 2>/dev/null | awk 'NR<=4 { printf "%s %s %s %s %s\n", $1, $3"%", $4"%", $(NF-1), $NF }' || true

        printf '\n[top_memory_processes]\n'
        ps aux --sort=-%mem 2>/dev/null | awk 'NR<=4 { printf "%s %s %s %s %s\n", $1, $3"%", $4"%", $(NF-1), $NF }' || true

        printf '\n[io_performance]\n'
        awk '
            /^read_io_stat / { reads=$2 }
            /^write_io_stat / { writes=$2 }
            END {
                if (reads > 0) printf "disk_read_stat: %s\n", reads
                if (writes > 0) printf "disk_write_stat: %s\n", writes
            }
        ' /proc/diskstats 2>/dev/null | head -1 || true
        awk '/^disk_reads / { print "disk_operations: " $2 " reads" }' /proc/vmstat 2>/dev/null || true
        awk '/^page / { s=s $0 " " } END { if (s != "") print "page_io: " s }' /proc/vmstat 2>/dev/null || true

        printf '\n[battery]\n'
        if command -v upower >/dev/null 2>&1; then
            BAT_PATH="$(upower -e 2>/dev/null | grep -i battery | head -1 || true)"
            if [ -n "$BAT_PATH" ]; then
                upower -i "$BAT_PATH" 2>/dev/null \
                    | grep -E 'state:|percentage:|energy:|capacity:|time to' || true
            else
                printf 'no battery device (upower)\n'
            fi
        elif [ -f /sys/class/power_supply/BAT0/capacity ]; then
            printf 'capacity: %s%%\n' "$(cat /sys/class/power_supply/BAT0/capacity)"
            [ -f /sys/class/power_supply/BAT0/status ] \
                && printf 'status: %s\n' "$(cat /sys/class/power_supply/BAT0/status)"
        else
            printf 'battery info not available\n'
        fi

        printf '\n[audio_state]\n'
        if command -v pactl >/dev/null 2>&1; then
            pactl info 2>/dev/null \
                | grep -E 'Server Name|Default Sink|Default Source' || true
            pactl stat 2>/dev/null | grep 'underrun\|overflow' || true
        elif command -v aplay >/dev/null 2>&1; then
            aplay -l 2>/dev/null | grep 'card' | head -3 || true
        else
            printf 'pactl/aplay not available\n'
        fi

        printf '\n[memory_pressure]\n'
        awk '
            /^MemTotal:/ { total=$2 }
            /^MemFree:/ { free=$2 }
            /^Buffers:/ { buf=$2 }
            /^Cached:/ { cached=$2 }
            /^SwapTotal:/ { swap_total=$2 }
            /^SwapFree:/ { swap_free=$2 }
            END {
                if (total > 0) {
                    used = total - free - buf - cached
                    used_pct = int(100 * used / total)
                    printf "memory_used_pct: %d%%\n", used_pct
                    printf "swap_used: %d MB\n", (swap_total - swap_free) / 1024
                }
            }
        ' /proc/meminfo 2>/dev/null || true

        printf '\n[kernel_tuning]\n'
        awk '{ printf "vm.swappiness = %s\n", $1 }' /proc/sys/vm/swappiness 2>/dev/null || printf 'vm.swappiness = unknown\n'
        awk '{ printf "dirty_pages = %d KB\n", $1 * 4 }' /proc/sys/vm/nr_dirty 2>/dev/null || true
        awk '{ printf "dirty_bytes = %d\n", $1 }' /proc/sys/vm/dirty_bytes 2>/dev/null || true
        awk '{ printf "vfs_cache_pressure = %s\n", $1 }' /proc/sys/vm/vfs_cache_pressure 2>/dev/null || true

        printf '\n[camera]\n'
        ls /dev/video* 2>/dev/null || printf 'no /dev/video* found\n'

        printf '\n[systemd]\n'
        systemctl is-system-running || true

        printf '\n[networkmanager]\n'
        nmcli device status || true

        printf '\n[wifi]\n'
        iw dev || true

        printf '\n[wifi_link]\n'
        if [ -n "$WIFI_IF" ]; then
            iw dev "$WIFI_IF" link 2>/dev/null \
                | grep -E 'Connected to|SSID:|freq:|signal:|tx bitrate:|rx bitrate:' \
                | sed 's/^\t//' || printf 'not connected\n'
            iw dev "$WIFI_IF" station dump 2>/dev/null \
                | grep -E 'tx retries:|tx failed:|beacon loss:|expected throughput:|connected time:|rx drop misc:' \
                | sed 's/^\t//' || true
            printf 'power_save: %s\n' \
                "$(iw dev "$WIFI_IF" get power_save 2>/dev/null | grep -oE 'on|off' || printf 'unknown')"
            grep -w "$WIFI_IF" /proc/net/dev 2>/dev/null \
                | awk '{printf "if_rx_errors: %s\nif_rx_drop: %s\nif_tx_errors: %s\n", $4,$5,$12}' || true
        else
            printf 'no wifi interface found\n'
        fi

        printf '\n[wifi_metrics]\n'
        if [ -n "$WIFI_IF" ]; then
            local WIFI_LATENCY WIFI_PACKET_LOSS
            IFS='|' read -r WIFI_LATENCY WIFI_PACKET_LOSS <<< "$(get_wifi_ping_metrics)"
            printf 'ping_target: %s\n' "$WIFI_PING_TARGET"
            printf 'latency_ms: %s\n' "${WIFI_LATENCY:-null}"
            printf 'packet_loss_pct: %s\n' "${WIFI_PACKET_LOSS:-null}"
        else
            printf 'ping_target: %s\n' "$WIFI_PING_TARGET"
            printf 'latency_ms: null\n'
            printf 'packet_loss_pct: null\n'
        fi

        printf '\n[wifi_nearby]\n'
        if [ -n "$WIFI_IF" ]; then
            local WIFI_FREQ WIFI_CHANNEL WIFI_NEARBY_RESULT WIFI_NEARBY_JSON WIFI_INTERFERENCE_COUNT WIFI_SCAN_SOURCE
            WIFI_FREQ="$(iw dev "$WIFI_IF" link 2>/dev/null | grep '^	freq:' | grep -oE '[0-9]+' | head -1 || true)"
            WIFI_CHANNEL="$(freq_to_channel "$WIFI_FREQ")"
            WIFI_NEARBY_RESULT="$(get_wifi_nearby_snapshot "$WIFI_IF" "$WIFI_CHANNEL")"
            IFS=$'\t' read -r WIFI_NEARBY_JSON WIFI_INTERFERENCE_COUNT WIFI_SCAN_SOURCE <<< "$WIFI_NEARBY_RESULT"
            printf 'scan_source: %s\n' "${WIFI_SCAN_SOURCE:-none}"
            printf 'channel: %s\n' "${WIFI_CHANNEL:-0}"
            printf 'interference_count: %s\n' "${WIFI_INTERFERENCE_COUNT:-0}"
            printf 'networks_json: %s\n' "${WIFI_NEARBY_JSON:-[]}"
        else
            printf 'scan_source: none\n'
            printf 'channel: 0\n'
            printf 'interference_count: 0\n'
            printf 'networks_json: []\n'
        fi

        printf '\n[rfkill]\n'
        rfkill list || true

        printf '\n[suspend_units]\n'
        systemctl status systemd-suspend.service --no-pager --lines=5 || true

        printf '\n[failed_units]\n'
        systemctl --failed --no-pager || true
    } >> "$SNAPSHOTS_LOG" 2>&1

    flock -u 9
}

journal_loop() {
    log_status "journal watcher started"
    printf '\n=== JOURNAL WATCH START %s ===\n' "$(timestamp)" >> "$EVENTS_LOG"

    local EVENT_BATCH_COUNT=0
    journalctl -f -o short-iso --no-pager 2>&1 |
        stdbuf -oL grep -Ei "$FAILURE_EVENT_REGEX" |
        stdbuf -oL grep -Eiv "$NOISY_EVENT_REGEX" |
        while IFS= read -r LINE; do
            printf '%s\n' "$LINE" >> "$EVENTS_LOG"
            EVENT_BATCH_COUNT=$((EVENT_BATCH_COUNT + 1))

            if [ "$EVENT_BATCH_COUNT" -ge 50 ]; then
                prune_log_file "$EVENTS_LOG" "$MAX_EVENT_LINES"
                EVENT_BATCH_COUNT=0
            fi
        done
}

serve_loop() {
    log_status "http server started on 127.0.0.1:$MBP_WATCH_PORT"
    exec python3 -m http.server "$MBP_WATCH_PORT" --bind 127.0.0.1 --directory "$BASE_DIR" 2>/dev/null
}

watch_children_alive() {
    is_running_pid "$JOURNAL_PID_FILE" && \
    is_running_pid "$SNAPSHOT_PID_FILE" && \
    is_running_pid "$SERVE_PID_FILE"
}

any_watch_child_running() {
    cleanup_stale_pid_file "$JOURNAL_PID_FILE"
    cleanup_stale_pid_file "$SNAPSHOT_PID_FILE"
    cleanup_stale_pid_file "$SERVE_PID_FILE"
    is_running_pid "$JOURNAL_PID_FILE" || \
    is_running_pid "$SNAPSHOT_PID_FILE" || \
    is_running_pid "$SERVE_PID_FILE"
}

launch_watch_children() {
    local DETACHED_MODE="${1:-false}"

    if [ "$DETACHED_MODE" = true ]; then
        nohup "$0" _journal_loop >/dev/null 2>&1 &
    else
        "$0" _journal_loop >/dev/null 2>&1 &
    fi
    echo "$!" > "$JOURNAL_PID_FILE"

    if [ "$DETACHED_MODE" = true ]; then
        nohup "$0" _snapshot_loop >/dev/null 2>&1 &
    else
        "$0" _snapshot_loop >/dev/null 2>&1 &
    fi
    echo "$!" > "$SNAPSHOT_PID_FILE"

    if [ "$DETACHED_MODE" = true ]; then
        nohup "$0" _serve_loop >/dev/null 2>&1 &
    else
        "$0" _serve_loop >/dev/null 2>&1 &
    fi
    echo "$!" > "$SERVE_PID_FILE"
}

capture_initial_report() {
    capture_hardware_inventory || true
    capture_driver_health || true
    capture_snapshot || true
    generate_data_json >/dev/null 2>&1 || true
    log_status "watch started"
}

snapshot_loop() {
    log_status "snapshot loop started interval=${INTERVAL_SECONDS}s"
    local _DH_LAST_CHECK=0
    local _INV_LAST_CHECK=0

    while true; do
        capture_snapshot || true
        prune_log_file "$SNAPSHOTS_LOG" "$MAX_SNAPSHOT_LINES"
        prune_log_file "$EVENTS_LOG"   "$MAX_EVENT_LINES"
        prune_log_file "$STATUS_LOG"   "$MAX_STATUS_LINES"

        local _NOW
        _NOW="$(date +%s)"
        if [ $((_NOW - _DH_LAST_CHECK)) -ge 60 ]; then
            capture_driver_health || true
            _DH_LAST_CHECK="$_NOW"
        fi

        if [ $((_NOW - _INV_LAST_CHECK)) -ge 300 ]; then
            capture_hardware_inventory || true
            _INV_LAST_CHECK="$_NOW"
        fi

        generate_data_json >/dev/null 2>&1 || true
        sleep "$INTERVAL_SECONDS"
    done
}

start_watch() {
    local START_COMPLETED=false

    if any_watch_child_running; then
        echo "mbp-watch already running in $BASE_DIR"
        exit 1
    fi

    trap 'stop_watch >/dev/null 2>&1 || true' INT TERM HUP
    trap '[ "$START_COMPLETED" = true ] || stop_watch >/dev/null 2>&1 || true' EXIT

    launch_watch_children true
    capture_initial_report
    START_COMPLETED=true

    trap - INT TERM HUP EXIT

    echo "mbp-watch started"
    echo "state dir : $BASE_DIR"
    echo "open      : http://localhost:$MBP_WATCH_PORT/report.html"
    echo "ai digest : $REPORT_TEXT"
}

run_watch() {
    local STOP_REQUESTED=false

    if any_watch_child_running; then
        echo "mbp-watch already running in $BASE_DIR"
        exit 1
    fi

    trap 'STOP_REQUESTED=true; stop_watch >/dev/null 2>&1 || true' INT TERM HUP
    trap 'stop_watch >/dev/null 2>&1 || true' EXIT

    launch_watch_children false
    capture_initial_report

    while true; do
        if watch_children_alive; then
            sleep 2
            continue
        fi

        if [ "$STOP_REQUESTED" = true ]; then
            exit 0
        fi

        stop_watch >/dev/null 2>&1 || true
        exit 1
    done
}

stop_watch() {
    local STOPPED=false

    if is_running_pid "$JOURNAL_PID_FILE"; then
        kill "$(< "$JOURNAL_PID_FILE")" 2>/dev/null || true
        STOPPED=true
    fi

    if is_running_pid "$SNAPSHOT_PID_FILE"; then
        kill "$(< "$SNAPSHOT_PID_FILE")" 2>/dev/null || true
        STOPPED=true
    fi

    if is_running_pid "$SERVE_PID_FILE"; then
        kill "$(< "$SERVE_PID_FILE")" 2>/dev/null || true
        STOPPED=true
    fi

    rm -f "$JOURNAL_PID_FILE" "$SNAPSHOT_PID_FILE" "$SERVE_PID_FILE"
    log_status "watch stopped"

    if [ "$STOPPED" = true ]; then
        echo "mbp-watch stopped"
    else
        echo "mbp-watch was not running"
    fi
}

status_watch() {
    printf 'state dir     : %s\n' "$BASE_DIR"

    if is_running_pid "$JOURNAL_PID_FILE"; then
        printf 'journal watcher: running (pid %s)\n' "$(< "$JOURNAL_PID_FILE")"
    else
        printf 'journal watcher: stopped\n'
    fi

    if is_running_pid "$SNAPSHOT_PID_FILE"; then
        printf 'snapshot loop  : running (pid %s)\n' "$(< "$SNAPSHOT_PID_FILE")"
    else
        printf 'snapshot loop  : stopped\n'
    fi

    if is_running_pid "$SERVE_PID_FILE"; then
        printf 'http server    : running (pid %s) → http://localhost:%s/report.html\n' \
            "$(< "$SERVE_PID_FILE")" "$MBP_WATCH_PORT"
    else
        printf 'http server    : stopped\n'
    fi

    printf 'events log     : %s\n' "$EVENTS_LOG"
    printf 'snapshots log  : %s\n' "$SNAPSHOTS_LOG"
    printf 'inventory log  : %s\n' "$INVENTORY_LOG"
    printf 'daily errors   : %s\n' "$DAILY_LOG"
    printf 'report         : %s\n' "$REPORT_HTML"
    printf 'ai digest      : %s\n' "$REPORT_TEXT"
}

keyword_count() {
    local REGEX="$1"
    local INPUT=""

    if [ -f "$EVENTS_LOG" ]; then
        INPUT="$(grep -Ev "^=== JOURNAL WATCH" "$EVENTS_LOG" 2>/dev/null | tail -n "$COUNT_WINDOW_LINES" || true)"
        if [ -n "$INPUT" ]; then
            printf '%s' "$(
                printf '%s\n' "$INPUT" |
                    grep -Ev "$NOISY_EVENT_REGEX" |
                    grep -Eic "$REGEX" || true
            )"
            return 0
        fi
    fi

    printf '0'
}

json_str() {
    printf '%s' "${1:-}" \
        | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g' \
        | tr -d '\000-\037'
}

epoch_now() {
    date +%s
}

freq_to_channel() {
    local FREQ="${1:-0}"
    FREQ="${FREQ%.*}"

    if [[ "$FREQ" =~ ^[0-9]+$ ]]; then
        if (( FREQ >= 2412 && FREQ <= 2484 )); then
            printf '%s\n' $(( (FREQ - 2407) / 5 ))
            return 0
        fi
        if (( FREQ >= 5000 && FREQ <= 6000 )); then
            printf '%s\n' $(( (FREQ - 5000) / 5 ))
            return 0
        fi
    fi

    printf '0\n'
}

get_wifi_ping_metrics() {
    local LATENCY="null"
    local LOSS="null"
    local PING_OUTPUT=""

    if command -v ping >/dev/null 2>&1; then
        PING_OUTPUT="$(ping -c 3 -W 1 "$WIFI_PING_TARGET" 2>/dev/null || true)"
        LATENCY="$(printf '%s\n' "$PING_OUTPUT" | awk -F'=' '/min\/avg\/max|round-trip/ {gsub(/^[[:space:]]+/, "", $2); split($2, stats, "/"); print stats[2]; exit}')"
        LOSS="$(printf '%s\n' "$PING_OUTPUT" | awk -F',' '/packet loss/ {gsub(/^[[:space:]]+/, "", $3); gsub(/% packet loss/, "", $3); print $3; exit}')"
    fi

    [ -n "$LATENCY" ] || LATENCY="null"
    [ -n "$LOSS" ] || LOSS="null"
    printf '%s|%s\n' "$LATENCY" "$LOSS"
}

build_wifi_nearby_networks_json() {
    local WIFI_IF="${1:-}"
    local CURRENT_CHANNEL="${2:-0}"
    local NETWORKS_JSON="[]"
    local SAME_CHANNEL_COUNT=0
    local SCAN_SOURCE="none"

    [ -n "$WIFI_IF" ] || {
        printf '%s\t%s\t%s\n' "$NETWORKS_JSON" "$SAME_CHANNEL_COUNT" "$SCAN_SOURCE"
        return 0
    }

    if command -v iw >/dev/null 2>&1; then
        local SCAN_OUTPUT
        local NETWORKS=()
        local CURRENT_SSID=""
        local CURRENT_SIGNAL=""
        local CURRENT_FREQ=""

        SCAN_OUTPUT="$(iw dev "$WIFI_IF" scan 2>/dev/null || true)"
        if [ -n "$SCAN_OUTPUT" ]; then
            while IFS= read -r LINE; do
                LINE="${LINE#"${LINE%%[![:space:]]*}"}"

                if [[ "$LINE" =~ ^SSID:\ (.*)$ ]]; then
                    CURRENT_SSID="${BASH_REMATCH[1]}"
                    [ -n "$CURRENT_SSID" ] || CURRENT_SSID="(hidden)"
                elif [[ "$LINE" =~ ^signal:\ (-[0-9.]+) ]]; then
                    CURRENT_SIGNAL="$(printf '%s' "${BASH_REMATCH[1]}" | cut -d. -f1)"
                elif [[ "$LINE" =~ ^freq:\ ([0-9.]+)$ ]]; then
                    local CHANNEL
                    local SAME_CHANNEL="false"

                    CURRENT_FREQ="${BASH_REMATCH[1]}"
                    if [ -n "$CURRENT_SSID" ] && [ -n "$CURRENT_SIGNAL" ]; then
                        CHANNEL="$(freq_to_channel "$CURRENT_FREQ")"
                        if [ "$CHANNEL" = "$CURRENT_CHANNEL" ] && [ "$CHANNEL" != "0" ]; then
                            SAME_CHANNEL="true"
                            SAME_CHANNEL_COUNT=$((SAME_CHANNEL_COUNT + 1))
                        fi
                        NETWORKS+=("{\"ssid\":\"$(json_str "$CURRENT_SSID")\",\"signal_dbm\":${CURRENT_SIGNAL:-0},\"channel\":${CHANNEL:-0},\"same_channel\":${SAME_CHANNEL}}")
                    fi

                    CURRENT_SSID=""
                    CURRENT_SIGNAL=""
                    CURRENT_FREQ=""
                fi
            done <<< "$SCAN_OUTPUT"

            if [ "${#NETWORKS[@]}" -gt 0 ]; then
                NETWORKS_JSON="[$(IFS=,; echo "${NETWORKS[*]}")]"
            fi
            SCAN_SOURCE="iw"
        fi
    fi

    if [ "$SCAN_SOURCE" = "none" ] && command -v iwctl >/dev/null 2>&1; then
        local SCAN_OUTPUT
        local NETWORKS=()

        iwctl station "$WIFI_IF" scan 2>/dev/null || true
        SCAN_OUTPUT="$(iwctl station "$WIFI_IF" get-networks 2>/dev/null || true)"
        if [ -n "$SCAN_OUTPUT" ]; then
            while IFS= read -r LINE; do
                local SSID STRENGTH SIGNAL_DBM

                LINE="${LINE#"${LINE%%[![:space:]]*}"}"
                [ -n "$LINE" ] || continue

                SSID="$(printf '%s\n' "$LINE" | awk '{print $1}')"
                STRENGTH="$(printf '%s\n' "$LINE" | grep -oE '[0-9]+%' | tr -d '%' | head -1 || true)"
                if [ -n "$SSID" ] && [ "$SSID" != "SSID" ] && [ -n "$STRENGTH" ]; then
                    SIGNAL_DBM=$(( STRENGTH / 2 - 100 ))
                    NETWORKS+=("{\"ssid\":\"$(json_str "$SSID")\",\"signal_dbm\":${SIGNAL_DBM},\"channel\":0,\"same_channel\":false}")
                fi
            done <<< "$SCAN_OUTPUT"

            if [ "${#NETWORKS[@]}" -gt 0 ]; then
                NETWORKS_JSON="[$(IFS=,; echo "${NETWORKS[*]}")]"
            fi
            SCAN_SOURCE="iwctl"
        fi
    fi

    printf '%s\t%s\t%s\n' "$NETWORKS_JSON" "$SAME_CHANNEL_COUNT" "$SCAN_SOURCE"
}

cache_get_value() {
    local KEY="$1"
    local FILE_PATH="$2"

    [ -f "$FILE_PATH" ] || return 0
    sed -n "s/^${KEY}=//p" "$FILE_PATH" | head -1
}

get_wifi_nearby_snapshot() {
    local WIFI_IF="${1:-}"
    local CURRENT_CHANNEL="${2:-0}"
    local CURRENT_TS CACHE_TS CACHE_AGE RESULT_JSON RESULT_COUNT RESULT_SOURCE

    CURRENT_TS="$(epoch_now)"
    CACHE_TS="$(cache_get_value timestamp "$WIFI_SCAN_CACHE_FILE")"
    CACHE_AGE=$(( CURRENT_TS - ${CACHE_TS:-0} ))

    if [ ! -f "$WIFI_SCAN_CACHE_FILE" ] || [ "$CACHE_AGE" -ge "$WIFI_SCAN_CACHE_TTL" ]; then
        local RESULT TMP_FILE

        RESULT="$(build_wifi_nearby_networks_json "$WIFI_IF" "$CURRENT_CHANNEL")"
        IFS=$'\t' read -r RESULT_JSON RESULT_COUNT RESULT_SOURCE <<< "$RESULT"

        TMP_FILE="$(mktemp "${BASE_DIR}/wifi-scan.XXXXXX")"
        {
            printf 'timestamp=%s\n' "$CURRENT_TS"
            printf 'source=%s\n' "${RESULT_SOURCE:-none}"
            printf 'interference_count=%s\n' "${RESULT_COUNT:-0}"
            printf 'networks_json=%s\n' "${RESULT_JSON:-[]}"
        } > "$TMP_FILE"
        mv "$TMP_FILE" "$WIFI_SCAN_CACHE_FILE"
        chmod 644 "$WIFI_SCAN_CACHE_FILE"
    fi

    RESULT_JSON="$(cache_get_value networks_json "$WIFI_SCAN_CACHE_FILE")"
    RESULT_COUNT="$(cache_get_value interference_count "$WIFI_SCAN_CACHE_FILE")"
    RESULT_SOURCE="$(cache_get_value source "$WIFI_SCAN_CACHE_FILE")"

    printf '%s\t%s\t%s\n' "${RESULT_JSON:-[]}" "${RESULT_COUNT:-0}" "${RESULT_SOURCE:-none}"
}

get_cpu_perf_field() {
    local FIELD="$1"

    [ -f "$SNAPSHOTS_LOG" ] || return 0

    awk -v field="$FIELD" '
        /^\[cpu_perf\]$/ { in_sect=1; next }
        in_sect && /^\[/ { exit }
        in_sect && $0 ~ "^"field": " {
            sub("^"field": ", "")
            print
            exit
        }
    ' "$SNAPSHOTS_LOG"
}

recent_suspend_resume_context() {
    local WINDOW_MINUTES="${1:-$RESUME_CONTEXT_WINDOW_MINUTES}"
    local JOURNAL_SLICE=""

    JOURNAL_SLICE="$(
        journalctl -b --since "${WINDOW_MINUTES} minutes ago" -o short-iso --no-pager 2>/dev/null \
            | tail -n 200 || true
    )"

    [ -n "$JOURNAL_SLICE" ] || return 1

    printf '%s\n' "$JOURNAL_SLICE" | grep -Eiq \
        'systemd-sleep|PM: (suspend|resume)|suspend.*resume|resume from suspend|system is (suspending|sleeping|resuming)|Lid (Switch|Open|Close)'
}

current_wifi_link_is_up() {
    local WLAN_IF
    local WIFI_LINK_STATE

    WLAN_IF="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}' || true)"
    [ -n "$WLAN_IF" ] || return 1

    WIFI_LINK_STATE="$(iw dev "$WLAN_IF" link 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g' || true)"
    printf '%s\n' "$WIFI_LINK_STATE" | grep -Eq 'Connected to|SSID:'
}

current_wifi_is_connected() {
    if command -v nmcli >/dev/null 2>&1; then
        nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null \
            | awk -F: '$2 == "wifi" && $3 == "connected" { found = 1 } END { exit(found ? 0 : 1) }'
        return $?
    fi

    current_wifi_link_is_up
}

compact_recent_events() {
    local MAX_LINES="${1:-10}"

    [ -f "$EVENTS_LOG" ] || return 0

    grep -Ev "^=== JOURNAL WATCH" "$EVENTS_LOG" 2>/dev/null |
        tail -n "$COUNT_WINDOW_LINES" |
        grep -Ev "$NOISY_EVENT_REGEX" |
        awk '!seen[$0]++' |
        tail -n "$MAX_LINES"
}

compact_last_snapshot() {
    [ -f "$SNAPSHOTS_LOG" ] || return 0

    awk '
        /^=== SNAPSHOT / {
            block = $0 ORS
            seen = 1
            next
        }
        seen {
            block = block $0 ORS
        }
        END {
            if (seen) {
                printf "%s", block
            }
        }
    ' "$SNAPSHOTS_LOG" |
        awk '
            /^=== SNAPSHOT / {
                section = ""
                lines = 0
                print
                next
            }
            /^\[[^]]+\]$/ {
                section = $0
                lines = 0
                print
                next
            }
            section != "" && NF > 0 && lines < 3 {
                print
                lines++
            }
        '
}

# Extracts content of a named section from the last snapshot block.
get_last_snapshot_section() {
    local SECTION="$1"

    [ -f "$SNAPSHOTS_LOG" ] || return 0

    awk -v sect="[$SECTION]" '
        /^=== SNAPSHOT / {
            delete lines
            n = 0
        }
        { n++; lines[n] = $0 }
        END {
            in_sect = 0
            for (i = 1; i <= n; i++) {
                if (lines[i] == sect) { in_sect = 1; continue }
                if (in_sect && lines[i] ~ /^\[[^\]]+\]$/) { in_sect = 0 }
                if (in_sect && length(lines[i]) > 0) print lines[i]
            }
        }
    ' "$SNAPSHOTS_LOG"
}

# Counts events in events.log matching REGEX that start with DATE (YYYY-MM-DD).
# Uses date-prefix grep because journalctl short-iso lines start with the timestamp.
keyword_count_for_date() {
    local DATE="$1"
    local REGEX="$2"

    [ -f "$EVENTS_LOG" ] || { printf '0'; return 0; }

    awk -v date_prefix="$DATE" -v regex="$REGEX" '
        index($0, date_prefix) == 1 && $0 ~ regex { count++ }
        END { print count + 0 }
    ' "$EVENTS_LOG" 2>/dev/null || printf '0'
}

# Writes or updates today's line in daily_errors.log.
# Called from generate_report every cycle; only rewrites today's entry.
# The file accumulates one line per day and is never truncated — it is the
# persistent historical record for multi-day AI analysis.
update_daily_summary() {
    local TODAY
    local W N E G B T P A TH TOT
    local NEW_LINE TMP_FILE

    TODAY="$(date +%Y-%m-%d)"

    W="$(keyword_count_for_date "$TODAY" 'brcmf|wpa_supplicant|iwlwifi|mt76|ath|rtl|rtw')"
    N="$(keyword_count_for_date "$TODAY" 'dhcp4 \(wlan[0-9]\).*(failed|timeout|no lease)|device \(wlan[0-9]\).*Activation: failed|wpa_supplicant.*(fail|error|timeout)')"
    E="$(keyword_count_for_date "$TODAY" 'dhcp4 \(en[a-z0-9]+\).*(no lease|timeout|failed)|device \(en[a-z0-9]+\).*Activation: failed|device \(en[a-z0-9]+\).*carrier')"
    G="$(keyword_count_for_date "$TODAY" 'gpu|drm|i915')"
    B="$(keyword_count_for_date "$TODAY" 'bluetoothd|bluetooth')"
    T="$(keyword_count_for_date "$TODAY" 'thermal|acpi')"
    P="$(keyword_count_for_date "$TODAY" 'PM:|s2idle')"
    A="$(keyword_count_for_date "$TODAY" 'snd_hda|applesmc|thunderbolt')"
    TH="$(keyword_count_for_date "$TODAY" 'cpu.*throttl|thermal.*throttl')"
    TOT=$((W + N + E + G + B + T + P + A + TH))

    NEW_LINE="$TODAY wifi=$W net=$N eth=$E gpu=$G bt=$B thermal=$T pm=$P audio=$A throttle=$TH total=$TOT"

    touch "$DAILY_LOG"
    chmod 644 "$DAILY_LOG"
    TMP_FILE="$(mktemp "${DAILY_LOG}.XXXXXX")"
    grep -v "^$TODAY " "$DAILY_LOG" > "$TMP_FILE" 2>/dev/null || true
    printf '%s\n' "$NEW_LINE" >> "$TMP_FILE"
    sort "$TMP_FILE" -o "$TMP_FILE"
    mv "$TMP_FILE" "$DAILY_LOG"
    chmod 644 "$DAILY_LOG"
}

generate_ai_digest() {
    local WIFI_COUNT NET_COUNT GPU_COUNT BT_COUNT THERMAL_COUNT PM_COUNT AUDIO_HW_COUNT THROTTLE_COUNT TOTAL_COUNT
    local SEVERITY_CLASS SEVERITY_TITLE SEVERITY_REASON
    local INV_TS INV_CPU INV_MODEL INV_KERNEL INV_GPU INV_WIFI INV_WIFI_FW INV_BT INV_AUDIO INV_CAMERA
    local SNAP_SYSTEMD SNAP_MEMORY SNAP_TEMPS SNAP_BATTERY SNAP_NM SNAP_RFKILL SNAP_FAILED SNAP_WIFI_LINK
    local RECENT_ERRORS
    local PERF_ISSUE=""

    WIFI_COUNT="$(keyword_count 'brcmf|wpa_supplicant|iwlwifi|mt76|ath|rtl|rtw')"
    NET_COUNT="$(keyword_count 'dhcp4 \(wlan[0-9]\).*(failed|timeout|no lease)|device \(wlan[0-9]\).*Activation: failed|wpa_supplicant.*(fail|error|timeout)')"
    ETH_COUNT="$(keyword_count 'dhcp4 \(en[a-z0-9]+\).*(no lease|timeout|failed)|device \(en[a-z0-9]+\).*Activation: failed|device \(en[a-z0-9]+\).*carrier')"
    GPU_COUNT="$(keyword_count 'gpu|drm|i915')"
    BT_COUNT="$(keyword_count 'bluetoothd|bluetooth')"
    THERMAL_COUNT="$(keyword_count 'thermal|acpi')"
    PM_COUNT="$(keyword_count 'PM:|s2idle')"
    AUDIO_HW_COUNT="$(keyword_count 'snd_hda|applesmc|thunderbolt')"
    THROTTLE_COUNT="$(keyword_count 'cpu.*throttl|thermal.*throttl')"

    # Check performance issues from latest snapshot
    local load1="$(get_last_snapshot_section 'load_and_processes' | grep '^load_average:' | sed 's/.*: //' | awk '{print $1}' | tr ',' '.' || echo '0')"
    local swap_mb="$(get_last_snapshot_section 'memory_pressure' | grep '^swap_used:' | awk '{print $NF}' | grep -oE '^[0-9]{1,4}' || echo '0')"
    local mem_pct="$(get_last_snapshot_section 'memory_pressure' | grep '^memory_used_pct:' | awk '{print $NF}' | grep -oE '[0-9]{1,3}' || echo '0')"
    # Context switches: skip if huge (system uptime counter), show nothing instead
    local ctx_raw="$(get_last_snapshot_section 'load_and_processes' | grep '^context_switches:' | awk '{print $NF}' || echo '0')"
    local ctx_switches=""
    if [ "$ctx_raw" -lt 100000 ] 2>/dev/null; then
        ctx_switches="$ctx_raw"
    fi

    if { [ "$WIFI_COUNT" -gt 0 ] || [ "$NET_COUNT" -gt 0 ]; } && \
        recent_suspend_resume_context && current_wifi_link_is_up; then
        WIFI_COUNT=0
        NET_COUNT=0
    fi

    TOTAL_COUNT=$((WIFI_COUNT + NET_COUNT + ETH_COUNT + GPU_COUNT + BT_COUNT + THERMAL_COUNT + PM_COUNT + AUDIO_HW_COUNT + THROTTLE_COUNT))

    # Assess performance-related issues
    if [ "$swap_mb" -gt 256 ]; then
        PERF_ISSUE="${PERF_ISSUE}swap_overuse=${swap_mb}MB "
    fi
    if (( $(echo "$load1 > 3" | bc 2>/dev/null || echo 0) )); then
        PERF_ISSUE="${PERF_ISSUE}high_load=${load1} "
    fi
    if [ "$ctx_switches" -gt 30000 ]; then
        PERF_ISSUE="${PERF_ISSUE}ctx_thrashing "
    fi

    SEVERITY_CLASS="ok"
    SEVERITY_TITLE="Stable"
    SEVERITY_REASON="No hardware errors and performance metrics healthy."

    if [ "$TOTAL_COUNT" -gt 0 ] || [ -n "$PERF_ISSUE" ]; then
        SEVERITY_CLASS="warn"
        SEVERITY_TITLE="Warnings Found"
        SEVERITY_REASON="${TOTAL_COUNT} hw_events — wifi=${WIFI_COUNT} net=${NET_COUNT} eth=${ETH_COUNT} gpu=${GPU_COUNT} bt=${BT_COUNT} thermal=${THERMAL_COUNT} pm=${PM_COUNT} audio=${AUDIO_HW_COUNT} throttle=${THROTTLE_COUNT}${PERF_ISSUE:+ | perf_issues=$PERF_ISSUE}"
    fi

    if [ "$WIFI_COUNT" -ge 3 ] || [ "$NET_COUNT" -ge 3 ] || [ "$ETH_COUNT" -ge 10 ] || \
       [ "$GPU_COUNT" -ge 3 ] || [ "$PM_COUNT" -ge 2 ] || [ "$AUDIO_HW_COUNT" -ge 3 ] || \
       [ "$BT_COUNT" -ge 5 ] || [ "$THERMAL_COUNT" -ge 5 ] || [ "$THROTTLE_COUNT" -ge 3 ] || \
       [ "$swap_mb" -gt 512 ] || (( $(echo "$load1 > 4" | bc 2>/dev/null || echo 0) )); then
        SEVERITY_CLASS="critical"
        SEVERITY_TITLE="Critical Issues Detected"
        local REASONS=""
        [ "$WIFI_COUNT" -ge 3 ]     && REASONS="${REASONS}wifi=${WIFI_COUNT} "
        [ "$NET_COUNT" -ge 3 ]      && REASONS="${REASONS}connectivity=${NET_COUNT} "
        [ "$ETH_COUNT" -ge 10 ]     && REASONS="${REASONS}eth=${ETH_COUNT} "
        [ "$GPU_COUNT" -ge 3 ]      && REASONS="${REASONS}gpu=${GPU_COUNT} "
        [ "$PM_COUNT" -ge 2 ]       && REASONS="${REASONS}suspend_pm=${PM_COUNT} "
        [ "$AUDIO_HW_COUNT" -ge 3 ] && REASONS="${REASONS}audio_hw=${AUDIO_HW_COUNT} "
        [ "$BT_COUNT" -ge 5 ]       && REASONS="${REASONS}bluetooth=${BT_COUNT} "
        [ "$THERMAL_COUNT" -ge 5 ]  && REASONS="${REASONS}thermal=${THERMAL_COUNT} "
        [ "$THROTTLE_COUNT" -ge 3 ] && REASONS="${REASONS}throttling=${THROTTLE_COUNT} "
        [ "$swap_mb" -gt 512 ]      && REASONS="${REASONS}swap_critical=${swap_mb}MB "
        (( $(echo "$load1 > 4" | bc 2>/dev/null || echo 0) )) && REASONS="${REASONS}cpu_overload=${load1} "
        SEVERITY_REASON="${REASONS% }"
    fi

    INV_TS="$(head -1 "$INVENTORY_LOG" 2>/dev/null | grep -oE '[0-9]{4}-[^ ]+' || printf 'unknown')"
    _inv() {
        awk -v s="[$1]" '/^\[/{f=0} $0==s{f=1;next} f && NF{print;exit}' "$INVENTORY_LOG" 2>/dev/null || printf 'unknown'
    }
    INV_CPU="$(_inv cpu)"
    INV_MODEL="$(_inv apple_model)"
    INV_KERNEL="$(_inv kernel)"
    INV_GPU="$(_inv gpu)"
    INV_WIFI="$(_inv wifi_chip)"
    INV_WIFI_FW="$(_inv wifi_firmware)"
    INV_BT="$(_inv bluetooth_chip)"
    INV_AUDIO="$(_inv audio_card)"
    INV_CAMERA="$(_inv camera)"

    SNAP_SYSTEMD="$(get_last_snapshot_section 'systemd' | head -1 || true)"
    SNAP_MEMORY="$(get_last_snapshot_section 'memory' | grep 'Mem:' | head -1 || true)"
    # Temperature: extract just the important parts
    SNAP_TEMPS="$(get_last_snapshot_section 'temperature_fans' | awk '/fan speed:|Package id|^Core [01]:/ {print}' | head -3 | tr '\n' ';' | sed 's/;$//' || true)"
    # Battery: extract state + percentage + energy in readable format
    local bat_state="$(get_last_snapshot_section 'battery' | grep '^[[:space:]]*state:' | sed 's/.*state:[[:space:]]*//' | sed 's/[;$].*//' | head -1 || echo 'unknown')"
    local bat_pct="$(get_last_snapshot_section 'battery' | grep 'percentage:' | sed 's/.*percentage:[[:space:]]*//' | sed 's/[;$].*//' | head -1 || echo 'N/A')"
    local bat_energy="$(get_last_snapshot_section 'battery' | grep 'energy:' | sed 's/.*energy:[[:space:]]*//' | sed 's/[;$].*//' | head -1 || echo 'N/A')"
    SNAP_BATTERY="$bat_state | $bat_pct | $bat_energy"
    SNAP_NM="$(get_last_snapshot_section 'networkmanager' | grep -v 'DEVICE\|^$\|^--' | head -1 || true)"
    SNAP_FAILED="$(get_last_snapshot_section 'failed_units' | grep -v 'No failed\|UNIT\|^$\|^0 loaded' | head -2 || true)"
    [ -z "$SNAP_FAILED" ] && SNAP_FAILED="none"
    # WiFi link: get the full line
    SNAP_WIFI_LINK="$(get_last_snapshot_section 'wifi_link' | head -1 || echo 'not connected')"

    RECENT_ERRORS="$(compact_recent_events 10)"

    cat > "$REPORT_TEXT" <<EOF
MBP-WATCH AI DIGEST
generated:      $(timestamp)
state_dir:      $BASE_DIR

SEVERITY
status:         $SEVERITY_CLASS
title:          $SEVERITY_TITLE
reason:         $SEVERITY_REASON

COUNTERS (last $COUNT_WINDOW_LINES journal events)
wifi:           $WIFI_COUNT
connectivity:   $NET_COUNT
eth:            $ETH_COUNT
gpu_drm:        $GPU_COUNT
bluetooth:      $BT_COUNT
thermal_acpi:   $THERMAL_COUNT
suspend_pm:     $PM_COUNT
audio_hw:       $AUDIO_HW_COUNT
throttle:       $THROTTLE_COUNT
TOTAL:          $TOTAL_COUNT

DRIVER HEALTH
$([ -f "$DRIVER_HEALTH_LOG" ] && grep -v '^===' "$DRIVER_HEALTH_LOG" | grep '|' \
    | awk -F'|' '{printf "%-14s %-6s %s\n", $1":", $2, $3; if ($4 != "") printf "               fix: %s\n", $4}' \
    || printf 'not captured yet')

HARDWARE (inventory: $INV_TS)
cpu:            ${INV_CPU:-unknown}
apple_model:    ${INV_MODEL:-unknown}
kernel:         ${INV_KERNEL:-unknown}
gpu:            ${INV_GPU:-unknown}
wifi_chip:      ${INV_WIFI:-unknown}
bluetooth:      ${INV_BT:-unknown}

SYSTEM (last snapshot)
systemd:        ${SNAP_SYSTEMD:-unknown}
memory:         ${SNAP_MEMORY:-unknown}
temperature:    ${SNAP_TEMPS:-unknown}
battery:        ${SNAP_BATTERY:-unknown}
network:        ${SNAP_NM:-unknown}
failed_units:   ${SNAP_FAILED:-none}

WIFI LINK
${SNAP_WIFI_LINK:-not connected}

HISTORY (daily errors — last 3 days)
$(tail -3 "$DAILY_LOG" 2>/dev/null | sed 's/ *$//' | grep -v '^$' || printf 'no history yet')

RECENT ERRORS (unique events, last $COUNT_WINDOW_LINES window)
${RECENT_ERRORS:-none captured}

PERFORMANCE_ANALYSIS (Python/web dev + music)
$(
    # Simple, robust extraction
    local load_line="$(get_last_snapshot_section 'load_and_processes' | grep '^load_average:' | head -1)"
    local mem_line="$(get_last_snapshot_section 'memory_pressure' | grep '^memory_used_pct:' | head -1)"
    local swap_line="$(get_last_snapshot_section 'memory_pressure' | grep '^swap_used:' | head -1)"
    local swap_val="$(echo "$swap_line" | awk '{print $NF}' | sed 's/MB//')"
    local mem_val="$(echo "$mem_line" | awk '{print $NF}' | sed 's/%//')"
    local load_val="$(echo "$load_line" | sed 's/.*: //' | awk '{print $1}' | tr ',' '.')"
    local swap_num=$([ -n "$swap_val" ] && [ "$swap_val" -eq "$swap_val" ] 2>/dev/null && echo "$swap_val" || echo "0")
    local mem_num=$([ -n "$mem_val" ] && [ "$mem_val" -eq "$mem_val" ] 2>/dev/null && echo "$mem_val" || echo "0")

    # Swappiness: safe extraction
    local swapp_line="$(get_last_snapshot_section 'kernel_tuning' | grep '^vm.swappiness' | head -1)"
    local swapp_val="$(echo "$swapp_line" | grep -oE '[0-9]+' | tail -1)"
    local swapp_num=$([ -n "$swapp_val" ] && [ "$swapp_val" -le 100 ] 2>/dev/null && echo "$swapp_val" || echo "60")

    # Top process: just the command name
    local top_proc="$(get_last_snapshot_section 'top_cpu_processes' | grep -v '^USER' | head -1 | awk '{print $NF " (" $1 ")"}')"

    # Output only valid metrics (clean load_val of any trailing dots)
    if [ -n "$load_val" ] && [ "$load_val" != "0" ]; then
        load_clean=$(echo "$load_val" | sed 's/\.$//')  # Remove trailing dot if present
        echo "load: $load_clean | memory: ${mem_num}% | swap: ${swap_num}MB | swappiness: $swapp_num"
    fi

    [ -n "$top_proc" ] && echo "top_process: $top_proc"

    # Alerts only if threshold exceeded
    [ "$swap_num" -gt 256 ] 2>/dev/null && echo "⚠️  SWAP CRITICAL (${swap_num}MB) — reduce swappiness to 10"
    [ "$mem_num" -gt 90 ] 2>/dev/null && echo "⚠️  MEMORY CRITICAL (${mem_num}%) — close Firefox tabs"
)

RAW_LOGS
events.log:     $EVENTS_LOG
snapshots.log:  $SNAPSHOTS_LOG
inventory.log:  $INVENTORY_LOG
daily_errors:   $DAILY_LOG
EOF

    log_status "ai digest generated at $REPORT_TEXT"
}

generate_data_json() {
    local WIFI_COUNT NET_COUNT GPU_COUNT BT_COUNT THERMAL_COUNT PM_COUNT AUDIO_HW_COUNT THROTTLE_COUNT TOTAL_COUNT
    local SEVERITY_CLASS SEVERITY_TITLE SEVERITY_TEXT SEVERITY_REASON
    local DH_JSON DH_CAPTURED
    local SNAP_SYSTEMD SNAP_FAILED
    local SNAP_SSID SNAP_SIGNAL_DBM SNAP_FREQ_MHZ SNAP_TX_MBPS SNAP_RX_MBPS SNAP_TX_RETRIES SNAP_POWER_SAVE SNAP_WIFI_CONNECTED
    local SNAP_WIFI_LATENCY SNAP_WIFI_PACKET_LOSS SNAP_WIFI_PING_TARGET SNAP_WIFI_NEARBY_JSON SNAP_WIFI_SCAN_SOURCE SNAP_WIFI_INTERFERENCE_COUNT SNAP_WIFI_CHANNEL
    local SNAP_BAT_PCT SNAP_BAT_STATE SNAP_BAT_TTE SNAP_BAT_CAPACITY SNAP_BAT_ENERGY
    local SNAP_CPU_FREQS SNAP_CPU_MAX SNAP_CPU_GOV SNAP_CPU_THROTTLE SNAP_CPU_USAGES SNAP_CPU_THERMAL_ALARM SNAP_CPU_PROCHOT SNAP_CPU_BASE_FREQ
    local SNAP_MEM_TOTAL SNAP_MEM_USED SNAP_MEM_AVAIL SNAP_SWAP_USED SNAP_LOAD_AVG SNAP_CTX_SWITCHES
    local SNAP_TOP_CPU SNAP_TOP_MEM SNAP_SWAP_USED_MB SNAP_SWAPPINESS
    local TEMPS_JSON TEMPS_ENTRIES FAN_RPM
    local DAILY_JSON DAILY_ENTRIES
    local EVENTS_JSON EV_ENTRIES
    local INV_CPU INV_MODEL INV_KERNEL INV_GPU INV_WIFI INV_WIFI_FW INV_BT INV_AUDIO INV_CAMERA INV_TS
    local TMP_JSON

    update_daily_summary

    WIFI_COUNT="$(keyword_count 'brcmf|wpa_supplicant|iwlwifi|mt76|ath|rtl|rtw')"
    NET_COUNT="$(keyword_count 'dhcp4 \(wlan[0-9]\).*(failed|timeout|no lease)|device \(wlan[0-9]\).*Activation: failed|wpa_supplicant.*(fail|error|timeout)')"
    ETH_COUNT="$(keyword_count 'dhcp4 \(en[a-z0-9]+\).*(no lease|timeout|failed)|device \(en[a-z0-9]+\).*Activation: failed|device \(en[a-z0-9]+\).*carrier')"
    GPU_COUNT="$(keyword_count 'gpu|drm|i915')"
    BT_COUNT="$(keyword_count 'bluetoothd|bluetooth')"
    THERMAL_COUNT="$(keyword_count 'thermal|acpi')"
    PM_COUNT="$(keyword_count 'PM:|s2idle')"
    AUDIO_HW_COUNT="$(keyword_count 'snd_hda|applesmc|thunderbolt')"
    THROTTLE_COUNT="$(keyword_count 'cpu.*throttl|thermal.*throttl')"

    if { [ "$WIFI_COUNT" -gt 0 ] || [ "$NET_COUNT" -gt 0 ]; } && \
        recent_suspend_resume_context && current_wifi_link_is_up; then
        WIFI_COUNT=0
        NET_COUNT=0
    fi

    TOTAL_COUNT=$((WIFI_COUNT + NET_COUNT + ETH_COUNT + GPU_COUNT + BT_COUNT + THERMAL_COUNT + PM_COUNT + AUDIO_HW_COUNT + THROTTLE_COUNT))
    SEVERITY_CLASS="ok"
    SEVERITY_TITLE="Stable"
    SEVERITY_TEXT="No hardware errors detected in the last ${COUNT_WINDOW_LINES} journal events."
    SEVERITY_REASON="No matched problems detected yet."

    if [ "$TOTAL_COUNT" -gt 0 ]; then
        SEVERITY_CLASS="warn"
        SEVERITY_TITLE="Warnings Found"
        SEVERITY_TEXT="Matched events detected. Review the recent events section."
        SEVERITY_REASON="${TOTAL_COUNT} matched event(s) — wifi=${WIFI_COUNT} net=${NET_COUNT} eth=${ETH_COUNT} gpu=${GPU_COUNT} bt=${BT_COUNT} thermal=${THERMAL_COUNT} pm=${PM_COUNT} audio=${AUDIO_HW_COUNT} throttle=${THROTTLE_COUNT}"
    fi

    if [ "$WIFI_COUNT" -ge 3 ] || [ "$NET_COUNT" -ge 3 ] || [ "$ETH_COUNT" -ge 10 ] || \
       [ "$GPU_COUNT" -ge 3 ] || [ "$PM_COUNT" -ge 2 ] || [ "$AUDIO_HW_COUNT" -ge 3 ] || \
       [ "$BT_COUNT" -ge 5 ] || [ "$THERMAL_COUNT" -ge 5 ] || [ "$THROTTLE_COUNT" -ge 3 ]; then
        SEVERITY_CLASS="critical"
        SEVERITY_TITLE="Critical Issues Detected"
        SEVERITY_TEXT="Repeated hardware failures detected. Investigate before considering the system stable."
        local REASONS=""
        [ "$WIFI_COUNT" -ge 3 ]     && REASONS="${REASONS}wifi=${WIFI_COUNT} "
        [ "$NET_COUNT" -ge 3 ]      && REASONS="${REASONS}connectivity=${NET_COUNT} "
        [ "$ETH_COUNT" -ge 10 ]     && REASONS="${REASONS}eth=${ETH_COUNT} "
        [ "$GPU_COUNT" -ge 3 ]      && REASONS="${REASONS}gpu=${GPU_COUNT} "
        [ "$PM_COUNT" -ge 2 ]       && REASONS="${REASONS}suspend_pm=${PM_COUNT} "
        [ "$AUDIO_HW_COUNT" -ge 3 ] && REASONS="${REASONS}audio_hw=${AUDIO_HW_COUNT} "
        [ "$BT_COUNT" -ge 5 ]       && REASONS="${REASONS}bluetooth=${BT_COUNT} "
        [ "$THERMAL_COUNT" -ge 5 ]  && REASONS="${REASONS}thermal=${THERMAL_COUNT} "
        [ "$THROTTLE_COUNT" -ge 3 ] && REASONS="${REASONS}throttling=${THROTTLE_COUNT} "
        SEVERITY_REASON="${REASONS% }"
    fi

    DH_JSON="[]"
    if [ -f "$DRIVER_HEALTH_LOG" ]; then
        local DH_ENTRIES="" _N _S _D _F
        while IFS='|' read -r _N _S _D _F; do
            [ -z "$_N" ] && continue
            case "$_S" in OK|WARN|ERROR) ;; *) continue ;; esac
            DH_ENTRIES="${DH_ENTRIES}{\"name\":\"$(json_str "$_N")\",\"status\":\"$(json_str "$_S")\",\"detail\":\"$(json_str "$_D")\",\"fix\":\"$(json_str "$_F")\"},"
        done < <(grep -v '^===' "$DRIVER_HEALTH_LOG" 2>/dev/null | grep '|' || true)
        [ -n "$DH_ENTRIES" ] && DH_JSON="[${DH_ENTRIES%,}]"
    fi
    DH_CAPTURED="$(head -1 "$DRIVER_HEALTH_LOG" 2>/dev/null | grep -oE '[0-9]{4}-[0-9T:+\-]+' | head -1 || printf '')"

    SNAP_SYSTEMD="$(get_last_snapshot_section 'systemd' | head -1 || true)"
    SNAP_FAILED="$(get_last_snapshot_section 'failed_units' | grep -v 'No failed\|UNIT\|^$\|^0 loaded' | head -5 | tr '\n' ';' | sed 's/;$//' || true)"
    [ -z "$SNAP_FAILED" ] && SNAP_FAILED=""

    SNAP_SSID="$(get_last_snapshot_section 'wifi_link' | awk -F'[: ]+' '/^SSID:/{print $2}' | head -1 || true)"
    SNAP_SIGNAL_DBM="$(get_last_snapshot_section 'wifi_link' | grep '^signal:' | grep -oE '\-[0-9]+' | head -1 || true)"
    SNAP_FREQ_MHZ="$(get_last_snapshot_section 'wifi_link' | grep '^freq:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_TX_MBPS="$(get_last_snapshot_section 'wifi_link' | grep 'tx bitrate:' | grep -oE '[0-9.]+' | head -1 || true)"
    SNAP_RX_MBPS="$(get_last_snapshot_section 'wifi_link' | grep 'rx bitrate:' | grep -oE '[0-9.]+' | head -1 || true)"
    SNAP_TX_RETRIES="$(get_last_snapshot_section 'wifi_link' | grep 'tx retries:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_POWER_SAVE="$(get_last_snapshot_section 'wifi_link' | grep 'power_save:' | grep -oE 'on|off' | head -1 || true)"
    if get_last_snapshot_section 'wifi_link' | grep -q 'Connected to\|SSID:'; then
        SNAP_WIFI_CONNECTED="true"
    else
        SNAP_WIFI_CONNECTED="false"
    fi
    SNAP_WIFI_PING_TARGET="$(get_last_snapshot_section 'wifi_metrics' | awk '/^ping_target:/{sub(/^ping_target: /, ""); print; exit}' || true)"
    SNAP_WIFI_LATENCY="$(get_last_snapshot_section 'wifi_metrics' | awk '/^latency_ms:/{print $2; exit}' || true)"
    SNAP_WIFI_PACKET_LOSS="$(get_last_snapshot_section 'wifi_metrics' | awk '/^packet_loss_pct:/{print $2; exit}' || true)"
    SNAP_WIFI_CHANNEL="$(get_last_snapshot_section 'wifi_nearby' | awk '/^channel:/{print $2; exit}' || true)"
    SNAP_WIFI_INTERFERENCE_COUNT="$(get_last_snapshot_section 'wifi_nearby' | awk '/^interference_count:/{print $2; exit}' || true)"
    SNAP_WIFI_SCAN_SOURCE="$(get_last_snapshot_section 'wifi_nearby' | sed -n 's/^scan_source: //p' | head -1 || true)"
    SNAP_WIFI_NEARBY_JSON="$(get_last_snapshot_section 'wifi_nearby' | sed -n 's/^networks_json: //p' | head -1 || true)"
    [ -n "$SNAP_WIFI_NEARBY_JSON" ] || SNAP_WIFI_NEARBY_JSON="[]"
    [ -n "$SNAP_WIFI_CHANNEL" ] || SNAP_WIFI_CHANNEL="$(freq_to_channel "$SNAP_FREQ_MHZ")"
    [ "$SNAP_WIFI_CHANNEL" != "0" ] || SNAP_WIFI_CHANNEL="null"
    [ -n "$SNAP_WIFI_INTERFERENCE_COUNT" ] || SNAP_WIFI_INTERFERENCE_COUNT="0"
    [ -n "$SNAP_WIFI_SCAN_SOURCE" ] || SNAP_WIFI_SCAN_SOURCE="none"
    [ -n "$SNAP_WIFI_LATENCY" ] || SNAP_WIFI_LATENCY="null"
    [ -n "$SNAP_WIFI_PACKET_LOSS" ] || SNAP_WIFI_PACKET_LOSS="null"
    [ -n "$SNAP_WIFI_PING_TARGET" ] || SNAP_WIFI_PING_TARGET="$WIFI_PING_TARGET"

    SNAP_BAT_PCT="$(get_last_snapshot_section 'battery' | grep 'percentage:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_BAT_STATE="$(get_last_snapshot_section 'battery' | grep 'state:' | awk '{print $2}' | head -1 || true)"
    SNAP_BAT_TTE="$(get_last_snapshot_section 'battery' | grep 'time to empty:' | sed 's/.*time to empty: *//' | head -1 || true)"
    SNAP_BAT_CAPACITY="$(get_last_snapshot_section 'battery' | grep 'capacity:' | grep -oE '[0-9.]+' | head -1 || true)"
    SNAP_BAT_ENERGY="$(get_last_snapshot_section 'battery' | grep 'energy:' | grep -oE '[0-9.]+' | head -1 || true)"

    # Leer cpu_perf una sola vez para evitar race condition con el writer
    local _CPU_PERF_RAW
    _CPU_PERF_RAW="$(get_last_snapshot_section 'cpu_perf')"
    SNAP_CPU_FREQS="$(printf '%s\n' "$_CPU_PERF_RAW"    | grep '^current_freq:'    | sed 's/current_freq: //'    | head -1 || true)"
    SNAP_CPU_MAX="$(printf '%s\n' "$_CPU_PERF_RAW"      | grep '^max_freq_mhz:'   | grep -oE '[0-9]+'           | head -1 || true)"
    SNAP_CPU_FREQ_RATIO="$(printf '%s\n' "$_CPU_PERF_RAW"   | grep '^freq_ratio:'     | grep -oE '[0-9]+'       | head -1 || true)"
    SNAP_CPU_FREQ_HEADROOM="$(printf '%s\n' "$_CPU_PERF_RAW" | grep '^freq_headroom:'  | grep -oE '[0-9]+'      | head -1 || true)"
    SNAP_CPU_FREQ_STATE="$(printf '%s\n' "$_CPU_PERF_RAW"   | grep '^freq_state:'     | awk '{print $2}'        | head -1 || true)"
    SNAP_CPU_ENERGY="$(printf '%s\n' "$_CPU_PERF_RAW"       | grep '^energy_mode:'    | awk '{print $2}'        | head -1 || true)"
    SNAP_CPU_GOV="$(printf '%s\n' "$_CPU_PERF_RAW"          | grep '^governor:'       | awk '{print $2}'        | head -1 || true)"
    SNAP_CPU_THROTTLE="$(printf '%s\n' "$_CPU_PERF_RAW"     | grep '^throttle_status:'| sed 's/throttle_status: //' | head -1 || true)"
    SNAP_CPU_USAGES="$(printf '%s\n' "$_CPU_PERF_RAW"       | grep '^cpu_usage:'      | sed 's/cpu_usage: //'   | head -1 || true)"
    SNAP_CPU_THERMAL_ALARM="$(printf '%s\n' "$_CPU_PERF_RAW" | grep '^thermal_alarm:' | sed 's/thermal_alarm: *//' | head -1 || true)"
    [ -n "$SNAP_CPU_THERMAL_ALARM" ] || SNAP_CPU_THERMAL_ALARM="none"
    SNAP_CPU_PROCHOT="$(printf '%s\n' "$_CPU_PERF_RAW"      | grep '^prochot:'        | awk '{print $2}'        | head -1 || true)"
    [ "$SNAP_CPU_PROCHOT" = "true" ] || SNAP_CPU_PROCHOT="false"
    SNAP_CPU_BASE_FREQ="$(printf '%s\n' "$_CPU_PERF_RAW"    | grep '^base_freq_mhz:'  | grep -oE '[0-9]+'       | head -1 || true)"
    SNAP_CPU_THROTTLE_DELTA="$(printf '%s\n' "$_CPU_PERF_RAW" | grep '^throttle_count_delta:' | grep -oE '[0-9]+' | head -1 || true)"
    [ -n "$SNAP_CPU_THROTTLE_DELTA" ] || SNAP_CPU_THROTTLE_DELTA="0"
    # Si hubo throttle en el intervalo, forzar prochot=true para el frontend
    [ "$SNAP_CPU_THROTTLE_DELTA" -gt 0 ] 2>/dev/null && SNAP_CPU_PROCHOT="true" || true

    SNAP_MEM_TOTAL="$(get_last_snapshot_section 'memory_parsed' | grep '^mem_total_kb:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_MEM_USED="$(get_last_snapshot_section 'memory_parsed' | grep '^mem_used_kb:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_MEM_AVAIL="$(get_last_snapshot_section 'memory_parsed' | grep '^mem_available_kb:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_SWAP_USED="$(get_last_snapshot_section 'memory_parsed' | grep '^swap_used_kb:' | grep -oE '[0-9]+' | head -1 || true)"

    SNAP_LOAD_AVG="$(get_last_snapshot_section 'load_and_processes' | grep '^load_average:' | sed 's/load_average: //' | head -1 || true)"
    SNAP_CTX_SWITCHES="$(get_last_snapshot_section 'load_and_processes' | grep '^context_switches:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_TOP_CPU="$(get_last_snapshot_section 'top_cpu_processes' | tail -3 | tr '\n' ';' | sed 's/;$//' || true)"
    SNAP_TOP_MEM="$(get_last_snapshot_section 'top_memory_processes' | tail -3 | tr '\n' ';' | sed 's/;$//' || true)"
    SNAP_SWAP_USED_MB="$(get_last_snapshot_section 'memory_pressure' | grep '^swap_used:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_SWAPPINESS="$(get_last_snapshot_section 'kernel_tuning' | grep '^vm.swappiness' | grep -oE '[0-9]+' | head -1 || true)"

    TEMPS_JSON="[]"
    TEMPS_ENTRIES=""
    FAN_RPM=""
    local _TEMPS_RAW
    _TEMPS_RAW="$(get_last_snapshot_section 'temperature_fans')"
    while IFS= read -r LINE; do
        case "$LINE" in
            fan\ speed:*)
                FAN_RPM="${LINE#fan speed: }"
                ;;
            *:*'('*'high = '*)
                local LABEL CURRENT HIGH CRIT
                LABEL="${LINE%%:*}"
                CURRENT=$(printf '%s\n' "$LINE" | grep -oE '\+[0-9.]+' | head -1 | tr -d '+°C')
                HIGH=$(printf '%s\n' "$LINE" | grep -oE 'high = \+[0-9.]+' | grep -oE '[0-9.]+')
                CRIT=$(printf '%s\n' "$LINE" | grep -oE 'crit = \+[0-9.]+' | grep -oE '[0-9.]+')
                case "$LABEL" in 'Package id 0') LABEL="CPU Package" ;; esac
                TEMPS_ENTRIES="${TEMPS_ENTRIES}{\"label\":\"$(json_str "$LABEL")\",\"current_c\":${CURRENT:-0},\"high_c\":${HIGH:-0},\"crit_c\":${CRIT:-0}},"
                ;;
        esac
    done < <(printf '%s\n' "$_TEMPS_RAW")
    [ -n "$TEMPS_ENTRIES" ] && TEMPS_JSON="[${TEMPS_ENTRIES%,}]"

    DAILY_JSON="[]"
    if [ -f "$DAILY_LOG" ]; then
        local LINE D W N G B TH P A TOT
        DAILY_ENTRIES=""
        while IFS= read -r LINE; do
            [ -n "$LINE" ] || continue
            D="${LINE%% *}"
            W="$(printf '%s' "$LINE" | grep -oE 'wifi=[0-9]+' | grep -oE '[0-9]+')"
            N="$(printf '%s' "$LINE" | grep -oE 'net=[0-9]+' | grep -oE '[0-9]+')"
            G="$(printf '%s' "$LINE" | grep -oE 'gpu=[0-9]+' | grep -oE '[0-9]+')"
            B="$(printf '%s' "$LINE" | grep -oE 'bt=[0-9]+' | grep -oE '[0-9]+')"
            TH="$(printf '%s' "$LINE" | grep -oE 'thermal=[0-9]+' | grep -oE '[0-9]+')"
            P="$(printf '%s' "$LINE" | grep -oE 'pm=[0-9]+' | grep -oE '[0-9]+')"
            A="$(printf '%s' "$LINE" | grep -oE 'audio=[0-9]+' | grep -oE '[0-9]+')"
            TR="$(printf '%s' "$LINE" | grep -oE 'throttle=[0-9]+' | grep -oE '[0-9]+')"
            TOT="$(printf '%s' "$LINE" | grep -oE 'total=[0-9]+' | grep -oE '[0-9]+')"
            DAILY_ENTRIES="${DAILY_ENTRIES}{\"date\":\"$(json_str "$D")\",\"wifi\":${W:-0},\"net\":${N:-0},\"gpu\":${G:-0},\"bt\":${B:-0},\"thermal\":${TH:-0},\"pm\":${P:-0},\"audio\":${A:-0},\"throttle\":${TR:-0},\"total\":${TOT:-0}},"
        done < "$DAILY_LOG"
        [ -n "$DAILY_ENTRIES" ] && DAILY_JSON="[${DAILY_ENTRIES%,}]"
    fi

    EVENTS_JSON="[]"
    if [ -f "$EVENTS_LOG" ]; then
        EV_ENTRIES=""
        while IFS= read -r LINE; do
            case "$LINE" in '=== '*) continue ;; esac
            case "$LINE" in [0-9][0-9][0-9][0-9]-*)
                local EV_TS EV_MSG EV_CAT EV_LOWER
                EV_TS="${LINE%% *}"
                EV_MSG="${LINE#* }"
                EV_LOWER="$(printf '%s' "$EV_MSG" | tr '[:upper:]' '[:lower:]')"
                case "$EV_LOWER" in
                    *brcmf*|*wpa_supplicant*|*networkmanager*|*dhcp4*|*iwlwifi*) EV_CAT="wifi" ;;
                    *gpu*|*drm*|*i915*) EV_CAT="gpu" ;;
                    *pm:*|*suspend*|*resume*|*s2idle*) EV_CAT="power" ;;
                    *thermal*|*acpi*|*applesmc*|*throttl*) EV_CAT="thermal" ;;
                    *snd_hda*|*audio*|*pipewire*) EV_CAT="audio" ;;
                    *bluetooth*|*btusb*|*hci*) EV_CAT="bluetooth" ;;
                    *) EV_CAT="other" ;;
                esac
                EV_ENTRIES="${EV_ENTRIES}{\"ts\":\"$(json_str "$EV_TS")\",\"category\":\"$(json_str "$EV_CAT")\",\"message\":\"$(json_str "$EV_MSG")\"},"
                ;;
            esac
        done < <(
            grep -Ev "^=== JOURNAL WATCH" "$EVENTS_LOG" 2>/dev/null |
                tail -n "$COUNT_WINDOW_LINES" |
                grep -Ev "$NOISY_EVENT_REGEX" |
                awk '!seen[$0]++ { lines[++n] = $0 } END { for (i = n; i >= 1; i--) print lines[i] }'
        )
        [ -n "$EV_ENTRIES" ] && EVENTS_JSON="[${EV_ENTRIES%,}]"
    fi

    _inv() { awk -v s="[$1]" '/^\[/{f=0} $0==s{f=1;next} f && NF{print;exit}' "$INVENTORY_LOG" 2>/dev/null || true; }
    _inv_line() { awk -v s="[$1]" -v n="$2" '/^\[/{f=0;c=0} $0==s{f=1;next} f && NF{c++;if(c==n){print;exit}}' "$INVENTORY_LOG" 2>/dev/null || true; }
    INV_CPU="$(_inv cpu)"
    INV_CPU_DESC="$(_inv_line cpu 2)"
    INV_MODEL="$(_inv apple_model)"
    INV_MODEL_DESC="$(_inv_line apple_model 2)"
    INV_KERNEL="$(_inv kernel)"
    INV_KERNEL_DESC=""
    INV_GPU="$(_inv gpu)"
    INV_GPU_DESC="$(_inv_line gpu 2)"
    INV_WIFI="$(_inv wifi_chip)"
    INV_WIFI_DESC="$(_inv_line wifi_chip 2)"
    INV_WIFI_FW="$(_inv wifi_firmware)"
    INV_WIFI_FW_DESC=""
    INV_BT="$(_inv bluetooth_chip)"
    INV_BT_DESC=""
    INV_AUDIO="$(_inv audio_card)"
    INV_AUDIO_DESC=""
    INV_CAMERA="$(_inv camera)"
    INV_CAMERA_DESC=""
    INV_TS="$(head -1 "$INVENTORY_LOG" 2>/dev/null | grep -oE '[0-9]{4}-[^ ]+' || printf '')"

    TMP_JSON="$(mktemp "${BASE_DIR}/data.json.XXXXXX")"
    cat > "$TMP_JSON" <<JSONEOF
{
  "generated": "$(timestamp)",
  "state_dir": "$(json_str "$BASE_DIR")",
  "severity": {
    "class": "$(json_str "$SEVERITY_CLASS")",
    "title": "$(json_str "$SEVERITY_TITLE")",
    "text": "$(json_str "$SEVERITY_TEXT")",
    "reason": "$(json_str "$SEVERITY_REASON")"
  },
  "counters": {
    "wifi": $WIFI_COUNT,
    "connectivity": $NET_COUNT,
    "eth": $ETH_COUNT,
    "gpu": $GPU_COUNT,
    "bluetooth": $BT_COUNT,
    "thermal": $THERMAL_COUNT,
    "pm": $PM_COUNT,
    "audio": $AUDIO_HW_COUNT,
    "throttle": $THROTTLE_COUNT,
    "total": $TOTAL_COUNT
  },
  "driver_health": {
    "captured": "$(json_str "$DH_CAPTURED")",
    "drivers": $DH_JSON
  },
  "snapshot": {
    "captured": "$(timestamp)",
    "systemd": "$(json_str "$SNAP_SYSTEMD")",
    "failed_units": "$(json_str "$SNAP_FAILED")",
    "load_and_system": {
      "load_average": "$(json_str "$SNAP_LOAD_AVG")",
      "context_switches": ${SNAP_CTX_SWITCHES:-0},
      "top_cpu_processes": "$(json_str "$SNAP_TOP_CPU")",
      "top_memory_processes": "$(json_str "$SNAP_TOP_MEM")"
    },
    "battery": {
      "percentage": ${SNAP_BAT_PCT:-null},
      "state": "$(json_str "$SNAP_BAT_STATE")",
      "time_to_empty": "$(json_str "$SNAP_BAT_TTE")",
      "capacity_pct": ${SNAP_BAT_CAPACITY:-null},
      "energy_wh": ${SNAP_BAT_ENERGY:-null}
    },
    "wifi_link": {
      "connected": $SNAP_WIFI_CONNECTED,
      "ssid": "$(json_str "$SNAP_SSID")",
      "signal_dbm": ${SNAP_SIGNAL_DBM:-null},
      "freq_mhz": ${SNAP_FREQ_MHZ:-null},
      "tx_mbps": ${SNAP_TX_MBPS:-null},
      "rx_mbps": ${SNAP_RX_MBPS:-null},
      "tx_retries": ${SNAP_TX_RETRIES:-null},
      "power_save": "$(json_str "$SNAP_POWER_SAVE")"
    },
    "wifi_analysis": {
      "channel": ${SNAP_WIFI_CHANNEL},
      "latency_ms": ${SNAP_WIFI_LATENCY},
      "packet_loss_pct": ${SNAP_WIFI_PACKET_LOSS},
      "interference_count": ${SNAP_WIFI_INTERFERENCE_COUNT},
      "ping_target": "$(json_str "$SNAP_WIFI_PING_TARGET")",
      "scan_source": "$(json_str "$SNAP_WIFI_SCAN_SOURCE")",
      "signal_warn_dbm": ${WIFI_SIGNAL_WARN_DBM},
      "interference_signal_dbm": ${WIFI_INTERFERENCE_SIGNAL_DBM},
      "nearby_networks": ${SNAP_WIFI_NEARBY_JSON}
    },
    "cpu_perf": {
        "current_freqs": "$(json_str "$SNAP_CPU_FREQS")",
        "cpu_usage": "$(json_str "$SNAP_CPU_USAGES")",
        "max_freq_mhz": ${SNAP_CPU_MAX:-null},
        "freq_ratio": ${SNAP_CPU_FREQ_RATIO:-null},
        "freq_headroom": ${SNAP_CPU_FREQ_HEADROOM:-null},
        "freq_state": "$(json_str "$SNAP_CPU_FREQ_STATE")",
        "energy_mode": "$(json_str "$SNAP_CPU_ENERGY")",
        "governor": "$(json_str "$SNAP_CPU_GOV")",
        "throttle_status": "$(json_str "$SNAP_CPU_THROTTLE")",
        "thermal_alarm": "$(json_str "$SNAP_CPU_THERMAL_ALARM")",
        "prochot": ${SNAP_CPU_PROCHOT},
        "throttle_count_delta": ${SNAP_CPU_THROTTLE_DELTA:-0},
        "base_freq_mhz": ${SNAP_CPU_BASE_FREQ:-null}
      },
    "memory": {
      "total_kb": ${SNAP_MEM_TOTAL:-null},
      "used_kb": ${SNAP_MEM_USED:-null},
      "available_kb": ${SNAP_MEM_AVAIL:-null},
      "swap_used_kb": ${SNAP_SWAP_USED:-0},
      "swap_used_mb": ${SNAP_SWAP_USED_MB:-0},
      "swappiness": ${SNAP_SWAPPINESS:-60}
    },
    "temperatures": $TEMPS_JSON,
    "fan_rpm": "$(json_str "$FAN_RPM")"
  },
  "inventory": {
    "captured": "$(json_str "$INV_TS")",
    "cpu": "$(json_str "$INV_CPU")",
    "cpu_desc": "$(json_str "$INV_CPU_DESC")",
    "apple_model": "$(json_str "$INV_MODEL")",
    "apple_model_desc": "$(json_str "$INV_MODEL_DESC")",
    "kernel": "$(json_str "$INV_KERNEL")",
    "kernel_desc": "$(json_str "$INV_KERNEL_DESC")",
    "gpu": "$(json_str "$INV_GPU")",
    "gpu_desc": "$(json_str "$INV_GPU_DESC")",
    "wifi_chip": "$(json_str "$INV_WIFI")",
    "wifi_chip_desc": "$(json_str "$INV_WIFI_DESC")",
    "wifi_firmware": "$(json_str "$INV_WIFI_FW")",
    "wifi_firmware_desc": "$(json_str "$INV_WIFI_FW_DESC")",
    "bluetooth": "$(json_str "$INV_BT")",
    "bluetooth_desc": "$(json_str "$INV_BT_DESC")",
    "audio": "$(json_str "$INV_AUDIO")",
    "audio_desc": "$(json_str "$INV_AUDIO_DESC")",
    "camera": "$(json_str "$INV_CAMERA")",
    "camera_desc": "$(json_str "$INV_CAMERA_DESC")"
  },
  "recent_events": $EVENTS_JSON,
  "daily_history": $DAILY_JSON
}
JSONEOF

    mv "$TMP_JSON" "$BASE_DIR/data.json"
    chmod 644 "$BASE_DIR/data.json"
    generate_ai_digest
}

generate_report() {
    generate_data_json >/dev/null 2>&1 || true
    return 0
}

usage() {
    cat <<EOF
Usage:
  $0 start
  $0 run
  $0 stop
  $0 status
  $0 snapshot
  $0 report
  $0 inventory
  $0 drivers

Environment:
  MBP_WATCH_DIR       default: $BASE_DIR
  MBP_WATCH_INTERVAL  default: $INTERVAL_SECONDS
  MBP_WATCH_RESUME_WINDOW_MINUTES default: $RESUME_CONTEXT_WINDOW_MINUTES

Outputs:
  report.html       full HTML report (auto-refreshes every \$INTERVAL seconds)
  report.txt        AI digest — compact structured text for AI analysis
  inventory.log     static hardware inventory (model, GPU, WiFi chip, firmware, audio, camera)
  daily_errors.log  persistent per-day error counts — never truncated, ideal for multi-day AI analysis
  events.log        raw matched journal events (last $MAX_EVENT_LINES lines)
  snapshots.log     periodic system snapshots (temp, battery, NM, rfkill, failed units)

Notes:
  - Installed system-wide, this is expected to run as root under systemd.
  - Keep it enabled during the first days of CachyOS use.
  - Disable once Wi-Fi, suspend/resume, and thermals are confirmed stable.
  - report.txt is intended to be fed directly to an AI for analysis.
EOF
}

case "${1:-}" in
    start)
        start_watch
        ;;
    run)
        run_watch
        ;;
    stop)
        stop_watch
        ;;
    status)
        status_watch
        ;;
    snapshot)
        capture_snapshot
        echo "snapshot captured in $SNAPSHOTS_LOG"
        ;;
    report)
        generate_data_json
        ;;
    inventory)
        capture_hardware_inventory
        capture_driver_health
        echo "inventory captured in $INVENTORY_LOG"
        cat "$INVENTORY_LOG"
        ;;
    drivers)
        capture_driver_health
        echo "driver health captured in $DRIVER_HEALTH_LOG"
        awk -F'|' '
            /^===/ { print; next }
            NF >= 3 {
                s=$2
                if (s == "OK")         tag="[OK   ]"
                else if (s == "WARN")  tag="[WARN ]"
                else if (s == "ERROR") tag="[ERROR]"
                else next
                fix = $4; for (i=5; i<=NF; i++) fix = fix "|" $i
                printf "%s %-12s %s\n", tag, $1":", $3
                if (fix != "") printf "         fix: %s\n", fix
            }
        ' "$DRIVER_HEALTH_LOG"
        ;;
    _journal_loop)
        journal_loop
        ;;
    _snapshot_loop)
        snapshot_loop
        ;;
    _serve_loop)
        serve_loop
        ;;
    *)
        usage
        exit 1
        ;;
esac
