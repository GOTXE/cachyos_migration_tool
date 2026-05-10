# MBP Watch — Plan de Refactorización

> MacBook Pro 13" 2015 (MacBookPro12,1) · i5-5257U · 16 GB · CachyOS + KDE Plasma  
> Objetivo: monitorización orientada a desarrollo (scripts, Python, web)  
> Mockup visual en `mbp-watch-web-mockup.pen`

---

## Contexto del hardware

El i5-5257U es un dual-core Broadwell de 28 W TDP con Turbo Boost hasta 3.1 GHz.
Con CachyOS (kernel parchado, BORE scheduler) el rendimiento en tareas dev es bueno,
pero hay tres problemas reales y silenciosos en Linux en esta máquina:

| Problema | Por qué importa al dev |
|---|---|
| **Throttling térmico** | La CPU baja a 800 MHz sin avisar bajo carga sostenida (pytest, compilación, servidor dev). El trabajo tarda más y no se sabe por qué. |
| **Wi-Fi post-suspend** | brcmfmac / BCM43602 pierde el enlace al despertar. Interrumpe SSH, git push, descarga de dependencias. |
| **Governor inesperado** | KDE Power Management puede cambiar el governor a `powersave` silenciosamente. Toda la sesión va lenta. |

16 GB de RAM cubre holgadamente el uso dev (browser + IDE + servidor local). No es un cuello de botella, pero conviene tenerlo en el dashboard para confirmar que el sistema no está en swap.

---

## Estado actual — qué hace mbp-watch

```
mbp_watch.sh (único archivo bash, ~2100 líneas)
├── capture_hardware_inventory()   → escribe inventory.log (texto estructurado)
├── capture_driver_health()        → escribe driver_health.log (pipe-separated)
├── capture_snapshot()             → escribe snapshots.log (texto estructurado)
├── journal_loop()                 → escribe events.log (journalctl en tiempo real)
├── update_daily_summary()         → escribe daily_errors.log (una línea por día)
├── generate_report()              → escribe report.html (HTML completo, ~600 líneas bash)
│   ├── render_events_html()
│   ├── render_inventory_html()
│   ├── render_snapshot_html()
│   ├── render_driver_health_html()
│   └── render_temperature_fans_html()
└── serve_loop()                   → python3 HTTP server en 127.0.0.1:7070
```

**El problema central:** `generate_report()` mezcla datos, lógica y presentación en un heredoc gigante.
Cada 5 s se regenera el HTML completo (~600 líneas de bash) para cambiar quizás 3 valores.

---

## Visión objetivo

```
mbp_watch.sh (bash — solo datos)
├── capture_hardware_inventory()   → sin cambios
├── capture_driver_health()        → sin cambios
├── capture_snapshot()             → AMPLIADO con CPU freq, governor, throttling
├── journal_loop()                 → AMPLIADO regex con throttling
├── update_daily_summary()         → AMPLIADO con throttle counter
├── generate_data_json()           → NUEVO — reemplaza generate_report()
└── serve_loop()                   → sin cambios

/var/lib/mbp-watch/
├── data.json         ← único archivo que cambia cada 5 s
├── report.html       ← estático, nunca se regenera
├── report.css        ← estático
├── report.js         ← estático, fetch(data.json) y renderiza
├── report.txt        ← AI digest, sin cambios
└── *.log             ← logs de datos crudos, sin cambios
```

---

## Fase 0 — Preparación (sin tocar el script en producción)

**Objetivo:** tener el entorno listo para trabajar sin romper el servicio activo.

### Pasos

**0.1** Hacer copia de trabajo del script actual:
```bash
cp /usr/local/bin/mbp_watch.sh ~/mbp_watch_dev.sh
```

**0.2** Crear directorio de desarrollo para los archivos web:
```bash
mkdir -p ~/mbp-watch-web
```

**0.3** Verificar que el servicio funciona antes de tocar nada:
```bash
systemctl is-active mbp-watch.service
curl -s http://localhost:7070/report.html | head -5
```

**0.4** Tener el estado dir actual a mano para pruebas:
```bash
ls /var/lib/mbp-watch/
# debe mostrar: events.log  snapshots.log  inventory.log  driver_health.log
#               daily_errors.log  report.html  report.txt  status.log  *.pid
```

---

## Fase 1 — Ampliar captura de datos (throttling + CPU + memoria)

**Objetivo:** enriquecer los datos que ya recoge el script sin cambiar la arquitectura.
Esta fase es independiente y segura: solo añade datos a los logs existentes.

**Archivos afectados:** `mbp_watch.sh` — función `capture_snapshot()` y constante `FAILURE_EVENT_REGEX`.

### 1.1 Añadir detección de throttling a `capture_snapshot()`

Localizar el bloque `[temperature_fans]` en `capture_snapshot()` (línea ~443) y
añadir un nuevo bloque `[cpu_perf]` justo después:

```bash
printf '\n[cpu_perf]\n'

# Frecuencia actual de cada núcleo (kHz → MHz)
local CORE_FREQS="" CORE_N=0 FREQ_KHZ FREQ_MHZ
for FREQ_KHZ_FILE in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
    [ -r "$FREQ_KHZ_FILE" ] || continue
    FREQ_KHZ="$(cat "$FREQ_KHZ_FILE" 2>/dev/null || printf '0')"
    FREQ_MHZ=$(( FREQ_KHZ / 1000 ))
    CORE_FREQS="${CORE_FREQS}core${CORE_N}=${FREQ_MHZ}MHz "
    CORE_N=$(( CORE_N + 1 ))
done
printf 'current_freq: %s\n' "${CORE_FREQS% }"

# Frecuencia máxima del procesador (fija, de cpuinfo)
local MAX_FREQ_KHZ MAX_FREQ_MHZ
MAX_FREQ_KHZ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || printf '0')"
MAX_FREQ_MHZ=$(( MAX_FREQ_KHZ / 1000 ))
printf 'max_freq_mhz: %s\n' "$MAX_FREQ_MHZ"

# Governor activo
local GOV
GOV="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || printf 'unknown')"
printf 'governor: %s\n' "$GOV"

# Detectar throttling: si el núcleo 0 corre < 70% de la freq máxima
local CUR0_KHZ THROTTLE_STATUS
CUR0_KHZ="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || printf '0')"
if [ "$MAX_FREQ_KHZ" -gt 0 ]; then
    # Ratio en porcentaje entero (sin bc, solo aritmética bash)
    local RATIO=$(( CUR0_KHZ * 100 / MAX_FREQ_KHZ ))
    if [ "$RATIO" -lt 70 ]; then
        THROTTLE_STATUS="THROTTLING ratio=${RATIO}%"
    else
        THROTTLE_STATUS="ok ratio=${RATIO}%"
    fi
else
    THROTTLE_STATUS="unknown"
fi
printf 'throttle_status: %s\n' "$THROTTLE_STATUS"

# Alarm de throttling térmico via sysfs (si el sensor lo expone)
local THERM_ALARM=""
for ALARM_FILE in /sys/class/hwmon/hwmon*/temp*_crit_alarm; do
    [ -r "$ALARM_FILE" ] || continue
    local VAL
    VAL="$(cat "$ALARM_FILE" 2>/dev/null || printf '0')"
    if [ "$VAL" = "1" ]; then
        THERM_ALARM="${THERM_ALARM}$(basename "$(dirname "$ALARM_FILE")")/$(basename "$ALARM_FILE") "
    fi
done
printf 'thermal_alarm: %s\n' "${THERM_ALARM:-none}"
```

