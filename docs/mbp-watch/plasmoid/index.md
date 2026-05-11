# MBP Watch KDE Plasmoid v1 — Índice maestro

## 1. Objetivo

Este archivo es el punto de entrada único para implementar el plasmoid KDE `mbp-watch` v1.

Su función es decir, sin ambigüedad:

- qué debe leer primero un agente o implementador,
- qué documento resuelve cada tipo de duda,
- dónde se generará el código,
- en qué orden debe ejecutarse el trabajo,
- y qué límites no debe cruzar.

Si un agente sólo leyera un documento para orientarse, debería ser este.

---

## 2. Dónde se generará el código

El código del plasmoid debe generarse en:

- [assets/plasmoids/mbp-watch](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/assets/plasmoids/mbp-watch)

La integración de instalación debe tocar:

- [src/modules/bootstrap.sh](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/bootstrap.sh:1)

No debe generarse código del plasmoid en:

- `src/`
- `assets/diagnostics/web/`
- `docs/`
- `firmware/`

salvo la integración concreta de `bootstrap.sh`.

---

## 3. Orden obligatorio de lectura

El orden correcto para cualquier agente es este:

1. [mbp-watch-kde-plasmoid-v1-index.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-index.md:1)
2. [mbp-watch-kde-plasmoid-ai-implementation-guide.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-ai-implementation-guide.md:1)
3. [mbp-watch-kde-plasmoid-v1-spec.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)
4. [mbp-watch-kde-plasmoid-v1-mapping.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)
5. [mbp-watch-kde-plasmoid-v1-task-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-task-plan.md:1)
6. [mbp-watch-kde-plasmoid-v1-file-structure.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-file-structure.md:1)
7. [mbp-watch-kde-plasmoid-v1-installation-flow.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-installation-flow.md:1)
8. [mbp-watch-kde-plasmoid-v1-bootstrap-integration.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-bootstrap-integration.md:1)
9. [mbp-watch-kde-plasmoid-v1-autoload-script.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-autoload-script.md:1)
10. [mbp-watch-kde-plasmoid-v1-commit-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-commit-plan.md:1)

Regla:

- no saltarse `ai-implementation-guide`
- no empezar a codificar tras leer sólo `spec`

---

## 4. Qué resuelve cada documento

## 4.1 Producto y UX

Documento:

- [mbp-watch-kde-plasmoid-v1-spec.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)

Responde:

- qué es la v1
- qué bloques entran
- qué bloques no entran
- cómo se comportan eventos, popup y notificaciones
- qué papel tiene la web completa

## 4.2 Contrato de datos

Documento:

- [mbp-watch-kde-plasmoid-v1-mapping.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)

Responde:

- qué campos del `data.json` consume cada bloque
- qué es obligatorio
- qué es opcional
- cómo se adapta el estado para UI

## 4.3 Orden de ejecución

Documento:

- [mbp-watch-kde-plasmoid-v1-task-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-task-plan.md:1)

Responde:

- qué tarea va primero
- qué dependencia tiene cada tarea
- cuál es la secuencia correcta de implementación

## 4.4 Ubicación y nombres de archivos

Documento:

- [mbp-watch-kde-plasmoid-v1-file-structure.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-file-structure.md:1)

Responde:

- qué archivos deben existir
- dónde deben vivir
- qué responsabilidad tiene cada uno

## 4.5 Instalación y despliegue

Documento:

- [mbp-watch-kde-plasmoid-v1-installation-flow.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-installation-flow.md:1)

Responde:

- cómo se instala el paquete Plasma
- cómo se actualiza
- cómo se añade automáticamente al escritorio
- cómo se degrada si no hay sesión gráfica

## 4.6 Integración en bootstrap

Documento:

- [mbp-watch-kde-plasmoid-v1-bootstrap-integration.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-bootstrap-integration.md:1)

Responde:

- qué funciones nuevas van en `bootstrap.sh`
- qué orden deben seguir
- qué variables deben centralizarse

## 4.7 Script exacto de auto-add

Documento:

- [mbp-watch-kde-plasmoid-v1-autoload-script.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-autoload-script.md:1)

Responde:

- qué JS exacto se debe pasar a `qdbus6`
- qué resultados debe devolver
- cómo interpretar esos resultados en shell

## 4.8 Modo de trabajo del agente

Documento:

- [mbp-watch-kde-plasmoid-ai-implementation-guide.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-ai-implementation-guide.md:1)

Responde:

- qué puede decidir la IA
- qué no puede decidir
- qué límites de producto y técnicos debe respetar
- cómo debe trabajar con Git

## 4.9 Trazabilidad en Git

Documento:

- [mbp-watch-kde-plasmoid-v1-commit-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-commit-plan.md:1)

Responde:

- qué commits debería hacer
- cómo partir el trabajo por bloques
- cómo evitar commits demasiado grandes

---

## 5. Alcance cerrado de v1

La v1 debe incluir:

