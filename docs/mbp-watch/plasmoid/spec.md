# MBP Watch KDE Plasmoid v1

## 1. Objetivo

Definir una **v1 implementable** del plasmoid KDE Plasma para MBP Watch, usando como fuente única de verdad el `data.json` ya generado por `mbp_watch.sh`.

Esta v1 debe:

- instalarse opcionalmente desde `bootstrap`,
- añadirse automáticamente al escritorio Plasma si el usuario acepta,
- mostrar una vista compacta persistente del sistema,
- disparar notificaciones KDE cuando aparezcan eventos nuevos,
- abrir la web completa de MBP Watch en el navegador por defecto.

---

## 2. Decisiones cerradas

Estas decisiones ya quedan fijadas para la v1:

1. El plasmoid depende de los **datos ya generados por el script**.
2. La intención funcional es ser una **copia adaptada del dashboard web**, no una fuente de lógica independiente.
3. La lógica de eventos leídos/no leídos la gestiona el **plasmoid**, no el backend.
4. La instalación del plasmoid se integrará en `bootstrap` si el usuario acepta su uso.
5. Debe seguir la **forma oficial de instalación y registro de plasmoids de KDE Plasma**.
6. El estilo visual debe ser **cyberpunk sobrio / fósforo verde / HUD técnico**.
7. El plasmoid debe mostrar inicialmente todos estos bloques:
   - `severity`
   - `counters`
   - `snapshot`
   - `recent_events`
   - `driver_health`
   - `daily_history`
8. `inventory` queda **fuera del alcance inicial**.
9. `recent_events` **no muestra texto persistente** en la vista principal.
10. El texto del evento se ve al hacer clic y se muestra en un popup temporal.
11. El popup de evento dura **30 segundos** o hasta que el usuario lo cierre.
12. Debe haber notificación KDE cuando aparezca un evento nuevo.
13. Al hacer clic en la notificación KDE se debe abrir la **web completa**.
14. El plasmoid debe incluir una acción clara para **abrir la web**.
15. La web debe abrirse en el **navegador por defecto** del sistema.
16. Tras instalarse, el plasmoid debe **añadirse automáticamente al escritorio**.

---

## 3. Fuente de datos

## 3.1 Fuente de verdad

El plasmoid consumirá el mismo fichero que consume la web:

- `/var/lib/mbp-watch/data.json`

La web actual sigue siendo la referencia funcional canónica.

Regla:

> `mbp_watch.sh` genera estado  
> `data.json` lo publica  
> web y plasmoid consumen el mismo modelo

## 3.2 URL oficial de la web

La vista completa oficial será:

- `http://127.0.0.1:7070/report.html`

Debe tratarse como valor configurable del plasmoid, aunque por defecto use esa URL.

---

## 4. Bloques incluidos en v1

## 4.1 Severity

Origen:

- `severity.class`
- `severity.title`
- `severity.text`
- `severity.reason`

Uso:

- estado global del sistema,
- tono visual general del plasmoid,
- texto breve visible de forma persistente.

## 4.2 Counters

Origen:

- `counters.wifi`
- `counters.connectivity`
- `counters.gpu`
- `counters.bluetooth`
- `counters.thermal`
- `counters.pm`
- `counters.audio`
- `counters.throttle`

Uso:

- matriz compacta o lista de indicadores,
- color semafórico consistente con la web,
- acento especial si hay evento reciente no leído relacionado.

## 4.3 Snapshot

Origen:

- `snapshot.temperatures`
- `snapshot.fan_rpm`
- `snapshot.cpu_perf`
- `snapshot.load_and_system`
- `snapshot.battery`
- `snapshot.wifi_link`
- `snapshot.wifi_analysis`

Uso:

- telemetría persistente y compacta,
- barras finas,
- lectura de un vistazo.

## 4.4 Recent Events

Origen:

- `recent_events`

Uso:

- no se muestra el texto en la vista persistente,
- sólo se muestran indicadores/accentos por categoría o subsistema,
- el texto técnico aparece en popup al interactuar.

## 4.5 Driver Health

Origen:

- `driver_health.captured`
- `driver_health.drivers[]`

Uso:

- resumen persistente compacto,
- no lista grande,
- detalle secundario o expandible.

## 4.6 Daily History

Origen:

- `daily_history[]`

Uso:

- resumen visual pequeño,
- no histórico grande,
- lectura compacta del estado reciente multi-día.

## 4.7 Fuera de alcance inicial

- `inventory`

Motivo:

- ocupa demasiado para la densidad visual objetivo,
- aporta menos valor al overlay persistente,
- ya está disponible en la web completa.

---

## 5. Comportamiento de eventos

## 5.1 Regla principal

Los eventos recientes deben existir en dos niveles:

1. **nivel persistente del plasmoid**: sólo indicador visual,
2. **nivel de detalle**: popup local del plasmoid.

## 5.2 Vista persistente

No debe mostrar:

- texto completo del evento,
- lista de logs abierta,
- consola embebida.

Sí debe mostrar:

- categoría afectada,
- estado no leído,
- acento rojo o ámbar según severidad,
- clic para abrir detalle.

## 5.3 Popup de evento

Al hacer clic en un evento o subsistema afectado:

- se abre un popup pequeño,
- se muestra el detalle técnico,
- se permite copiar,
- se permite marcar como leído,
- se permite abrir la web completa,
- se cierra tras 30s o al cerrarlo manualmente.

## 5.4 Estado leído/no leído

Este estado no lo gestiona `mbp_watch.sh`.

Lo gestiona el plasmoid localmente.

Debe guardar al menos:

- identificador del evento,
- timestamp visto,
- estado leído/no leído.

Persistencia recomendada:

