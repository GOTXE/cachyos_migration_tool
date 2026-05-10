#!/usr/bin/env bash
# Estresar los 4 núcleos al 100% hasta que se mate el proceso (Ctrl+C).
# Uso: sudo bash stress_cpu.sh
# Para parar: Ctrl+C o kill <pid>

CORES=4

cleanup() {
    echo ""
    echo "Parando workers..."
    kill "${PIDS[@]}" 2>/dev/null || true
    wait 2>/dev/null || true
    echo "Listo."
}
trap cleanup EXIT INT TERM

echo "Estresando ${CORES} núcleos al 100%. Ctrl+C para parar."
echo "Monitoriza en: http://localhost:7070/report.html"
echo ""

PIDS=()
for (( i=0; i<CORES; i++ )); do
    ( while :; do :; done ) &
    PIDS+=($!)
    echo "  Worker $i → PID ${PIDS[-1]}"
done

echo ""
echo "Temperatura actual:"
sensors 2>/dev/null | grep -E 'Core|Package' || echo "(sensors no disponible)"

echo ""
echo "--- Presiona Ctrl+C para detener ---"

while :; do
    sleep 10
    echo -n "$(date +%H:%M:%S) temps: "
    sensors 2>/dev/null | grep -oP '(?<=Package id 0:  \+)[0-9.]+' | head -1 | tr -d '\n'
    echo -n "°C | cpu_perf: "
    python3 -c "
import json
d=json.load(open('/var/lib/mbp-watch/data.json'))
c=d['snapshot']['cpu_perf']
print(c.get('throttle_status','?'), '|', c.get('current_freqs','?'))
" 2>/dev/null || echo "?"
done