### 1.2 Parsear memoria como números en `capture_snapshot()`

El bloque `[memory]` actual solo hace `free -h`. Añadir parsing numérico:

```bash
printf '\n[memory]\n'
free -h || true

# Añadir valores parseables para el JSON
printf '\n[memory_parsed]\n'
awk '/^Mem:/ {
    printf "mem_total_kb: %s\n", $2
    printf "mem_used_kb: %s\n", $3
    printf "mem_available_kb: %s\n", $7
}
/^Swap:/ {
    printf "swap_total_kb: %s\n", $2
    printf "swap_used_kb: %s\n", $3
}' /proc/meminfo 2>/dev/null || true
```

> `/proc/meminfo` da valores en kB sin decimales, ideal para aritmética bash.

### 1.3 Añadir throttling al `FAILURE_EVENT_REGEX`

Localizar la constante al inicio del script y añadir al final de la línea:

```bash
# Añadir al final del regex existente (antes de la comilla de cierre):
|cpu.*throttl|thermal.*throttl|CPU.*max.*freq|turbo.*disabled
```

### 1.4 Añadir counter de throttling a `update_daily_summary()`

```bash
# Añadir junto a los otros counters (W=wifi, N=net, etc.):
TH_COUNT="$(keyword_count_for_date "$TODAY" 'cpu.*throttl|thermal.*throttl')"

# Añadir a NEW_LINE:
NEW_LINE="$TODAY wifi=$W net=$N gpu=$G bt=$B thermal=$T pm=$P audio=$A throttle=$TH_COUNT total=$TOT"
```

### Verificación de Fase 1

```bash
# Parar, actualizar, arrancar
sudo systemctl stop mbp-watch.service
sudo cp ~/mbp_watch_dev.sh /usr/local/bin/mbp_watch.sh
sudo systemctl start mbp-watch.service

# Esperar 10 s y verificar que el snapshot contiene los nuevos bloques
sleep 10
grep -A 10 '\[cpu_perf\]' /var/lib/mbp-watch/snapshots.log
grep -A 5  '\[memory_parsed\]' /var/lib/mbp-watch/snapshots.log
```

---

## Fase 2 — Crear `generate_data_json()` en paralelo

**Objetivo:** escribir la nueva función sin eliminar aún `generate_report()`.
Ambas coexisten. Al final de esta fase, `data.json` se genera junto a `report.html`.

**Archivos afectados:** `mbp_watch.sh` — añadir función nueva, modificar `snapshot_loop()`.

### 2.1 Función auxiliar `json_str()`

Añadir al script (cerca de `html_escape()`):

```bash
# Escapa un valor para incluirlo en una string JSON (comillas y backslashes)
json_str() {
    printf '%s' "$1" \
        | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g' \
        | tr -d '\000-\037'
}
```

### 2.2 Función auxiliar `get_cpu_perf_field()`

```bash
get_cpu_perf_field() {
    local FIELD="$1"
    [ -f "$SNAPSHOTS_LOG" ] || printf ''; return 0

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
```

### 2.3 La función `generate_data_json()`

Esta función extrae los mismos datos que usaba `generate_report()` pero los emite como JSON.
Añadir al script después de `generate_report()`:

