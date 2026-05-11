# MBP Watch KDE Plasmoid v1 — Estructura de archivos, nombres e integración

## 1. Objetivo

Definir la **estructura exacta esperada** del plasmoid KDE Plasma v1 dentro del repo, junto con:

- convenciones de nombres,
- responsabilidades por archivo,
- puntos de integración con `bootstrap`,
- y límites claros entre backend, plasmoid e instalación.

Este documento pretende que la fase de implementación sea casi directa:

- crear archivos según esta estructura,
- rellenar cada uno según tareas y contratos ya definidos,
- integrar la instalación siguiendo el mismo esquema.

Documentos previos:

- [mbp-watch-kde-plasmoid-v1-spec.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)
- [mbp-watch-kde-plasmoid-v1-mapping.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)
- [mbp-watch-kde-plasmoid-v1-task-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-task-plan.md:1)

---

## 2. Regla general de ubicación en el repo

El plasmoid no debe mezclarse con:

- `src/` del script bash principal,
- `assets/diagnostics/web/` de la web actual,
- `docs/` de documentación,
- `firmware/`.

Debe vivir como artefacto propio de frontend Plasma.

## 2.1 Ubicación propuesta

Se propone crear:

- `assets/plasmoids/mbp-watch/`

Motivo:

- es un artefacto instalable,
- no pertenece al runtime bash principal,
- no es documentación,
- y su contenido es frontend KDE específico.

---

## 3. Estructura propuesta del plasmoid

## 3.1 Árbol base

```text
assets/plasmoids/mbp-watch/
├── metadata.json
├── contents/
│   ├── ui/
│   │   ├── main.qml
│   │   ├── theme/
│   │   │   └── Theme.qml
│   │   ├── blocks/
│   │   │   ├── SeverityBlock.qml
│   │   │   ├── CountersBlock.qml
│   │   │   ├── SnapshotBlock.qml
│   │   │   ├── ThermalMiniBlock.qml
│   │   │   ├── CpuMiniBlock.qml
│   │   │   ├── BatteryMiniBlock.qml
│   │   │   ├── WifiMiniBlock.qml
│   │   │   ├── SystemLoadMiniBlock.qml
│   │   │   ├── DriverHealthBlock.qml
│   │   │   ├── DailyHistoryBlock.qml
│   │   │   └── EventIndicatorsBlock.qml
│   │   ├── popups/
│   │   │   └── EventPopup.qml
│   │   ├── common/
│   │   │   ├── HudPanel.qml
│   │   │   ├── ThinBar.qml
│   │   │   ├── StatusDot.qml
│   │   │   ├── MonoLabel.qml
│   │   │   └── IconActionButton.qml
│   │   └── config/
│   │       └── ConfigPage.qml
│   ├── code/
│   │   ├── constants.js
│   │   ├── dataSource.js
│   │   ├── stateAdapter.js
│   │   ├── eventStore.js
│   │   ├── eventsModel.js
│   │   ├── notifications.js
│   │   ├── openDashboard.js
│   │   ├── formatters.js
│   │   └── mappings.js
│   ├── config/
│   │   └── main.xml
│   └── images/
│       └── icon-dashboard.svg
└── README.md
```

---

## 4. Responsabilidad por directorio

## 4.1 `metadata.json`

Responsabilidad:

- identificar el plasmoid,
- definir nombre,
- definir id/plugin id,
- definir versión,
- definir metadatos exigidos por Plasma.

Regla:

- este archivo debe contener el identificador estable del plasmoid usado por instalación y activación.

## 4.2 `contents/ui/`

Responsabilidad:

- toda la UI declarativa en QML.

Subdivisión:

- `blocks/`: bloques funcionales del dashboard
- `popups/`: elementos temporales e interactivos
- `common/`: primitivas visuales reutilizables
- `theme/`: tokens de estilo
- `config/`: UI de configuración del plasmoid

## 4.3 `contents/code/`

Responsabilidad:

- lógica JS auxiliar,
- lectura de `data.json`,
- adaptación de estado,
- notificaciones,
- persistencia local,
- mapping de eventos.

## 4.4 `contents/config/`

Responsabilidad:

- esquema de configuración oficial del plasmoid.

## 4.5 `contents/images/`

Responsabilidad:

- iconos mínimos necesarios del propio plasmoid.

No debe convertirse en un dump de assets grandes.

---

## 5. Convenciones de nombres

## 5.1 Convención QML

Todos los componentes QML deben usar:

- `PascalCase.qml`

Ejemplos:

- `SeverityBlock.qml`
- `EventPopup.qml`
- `ThinBar.qml`

## 5.2 Convención JS

Todos los módulos JS deben usar:

- `camelCase.js`

Ejemplos:

- `dataSource.js`
- `stateAdapter.js`
- `eventStore.js`

## 5.3 Convención de bloques

Los componentes visuales de primer nivel deben acabar en:

- `Block.qml`

Los componentes pequeños reutilizables deben acabar en algo más semántico:

- `MiniBlock.qml`
- `Button.qml`
- `Bar.qml`
- `Dot.qml`

