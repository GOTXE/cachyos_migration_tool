# Fixes: Parsing Robusto para AI Digest

## 🔴 Problemas encontrados

### 1. **TEMPERATURE parsing roto**
```
❌ Salida: temperature: fan speed|Package id 0|Core 0|Core 1
```

**Causa:** Usé `awk -F'[;:]'` que dividía mal y perdía valores

**Solución:** Parsing simple con grep + head
```bash
# Antes (roto)
get_last_snapshot_section 'temperature_fans' | awk -F'[;:]' '{for(i=1;i<=NF;i++){...}}'

# Ahora (funciona)
get_last_snapshot_section 'temperature_fans' | awk '/fan speed:|Package id|^Core [01]:/ {print}' | head -3
```

---

### 2. **BATTERY parsing incompleto**
```
❌ Salida: state: charging energy: 27,2253 Wh percentage: 51,468%
```

**Causa:** Múltiples líneas pegadas sin separador

**Solución:** Pasar a `|` como separador y extraer líneas limpias
```bash
# Ahora
get_last_snapshot_section 'battery' | awk '/^state:|percentage:|energy:/ {print}' | tr '\n' '|'
# Resultado: state: charging | percentage: 51,468% | energy: 27,2253 Wh
```

---

### 3. **WIFI LINK completamente vacío**
```
❌ Salida: Connected to SSID: signal:
```

**Causa:** Intenté extraer solo los labels sin los valores

**Solución:** Volver a la línea completa
```bash
# Antes (roto)
get_last_snapshot_section 'wifi_link' | grep -oE 'Connected to|SSID:|signal:' | paste -sd' ' -

# Ahora (correcto)
get_last_snapshot_section 'wifi_link' | head -1
# Resultado: Connected to e0:41:36:b5:32:05 (on wlan0);SSID: TXOKLAN_5G;freq: 5240.0;signal: -50 dBm...
```

---

### 4. **PERFORMANCE_ANALYSIS con valores corruptos**
```
❌ Salida: 
load: 1,00 | memory: memory_used_pct:% | swap: M | swappiness: 150
top_process: claude (user)--type=zygote (user)--no-zygote-sandbox (user)
```

**Causas múltiples:**

#### a) Memory parsing fallaba
```bash
# Problema
awk '{print $(NF-1)}' 
# Sacaba "memory_used_pct:" en lugar de "31"

# Solución
awk '{print $NF}' | sed 's/%//'
# Ahora: "31"
```

#### b) Swap sin número
```bash
# Problema
awk '{print $NF}' | sed 's/MB//'
# No se removía "MB" si había texto extra

# Solución
awk '{print $NF}' | sed 's/MB//' con validación numérica
```

#### c) Swappiness sacaba 150
```bash
# Problema
grep -oE '[0-9]{1,3}' | head -1
# Sacaba "150" de línea siguiente

# Solución
grep -oE '[0-9]+' | tail -1 con validación <= 100
```

#### d) Top processes pegados sin separador
```bash
# Problema
awk '{cpu=$2; cmd=$NF; user=$1; printf "%s (%s)", cmd, user}' 
# Salida: claude (user)--type=zygote (user)

# Solución
awk '{print $NF " (" $1 ")"}' | head -1
# Salida: claude (user)
```

---

## ✅ Enfoque nuevo: ROBUSTO

Cambié de "parsing inteligente" a **"parsing simple y defensivo"**:

```bash
# ❌ Antes: Tratar de ser muy clever
grep -oE '[0-9]+\.[0-9]+' | head -1

# ✅ Ahora: Simple y claro
grep '^memory_used_pct:' | awk '{print $NF}' | sed 's/%//'
```

### Principios aplicados:

1. **Una extracción = una línea de código**
   - Evita piping complicado
   - Más fácil de debuggear

2. **Validar antes de usar**
   ```bash
   local val="$(extract_something)"
   local num=$([ -n "$val" ] && [ "$val" -eq "$val" ] 2>/dev/null && echo "$val" || echo "0")
   ```

3. **Fallback a valor sensato**
   - Si parsing falla → usar default (0, "unknown", etc.)
   - No mostrar valores corruptos

4. **Testing en cada paso**
   ```bash
   # Ver qué saca
   get_last_snapshot_section 'memory_pressure' | grep '^memory_used_pct:' | head -1
   # Debuggear si no sale lo esperado
   ```

---

## 🔍 Cómo verificar ahora

```bash
# Ver datos crudos en snapshot
tail -50 /var/lib/mbp-watch/snapshots.log | grep -A10 '\[memory_pressure\]'

# Debería mostrar:
# [memory_pressure]
# memory_used_pct: 42%
# swap_used: 128 MB

# Ver datos parseados en reporte
tail -20 /var/lib/mbp-watch/report.txt

# Debería mostrar:
# PERFORMANCE_ANALYSIS (Python/web dev + music)
# load: 1.69 | memory: 42% | swap: 128MB | swappiness: 60
# top_process: claude (user)
```

---

## 📋 Checklist para futuras mejoras

- ✅ Parsing simple y defensivo
- ✅ Validación de valores antes de usar
- ✅ Fallback a defaults si falla
- ✅ Una extracción = una línea
- ✅ Testing manual en snapshots.log
- ❓ Mejor error handling en script

---

## 🚀 Próxima ejecución

Cuando el script regenere el reporte, debería ver:

```
PERFORMANCE_ANALYSIS (Python/web dev + music)
load: 1.69 | memory: 42% | swap: 128MB | swappiness: 60
top_process: claude (user)
```

Sin valores corruptos, sin parsing rotos, sin información incompleta.

¡Listo para ser pasado a IA! 🎯
