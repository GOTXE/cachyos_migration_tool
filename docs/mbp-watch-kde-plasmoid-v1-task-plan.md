# MBP Watch KDE Plasmoid v1 — Plan de tareas de implementación

## 1. Objetivo

Traducir la especificación y el mapeo ya cerrados en un **backlog técnico secuencial**, de forma que la implementación posterior pueda ejecutarse por bloques con el menor margen posible de interpretación.

Documentos base de referencia:

- [mbp-watch-kde-plasmoid-v1-spec.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)
- [mbp-watch-kde-plasmoid-v1-mapping.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)

---

## 2. Estrategia de implementación

La v1 se implementará en este orden:

1. esqueleto del plasmoid,
2. lectura fiable de `data.json`,
3. render mínimo del estado global,
4. render de bloques principales,
5. sistema de eventos y popup,
6. notificaciones KDE,
7. instalación automática desde `bootstrap`.

La regla general será:

- primero asegurar **contrato y datos**,
- luego **render persistente**,
- luego **interacción**,
- y al final **instalación**.

---

## 3. Tareas

## Task 01 — Estructura base del plasmoid

### Objetivo

Crear la estructura mínima oficial del plasmoid KDE Plasma.

### Entregables

- directorio del plasmoid en el repo
- `metadata.json` o formato oficial equivalente según Plasma objetivo
- `main.qml`
- estructura base de recursos

### Decisiones ya fijadas

- debe seguir la vía oficial de Plasma
- no es una web embebida

### Criterio de terminado

- el plasmoid existe como artefacto instalable
- Plasma puede reconocerlo como plasmoid válido

---

## Task 02 — Contrato de configuración interna

### Objetivo

Definir constantes y configuración base del plasmoid.

### Entregables

- archivo de constantes o módulo de configuración

### Debe incluir

- ruta de `data.json`
- URL del dashboard web
- refresco por defecto
- timeout del popup de evento

### Valores iniciales

- `data.json`: `/var/lib/mbp-watch/data.json`
- web: `http://127.0.0.1:7070/report.html`
- refresh: `5000 ms`
- popup TTL: `30000 ms`

### Criterio de terminado

- todos los valores globales están centralizados y no hardcodeados por componentes

---

## Task 03 — Lector de `data.json`

### Objetivo

Implementar la lectura periódica y segura del estado generado por MBP Watch.

### Entregables

- `DataSource.js` o módulo equivalente

### Debe resolver

- carga inicial
- refresco periódico
- parseo JSON seguro
- conservación de último estado válido
- estado `loading`
- estado `degraded`

### Criterio de terminado

- el plasmoid puede obtener un objeto de estado consistente sin bloquear la UI

---

## Task 04 — Adaptador de modelo de datos

### Objetivo

Normalizar el JSON bruto en un modelo de consumo simple para QML.

### Entregables

- `StateAdapter.js` o equivalente

### Debe resolver

- normalización de campos ausentes
- acceso seguro a `severity`
- acceso seguro a `counters`
- acceso seguro a `snapshot`
- acceso seguro a `recent_events`
- acceso seguro a `driver_health`
- acceso seguro a `daily_history`

### Criterio de terminado

- los componentes visuales no dependen de navegar el JSON bruto manualmente

---

## Task 05 — Acción global `openDashboard`

### Objetivo

Definir la acción centralizada para abrir la web.

### Entregables

- helper `openDashboard()`

### Reglas

- usar siempre el navegador por defecto
- usar siempre la URL configurada

### Criterio de terminado

- cualquier bloque o notificación puede abrir la web reutilizando la misma acción

---

## Task 06 — Shell visual del plasmoid

### Objetivo

Crear el layout maestro del overlay.

### Entregables

- estructura principal en `main.qml`

### Debe reflejar

- columna lateral estilo HUD
- estética cyberpunk/fósforo verde
- transparencia alta
- jerarquía compacta

### No debe hacer todavía

- render detallado de todos los bloques

### Criterio de terminado

- el plasmoid ya tiene composición general y estilo base

---

## Task 07 — `SeverityBlock`

### Objetivo

Implementar el bloque de estado global.

### Entregables

- `SeverityBlock.qml`

### Entrada

- `severity.class`
- `severity.title`
- `severity.text`
- `severity.reason`

### Criterio de terminado

- el bloque muestra el estado global de forma compacta y coherente con el contrato

---

## Task 08 — `CountersBlock`

### Objetivo

Implementar el bloque de contadores.

### Entregables

- `CountersBlock.qml`

### Entrada

- `counters`

### Debe resolver

- labels exactas acordadas
- resaltado si valor > 0
- soporte posterior para acentos de eventos

### Criterio de terminado

- los contadores se ven y respetan el mapeo del contrato

---

## Task 09 — `SnapshotBlock` contenedor