```bash
generate_data_json() {
    local WIFI_COUNT NET_COUNT GPU_COUNT BT_COUNT THERMAL_COUNT PM_COUNT AUDIO_HW_COUNT THROTTLE_COUNT TOTAL_COUNT
    local SEVERITY_CLASS SEVERITY_TITLE SEVERITY_TEXT SEVERITY_REASON

    update_daily_summary

    # ── Contadores (reutiliza la misma lógica que generate_report) ────────────
    WIFI_COUNT="$(keyword_count 'brcmf|wpa_supplicant|iwlwifi|mt76|ath|rtl|rtw')"
    NET_COUNT="$(keyword_count 'NetworkManager.*(failed|error|timeout|no lease|activation failed)|dhcp4 .* (failed|timeout|no lease)|wpa_supplicant.*(fail|error|timeout)|device .*Activation: failed')"
    GPU_COUNT="$(keyword_count 'gpu|drm|i915')"
    BT_COUNT="$(keyword_count 'bluetoothd|bluetooth')"
    THERMAL_COUNT="$(keyword_count 'thermal|acpi')"
    PM_COUNT="$(keyword_count 'PM:|s2idle')"
    AUDIO_HW_COUNT="$(keyword_count 'snd_hda|applesmc|thunderbolt')"
    THROTTLE_COUNT="$(keyword_count 'cpu.*throttl|thermal.*throttl')"

    if { [ "$WIFI_COUNT" -gt 0 ] || [ "$NET_COUNT" -gt 0 ]; } && \
        recent_suspend_resume_context && current_wifi_link_is_up; then
        WIFI_COUNT=0; NET_COUNT=0
    fi

    TOTAL_COUNT=$(( WIFI_COUNT + NET_COUNT + GPU_COUNT + BT_COUNT + THERMAL_COUNT + PM_COUNT + AUDIO_HW_COUNT + THROTTLE_COUNT ))

    # ── Severidad ─────────────────────────────────────────────────────────────
    SEVERITY_CLASS="ok"
    SEVERITY_TITLE="Stable"
    SEVERITY_TEXT="No hardware errors detected in the last ${COUNT_WINDOW_LINES} journal events."
    SEVERITY_REASON="No matched problems detected yet."

    if [ "$TOTAL_COUNT" -gt 0 ]; then
        SEVERITY_CLASS="warn"
        SEVERITY_TITLE="Warnings Found"
        SEVERITY_TEXT="Matched events detected. Review the recent events section."
        SEVERITY_REASON="${TOTAL_COUNT} matched event(s) — wifi=${WIFI_COUNT} net=${NET_COUNT} gpu=${GPU_COUNT} bt=${BT_COUNT} thermal=${THERMAL_COUNT} pm=${PM_COUNT} audio=${AUDIO_HW_COUNT} throttle=${THROTTLE_COUNT}"
    fi

    if [ "$WIFI_COUNT" -ge 3 ] || [ "$NET_COUNT" -ge 3 ] || [ "$GPU_COUNT" -ge 3 ] || \
       [ "$PM_COUNT" -ge 2 ] || [ "$AUDIO_HW_COUNT" -ge 3 ] || \
       [ "$BT_COUNT" -ge 5 ] || [ "$THERMAL_COUNT" -ge 5 ] || [ "$THROTTLE_COUNT" -ge 3 ]; then
        SEVERITY_CLASS="critical"
        SEVERITY_TITLE="Critical Issues Detected"
        SEVERITY_TEXT="Repeated hardware failures detected. Investigate before considering the system stable."
        local REASONS=""
        [ "$WIFI_COUNT" -ge 3 ]     && REASONS="${REASONS}wifi=${WIFI_COUNT} "
        [ "$NET_COUNT" -ge 3 ]      && REASONS="${REASONS}connectivity=${NET_COUNT} "
        [ "$GPU_COUNT" -ge 3 ]      && REASONS="${REASONS}gpu=${GPU_COUNT} "
        [ "$PM_COUNT" -ge 2 ]       && REASONS="${REASONS}suspend_pm=${PM_COUNT} "
        [ "$AUDIO_HW_COUNT" -ge 3 ] && REASONS="${REASONS}audio_hw=${AUDIO_HW_COUNT} "
        [ "$BT_COUNT" -ge 5 ]       && REASONS="${REASONS}bluetooth=${BT_COUNT} "
        [ "$THERMAL_COUNT" -ge 5 ]  && REASONS="${REASONS}thermal=${THERMAL_COUNT} "
        [ "$THROTTLE_COUNT" -ge 3 ] && REASONS="${REASONS}throttling=${THROTTLE_COUNT} "
        SEVERITY_REASON="${REASONS% }"
    fi

    # ── Datos de driver health ────────────────────────────────────────────────
    local DH_JSON="[]"
    if [ -f "$DRIVER_HEALTH_LOG" ]; then
        local DH_ENTRIES=""
        local _N _S _D _F
        while IFS='|' read -r _N _S _D _F; do
            [ -z "$_N" ] && continue
            case "$_S" in OK|WARN|ERROR) ;; *) continue ;; esac
            DH_ENTRIES="${DH_ENTRIES}{\"name\":\"$(json_str "$_N")\",\"status\":\"$(json_str "$_S")\",\"detail\":\"$(json_str "$_D")\",\"fix\":\"$(json_str "$_F")\"},"
        done < <(grep -v '^===' "$DRIVER_HEALTH_LOG" 2>/dev/null | grep '|' || true)
        [ -n "$DH_ENTRIES" ] && DH_JSON="[${DH_ENTRIES%,}]"
    fi
    local DH_CAPTURED
    DH_CAPTURED="$(head -1 "$DRIVER_HEALTH_LOG" 2>/dev/null | grep -oE '[0-9]{4}-[0-9T:+\-]+' | head -1 || printf '')"

    # ── Datos de snapshot (último) ────────────────────────────────────────────
    local SNAP_SYSTEMD SNAP_WIFI_CONNECTED SNAP_SSID SNAP_SIGNAL_DBM SNAP_FREQ_MHZ
    local SNAP_TX_MBPS SNAP_RX_MBPS SNAP_TX_RETRIES SNAP_POWER_SAVE
    local SNAP_BAT_PCT SNAP_BAT_STATE SNAP_BAT_TTE SNAP_BAT_CAPACITY SNAP_BAT_ENERGY
    local SNAP_CPU_FREQS SNAP_CPU_MAX SNAP_CPU_GOV SNAP_CPU_THROTTLE
    local SNAP_MEM_TOTAL SNAP_MEM_USED SNAP_MEM_AVAIL SNAP_SWAP_USED
    local SNAP_FAILED

    SNAP_SYSTEMD="$(get_last_snapshot_section 'systemd' | head -1 || true)"
    SNAP_FAILED="$(get_last_snapshot_section 'failed_units' | grep -v 'No failed\|UNIT\|^$\|^0 loaded' | head -5 | tr '\n' ';' | sed 's/;$//' || true)"
    [ -z "$SNAP_FAILED" ] && SNAP_FAILED=""

    # Wi-Fi link
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

    # Batería
    SNAP_BAT_PCT="$(get_last_snapshot_section 'battery' | grep 'percentage:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_BAT_STATE="$(get_last_snapshot_section 'battery' | grep 'state:' | awk '{print $2}' | head -1 || true)"
    SNAP_BAT_TTE="$(get_last_snapshot_section 'battery' | grep 'time to empty:' | sed 's/.*time to empty: *//' | head -1 || true)"
    SNAP_BAT_CAPACITY="$(get_last_snapshot_section 'battery' | grep 'capacity:' | grep -oE '[0-9.]+' | head -1 || true)"
    SNAP_BAT_ENERGY="$(get_last_snapshot_section 'battery' | grep 'energy:' | grep -oE '[0-9.]+' | head -1 || true)"

    # CPU performance / throttling
    SNAP_CPU_FREQS="$(get_last_snapshot_section 'cpu_perf' | grep '^current_freq:' | sed 's/current_freq: //' | head -1 || true)"
    SNAP_CPU_MAX="$(get_last_snapshot_section 'cpu_perf' | grep '^max_freq_mhz:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_CPU_GOV="$(get_last_snapshot_section 'cpu_perf' | grep '^governor:' | awk '{print $2}' | head -1 || true)"
    SNAP_CPU_THROTTLE="$(get_last_snapshot_section 'cpu_perf' | grep '^throttle_status:' | sed 's/throttle_status: //' | head -1 || true)"

    # Memoria
    SNAP_MEM_TOTAL="$(get_last_snapshot_section 'memory_parsed' | grep '^mem_total_kb:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_MEM_USED="$(get_last_snapshot_section 'memory_parsed' | grep '^mem_used_kb:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_MEM_AVAIL="$(get_last_snapshot_section 'memory_parsed' | grep '^mem_available_kb:' | grep -oE '[0-9]+' | head -1 || true)"
    SNAP_SWAP_USED="$(get_last_snapshot_section 'memory_parsed' | grep '^swap_used_kb:' | grep -oE '[0-9]+' | head -1 || true)"

    # ── Temperaturas (desde el último snapshot) ───────────────────────────────
    local TEMPS_JSON="[]"
    local TEMPS_ENTRIES=""
    local FAN_RPM=""
    while IFS= read -r LINE; do
        case "$LINE" in
            fan\ speed:*)
                FAN_RPM="${LINE#fan speed: }"
                ;;
            *:*'('*'high = '*)
                local LABEL CURRENT HIGH CRIT
                LABEL="${LINE%%:*}"
                local DETAIL="${LINE#*: }"
                CURRENT="${DETAIL%% *}"; CURRENT="${CURRENT#+}"
                local THRESH="${DETAIL#*(}"; THRESH="${THRESH%)*}"
                HIGH="${THRESH#high = }"; HIGH="${HIGH%%,*}"; HIGH="${HIGH#+}"
                CRIT="${THRESH##*, crit = }"; CRIT="${CRIT#+}"
                case "$LABEL" in 'Package id 0') LABEL="CPU Package" ;; esac
                TEMPS_ENTRIES="${TEMPS_ENTRIES}{\"label\":\"$(json_str "$LABEL")\",\"current_c\":${CURRENT:-0},\"high_c\":${HIGH:-0},\"crit_c\":${CRIT:-0}},"
                ;;
        esac
    done < <(get_last_snapshot_section 'temperature_fans')
    [ -n "$TEMPS_ENTRIES" ] && TEMPS_JSON="[${TEMPS_ENTRIES%,}]"

    # ── Historial diario ──────────────────────────────────────────────────────
    local DAILY_JSON="[]"
    if [ -f "$DAILY_LOG" ]; then
        local DAILY_ENTRIES=""
        while IFS= read -r LINE; do
            [ -n "$LINE" ] || continue
            local D W N G B TH P A TOT
            D="${LINE%% *}"
            W="$(printf '%s' "$LINE" | grep -oE 'wifi=[0-9]+' | grep -oE '[0-9]+')"
            N="$(printf '%s' "$LINE" | grep -oE 'net=[0-9]+' | grep -oE '[0-9]+')"
            G="$(printf '%s' "$LINE" | grep -oE 'gpu=[0-9]+' | grep -oE '[0-9]+')"
            B="$(printf '%s' "$LINE" | grep -oE 'bt=[0-9]+' | grep -oE '[0-9]+')"
            TH="$(printf '%s' "$LINE" | grep -oE 'thermal=[0-9]+' | grep -oE '[0-9]+')"
            P="$(printf '%s' "$LINE" | grep -oE 'pm=[0-9]+' | grep -oE '[0-9]+')"
            A="$(printf '%s' "$LINE" | grep -oE 'audio=[0-9]+' | grep -oE '[0-9]+')"
            TOT="$(printf '%s' "$LINE" | grep -oE 'total=[0-9]+' | grep -oE '[0-9]+')"
            DAILY_ENTRIES="${DAILY_ENTRIES}{\"date\":\"$(json_str "$D")\",\"wifi\":${W:-0},\"net\":${N:-0},\"gpu\":${G:-0},\"bt\":${B:-0},\"thermal\":${TH:-0},\"pm\":${P:-0},\"audio\":${A:-0},\"total\":${TOT:-0}},"
        done < "$DAILY_LOG"
        [ -n "$DAILY_ENTRIES" ] && DAILY_JSON="[${DAILY_ENTRIES%,}]"
    fi

    # ── Eventos recientes ─────────────────────────────────────────────────────
    local EVENTS_JSON="[]"
    if [ -f "$EVENTS_LOG" ]; then
        local EV_ENTRIES=""
        while IFS= read -r LINE; do
            case "$LINE" in '=== '*) continue ;; esac
            case "$LINE" in [0-9][0-9][0-9][0-9]-*)
                local EV_TS EV_MSG EV_CAT
                EV_TS="${LINE%% *}"
                EV_MSG="${LINE#* }"
                local EV_LOWER
                EV_LOWER="$(printf '%s' "$EV_MSG" | tr '[:upper:]' '[:lower:]')"
                case "$EV_LOWER" in
                    *brcmf*|*wpa_supplicant*|*networkmanager*|*dhcp4*|*iwlwifi*)
                        EV_CAT="wifi" ;;
                    *gpu*|*drm*|*i915*)
                        EV_CAT="gpu" ;;
                    *pm:*|*suspend*|*resume*|*s2idle*)
                        EV_CAT="power" ;;
                    *thermal*|*acpi*|*applesmc*|*throttl*)
                        EV_CAT="thermal" ;;
                    *snd_hda*|*audio*|*pipewire*)
                        EV_CAT="audio" ;;
                    *bluetooth*|*btusb*|*hci*)
                        EV_CAT="bluetooth" ;;
                    *)
                        EV_CAT="other" ;;
                esac
                EV_ENTRIES="${EV_ENTRIES}{\"ts\":\"$(json_str "$EV_TS")\",\"category\":\"$(json_str "$EV_CAT")\",\"message\":\"$(json_str "$EV_MSG")\"},"
            ;; esac
        done < <(
            tail -n 80 "$EVENTS_LOG" 2>/dev/null |
                grep -Ev "$NOISY_EVENT_REGEX" |
                awk '!seen[$0]++ { lines[++n] = $0 } END { for (i = n; i >= 1; i--) print lines[i] }'
        )
        [ -n "$EV_ENTRIES" ] && EVENTS_JSON="[${EV_ENTRIES%,}]"
    fi

    # ── Inventario hardware ───────────────────────────────────────────────────
    _inv() { awk -v s="[$1]" '/^\[/{f=0} $0==s{f=1;next} f && NF{print;exit}' "$INVENTORY_LOG" 2>/dev/null || true; }
    local INV_CPU INV_MODEL INV_KERNEL INV_GPU INV_WIFI INV_WIFI_FW INV_BT INV_AUDIO INV_CAMERA
    INV_CPU="$(_inv cpu)"
    INV_MODEL="$(_inv apple_model)"
    INV_KERNEL="$(_inv kernel)"
    INV_GPU="$(_inv gpu)"
    INV_WIFI="$(_inv wifi_chip)"
    INV_WIFI_FW="$(_inv wifi_firmware)"
    INV_BT="$(_inv bluetooth_chip)"
    INV_AUDIO="$(_inv audio_card)"
    INV_CAMERA="$(_inv camera)"
    local INV_TS
    INV_TS="$(head -1 "$INVENTORY_LOG" 2>/dev/null | grep -oE '[0-9]{4}-[^ ]+' || printf '')"

    # ── Emitir JSON (escritura atómica) ───────────────────────────────────────
    local TMP_JSON
    TMP_JSON="$(mktemp "${BASE_DIR}/data.json.XXXXXX")"

    cat > "$TMP_JSON" <<JSONEOF
{
  "generated": "$(timestamp)",
  "severity": {
    "class": "$(json_str "$SEVERITY_CLASS")",
    "title": "$(json_str "$SEVERITY_TITLE")",
    "text": "$(json_str "$SEVERITY_TEXT")",
    "reason": "$(json_str "$SEVERITY_REASON")"
  },
  "counters": {
    "wifi": $WIFI_COUNT,
    "connectivity": $NET_COUNT,
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
    "cpu_perf": {
      "current_freqs": "$(json_str "$SNAP_CPU_FREQS")",
      "max_freq_mhz": ${SNAP_CPU_MAX:-null},
      "governor": "$(json_str "$SNAP_CPU_GOV")",
      "throttle_status": "$(json_str "$SNAP_CPU_THROTTLE")"
    },
    "memory": {
      "total_kb": ${SNAP_MEM_TOTAL:-null},
      "used_kb": ${SNAP_MEM_USED:-null},
      "available_kb": ${SNAP_MEM_AVAIL:-null},
      "swap_used_kb": ${SNAP_SWAP_USED:-0}
    },
    "temperatures": $TEMPS_JSON,
    "fan_rpm": "$(json_str "$FAN_RPM")"
  },
  "inventory": {
    "captured": "$(json_str "$INV_TS")",
    "cpu": "$(json_str "$INV_CPU")",
    "apple_model": "$(json_str "$INV_MODEL")",
    "kernel": "$(json_str "$INV_KERNEL")",
    "gpu": "$(json_str "$INV_GPU")",
    "wifi_chip": "$(json_str "$INV_WIFI")",
    "wifi_firmware": "$(json_str "$INV_WIFI_FW")",
    "bluetooth": "$(json_str "$INV_BT")",
    "audio": "$(json_str "$INV_AUDIO")",
    "camera": "$(json_str "$INV_CAMERA")"
  },
  "recent_events": $EVENTS_JSON,
  "daily_history": $DAILY_JSON
}
JSONEOF

    mv "$TMP_JSON" "$BASE_DIR/data.json"
}
```