- almacenamiento local de Plasma / config del plasmoid.

## 5.5 Identificador de evento

Para evitar ambigüedad, el plasmoid debe considerar cada evento como combinación de:

- `event.ts`
- `event.category`
- `event.message`

Ese conjunto sirve como clave lógica estable para la v1.

---

## 6. Notificaciones KDE

## 6.1 Cuándo notificar

Cuando el plasmoid detecte un evento nuevo no visto previamente.

## 6.2 Qué debe mostrar la notificación

La notificación KDE debe incluir:

- categoría del evento,
- resumen corto,
- timestamp o indicación de recencia,
- acción para abrir la web.

No debe intentar meter:

- texto largo completo,
- listas,
- demasiada interacción.

## 6.3 Acción al hacer clic

Al hacer clic en la notificación:

- abrir la web completa de MBP Watch,
- usando el navegador por defecto del sistema.

## 6.4 Relación con el popup local

La notificación KDE no sustituye al popup del plasmoid.

La notificación:

- avisa cuando el escritorio está cubierto por ventanas.

El popup del plasmoid:

- sirve para revisar el detalle directamente desde el overlay.

---

## 7. Apertura de la web

## 7.1 Acción visible en el plasmoid

Debe existir una acción pequeña y clara en el plasmoid para:

- abrir la web completa.

## 7.2 Acción visible en popup

El popup de evento también puede incluir:

- botón o icono `Open dashboard`.

## 7.3 Comportamiento

Siempre debe abrir:

- `http://127.0.0.1:7070/report.html`

en el navegador por defecto del sistema.

---

## 8. Layout v1

## 8.1 Dirección visual

La referencia de estilo es `docs/plasmoid.jpg`.

Eso implica:

- columna lateral derecha,
- overlay integrado con el wallpaper,
- barras finas,
- transparencia alta,
- verde fósforo dominante,
- rojo sólo para anomalías,
- estética cyberpunk técnica, no ventana tradicional.

## 8.2 Regla de layout

No se debe intentar clonar la web como tarjetas apiladas grandes.

Debe hacerse una **reinterpretación visual fiel**:

- mismos datos,
- misma semántica,
- distinto lenguaje de densidad visual.

## 8.3 Orden de bloques recomendado

1. `severity`
2. `counters`
3. `snapshot`
4. `recent_events` como indicadores
5. `driver_health` en resumen compacto
6. `daily_history` en resumen compacto

## 8.4 Reglas por bloque

### Severity

- visible siempre,
- compacto,
- mensaje corto,
- razón resumida.

### Counters

- visibles siempre,
- lista compacta o matriz ligera,
- barras finas cuando ayuden.

### Snapshot

- visible siempre,
- resumido,
- sin tablas grandes.

### Recent Events

- visible como indicadores,
- sin texto persistente.

### Driver Health

- resumen compacto,
- no listado detallado completo.

### Daily History

- mini-resumen visual,
- no gráfica grande.

---

## 9. Integración en bootstrap

## 9.1 Punto de integración

La instalación debe integrarse en `bootstrap` como opción aceptable por el usuario.

## 9.2 Regla de activación

Sólo debe instalarse si:

- el usuario usa KDE Plasma,
- el usuario acepta expresamente el plasmoid.

## 9.3 Qué debe hacer bootstrap

1. Instalar MBP Watch si procede.
2. Instalar el plasmoid por la vía oficial de Plasma.
3. Registrar el plasmoid si hace falta.
4. Añadirlo automáticamente al escritorio Plasma.
5. Dejar configurada la URL del dashboard.

## 9.4 Qué no debe hacer bootstrap

- no duplicar la lógica de MBP Watch,
- no tocar semáforos ni criterios de backend,
- no forzar instalación en entornos no Plasma.

---

## 10. Arquitectura mínima recomendada

## 10.1 Separación

- `mbp_watch.sh`: genera estado
- web: vista completa
- plasmoid: vista compacta + eventos + notificaciones

## 10.2 Componentes esperables del plasmoid

Arquitectura orientativa:

- `main.qml`
- `SeverityBlock.qml`
- `CountersBlock.qml`
- `SnapshotBlock.qml`
- `EventsBlock.qml`
- `EventPopup.qml`
- `DriverHealthBlock.qml`
- `DailyHistoryBlock.qml`
- helper de lectura de `data.json`
- helper de persistencia de eventos vistos
- helper de apertura de URL
- helper de notificaciones KDE

## 10.3 Persistencia local

El plasmoid debe persistir localmente:

- eventos vistos,
- preferencia de URL si se hace configurable,
- quizá refresco y opacidad en fases posteriores.

---

## 11. Fases de implementación recomendadas

## 11.1 Fase 1

- shell del plasmoid,
- lectura de `data.json`,
- `severity`,
- `counters`,
- acción `Open dashboard`.

## 11.2 Fase 2

- `snapshot`,
- layout principal completo.

## 11.3 Fase 3

- `recent_events` como indicadores,
- popup local,
- copy,
- mark read,
- persistencia local de vistos.

## 11.4 Fase 4

- notificaciones KDE,
- clic para abrir la web.

## 11.5 Fase 5

- `driver_health`,
- `daily_history`,
- integración final en `bootstrap`.

---

## 12. Resumen v1

La v1 del plasmoid debe ser un overlay KDE Plasma:

- compacto,
- cyberpunk sobrio,
- integrado visualmente con el wallpaper,
- basado exactamente en los datos actuales de MBP Watch,
- con eventos tratados como indicadores + popup,
- con aviso por notificación KDE,
- y con la web como vista completa oficial.

No es una app nueva.

Es una vista de escritorio persistente del sistema ya existente.