### Objetivo

Crear el contenedor de telemetría compacta.

### Entregables

- `SnapshotBlock.qml`

### Debe agrupar

- thermal
- fan
- cpu
- load/system
- battery
- wifi

### Criterio de terminado

- existe un bloque general de telemetría preparado para subcomponentes

---

## Task 10 — subbloque térmico y ventilador

### Objetivo

Pintar temperatura principal y RPM de ventilador.

### Entregables

- `ThermalMiniBlock.qml` o componente equivalente

### Entrada

- `snapshot.temperatures`
- `snapshot.fan_rpm`

### Debe resolver

- selección de temperatura principal
- formato compacto
- barra fina o indicador equivalente

### Criterio de terminado

- térmicas visibles y legibles en espacio reducido

---

## Task 11 — subbloque CPU

### Objetivo

Pintar resumen CPU.

### Entregables

- `CpuMiniBlock.qml`

### Entrada

- `snapshot.cpu_perf`

### Debe mostrar

- ratio o headroom
- estado de throttle
- governor / energy mode sólo si cabe

### Criterio de terminado

- el bloque comunica si la CPU está normal o degradada sin sobrecargar el layout

---

## Task 12 — subbloque Battery

### Objetivo

Pintar batería de forma persistente.

### Entregables

- `BatteryMiniBlock.qml`

### Entrada

- `snapshot.battery`

### Debe mostrar

- porcentaje
- estado
- barra

### Criterio de terminado

- batería visible con lectura inmediata

---

## Task 13 — subbloque Wi-Fi

### Objetivo

Pintar resumen Wi-Fi.

### Entregables

- `WifiMiniBlock.qml`

### Entrada

- `snapshot.wifi_link`
- `snapshot.wifi_analysis`

### Debe mostrar

- conectado/desconectado
- señal
- latencia / packet loss si aportan valor
- warning si aplica

### Criterio de terminado

- Wi-Fi queda visible como estado rápido y coherente con la web

---

## Task 14 — subbloque Load/System

### Objetivo

Pintar carga resumida del sistema.

### Entregables

- `SystemLoadMiniBlock.qml`

### Entrada

- `snapshot.load_and_system`

### Debe mostrar

- `load_average`
- opcional `context_switches`

### Criterio de terminado

- el plasmoid comunica carga general sin ruido técnico excesivo

---

## Task 15 — Modelo de eventos locales

### Objetivo

Implementar el estado local de `recent_events`.

### Entregables

- `EventStore.js`
- `EventsModel.js`

### Debe resolver

- construir `eventId = ts + category + message`
- detectar eventos nuevos
- distinguir vistos / leídos
- persistencia local

### Criterio de terminado

- el plasmoid puede responder a eventos nuevos de forma estable

---

## Task 16 — Indicadores persistentes de eventos

### Objetivo

Representar `recent_events` sin texto persistente.

### Entregables

- `EventsIndicatorsBlock.qml` o lógica integrada en bloques afectados

### Debe mostrar

- acentos visuales por categoría
- estado no leído
- sin logs visibles

### Criterio de terminado

- el usuario ve que existe un evento reciente sin necesidad de ver el texto

---

## Task 17 — Mapeo evento → bloque afectado

### Objetivo

Implementar la relación entre categorías de evento y bloques visuales.

### Entregables

- helper de mapping

### Relación inicial

- `wifi` → Wi-Fi / connectivity
- `gpu` → GPU counter
- `power` → PM / power
- `thermal` → thermal / throttle
- `audio` → audio
- `bluetooth` → bluetooth
- `other` → alerta general

### Criterio de terminado

- cada evento nuevo resalta el bloque correcto

---

## Task 18 — `EventPopup`

### Objetivo

Implementar el popup de detalle de evento.

### Entregables

- `EventPopup.qml`

### Debe mostrar

- categoría
- timestamp
- texto técnico
- copy
- mark read
- open dashboard

### Reglas

- cierre automático a 30s
- cierre manual siempre posible

### Criterio de terminado

- un evento puede abrirse, leerse, copiarse y cerrarse sin salir del plasmoid

---

## Task 19 — Acción `mark read`

### Objetivo

Persistir el estado leído.

### Entregables

- integración popup ↔ `EventStore`

### Criterio de terminado

- un evento marcado como leído deja de resaltarse como no leído

---

## Task 20 — Acción `copy event`

### Objetivo

Permitir copiar el evento en formato técnico útil.

### Entregables

- helper de copy al portapapeles

### Formato

`[category] ts message`

### Criterio de terminado

- el texto copiado sirve para pegar en Codex, tickets o chat técnico

---

## Task 21 — Notificaciones KDE

### Objetivo

Disparar notificaciones al detectar eventos nuevos.

### Entregables