### 2.4 Llamar a `generate_data_json()` desde `snapshot_loop()`

Localizar en `snapshot_loop()` la línea:
```bash
generate_report >/dev/null 2>&1 || true
```

Cambiar a:
```bash
generate_report >/dev/null 2>&1 || true      # mantener durante transición
generate_data_json >/dev/null 2>&1 || true   # nueva función, en paralelo
```

### Verificación de Fase 2

```bash
sudo systemctl restart mbp-watch.service
sleep 10

# Verificar que se genera data.json
ls -la /var/lib/mbp-watch/data.json

# Verificar que es JSON válido (si Python está disponible)
python3 -m json.tool /var/lib/mbp-watch/data.json | head -40

# Verificar que el CPU throttling aparece
python3 -m json.tool /var/lib/mbp-watch/data.json | grep -A 5 'cpu_perf'

# Verificar que report.html sigue funcionando (sin cambios)
curl -s http://localhost:7070/report.html | head -5
```

---

## Fase 3 — Crear los archivos web estáticos

**Objetivo:** construir `report.html`, `report.css`, `report.js` que consuman `data.json`.
El servicio no se toca en esta fase — se trabaja localmente con un `data.json` de muestra.

**Archivos nuevos:** `report.html`, `report.css`, `report.js` (en `~/mbp-watch-web/`)

