# MBP Watch KDE Plasmoid v1 — Mapeo técnico, contratos y tareas

## 1. Objetivo del documento

Dejar **cerrado el contrato técnico** entre:

- `mbp_watch.sh`
- `data.json`
- el futuro plasmoid KDE Plasma

para que la implementación posterior se reduzca a:

1. crear los componentes QML/JS,
2. conectarlos a este contrato,
3. instalar el plasmoid vía `bootstrap`.

Este documento no redefine la UX general. La UX base ya está fijada en:

- [mbp-watch-kde-plasmoid-v1-spec.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)

Aquí se fija:

- qué campos consume el plasmoid,
- qué campos son obligatorios,
- qué representación mínima tiene cada bloque,
- qué estado local debe gestionar el plasmoid,
- y cómo dividir el trabajo en tareas codificables.

---

## 2. Principio rector

## 2.1 Fuente única de verdad

El plasmoid no calcula métricas de sistema por su cuenta.

Consume:

- `/var/lib/mbp-watch/data.json`

La web y el plasmoid deben representar el mismo modelo.

## 2.2 Lo que sí puede decidir el plasmoid

El plasmoid sólo puede añadir lógica de **interfaz local**, por ejemplo:

- qué evento está leído/no leído,
- qué popup está abierto,
- cuándo lanzar una notificación KDE,
- cuándo cerrar automáticamente el popup,
- cómo compactar visualmente un bloque.

## 2.3 Lo que NO debe decidir el plasmoid

- severidad del sistema,
- clasificación de eventos,
- rangos de color funcionales,
- métricas derivadas del backend.

---

## 3. Contrato de entrada global

## 3.1 Ruta esperada

- `MBP_WATCH_DATA_PATH = /var/lib/mbp-watch/data.json`

## 3.2 Frecuencia de refresco inicial

Valor recomendado v1:

- refresco cada `5000 ms`

Debe ser configurable más adelante, pero no es requisito de cierre previo.

## 3.3 Comportamiento si falta `data.json`

El plasmoid debe entrar en estado:

- `loading`

y mostrar:

- placeholder discreto,
- sin errores invasivos,
- sin notificaciones.

## 3.4 Comportamiento si el JSON es inválido

Estado:

- `degraded`

Comportamiento:

- mantener la última lectura válida si existe,
- no vaciar bruscamente la UI,
- permitir abrir la web igualmente,
- no disparar nuevas alertas hasta tener una lectura válida.

---

## 4. Contrato de datos raíz

Campos raíz actuales:

- `generated`
- `state_dir`
- `severity`
- `counters`
- `driver_health`
- `snapshot`
- `inventory`
- `recent_events`
- `daily_history`

Para v1 del plasmoid:

- `inventory` se ignora en la UI inicial,
- el resto sí entra en el modelo del plasmoid.

## 4.1 Campos obligatorios mínimos para render útil

Obligatorios:

- `generated`
- `severity`
- `counters`
- `snapshot`
- `recent_events`

Secundarios pero esperados:

- `driver_health`
- `daily_history`

Ignorados inicialmente:

- `inventory`

---

## 5. Mapeo exacto por bloque

## 5.1 Bloque `severity`

### Origen JSON

- `severity.class`
- `severity.title`
- `severity.text`
- `severity.reason`

### Obligatorio

Sí, completo.

### Contrato visual

Debe producir:

- un estado global persistente,
- una línea principal,
- una razón breve.

### Reglas

- `severity.class` manda el tono visual global del bloque.
- valores actuales esperados:
  - `ok`
  - `warn`
  - `critical`

### Representación v1

- `title` visible siempre
- `text` visible siempre
- `reason` visible resumido o en segunda línea compacta

### Acciones

- abrir dashboard web

### Tarea de implementación

- crear `SeverityBlock.qml`
- entrada: objeto `severity`
- salida: bloque compacto sin lógica adicional

---

## 5.2 Bloque `counters`

### Origen JSON