## 5.4 Convención de ids internos

En QML:

- `camelCase`

Ejemplos:

- `dashboardButton`
- `eventPopup`
- `severityBlock`

---

## 6. Contrato por archivo

## 6.1 `main.qml`

Responsabilidad:

- shell principal,
- layout general,
- orquestación del estado global,
- refresco periódico,
- conexión entre bloques,
- integración del popup de evento.

No debe contener:

- parseo directo del JSON bruto,
- lógica grande de negocio,
- mappings largos hardcodeados.

## 6.2 `Theme.qml`

Responsabilidad:

- tokens visuales del estilo cyberpunk/HUD.

Debe contener:

- colores base
- opacidades
- spacing
- tipografía base
- tamaños de barra
- colores `ok / warn / critical`

No debe contener:

- lógica de eventos,
- lógica de datos.

## 6.3 `SeverityBlock.qml`

Responsabilidad:

- pintar `severity`.

Entrada:

- objeto severity ya adaptado.

## 6.4 `CountersBlock.qml`

Responsabilidad:

- pintar `counters`,
- aplicar acentos por evento nuevo/no leído.

No debe decidir:

- qué eventos son nuevos; eso viene ya resuelto desde modelo.

## 6.5 `SnapshotBlock.qml`

Responsabilidad:

- agrupar subbloques de telemetría.

Debe delegar:

- térmicas
- CPU
- batería
- Wi-Fi
- load/system

## 6.6 `EventIndicatorsBlock.qml`

Responsabilidad:

- representar visualmente la existencia de eventos recientes,
- abrir el popup apropiado al interactuar.

No debe mostrar:

- logs persistentes.

## 6.7 `EventPopup.qml`

Responsabilidad:

- mostrar detalle técnico corto del evento,
- copy,
- mark read,
- open dashboard,
- auto-close a 30s.

## 6.8 `DriverHealthBlock.qml`

Responsabilidad:

- resumen compacto de `driver_health`.

## 6.9 `DailyHistoryBlock.qml`

Responsabilidad:

- resumen compacto de `daily_history`.

## 6.10 `HudPanel.qml`

Responsabilidad:

- contenedor base reutilizable del estilo overlay.

Útil para:

- fondo translúcido
- bordes mínimos
- glow sutil

## 6.11 `ThinBar.qml`

Responsabilidad:

- barra horizontal fina reutilizable.

Debe poder usarse en:

- thermal
- battery
- Wi-Fi
- counters si hace falta

## 6.12 `IconActionButton.qml`

Responsabilidad:

- botón pequeño de acción, por ejemplo:
  - open dashboard
  - copy
  - mark read

## 6.13 `constants.js`

Responsabilidad:

- valores por defecto:
  - `DATA_JSON_PATH`
  - `DASHBOARD_URL`
  - `REFRESH_MS`
  - `EVENT_POPUP_TTL_MS`

## 6.14 `dataSource.js`

Responsabilidad:

- lectura periódica de `data.json`
- parseo seguro
- fallback a último estado válido

## 6.15 `stateAdapter.js`

Responsabilidad:

- convertir el JSON bruto en un modelo simple para QML

Debe encapsular:

- defaults
- protección ante nulls
- acceso consistente a los bloques

## 6.16 `eventStore.js`

Responsabilidad:

- persistencia local de vistos/leídos

Debe guardar:

- `seenEventIds`
- `readEventIds`
- quizá `lastNotifiedAtByEventId`

## 6.17 `eventsModel.js`

Responsabilidad:

- generar `eventId`
- detectar nuevos
- clasificar relación evento → bloque
- decidir qué indicadores persistentes se activan

## 6.18 `notifications.js`

Responsabilidad:

- encapsular la integración con notificaciones KDE

Debe exponer algo como:

- `notifyNewEvent(event, onActivate)`

## 6.19 `openDashboard.js`

Responsabilidad:

- abrir la web en navegador por defecto

Debe ser el único punto desde el que se abre el dashboard.

## 6.20 `formatters.js`

Responsabilidad:

- helpers visuales:
  - formateo de fecha
  - porcentaje
  - RSS/RPM
  - labels compactas

## 6.21 `mappings.js`

Responsabilidad:

- mapas estables:
  - counters → label visible
  - categoría de evento → bloque afectado
  - posibles prioridades visuales

---

## 7. Convención de flujo de datos

## 7.1 Flujo general

```text
data.json
  -> dataSource.js
  -> stateAdapter.js
  -> main.qml
  -> bloques QML
```

## 7.2 Flujo de eventos

```text
recent_events
  -> eventsModel.js
  -> eventStore.js
  -> indicadores persistentes
  -> EventPopup.qml
  -> notifications.js
```

## 7.3 Flujo de apertura de web

```text
UI action / popup / notification
  -> openDashboard.js
  -> navegador por defecto
```

---

## 8. Estado local del plasmoid

## 8.1 Persistencia requerida

La v1 debe persistir al menos:

- eventos vistos
- eventos leídos
- URL del dashboard si se decide configurable