### 3.1 Crear `data.json` de muestra para desarrollo

```bash
# Copiar el JSON real como fixture de desarrollo
cp /var/lib/mbp-watch/data.json ~/mbp-watch-web/data.json

# Servidor local para desarrollar el frontend
cd ~/mbp-watch-web
python3 -m http.server 8080
# Abrir http://localhost:8080/report.html en el navegador
```

### 3.2 `report.html` — shell mínimo

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MBP Watch</title>
  <link rel="stylesheet" href="report.css">
</head>
<body>
  <main id="app">
    <p style="color:#7d8590;padding:32px">Loading…</p>
  </main>
  <script src="report.js"></script>
</body>
</html>
```

### 3.3 `report.css` — estilos (dark theme)

Extraer y reorganizar el CSS del heredoc actual. Variables CSS para todos los colores:

```css
:root {
  --bg:        #0d1117;
  --surface:   #161b22;
  --surface2:  #1c2128;
  --border:    #30363d;
  --text:      #e6edf3;
  --muted:     #7d8590;
  --accent:    #4493f8;

  --ok:        #3fb950;  --ok-bg:   #0d1f14;  --ok-border:   #1a3327;
  --warn:      #d29922;  --warn-bg: #271d05;  --warn-border: #2d2415;
  --error:     #f85149;  --err-bg:  #2d0f10;  --err-border:  #3d1318;
}

/* ... resto de estilos reorganizados ... */
```

### 3.4 `report.js` — lógica frontend

Estructura modular en vanilla JS (sin build step, sin import maps complejos):

```javascript
// report.js — MBP Watch frontend
'use strict';

const REFRESH_MS = 5000;
const KEY_DETAILS = 'mbpw-details';
const KEY_AUDIO   = 'mbpw-audio';

// ── Helpers de render ──────────────────────────────────────────────────────