- `counters.wifi`
- `counters.connectivity`
- `counters.gpu`
- `counters.bluetooth`
- `counters.thermal`
- `counters.pm`
- `counters.audio`
- `counters.throttle`
- `counters.total`

### Obligatorio

Sí.

### Etiquetas visibles exactas

- `wifi` → `WI-FI`
- `connectivity` → `CONNECTIVITY`
- `gpu` → `GPU / DRM`
- `bluetooth` → `BLUETOOTH`
- `thermal` → `THERMAL / ACPI`
- `pm` → `SUSPEND / PM`
- `audio` → `AUDIO / HW`
- `throttle` → `THROTTLE EVENTS`

### Contrato visual

Cada contador debe renderizar:

- etiqueta corta,
- valor,
- color base según valor,
- acento de evento no leído si aplica.

### Regla funcional

- valor `0` = estado limpio
- valor `> 0` = estado activo / resaltado

### Reglas de relación con eventos

Si hay un evento no leído asociado a una categoría, el bloque afectado debe mostrar:

- acento rojo,
- punto,
- o glow discreto

sin necesidad de enseñar el texto.

### Tarea de implementación

- crear `CountersBlock.qml`
- crear mapeo estable entre categorías de `recent_events` y contadores

### Tabla de relación inicial

- `wifi` event → `wifi` y/o `connectivity`
- `gpu` event → `gpu`
- `power` event → `pm`
- `thermal` event → `thermal` y/o `throttle` según severidad visible
- `audio` event → `audio`
- `bluetooth` event → `bluetooth`
- `other` event → no contador fijo, usar canal general de alerta

---

## 5.3 Bloque `snapshot`

## 5.3.1 Subbloque `snapshot.temperatures`

### Origen JSON

- `snapshot.temperatures[]`

Cada item:

- `label`
- `current_c`
- `high_c`
- `crit_c`

### Representación v1

- no lista larga completa
- sí temperatura principal visible
- sí semáforo/barras finas

### Regla de prioridad recomendada

Usar primero:

1. `CPU Package`
2. primera entrada disponible

### Tarea

- helper de selección de temperatura principal

## 5.3.2 Subbloque `snapshot.fan_rpm`

### Origen JSON

- `snapshot.fan_rpm`

### Tipo

Cadena como:

- `fan1: 1290 RPM`

### Representación v1

- texto visible compacto
- barra proporcional opcional

### Tarea

- helper de parseo de RPM numérica si se quiere barra

## 5.3.3 Subbloque `snapshot.cpu_perf`

### Origen JSON

- `current_freqs`
- `cpu_usage`
- `max_freq_mhz`
- `freq_ratio`
- `freq_headroom`
- `freq_state`
- `energy_mode`
- `governor`
- `throttle_status`
- `thermal_alarm`
- `prochot`
- `throttle_count_delta`
- `base_freq_mhz`

### Representación v1

Persistente:

- estado resumido CPU
- ratio o headroom
- throttle / prochot si aplica

Secundario:

- governor
- energy mode

### Regla funcional

Debe usarse la misma semántica visible que la web:

- `freq_state`
- `prochot`
- `throttle_count_delta`

### Tarea

- helper de resumen CPU:
  - `normal`
  - `warning`
  - `throttling`

## 5.3.4 Subbloque `snapshot.load_and_system`

### Origen JSON

- `load_average`
- `context_switches`
- `top_cpu_processes`
- `top_memory_processes`

### Representación v1

Persistente:

- load average
- context switches resumido si cabe

No persistente por defecto:

- top processes completos

### Tarea

- decidir si top processes se dejan para tooltip/popup futuro

## 5.3.5 Subbloque `snapshot.battery`

### Origen JSON

- `percentage`
- `state`
- `time_to_empty`
- `capacity_pct`
- `energy_wh`

### Representación v1

Persistente:

- porcentaje
- estado
- barra

Secundario:

- `time_to_empty`
- `capacity_pct`

### Tarea

- helper de color batería reutilizando lógica/umbral web

## 5.3.6 Subbloque `snapshot.wifi_link`

### Origen JSON