## 8.2 Ubicación lógica

Debe usarse el mecanismo estándar de configuración/almacenamiento del plasmoid/Plasma.

No debe:

- escribir archivos arbitrarios fuera del espacio esperado por Plasma,
- crear dependencias extrañas en `/var/lib/mbp-watch`.

---

## 9. Integración con bootstrap

## 9.1 Principio

`bootstrap.sh` no debe conocer detalles internos de QML.

Sólo debe conocer:

- ruta del plasmoid en el repo
- comando oficial de instalación
- comando o método oficial para añadirlo al escritorio
- condición de KDE Plasma
- decisión del usuario

## 9.2 Ubicación de la lógica de instalación

Se recomienda añadir un helper instalable específico fuera de `src/` si hace falta.

Ubicación propuesta:

- `assets/plasmoids/install_mbp_watch_plasmoid.sh`

Responsabilidad:

- instalar/actualizar el plasmoid siguiendo el método oficial
- dejarlo disponible para Plasma
- opcionalmente añadirlo al escritorio

## 9.3 Rol de `bootstrap.sh`

`src/modules/bootstrap.sh` debe:

1. detectar KDE Plasma,
2. preguntar si instalar el plasmoid,
3. llamar al helper de instalación,
4. reportar éxito o fallo.

## 9.4 No mezclar responsabilidades

`bootstrap.sh` no debe:

- editar archivos internos del plasmoid,
- recalcular configuraciones visuales,
- duplicar comandos de notificación o UI.

---

## 10. Archivos complementarios recomendados

## 10.1 `README.md` del plasmoid

Ubicación:

- `assets/plasmoids/mbp-watch/README.md`

Debe incluir:

- qué hace el plasmoid
- qué consume
- cómo instalarlo manualmente
- cómo actualizarlo
- limitaciones de v1

## 10.2 Script de instalación

Ubicación:

- `assets/plasmoids/install_mbp_watch_plasmoid.sh`

Debe incluir:

- validaciones mínimas
- instalación oficial
- salida clara para `bootstrap`

## 10.3 Script opcional de desinstalación

Ubicación recomendada:

- `assets/plasmoids/uninstall_mbp_watch_plasmoid.sh`

No es obligatorio para arrancar, pero sí recomendable.

---

## 11. Qué no debe existir en la v1

Para evitar desorden, no debe aparecer:

- código QML grande incrustado en un único `main.qml`
- lógica de parseo JSON distribuida por muchos componentes
- mappings duplicados en varios archivos
- apertura de URL duplicada en distintos sitios
- persistencia de eventos mezclada con render
- instalación del plasmoid metida “a pelo” dentro de `bootstrap.sh`

---

## 12. Trazabilidad tarea → archivo

Relación orientativa:

- `Task 01` → `metadata.json`, `main.qml`, árbol base
- `Task 02` → `constants.js`, `main.xml`
- `Task 03` → `dataSource.js`
- `Task 04` → `stateAdapter.js`
- `Task 05` → `openDashboard.js`
- `Task 06` → `main.qml`, `Theme.qml`, `HudPanel.qml`
- `Task 07` → `SeverityBlock.qml`
- `Task 08` → `CountersBlock.qml`, `mappings.js`
- `Task 09` → `SnapshotBlock.qml`
- `Task 10` → `ThermalMiniBlock.qml`, `ThinBar.qml`
- `Task 11` → `CpuMiniBlock.qml`
- `Task 12` → `BatteryMiniBlock.qml`
- `Task 13` → `WifiMiniBlock.qml`
- `Task 14` → `SystemLoadMiniBlock.qml`
- `Task 15` → `eventStore.js`, `eventsModel.js`
- `Task 16` → `EventIndicatorsBlock.qml`
- `Task 17` → `mappings.js`, `eventsModel.js`
- `Task 18` → `EventPopup.qml`
- `Task 19` → `eventStore.js`, `EventPopup.qml`
- `Task 20` → `EventPopup.qml`, helper de clipboard si hace falta
- `Task 21` → `notifications.js`
- `Task 22` → `DriverHealthBlock.qml`
- `Task 23` → `DailyHistoryBlock.qml`
- `Task 24` → `main.qml`, `dataSource.js`, `stateAdapter.js`
- `Task 25` → `Theme.qml`, `common/*`, todos los bloques
- `Task 26` → `install_mbp_watch_plasmoid.sh`
- `Task 27` → `src/modules/bootstrap.sh`
- `Task 28` → helper de instalación + integración Plasma
- `Task 29` → validación funcional global

---

## 13. Resumen operativo

Con este documento ya queda cerrada también la capa de estructura:

- dónde vive el plasmoid,
- cómo se divide,
- qué archivo hace qué,
- cómo se integra con bootstrap,
- y qué límites de responsabilidad debe respetar cada parte.

La siguiente fase ya sería implementación real de la estructura o, si se quiere cerrar aún más antes de codificar, un documento final de:

- comandos de instalación oficiales Plasma concretos,
- detección exacta de KDE Plasma,
- y flujo automático de añadido al escritorio.