- `severity`
- `counters`
- `snapshot`
- `recent_events` como indicadores
- `driver_health` compacto
- `daily_history` compacto
- popup de evento
- notificaciones KDE
- acción para abrir la web
- instalación opcional desde `bootstrap`
- auto-add al escritorio

La v1 no debe incluir inicialmente:

- `inventory`
- clon 1:1 de la web
- configuración avanzada no documentada
- instalación global del plasmoid

---

## 6. Primeros archivos reales a crear

El primer bloque de implementación real debe crear como mínimo:

1. [assets/plasmoids/mbp-watch/metadata.json](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/assets/plasmoids/mbp-watch/metadata.json)
2. [assets/plasmoids/mbp-watch/contents/ui/main.qml](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/assets/plasmoids/mbp-watch/contents/ui/main.qml)
3. el árbol base descrito en [mbp-watch-kde-plasmoid-v1-file-structure.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-file-structure.md:1)

No debe empezar por `bootstrap.sh`.

Primero:

- paquete Plasma válido
- shell visual mínimo
- lectura de datos

Después:

- integración

---

## 7. Orden obligatorio de implementación

La implementación debe seguir esta secuencia:

1. scaffold del paquete
2. `metadata.json`
3. `main.qml`
4. constantes y lectura de `data.json`
5. adaptador de estado
6. shell visual y primitives
7. bloques `severity` y `counters`
8. bloques compactos de `snapshot`
9. indicadores de eventos y popup
10. `driver_health` y `daily_history`
11. apertura web y notificaciones
12. instalación
13. auto-add en `bootstrap`

Referencia principal:

- [mbp-watch-kde-plasmoid-v1-task-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-task-plan.md:1)

---

## 8. Reglas de trabajo para el agente

El agente debe:

1. implementar por bloques pequeños
2. validar cada bloque antes de seguir
3. hacer un commit por bloque lógico
4. no mezclar cambios no relacionados
5. actualizar documentación primero si descubre un hueco real

El agente no debe:

1. improvisar cambios de producto
2. reintroducir `inventory` en v1
3. convertir el plasmoid en una mini web
4. usar hacks no oficiales si existe vía oficial Plasma
5. modificar archivos del usuario de Plasma a mano como estrategia principal

---

## 9. Commit de referencia actual

Punto de partida actual del repo:

- baseline snapshot: `6f59f80`

Commit de documentación del plasmoid:

- `0b0f6bc`

Implementación v1 del plasmoid:

- `35a2fed` Scaffold Plasma 6 plasmoid package
- `4bc126a` Add plasmoid constants and data source
- `f79e12b` Add state adapter for mbp_watch data
- `69575b5` Implement plasmoid shell and theme primitives
- `810a6a3` Implement severity and counters blocks
- `aa576e6` Implement compact snapshot blocks
- `39a6a2e` Add recent event indicators and popup
- `058fd8c` Implement driver health and daily history blocks
- `d29cae5` Add dashboard action and KDE notifications
- `1fc4fda` Add plasmoid config schema
- `02ee707` Integrate plasmoid install flow into bootstrap

Esto deja la documentación inicial y la implementación v1 con trazabilidad en Git.

---

## 10. Estado de implementación

La implementación completa del plasmoid v1 vive en:

- [assets/plasmoids/mbp-watch](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/assets/plasmoids/mbp-watch)

La integración de instalación, upgrade y auto-add vive en:

- [src/modules/bootstrap.sh](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/bootstrap.sh:1)

Validaciones no destructivas realizadas:

- `bash -n migration.sh src/main.sh src/lib/common.sh src/modules/*.sh src/tools/*.sh`
- `shellcheck migration.sh src/main.sh src/lib/common.sh src/modules/*.sh src/tools/*.sh`
- `kpackagetool6 --type Plasma/Applet --appstream-metainfo assets/plasmoids/mbp-watch`

Limitación pendiente:

- No se ha verificado todavía dentro de una sesión KDE Plasma real el runtime del plasmoid.
- No se ha ejecutado todavía `kpackagetool6 --install/--upgrade assets/plasmoids/mbp-watch` contra el usuario real.
- No se ha ejecutado todavía `plasmawindowed io.github.gtx.mbpwatch`.
- No se ha ejecutado todavía el `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript ...` de auto-add contra una sesión real de `org.kde.plasmashell`.

Por tanto, para siguientes agentes: no rehacer la implementación v1 desde cero. El trabajo pendiente es validación runtime en Plasma real y corrección de cualquier incidencia que aparezca ahí.

---

## 11. Uso correcto de este índice

Si un agente va a retomar el plasmoid, debería hacer esto:

1. leer este índice
2. revisar el estado de implementación anterior
3. inspeccionar [assets/plasmoids/mbp-watch](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/assets/plasmoids/mbp-watch)
4. inspeccionar el bloque de integración en [src/modules/bootstrap.sh](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/bootstrap.sh:1)
5. repetir las validaciones no destructivas
6. validar runtime en una sesión KDE Plasma real
7. corregir sólo las incidencias observadas en runtime

Ese es el flujo correcto después de la implementación v1.