- integración oficial con notificaciones de Plasma/KDE

### Debe resolver

- cuándo notificar
- evitar spam por el mismo evento
- acción principal que abre la web

### Criterio de terminado

- un evento nuevo genera notificación KDE clicable

---

## Task 22 — `DriverHealthBlock`

### Objetivo

Implementar resumen compacto de salud de drivers.

### Entregables

- `DriverHealthBlock.qml`

### Entrada

- `driver_health`

### Debe mostrar

- driver
- estado
- detalle corto

### No debe mostrar

- fixes largos completos persistentes

### Criterio de terminado

- el bloque aporta valor sin convertir el overlay en una tabla extensa

---

## Task 23 — `DailyHistoryBlock`

### Objetivo

Implementar resumen compacto del histórico diario.

### Entregables

- `DailyHistoryBlock.qml`

### Entrada

- `daily_history`

### Debe mostrar

- últimos 7 días o equivalente compacto
- lectura resumida del total

### Criterio de terminado

- el histórico aporta contexto sin dominar el espacio vertical

---

## Task 24 — Estado vacío / degradado / loading

### Objetivo

Cerrar los estados operativos de la UI.

### Entregables

- placeholders y comportamiento consistente

### Debe cubrir

- sin `data.json`
- JSON inválido
- sin `recent_events`
- sin `driver_health`
- sin `daily_history`

### Criterio de terminado

- el plasmoid no se rompe visualmente ante entradas incompletas

---

## Task 25 — Afinado visual cyberpunk

### Objetivo

Ajustar el estilo final a la referencia `docs/plasmoid.jpg`.

### Entregables

- revisión visual de spacing, opacidad, tipografía y color

### Debe reforzar

- verde fósforo base
- rojo sólo en anomalías
- barras finas
- HUD discreto

### Criterio de terminado

- el plasmoid se siente parte del wallpaper, no una app flotante

---

## Task 26 — Instalación oficial del plasmoid

### Objetivo

Preparar la instalación según guías oficiales de Plasma.

### Entregables

- script o rutina instalable desde el repo

### Debe resolver

- copiar/instalar plasmoid
- registrar si hace falta
- dejarlo disponible para Plasma

### Criterio de terminado

- puede instalarse de forma repetible en un sistema Plasma

---

## Task 27 — Integración en `bootstrap.sh`

### Objetivo

Integrar la instalación en el flujo de bootstrap.

### Entregables

- cambios en `src/modules/bootstrap.sh`

### Debe resolver

- detección de KDE Plasma
- prompt de aceptación
- instalación sólo si el usuario acepta
- manejo de errores razonable

### Criterio de terminado

- el bootstrap puede instalar el plasmoid sin romper otros flujos

---

## Task 28 — Añadido automático al escritorio

### Objetivo

Añadir el plasmoid automáticamente al escritorio tras instalarlo.

### Entregables

- rutina de activación en Plasma

### Reglas

- sólo en KDE Plasma
- sólo si el usuario aceptó

### Criterio de terminado

- tras bootstrap, el plasmoid aparece ya visible en el escritorio

---

## Task 29 — Validación funcional mínima

### Objetivo

Comprobar el circuito completo.

### Casos mínimos

1. el plasmoid carga `data.json`
2. se renderiza `severity`
3. se renderizan `counters`
4. se renderiza `snapshot`
5. un evento nuevo resalta indicador
6. un evento nuevo dispara notificación KDE
7. clic en notificación abre la web
8. clic en indicador abre popup
9. `Copy` funciona
10. `Mark read` limpia el estado visual
11. bootstrap instala el plasmoid
12. el plasmoid aparece automáticamente

### Criterio de terminado

- todos los flujos críticos v1 funcionan en el MBP real

---

## 4. Dependencias entre tareas

Orden recomendado de ejecución:

1. `Task 01`
2. `Task 02`
3. `Task 03`
4. `Task 04`
5. `Task 05`
6. `Task 06`
7. `Task 07`
8. `Task 08`
9. `Task 09`
10. `Task 10`
11. `Task 11`
12. `Task 12`
13. `Task 13`
14. `Task 14`
15. `Task 15`
16. `Task 16`
17. `Task 17`
18. `Task 18`
19. `Task 19`
20. `Task 20`
21. `Task 21`
22. `Task 22`
23. `Task 23`
24. `Task 24`
25. `Task 25`
26. `Task 26`
27. `Task 27`
28. `Task 28`
29. `Task 29`

---

## 5. Resumen operativo

Con este plan, la implementación del plasmoid ya queda descompuesta en tareas concretas, con:

- objetivo,
- entregables,
- dependencias,
- criterio de terminado.

La intención es que el siguiente paso pueda hacerse con Codex casi como ejecución de backlog, no como nueva fase de descubrimiento.
