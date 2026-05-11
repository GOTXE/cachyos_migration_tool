# MBP-Watch: Performance Monitoring para Programación + Música

## Mejoras implementadas

El script `mbp_watch.sh` ha sido mejorado para capturar datos específicos de **rendimiento bajo carga**, optimizado para tu caso de uso:
- Programación Python/web
- Uso web normal  
- Música en background

---

## 📊 Nuevas métricas capturadas

### 1. **Load and Processes** (`[load_and_processes]`)
```
load_average: 1.23, 0.98, 0.75
context_switches: 12847
procs_created: 2341
top_cpu_processes: USER %CPU %MEM COMMAND
top_memory_processes: USER %CPU %MEM COMMAND
```

**Por qué importa:**
- `load_average`: Detecta contención de CPU durante compilaciones Python
- `context_switches`: Indica si hay thrashing de memoria/CPU
- **Top procesos**: Identifica qué consume recursos cuando todo se ralentiza

### 2. **I/O Performance** (`[io_performance]`)
Monitorea lecturas/escrituras de disco bajo compilación.

**Problema típico:** Python + npm/pip puede saturar I/O, ralentizando compilación

### 3. **Memory Pressure** (`[memory_pressure]`)
```
memory_used_pct: 48%
swap_used: 128 MB
```

**Por qué es crítico en MBP 2015:**
- 15GB RAM es suficiente PERO si subes a swap (disco), todo se ralentiza 10-100x
- Python + Firefox juntos pueden llenar memoria rápido

### 4. **Kernel Tuning** (`[kernel_tuning]`)
```
vm.swappiness = 60
dirty_pages = 1024 KB
vfs_cache_pressure = 100
```

**Estos valores impactan MUCHO en rendimiento:**
- `swappiness=60`: Demasiado alto → usa swap frecuentemente → lento
- `dirty_pages`: Decide cuándo hace flush a disco (afecta compilaciones)

---

## 🎯 Análisis enfocado en tu uso

El reporte ahora incluye una sección `PERFORMANCE_ANALYSIS` que analiza:

1. **¿Está throttleando?** → Temperatura + load average = contexto
2. **¿Qué consume CPU?** → Top procesos + load → identifica culpables
3. **¿Hay presión de memoria?** → swap_used + context_switches → si ambos altos = problema
4. **¿Qué esperar para música?** → Swappiness alto + load > 2 = posibles glitches de audio

---

## 📈 Dashboard web mejorado

Nueva tarjeta: **"System Load & Performance"**

Muestra en tiempo real:
- System load con color: 🟢 < 2 | 🟡 2-4 | 🔴 > 4
- Top procesos CPU/memoria
- Context switches (indicador de presión)

---

## 🔍 Cómo interpretarlo para optimización

### Escenario 1: Python compilation se ralentiza
```
load_average: 3.2, 2.1, 1.5  ← Load alto
top_cpu_processes: python 87%  ← Culpable identificado
swap_used: 512 MB  ← WARNING: usando swap!
```

**Acción:** Bajar `vm.swappiness` a 10-20 para evitar swap

### Escenario 2: Música con glitches
```
context_switches: 45000  ← MUY ALTO = thrashing
top_cpu_processes: firefox 65%, python 22%  ← Juntos consumen todo
memory_used_pct: 92%  ← Casi lleno
```

**Acciones:**
1. Cerrar tabs innecesarios en Firefox
2. Reducir load antes de compilar (esperar o matar proceso)
3. Aumentar frequencia de I/O flush (dirty_ratio bajo)

### Escenario 3: Todo "normal" pero lento
```
load_average: 1.5, 1.2, 1.0  ← Aparentemente bien
throttle_status: THROTTLING ratio=45%  ← AH! CPU a 45% max
temp: 85°C  ← Caliente
```

**Acciones:**
1. Limpiar polvo (ganancia: 10-15°C)
2. Repaste térmico (ganancia: 15-20°C)
3. Mejorar ventilación

---

## 📋 Checklist de optimización

Para sacar máximo rendimiento:

- [ ] Revisar `daily_errors.log` durante 3-7 días para patrones
- [ ] Ejecutar compilación típica (ej: `pip install -r requirements.txt`)
- [ ] Observar en dashboard: load, CPU temps, swap usage
- [ ] Si `swap_used > 100MB`: Bajar `vm.swappiness`
- [ ] Si temperatura > 80°C idle: Revisar ventiladores/polvo
- [ ] Si throttle activo: Buscar solución térmica

---

## 📡 Cómo usar el reporte para IA

El archivo `report.txt` está diseñado para feed directo a Claude/GPT:

```bash
# Ver reporte actual
cat /var/lib/mbp-watch/report.txt

# O con historial (7 días)
cat /var/lib/mbp-watch/daily_errors.log
```

**Ejemplo de prompt:**
```
Aquí está mi reporte de diagnostico MBP 2015 con CachyOS.
Programo en Python + web, escucho música.
¿Qué optimizaciones me recomiendas?

[pegar reporte.txt]
```

---

## ⚡ Tuning rápido recomendado

Para MBP 2015 con 15GB RAM + CachyOS + Python:

```bash
# Reducir agresividad de swap (crítico para compilación)
echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-mbp-optimization.conf

# Mejorar response time (menos glitches de audio)
echo "vm.vfs_cache_pressure=50" | sudo tee -a /etc/sysctl.d/99-mbp-optimization.conf

# Aplicar cambios
sudo sysctl -p /etc/sysctl.d/99-mbp-optimization.conf

# Verificar
cat /proc/sys/vm/swappiness
```

---

## 📌 Notas importantes

1. **El reporte es histórico**: `daily_errors.log` acumula datos día a día. Usa 7+ días para ver patrones reales.

2. **Contexto es clave**: Un `swap_used=100MB` con `load=1.0` es normal. Con `load=4.0` es problema.

3. **Música requiere latencia baja**: Si ves `context_switches > 20000`, espera a que compile termine antes de reproducir.

4. **Los datos se actualizan cada 5 segundos** (configurable con `MBP_WATCH_INTERVAL`)

---

## 🚀 Próximos pasos

1. Ejecutar: `sudo /path/to/mbp_watch.sh start`
2. Hacer trabajo normal (programación + música)
3. Esperar 1-2 días para acumular datos
4. Revisar `report.txt` o dashboard web en `http://localhost:7070`
5. Compartir reporte con IA para análisis profundo

¡Listo para optimizar! 🎵💻