- `connected`
- `ssid`
- `signal_dbm`
- `freq_mhz`
- `tx_mbps`
- `rx_mbps`
- `tx_retries`
- `power_save`

### Representación v1

Persistente:

- estado conexión
- calidad de señal
- etiqueta corta `OK/WARN/ALERT`

Secundario:

- SSID
- bitrate
- retries

## 5.3.7 Subbloque `snapshot.wifi_analysis`

### Origen JSON

- `channel`
- `latency_ms`
- `packet_loss_pct`
- `interference_count`
- `ping_target`
- `scan_source`
- `signal_warn_dbm`
- `interference_signal_dbm`
- `nearby_networks`

### Representación v1

Persistente:

- latencia resumida si hay
- packet loss si hay
- interferencia si hay

No persistente:

- lista larga de redes cercanas

### Tarea

- helper de salud Wi-Fi compacta

---

## 5.4 Bloque `recent_events`

### Origen JSON

- `recent_events[]`

Cada item:

- `ts`
- `category`
- `message`

### Categorías actuales esperadas

- `wifi`
- `gpu`
- `power`
- `thermal`
- `audio`
- `bluetooth`
- `other`

### Regla visual principal

En vista persistente:

- no mostrar texto
- sí mostrar indicador visual

### Popup de detalle

Al hacer clic en un evento o indicador:

mostrar:

- categoría
- timestamp
- mensaje técnico
- botón copy
- botón mark read
- botón open dashboard

### Tiempo de vida del popup

- 30 segundos
- o cierre manual

### Formato recomendado para copy

Formato mínimo:

`[category] ts message`

### Identidad de evento

Clave lógica v1:

`ts + category + message`

### Estado local necesario

Por cada evento:

- `eventId`
- `read`
- `firstSeenAt`
- `lastNotifiedAt` opcional

### Regla de “nuevo evento”

Un evento es nuevo si:

- aparece en `recent_events`
- y su `eventId` no está en el almacén local como ya visto

### Regla de notificación KDE

Cuando aparece un evento nuevo:

- lanzar notificación KDE
- clic en notificación abre la web

### Agregación de notificaciones

Pendiente de decisión futura.

Si no se define otra cosa, la implementación inicial puede ser:

- una notificación por evento nuevo

### Tareas

- `EventsModel.js`
- `EventPopup.qml`
- `EventStore.js`
- `NotificationBridge`

---

## 5.5 Bloque `driver_health`

### Origen JSON

- `driver_health.captured`
- `driver_health.drivers[]`

Cada driver:

- `name`
- `status`
- `detail`
- `fix`

### Regla de alcance v1

Visible siempre, pero en forma compacta.

No mostrar:

- lista larga de fixes,
- texto enorme persistente.

Sí mostrar:

- nombre
- estado
- detalle corto

### Estados esperados

- `OK`
- `WARN`
- `ERROR`

### Tarea

- `DriverHealthBlock.qml`
- helper de compactación de detalle

---

## 5.6 Bloque `daily_history`

### Origen JSON

- `daily_history[]`

Cada item:

- `date`
- `wifi`
- `net`
- `gpu`
- `bt`
- `thermal`
- `pm`
- `audio`
- `throttle`
- `total`

### Regla de alcance v1

Visible siempre, pero compacto.

### Representación recomendada

- mini resumen de últimos N días
- N inicial recomendado: `7`

### No hacer en v1

- gráfica grande
- análisis histórico complejo

### Tarea

- `DailyHistoryBlock.qml`
- helper de slicing y normalización visual

---

## 6. Campos ignorados inicialmente

## 6.1 `inventory`

### Estado

Fuera de alcance v1.

### Motivo

- densidad visual
- poca utilidad en overlay persistente
- ya disponible en la web

### Regla

No consumirlo visualmente en la v1, aunque exista en JSON.

---

## 7. Contratos locales del plasmoid

## 7.1 Estado local persistente mínimo

El plasmoid debe persistir:

- `seenEventIds[]`
- `readEventIds[]`
- `lastDashboardUrl`

Opcional más adelante:

