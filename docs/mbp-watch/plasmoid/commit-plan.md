# MBP Watch KDE Plasmoid v1 — Plan de commits y trazabilidad

## 1. Objetivo

Definir una secuencia concreta de commits para que la implementación del plasmoid quede:

- trazable,
- revisable por bloques,
- reversible,
- y fácil de auditar después.

Este documento complementa la guía general de IA:

- [mbp-watch-kde-plasmoid-ai-implementation-guide.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-ai-implementation-guide.md:1)

---

## 2. Regla general

Cada commit debe cerrar un bloque funcional verificable.

No mezclar en un mismo commit:

- varios bloques grandes,
- cambios de producto no relacionados,
- refactors oportunistas,
- o ediciones de limpieza no necesarias.

---

## 3. Secuencia recomendada de commits

## Commit 01

Mensaje:

```text
Scaffold Plasma 6 plasmoid package
```

Debe incluir:

- `assets/plasmoids/mbp-watch/`
- `metadata.json`
- `contents/ui/main.qml`
- árbol base de `contents/ui`, `contents/code`, `contents/config`, `contents/images`
- `README.md` mínimo del plasmoid

Validación mínima:

- estructura presente
- metadata coherente con Plasma 6

## Commit 02

Mensaje:

```text
Add plasmoid constants and data source
```

Debe incluir:

- `constants.js`
- `dataSource.js`
- valores base de `data.json`, URL web, refresh, popup TTL

Validación mínima:

- lectura segura del JSON
- conservación de último estado válido

## Commit 03

Mensaje:

```text
Add state adapter for mbp_watch data
```

Debe incluir:

- `stateAdapter.js`
- helpers de normalización
- contrato estable para QML

Validación mínima:

- acceso seguro a `severity`, `counters`, `snapshot`, `recent_events`, `driver_health`, `daily_history`

## Commit 04

Mensaje:

```text
Implement plasmoid shell and theme primitives
```

Debe incluir:

- `Theme.qml`
- `HudPanel.qml`
- `ThinBar.qml`
- `StatusDot.qml`
- `MonoLabel.qml`
- `IconActionButton.qml`
- composición base en `main.qml`

Validación mínima:

- shell visual coherente con el estilo HUD

## Commit 05

Mensaje:

```text
Implement severity and counters blocks
```

Debe incluir:

- `SeverityBlock.qml`
- `CountersBlock.qml`

Validación mínima:

- render estable con datos reales o mock compatibles

## Commit 06

Mensaje:

```text
Implement compact snapshot blocks
```

Debe incluir:

- `SnapshotBlock.qml`
- mini bloques de thermal/cpu/battery/wifi/system load

Validación mínima:

- snapshot legible y compacto

## Commit 07

Mensaje:

```text
Add recent event indicators and popup
```

Debe incluir:

- `EventIndicatorsBlock.qml`
- `EventPopup.qml`
- `eventStore.js`
- `eventsModel.js`

Validación mínima:

- no muestra texto persistente
- popup abre y cierra bien
- TTL de 30s o cierre manual

## Commit 08

Mensaje:

```text
Implement driver health and daily history blocks
```

Debe incluir:

- `DriverHealthBlock.qml`
- `DailyHistoryBlock.qml`

Validación mínima:

- ambos bloques compactos sin romper el layout

## Commit 09

Mensaje:

```text
Add dashboard action and KDE notifications
```

Debe incluir:

- `openDashboard.js`
- `notifications.js`
- wiring desde popup y shell principal

Validación mínima:

- abre la web por defecto
- notificaciones disparan el flujo esperado

## Commit 10

Mensaje:

```text
Add plasmoid config schema
```

Debe incluir:

- `contents/config/main.xml`
- `ConfigPage.qml` si entra en la v1 efectiva

Validación mínima:

- configuración mínima consistente con el contrato

## Commit 11

Mensaje:

```text
Integrate plasmoid install flow into bootstrap
```

Debe incluir:

- helpers en `src/modules/bootstrap.sh`
- instalación/upgrade con `kpackagetool6`
- auto-add con `qdbus6`
- prompt opt-in

Validación mínima:

- instalación per-user
- no duplica widget
- degrada bien si falla la sesión gráfica

## Commit 12

Mensaje:

```text
Document plasmoid install and recovery workflow
```

Debe incluir sólo documentación adicional si hiciera falta tras validar el flujo real.

---

## 4. Regla de validación antes de cada commit

Antes de hacer cada commit, la IA o implementador debe dejar claro:

1. qué archivos tocó
2. qué validó realmente
3. qué no pudo validar
4. qué riesgos quedan

Si un bloque no puede validarse, el commit sigue siendo aceptable sólo si:

- el alcance del riesgo está explicado
- y no se presenta como cerrado del todo

---

## 5. Regla de staging

No usar:

```bash
git add .
```

como hábito por defecto en esta implementación.

Preferir siempre:

```bash
git add <archivos del bloque>
```

Motivo:

- evita arrastrar cambios ajenos del repo
- mantiene cada commit limpio

---

## 6. Regla de mensajes de commit

Los mensajes deben ser:

- cortos
- imperativos
- descriptivos del bloque

Evitar:

- `misc fixes`
- `changes`
- `wip`
- `more work`

Buena regla:

- si el mensaje no deja claro qué parte del plasmoid cambia, no sirve

---

## 7. Regla de rollback

La secuencia por bloques existe precisamente para que puedas revertir:

- sólo el popup
- sólo las notificaciones
- sólo el bootstrap
- sólo la shell visual

Eso se pierde si se mezclan demasiadas piezas por commit.

---

## 8. Resultado esperado

Cuando este plan se siga bien:

- cada parte del plasmoid tendrá su commit identificable
- el review será mucho más simple
- y cualquier fallo introducido por IA será localizable con bastante rapidez