function esc(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function badge(status) {
  const map = {
    OK:    ['ok-bg',   'ok',   'OK'],
    WARN:  ['warn-bg', 'warn', 'WARN'],
    ERROR: ['err-bg',  'error','ERROR'],
  };
  const [bg, color, label] = map[status] ?? ['surface2', 'muted', status];
  return `<span class="badge badge-${color}">${label}</span>`;
}

function severityBanner(d) { /* ... */ }
function metricCards(c, throttle)  { /* ... */ }
function driverHealth(dh)  { /* ... */ }
function cpuPerfPanel(cpu) { /* ... */ }   // NUEVO
function temperaturePanel(temps, fan) { /* ... */ }
function batteryCard(bat)  { /* ... */ }
function wifiLinkCard(wl)  { /* ... */ }
function eventsPanel(events) { /* ... */ }
function dailyChart(history) { /* ... */ }
function inventoryPanel(inv) { /* ... */ }

// ── Render principal ───────────────────────────────────────────────────────

function render(data) {
  document.getElementById('app').innerHTML = `
    ${header(data)}
    ${severityBanner(data.severity)}
    <section class="section">${metricCards(data.counters)}</section>
    <section class="section">${driverHealth(data.driver_health)}</section>
    <section class="section live-row">
      <div class="live-left">
        ${temperaturePanel(data.snapshot.temperatures, data.snapshot.fan_rpm)}
        ${cpuPerfPanel(data.snapshot.cpu_perf)}
      </div>
      <div class="live-right">
        ${batteryCard(data.snapshot.battery)}
        ${wifiLinkCard(data.snapshot.wifi_link)}
      </div>
    </section>
    <section class="section">${eventsPanel(data.recent_events)}</section>
    <section class="section">${dailyChart(data.daily_history)}</section>
    <section class="section">${inventoryPanel(data.inventory)}</section>
  `;
  restoreDetails();
}

// ── Fetch loop ─────────────────────────────────────────────────────────────

let lastTotal = null;

async function refresh() {
  try {
    const res  = await fetch(`data.json?t=${Date.now()}`);
    const data = await res.json();

    if (lastTotal !== null && data.counters.total > lastTotal) {
      playAlert(data.severity.class === 'critical');
    }
    lastTotal = data.counters.total;

    saveDetails();
    render(data);
  } catch (e) { /* no interrumpir el loop si falla una vez */ }
  setTimeout(refresh, REFRESH_MS);
}

refresh();
```

**Nota sobre `cpuPerfPanel()`** — función nueva específica para throttling:

```javascript
function cpuPerfPanel(cpu) {
  if (!cpu || !cpu.throttle_status) return '';

  const isThrottling = cpu.throttle_status.startsWith('THROTTLING');
  const ratio = cpu.throttle_status.match(/ratio=(\d+)%/)?.[1] ?? '?';
  const gov   = cpu.governor ?? 'unknown';

  // Alerta si el governor no es el esperado en CachyOS (schedutil/performance)
  const govOk = ['schedutil', 'performance'].includes(gov);

  return `
    <div class="panel cpu-perf-panel ${isThrottling ? 'panel-warn' : ''}">
      <div class="panel-header">
        <span class="panel-title">CPU Performance</span>
        ${isThrottling
          ? `<span class="badge badge-warn">THROTTLING ${ratio}%</span>`
          : `<span class="badge badge-ok">OK ${ratio}%</span>`}
      </div>
      <div class="cpu-perf-grid">
        <div class="kv">
          <span class="kv-key">Governor</span>
          <span class="kv-val ${govOk ? '' : 'text-warn'}">${esc(gov)}</span>
        </div>
        <div class="kv">
          <span class="kv-key">Max freq</span>
          <span class="kv-val">${esc(cpu.max_freq_mhz)} MHz</span>
        </div>
        <div class="kv kv-wide">
          <span class="kv-key">Current</span>
          <span class="kv-val ${isThrottling ? 'text-warn' : ''}">${esc(cpu.current_freqs)}</span>
        </div>
      </div>
    </div>
  `;
}
```

### 3.5 Añadir "CPU Performance" como tarjeta de métrica

En `metricCards()`, añadir una octava tarjeta junto a las 7 actuales:

```javascript
// throttle = data.counters.throttle
const throttleCard = `
  <div class="metric-card ${throttle > 0 ? 'metric-card-warn' : ''}">
    <div class="metric-label">CPU THROTTLE</div>
    <div class="metric-value ${throttle > 0 ? 'text-warn' : 'text-muted'}">
      ${throttle > 0 ? throttle : '—'}
    </div>
    <div class="metric-sub">events</div>
  </div>
`;
```

### Verificación de Fase 3

```bash
cd ~/mbp-watch-web
python3 -m http.server 8080
# Abrir http://localhost:8080 en el navegador
# Verificar todas las secciones visualmente con data.json de muestra
# Simular throttling: cambiar cpu_perf.throttle_status en data.json manualmente
```

---

## Fase 4 — Desplegar y eliminar el heredoc

**Objetivo:** poner en producción el frontend estático y eliminar `generate_report()` del bash.

### 4.1 Copiar archivos al state dir

Añadir a `deploy_mbp_watch.sh`:

```bash
WEB_ASSETS_DIR="$SCRIPT_DIR/../web"   # o donde estén los archivos
TARGET_STATE_DIR="${MBP_WATCH_DIR:-/var/lib/mbp-watch}"

echo "Copiando archivos web estáticos..."
for F in report.html report.css report.js; do
    if [ -f "$WEB_ASSETS_DIR/$F" ]; then
        cp "$WEB_ASSETS_DIR/$F" "$TARGET_STATE_DIR/$F"
    else
        echo "AVISO: no encontrado $WEB_ASSETS_DIR/$F"
    fi
done
```

### 4.2 En `snapshot_loop()` — eliminar la llamada a `generate_report()`

```bash
# ELIMINAR esta línea:
generate_report >/dev/null 2>&1 || true

# DEJAR solo:
generate_data_json >/dev/null 2>&1 || true
```

### 4.3 En `capture_initial_report()` — actualizar

```bash
capture_initial_report() {
    capture_hardware_inventory
    capture_driver_health
    capture_snapshot
    generate_data_json >/dev/null 2>&1 || true   # era generate_report
    log_status "watch started"
}
```

### 4.4 Eliminar las funciones obsoletas

Marcar para borrar en el script:
- `generate_report()` (~200 líneas)
- `render_events_html()`
- `render_inventory_html()`
- `render_snapshot_html()`
- `render_temperature_fans_html()`
- `render_kv_card()`
- `render_daily_history_html()`
- `html_escape()`
- `humanize_snapshot_section_title()`
- `humanize_inventory_section_title()`
- `humanize_driver_health_section_title()`
- `temperature_state_class()`

Ahorro aproximado: **~350 líneas** de bash eliminadas.

### 4.5 Actualizar `status_watch()` y `report.txt`

`report.txt` (AI digest) no cambia — seguir generándolo como hasta ahora dentro de `generate_data_json()` o en una función separada `generate_ai_digest()`.

### Verificación de Fase 4

```bash
sudo bash deploy_mbp_watch.sh deploy

# Verificar que el nuevo report.html funciona
curl -s http://localhost:7070/report.html | head -10
# Debe mostrar el HTML estático (sin variables bash embebidas)

# Verificar que data.json se actualiza
watch -n 3 'stat -c "%y" /var/lib/mbp-watch/data.json'

# Verificar que report.html ya NO se regenera
watch -n 3 'stat -c "%y" /var/lib/mbp-watch/report.html'
# El timestamp de report.html no debe cambiar

# Test de throttling: estresar la CPU y ver si cambia el dashboard
stress-ng --cpu 2 --timeout 30s &
sleep 10
python3 -m json.tool /var/lib/mbp-watch/data.json | grep -A 5 cpu_perf
```

---

## Fase 5 — Mejoras incrementales de presentación

**Objetivo:** mejorar el dashboard visual una vez que la arquitectura es sólida.
Cada mejora es independiente — se puede hacer en cualquier orden.

### 5.A Sparkline de señal Wi-Fi

**Backend:** añadir a `capture_snapshot()`:
```bash
printf '\n[wifi_signal_point]\n'
# Guarda un punto de la serie temporal de señal
local SIG_FILE="$BASE_DIR/wifi_signal.tsv"
if [ -n "$WIFI_IF" ]; then
    local SIG_NOW
    SIG_NOW="$(iw dev "$WIFI_IF" link 2>/dev/null | grep 'signal:' | grep -oE '\-[0-9]+' | head -1 || true)"
    if [ -n "$SIG_NOW" ]; then
        printf '%s\t%s\n' "$(date +%s)" "$SIG_NOW" >> "$SIG_FILE"
        # Mantener solo los últimos 120 puntos (~10 minutos a 5s de intervalo)
        tail -n 120 "$SIG_FILE" > "${SIG_FILE}.tmp" && mv "${SIG_FILE}.tmp" "$SIG_FILE"
        printf 'latest_dbm: %s\n' "$SIG_NOW"
    fi
fi
```

**Frontend:** leer `wifi_signal_series` en `data.json` y renderizar un SVG inline mínimo.

### 5.B Sparkline de CPU freq (detectar patrones de throttling)

Similar al de Wi-Fi: `cpu_freq.tsv` con `timestamp\tfreq_mhz`.
El sparkline en el panel CPU Performance muestra si el throttling fue puntual o sostenido.

### 5.C Detección de suspend/resume con resultado

**Backend:** en `journal_loop()`, añadir log de eventos de suspend/resume:
```bash
# Filtro adicional para resume events
RESUME_LOG="$BASE_DIR/suspend_resume.log"
journalctl -f -o short-iso --no-pager 2>&1 |
    grep -Ei 'PM: suspend|PM: resume|systemd-sleep' |
    while IFS= read -r LINE; do
        printf '%s\n' "$LINE" >> "$RESUME_LOG"
        prune_log_file "$RESUME_LOG" 200
    done
```

**Frontend:** tabla en el dashboard: fecha/hora de cada suspend, duración, si Wi-Fi se recuperó.

### 5.D Indicadores de calidad de enlace Wi-Fi

En `wifiLinkCard()`:
- Si `tx_retries` > 50 → badge WARN "high retries"
- Si `signal_dbm` < -75 → color rojo en el valor de señal  
- Si `power_save` = "on" → badge informativo (puede causar latencia)

### 5.E Governor alert

En el header o en el panel CPU Performance:
- Si `governor !== 'schedutil' && governor !== 'performance'` → banner de aviso visible
- Mensaje: "CPU governor is `powersave` — dev performance may be degraded"

---

## Resumen de cambios por archivo

### `mbp_watch.sh`

| Función | Acción |
|---|---|
| `capture_snapshot()` | **AMPLIAR** con `[cpu_perf]` y `[memory_parsed]` |
| `FAILURE_EVENT_REGEX` | **AMPLIAR** con throttling patterns |
| `update_daily_summary()` | **AMPLIAR** con `throttle=N` counter |
| `generate_data_json()` | **AÑADIR** (nueva función, ~150 líneas) |
| `json_str()` | **AÑADIR** (helper de escape JSON) |
| `get_cpu_perf_field()` | **AÑADIR** (helper de extracción) |
| `generate_report()` | **ELIMINAR** (en Fase 4) |
| `render_*_html()` (7 funciones) | **ELIMINAR** (en Fase 4) |
| `html_escape()` | **ELIMINAR** (en Fase 4) |
| `humanize_*()` (3 funciones) | **ELIMINAR** (en Fase 4) |
| `temperature_state_class()` | **ELIMINAR** (en Fase 4) |
| `snapshot_loop()` | **MODIFICAR** llamada a generate |
| `capture_initial_report()` | **MODIFICAR** llamada a generate |

### Archivos nuevos

| Archivo | Ubicación | Descripción |
|---|---|---|
| `report.html` | `assets/diagnostics/web/` | Shell HTML estático |
| `report.css`  | `assets/diagnostics/web/` | Estilos, dark theme con variables CSS |
| `report.js`   | `assets/diagnostics/web/` | Fetch + render de data.json |

### `deploy_mbp_watch.sh`

Añadir copia de `report.html`, `report.css`, `report.js` al state dir.

---

## Orden de ejecución recomendado

```
Fase 0 — Preparación        (15 min)   — sin riesgo
Fase 1 — Nuevos datos       (2-3 h)    — sin riesgo (solo añade bloques)
Fase 2 — generate_data_json (3-4 h)    — sin riesgo (coexiste con generate_report)
Fase 3 — Frontend web       (4-6 h)    — sin riesgo (desarrollo local)
Fase 4 — Despliegue/limpieza (1 h)     — requiere test previo en Fase 3
Fase 5 — Mejoras            (incremental) — sin riesgo
```

Las Fases 1 y 2 se pueden hacer en la misma sesión sin parar el servicio en producción.
La Fase 4 es el único momento de "corte" real — dura menos de 1 minuto con `deploy_mbp_watch.sh`.

---

## Fase 6 — Notificaciones de escritorio (KDE Plasma)

**Objetivo:** cuando mbp-watch detecta un evento crítico, lanzar una notificación nativa
en el escritorio de KDE — visible aunque el navegador esté cerrado o minimizado.

### Por qué es un reto técnico

mbp-watch corre como **root en un servicio systemd**, pero las notificaciones de escritorio
van ligadas a la **sesión gráfica del usuario** (D-Bus de sesión, no D-Bus de sistema).
Hay que cruzar ese puente de forma explícita.

### Solución recomendada: `notify-send` vía `/run/user/UID/bus`

```bash
# Función para enviar notificación al usuario gráfico desde root/systemd
notify_desktop() {
    local TITLE="$1"
    local BODY="$2"
    local URGENCY="${3:-normal}"   # normal | critical
    local ICON="${4:-utilities-system-monitor}"

    # Buscar el usuario con sesión gráfica activa
    local GRAPHICAL_USER GRAPHICAL_UID
    GRAPHICAL_USER="$(who 2>/dev/null | grep -E '\(:[0-9]' | head -1 | awk '{print $1}')"
    [ -n "$GRAPHICAL_USER" ] || return 0   # nadie conectado, no enviar

    GRAPHICAL_UID="$(id -u "$GRAPHICAL_USER" 2>/dev/null)" || return 0

    # Usar el bus de sesión del usuario (disponible sin contraseña para root)
    local USER_BUS="unix:path=/run/user/${GRAPHICAL_UID}/bus"
    [ -S "/run/user/${GRAPHICAL_UID}/bus" ] || return 0   # sesión no iniciada

    DBUS_SESSION_BUS_ADDRESS="$USER_BUS" \
    sudo -u "$GRAPHICAL_USER" \
        notify-send \
            --urgency="$URGENCY" \
            --icon="$ICON" \
            --app-name="MBP Watch" \
            --expire-time=$([ "$URGENCY" = "critical" ] && printf '0' || printf '8000') \
            "$TITLE" "$BODY" 2>/dev/null || true
}
```

`--expire-time=0` en urgencia `critical` hace que la notificación **no se cierre sola**
hasta que el usuario la descarte — muy útil para alertas de throttling sostenido o GPU hang.

### Cuándo enviar notificaciones

Añadir en `generate_data_json()`, después de calcular `SEVERITY_CLASS`:

```bash
# Archivo de estado para no re-notificar en cada ciclo
NOTIFY_STATE_FILE="$BASE_DIR/last_notify_severity"
LAST_NOTIFY="$(cat "$NOTIFY_STATE_FILE" 2>/dev/null || printf 'ok')"

# Solo notificar cuando la severidad EMPEORA (ok→warn, warn→critical, ok→critical)
# No re-notificar si la severidad ya era esa misma desde el ciclo anterior
if [ "$SEVERITY_CLASS" = "critical" ] && [ "$LAST_NOTIFY" != "critical" ]; then
    notify_desktop \
        "MBP Watch — Critical Issues" \
        "$SEVERITY_REASON" \
        "critical" \
        "dialog-error"
    printf '%s' "critical" > "$NOTIFY_STATE_FILE"

elif [ "$SEVERITY_CLASS" = "warn" ] && [ "$LAST_NOTIFY" = "ok" ]; then
    notify_desktop \
        "MBP Watch — Warning" \
        "$SEVERITY_REASON" \
        "normal" \
        "dialog-warning"
    printf '%s' "warn" > "$NOTIFY_STATE_FILE"

elif [ "$SEVERITY_CLASS" = "ok" ] && [ "$LAST_NOTIFY" != "ok" ]; then
    # Recuperación: notificar que el sistema volvió a estable
    notify_desktop \
        "MBP Watch — Stable" \
        "All hardware errors resolved." \
        "low" \
        "dialog-information"
    printf '%s' "ok" > "$NOTIFY_STATE_FILE"
fi
```

### Notificaciones específicas de throttling

El throttling merece notificación propia porque no siempre eleva la severidad general:

```bash
# En generate_data_json(), tras calcular THROTTLE_COUNT:
THROTTLE_NOTIFIED_FILE="$BASE_DIR/throttle_notified"
THROTTLE_NOTIFIED="$(cat "$THROTTLE_NOTIFIED_FILE" 2>/dev/null || printf '0')"

if [ "$THROTTLE_COUNT" -ge 3 ] && [ "$THROTTLE_NOTIFIED" != "1" ]; then
    # Incluir frecuencia actual para que el usuario sepa cuánto está bajando
    local CURRENT_THROTTLE_DETAIL
    CURRENT_THROTTLE_DETAIL="$(get_cpu_perf_field 'throttle_status')"
    notify_desktop \
        "MBP Watch — CPU Throttling" \
        "CPU throttling detected: ${CURRENT_THROTTLE_DETAIL}. Check temperature panel." \
        "critical" \
        "temperature"
    printf '1' > "$THROTTLE_NOTIFIED_FILE"
elif [ "$THROTTLE_COUNT" -lt 1 ]; then
    printf '0' > "$THROTTLE_NOTIFIED_FILE"   # reset cuando se resuelve
fi
```

### Notificación de governor inesperado

Esta es una alerta de baja urgencia pero muy accionable:

```bash
# En generate_data_json(), tras leer SNAP_CPU_GOV:
GOV_WARNED_FILE="$BASE_DIR/governor_warned"
LAST_GOV_WARNED="$(cat "$GOV_WARNED_FILE" 2>/dev/null || printf '')"

case "$SNAP_CPU_GOV" in
    schedutil|performance|powersave)
        ;;   # governors normales, no notificar powersave (puede ser intencional)
    conservative|userspace|ondemand)
        if [ "$LAST_GOV_WARNED" != "$SNAP_CPU_GOV" ]; then
            notify_desktop \
                "MBP Watch — CPU Governor Changed" \
                "Governor is now '${SNAP_CPU_GOV}'. Expected: schedutil or performance." \
                "normal" \
                "cpu"
            printf '%s' "$SNAP_CPU_GOV" > "$GOV_WARNED_FILE"
        fi
        ;;