- opacidad
- tamaño
- refresco

## 7.2 Dashboard URL

Valor por defecto:

- `http://127.0.0.1:7070/report.html`

Acciones que deben usarla:

- icono/botón del plasmoid
- acción del popup
- clic en notificación KDE

## 7.3 Política de apertura

Abrir siempre con el navegador por defecto del sistema.

---

## 8. Contrato de layout v1

## 8.1 Regla de composición

El plasmoid **no** reproduce la estructura de tarjetas de la web.

Debe reinterpretar el mismo contenido como:

- columna lateral
- HUD técnico
- barras finas
- bajo peso visual

## 8.2 Orden obligatorio de render

1. `severity`
2. `counters`
3. `snapshot`
4. `recent_events` indicadores
5. `driver_health`
6. `daily_history`

## 8.3 Regla para `recent_events`

Siempre separar:

- estado actual de subsistema
- evento reciente no leído

Nunca mezclar ambos en una sola línea ambigua.

---

## 9. Tareas de implementación

## 9.1 Tarea A — Modelo de datos

Crear un adaptador de lectura de `data.json` con:

- parseo seguro
- fallback a último estado válido
- normalización mínima

Entregable:

- `DataSource.js` o equivalente

## 9.2 Tarea B — Contrato de apertura web

Crear helper centralizado:

- `openDashboard()`

Debe:

- abrir la URL configurada
- usar navegador por defecto

## 9.3 Tarea C — Severity block

Entregable:

- `SeverityBlock.qml`

Entrada:

- `severity`

## 9.4 Tarea D — Counters block

Entregable:

- `CountersBlock.qml`

Entrada:

- `counters`
- `eventIndicators`

## 9.5 Tarea E — Snapshot block

Entregable:

- `SnapshotBlock.qml`

Entrada:

- `snapshot`

Debe contener subcomponentes internos si hace falta:

- thermal
- battery
- wifi
- cpu
- load

## 9.6 Tarea F — Event state model

Entregable:

- `EventStore.js`
- `EventsModel.js`

Responsabilidad:

- generar `eventId`
- detectar nuevos
- persistir leídos
- decidir si notificar

## 9.7 Tarea G — Event popup

Entregable:

- `EventPopup.qml`

Entrada:

- `event`

Acciones:

- copy
- mark read
- open dashboard
- close

Regla:

- auto-close 30s

## 9.8 Tarea H — KDE notifications

Entregable:

- integración oficial Plasma/KNotifications

Comportamiento:

- notificar sólo eventos nuevos
- clic abre la web

## 9.9 Tarea I — Driver health block

Entregable:

- `DriverHealthBlock.qml`

Entrada:

- `driver_health`

## 9.10 Tarea J — Daily history block

Entregable:

- `DailyHistoryBlock.qml`

Entrada:

- `daily_history`

## 9.11 Tarea K — Instalación y bootstrap

Entregable:

- integración en `src/modules/bootstrap.sh`

Comportamiento:

- ofrecer instalación sólo si KDE Plasma
- instalar plasmoid oficialmente
- configurarlo
- añadirlo automáticamente al escritorio

---

## 10. Checklist de cierre previo a codificación

Antes de implementar, debe considerarse cerrado:

- contrato de campos JSON
- lista de bloques v1
- exclusión de `inventory`
- política de popup
- política de notificaciones
- política de apertura de web
- política de leído/no leído
- orden de bloques
- instalación automática en Plasma

Estado actual:

- **cerrado**

---

## 11. Resumen final

Este documento deja el plasmoid v1 definido como:

- consumidor directo del `data.json` actual,
- sin lógica duplicada de backend,
- con `severity`, `counters`, `snapshot`, `recent_events`, `driver_health` y `daily_history`,
- con `recent_events` visibles sólo como indicadores,
- popup local para detalle técnico,
- notificaciones KDE para eventos nuevos,
- y acción centralizada para abrir la web completa.

Lo siguiente ya debería ser convertir estas tareas en estructura de plasmoid y empezar la implementación bloque por bloque.