esac
```

### Dependencias y verificación

```bash
# Verificar que notify-send está instalado
pacman -Q libnotify 2>/dev/null || echo "AVISO: instalar libnotify"

# Test manual desde terminal (como root, con sesión gráfica activa)
GRAPHICAL_UID=$(id -u gtx)
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${GRAPHICAL_UID}/bus" \
sudo -u gtx notify-send --urgency=critical "MBP Watch Test" "Notificación de prueba"

# Verificar que llega a KDE Plasma
# Debería aparecer en la esquina superior derecha (o según config de KDE Notifications)
```

### Personalizar en KDE

Las notificaciones de `notify-send` con `--app-name="MBP Watch"` aparecen en:
- **Centro de notificaciones** de KDE (campana en la barra de tareas)
- Las notificaciones `critical` (expire-time=0) abren un popup modal hasta que se cierra

Para personalizar comportamiento: **Ajustes del sistema → Notificaciones → Configurar notificaciones por aplicación** — buscar "MBP Watch".

---

## Plan de tareas

Lista de tareas ordenada y con dependencias claras. Cada tarea es independiente dentro de su fase.

### Fase 1 — Nuevos datos en el backend

- [x] **1.1** Añadir bloque `[cpu_perf]` a `capture_snapshot()` con current\_freq, max\_freq, governor, throttle\_status
- [x] **1.2** Añadir bloque `[memory_parsed]` a `capture_snapshot()` parseando `/proc/meminfo`
- [x] **1.3** Ampliar `FAILURE_EVENT_REGEX` con patrones de throttling CPU/thermal
- [x] **1.4** Añadir `throttle=N` al counter de `update_daily_summary()`
- [ ] **1.5** Verificar con `grep '[cpu_perf]' /var/lib/mbp-watch/snapshots.log` que los datos aparecen

### Fase 2 — Generación de `data.json`

- [x] **2.1** Añadir función `json_str()` al script
- [x] **2.2** Añadir función `get_cpu_perf_field()` al script
- [x] **2.3** Implementar `generate_data_json()` completa
- [x] **2.4** Añadir llamada a `generate_data_json()` en `snapshot_loop()` (junto a `generate_report()`, en paralelo)
- [x] **2.5** Añadir llamada a `generate_data_json()` en `capture_initial_report()`
- [x] **2.6** Verificar que `data.json` es JSON válido: `python3 -m json.tool /var/lib/mbp-watch/data.json`
- [x] **2.7** Verificar que `data.json` incluye `cpu_perf.throttle_status` y `memory`

### Fase 3 — Frontend web

- [x] **3.1** Crear directorio `assets/diagnostics/web/`
- [x] **3.2** Crear `report.html` (shell mínimo con link a css y js)
- [x] **3.3** Extraer y reorganizar CSS del heredoc actual → `report.css` con variables CSS
- [x] **3.4** Implementar `report.js`: función `render(data)` y fetch loop
- [x] **3.5** Implementar `severityBanner()` en JS
- [x] **3.6** Implementar `metricCards()` en JS (incluye tarjeta CPU THROTTLE)
- [x] **3.7** Implementar `driverHealth()` en JS con badges coloreados
- [x] **3.8** Implementar `cpuPerfPanel()` en JS con alerta de throttling y governor
- [x] **3.9** Implementar `temperaturePanel()` en JS con barras de progreso por umbral
- [x] **3.10** Implementar `batteryCard()` en JS con barra de progreso
- [x] **3.11** Implementar `wifiLinkCard()` en JS con colores por señal dBm
- [x] **3.12** Implementar `eventsPanel()` en JS con filtros por categoría
- [x] **3.13** Implementar `dailyChart()` en JS con barras SVG por categoría
- [x] **3.14** Implementar `inventoryPanel()` en JS
- [ ] **3.15** Test completo en `localhost:8080` con `data.json` de muestra
- [ ] **3.16** Test simulando severidad `critical` editando `data.json` manualmente
- [ ] **3.17** Test simulando `cpu_perf.throttle_status = "THROTTLING ratio=45%"` manualmente

### Fase 4 — Despliegue y limpieza

- [x] **4.1** Actualizar `deploy_mbp_watch.sh` para copiar `web/report.{html,css,js}` al state dir
- [x] **4.2** En `snapshot_loop()`: eliminar llamada a `generate_report()`, dejar solo `generate_data_json()`
- [x] **4.3** En `capture_initial_report()`: cambiar `generate_report()` por `generate_data_json()`
- [x] **4.4** Eliminar funciones obsoletas: `generate_report()`, `render_*_html()` (7), `html_escape()`, `humanize_*()` (3), `temperature_state_class()`
- [ ] **4.5** Ejecutar `deploy_mbp_watch.sh deploy` y verificar que el servicio arranca
- [ ] **4.6** Verificar que `report.html` es el nuevo frontend (no el heredoc bash)
- [ ] **4.7** Verificar que `report.html` no se regenera cada 5 s (timestamp fijo)
- [ ] **4.8** Test de stress: `stress-ng --cpu 2 --timeout 60s` y comprobar que aparece throttling en el dashboard

### Fase 5 — Mejoras de presentación

- [ ] **5.A.1** Añadir serie temporal de señal Wi-Fi: append a `wifi_signal.tsv` en cada snapshot
- [ ] **5.A.2** Incluir últimos N puntos de señal en `data.json` como `wifi_signal_series`
- [ ] **5.A.3** Renderizar sparkline SVG inline en `wifiLinkCard()`
- [ ] **5.B.1** Añadir serie temporal de CPU freq: append a `cpu_freq.tsv`
- [ ] **5.B.2** Renderizar sparkline en `cpuPerfPanel()`
- [x] **5.C.1** Añadir indicadores de calidad de enlace: alerta si `tx_retries > 50`
- [x] **5.C.2** Color de señal Wi-Fi por rango dBm (verde/ámbar/rojo)
- [x] **5.D.1** Banner de alerta si governor es inesperado

### Fase 6 — Notificaciones de escritorio

- [ ] **6.1** Verificar que `libnotify` está instalado: `pacman -Q libnotify`
- [ ] **6.2** Test manual de `notify-send` desde root con D-Bus de sesión del usuario
- [ ] **6.3** Añadir función `notify_desktop()` al script
- [ ] **6.4** Añadir lógica de notificación por severidad en `generate_data_json()`
- [ ] **6.5** Añadir notificación específica de throttling sostenido (≥3 eventos)
- [ ] **6.6** Añadir notificación de governor inesperado
- [ ] **6.7** Test completo: provocar throttling, verificar que llega la notificación a KDE
- [ ] **6.8** Verificar que las notificaciones `critical` no se cierran solas (`--expire-time=0`)

### Paso final — Actualizar `assets/diagnostics/deploy_mbp_watch.sh`

> Ejecutar solo cuando Fases 3 y 4 estén completas y los archivos web existan en `assets/diagnostics/web/`.

- [x] **F.1** Añadir al script la copia de los archivos web estáticos al state dir:

```bash
WEB_DIR="$SCRIPT_DIR/web"
for F in report.html report.css report.js; do
    if [ -f "$WEB_DIR/$F" ]; then
        cp "$WEB_DIR/$F" "$STATE_DIR/$F"
    else
        echo "AVISO: no encontrado $WEB_DIR/$F"
    fi
done
```

- [ ] **F.2** Verificar que tras el deploy el navegador carga el nuevo `report.html` estático
- [ ] **F.3** Verificar que `report.html` no se regenera cada 5 s (timestamp fijo en disco)
- [ ] **F.4** Verificar que `data.json` sí se actualiza cada 5 s (timestamp cambiante)
- [x] **F.5** Ejecutar `bash -n assets/diagnostics/deploy_mbp_watch.sh` para validar sintaxis
