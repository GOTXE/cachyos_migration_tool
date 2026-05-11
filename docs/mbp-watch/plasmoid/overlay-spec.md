# MBP Watch — Proyecto de plugin/overlay para KDE Plasma

## 1. Objetivo

Crear un **plugin de escritorio para KDE Plasma** (plasmoid/desktop widget) que muestre de forma **persistente, discreta y visualmente integrada en el escritorio** el estado del sistema recogido por **MBP Watch** en un **MacBook Pro 13" Retina 2015** con **CachyOS**.

El plugin no debe ser una app tradicional con ventana flotante ni una reinterpretación libre del dashboard web actual. Debe ser una **vista compacta y fiel** del sistema ya existente, reutilizando:

- los **mismos datos** que ya expone la web,
- la **misma lógica de severidad**,
- los **mismos rangos semafóricos**,
- y la **misma clasificación de eventos**.

La interfaz debe parecer parte del escritorio, casi como una **capa ambiental integrada en el wallpaper**, con una estética inspirada en:

- pantalla de fósforo verde,
- HUD técnico discreto,
- toques cyberpunk sobrios,
- semáforos en color solo cuando aporten información.

---

## 2. Principios del proyecto

### 2.1 Fuente de verdad

La **web actual es la referencia canónica**.

Regla principal:

> **Web = fuente de verdad**  
> **Plugin KDE = vista compacta del mismo modelo de datos**

El plugin **no debe inventar métricas**, ni renombrar bloques sin definirlo explícitamente, ni reagrupar datos arbitrariamente.

### 2.2 Objetivo funcional

El plugin debe servir para:

- ver el estado general del sistema de un vistazo,
- detectar rápidamente incidencias recientes,
- abrir detalles puntuales de un evento al hacer clic,
- copiar texto técnico del evento,
- mantener una presencia continua pero no intrusiva en el escritorio.

### 2.3 Objetivo visual

Debe verse como una **extensión del wallpaper**, no como una ventana superpuesta.

Eso implica:

- sin cajas fuertes,
- sin grandes tarjetas opacas,
- sin demasiada densidad visual,
- sin logs visibles permanentemente,
- sin ruido gráfico excesivo.

---

## 3. Contexto de uso

### 3.1 Equipo objetivo

- **Modelo**: MacBook Pro 13" Retina 2015 (MacBookPro12,1)
- **Sistema**: CachyOS
- **Escalado**: 150%
- **Entorno**: KDE Plasma

### 3.2 Implicaciones para el diseño

Al ser un portátil de 13" con escalado al 150%, la interfaz debe ser especialmente cuidadosa con:

- el tamaño de fuente,
- el ancho disponible,
- la altura del bloque,
- el peso visual,
- la legibilidad sin convertirse en un panel invasivo.

El plugin debe ser **útil en pantalla pequeña**, no solo bonito en una captura ideal.

---

## 4. Qué existe ya en la web

La referencia funcional y visual principal está en:

- `assets/diagnostics/web/report.html`
- `assets/diagnostics/web/report.js`
- `assets/diagnostics/web/report.css`

La web actual construye su contenido alrededor de estas estructuras:

- `severity`
- `counters`
- `snapshot`
- `recent_events`
- `driver_health`
- `daily_history`
- `inventory` / hardware inventory

### 4.1 Bloques visibles principales de la web

La web actual muestra al menos estos bloques:

1. Cabecera general.
2. Banner de severidad.
3. Contadores de incidencias.
4. Live Telemetry.
5. Recent Events.
6. Driver Health.
7. Daily History.
8. Hardware Inventory.

### 4.2 Elementos principales que deben influir en el plugin

Para el overlay persistente del escritorio, los bloques más relevantes son:

- `severity`
- `counters`
- `snapshot`
- `recent_events`

Los bloques siguientes son secundarios y, por tamaño o densidad, no deberían estar completos en la vista persistente:

- `driver_health`
- `daily_history`
- `inventory`

---

## 5. Qué debe mostrar el plugin KDE

## 5.1 Vista persistente principal

La vista persistente debe ser una **versión reducida** de la web, manteniendo la semántica.

Debe mostrar:

### A. Estado general

Tomado de `severity`:

- `severity.class`
- `severity.title`
- `severity.text`
- `severity.reason`

Esto debe dar el tono general del sistema.

Ejemplo conceptual:

- `Stable`
- `Warning`
- `Critical`

con una línea breve y una razón resumida.

### B. Contadores

Tomados de `counters`, con los nombres exactos usados por la web:

- `wifi` → **WI-FI**
- `connectivity` → **CONNECTIVITY**
- `gpu` → **GPU / DRM**
- `bluetooth` → **BLUETOOTH**
- `thermal` → **THERMAL / ACPI**
- `pm` → **SUSPEND / PM**
- `audio` → **AUDIO / HW**
- `throttle` → **THROTTLE EVENTS**

Estos deben presentarse como contadores compactos, no como una tabla grande.

### C. Live Telemetry

Tomado de `snapshot`, al menos en su parte relevante para vista rápida:

- `temperatures`
- `fan_rpm`
- `cpu_perf`
- `load_and_system`
- `battery`
- `wifi_link`

### D. Eventos recientes

Tomados de `recent_events`.

No deben mostrarse como lista completa fija en la vista principal. Deben reflejarse como:

- resaltado visual del bloque afectado,
- indicador de evento no leído,
- clic para abrir popup de detalle,
- opción de copiar el texto técnico.

---

## 6. Qué NO debe mostrar siempre

Para que el overlay siga siendo ligero y no invasivo, no debe mostrar de forma persistente:

- la lista completa de `recent_events`,
- el detalle completo de `driver_health`,
- la gráfica completa de `daily_history`,
- el `hardware inventory` completo,
- texto largo de logs,
- información de diagnóstico extensa,
- modales abiertos permanentemente.

Esos contenidos pueden existir como acciones secundarias:

- popup puntual,
- clic para abrir la web completa,
- vista expandida opcional,
- futura pantalla secundaria.

---

## 7. Mapeo funcional: web → plugin

## 7.1 Regla general

Cada elemento mostrado en el plugin debe poder mapearse a un origen claro en el dashboard web.

Formato conceptual de diseño:

`campo JSON → etiqueta visible → valor visible → color → barra → acción`

## 7.2 Mapeo principal recomendado

### Severity

Origen:

- `severity.class`
- `severity.title`
- `severity.text`
- `severity.reason`

Representación en plugin:

- título de estado,
- texto corto,
- pequeño indicador de severidad,
- razón resumida.

### Counters

Origen:

- `counters.wifi`
- `counters.connectivity`
- `counters.gpu`
- `counters.bluetooth`
- `counters.thermal`
- `counters.pm`
- `counters.audio`
- `counters.throttle`

Representación en plugin:

- fila compacta o matriz ligera,
- número visible,
- color según nivel,
- posible punto rojo si hay relación con eventos recientes no leídos.

### Snapshot — Temperature

Origen:

- `snapshot.temperatures`

Representación en plugin:

- temperatura actual relevante,
- barra fina,
- color con los mismos umbrales de la web.

### Snapshot — Fan

Origen:

- `snapshot.fan_rpm`

Representación en plugin:

- valor RPM,
- barra proporcional,
- color según la lógica actual de la web.

### Snapshot — CPU Perf

Origen:

- `snapshot.cpu_perf`

Representación en plugin:

- ratio o estado de frecuencia,
- estado de throttle,
- governor o modo, solo si cabe y aporta valor,
- barra fina y color coherente.

### Snapshot — Load & System

Origen:

- `snapshot.load_and_system`

Representación en plugin:

- carga resumida,
- datos de sistema solo si son visibles sin ruido,
- nunca en formato tabla grande en la vista persistente.

### Snapshot — Battery

Origen:

- `snapshot.battery`

Representación en plugin:

- porcentaje,
- estado,
- barra,
- color según los mismos rangos que usa la web.

### Snapshot — Wi-Fi Link

Origen:

- `snapshot.wifi_link`
- `snapshot.wifi_analysis`

Representación en plugin:

- estado del enlace,
- intensidad o resumen,
- color,
- clic para detalle si hay problemas o datos útiles.

### Recent Events

Origen:

- `recent_events`

Representación en plugin:

- indicador visual de evento reciente,
- popup por clic,
- botón de copiar,
- marca de leído,
- opcionalmente TTL visual del evento no leído.

---

## 8. Rangos y semáforos

## 8.1 Norma obligatoria

Los rangos y semáforos del plugin deben ser **exactamente los establecidos en la web**.

No deben redefinirse manualmente en el plugin salvo que se haga una refactorización explícita del backend/web y ambos se actualicen juntos.

## 8.2 Implicación técnica

El plugin debería, idealmente:

- reutilizar estados ya clasificados,
- o reutilizar la misma lógica de cálculo,
- o consumir un resumen derivado del backend/web,

pero evitar tener una tercera lógica paralela distinta.

## 8.3 Riesgo a evitar

El peor escenario sería:

- web mostrando un estado,
- overlay mostrando otro,
- backend teniendo una tercera interpretación.

Debe existir una **única lógica semafórica**.

---

## 9. Eventos recientes

## 9.1 Clasificación existente

Actualmente los eventos se filtran/categorizan en torno a:

- `wifi`
- `gpu`
- `power`
- `thermal`
- `audio`
- `bluetooth`
- `other`

Y además los contadores principales del dashboard incluyen:

- `wifi`
- `connectivity`
- `gpu`
- `bluetooth`
- `thermal`
- `pm`
- `audio`
- `throttle`

Esto significa que el plugin debe distinguir entre:

- **contadores agregados**,
- **eventos recientes concretos**.

No se deben mezclar ambas cosas sin criterio visual.

## 9.2 Comportamiento visual recomendado

Si existe un evento reciente no leído relacionado con un bloque:

- ese bloque cambia a rojo o recibe un acento rojo,
- no se muestra el texto completo en la vista principal,
- al hacer clic se abre un popup,
- el popup muestra el detalle,
- el usuario puede copiar el texto,
- el evento puede marcarse como leído.

## 9.3 Regla de UX importante

Separar siempre:

- **estado actual**
- **evento reciente**

porque no significan lo mismo.

Un subsistema puede estar ya normalizado pero conservar un evento reciente sin leer.

---

## 10. Interacción del popup de evento

## 10.1 Qué debe hacer

Al hacer clic en un indicador/bloque afectado por evento reciente, se abre una pequeña ventana emergente que permita:

- ver título/categoría,
- ver mensaje técnico breve,
- ver timestamp,
- copiar el contenido,
- marcar el evento como leído.

## 10.2 Qué no debe hacer

No debe convertirse en:

- un modal grande,
- una consola embebida,
- una lista enorme de eventos,
- una ventana compleja de gestión.

## 10.3 Copiado del texto

El texto copiado debe seguir el mismo formato o filosofía que la web actual, para que sea útil al pegarlo en:

- Codex,
- Claude,
- un ticket,
- un chat técnico,
- documentación.

---

## 11. Diseño visual del plugin

## 11.1 Dirección estética

La estética deseada es una mezcla de:

- pantalla de fósforo verde,
- interfaz técnica retro,
- HUD discreto,
- cyberpunk sobrio,
- colores de semáforo limitados a donde aporten información.

## 11.2 Reglas visuales

### Debe tener

- predominio del verde,
- barras finas horizontales,
- tipografía limpia y técnica,
- mucha transparencia,
- contenedores casi invisibles,
- integración con el fondo,
- jerarquía clara,
- colores ámbar/rojo solo cuando proceda.

### Debe evitar

- cajas fuertes,
- tarjetas muy marcadas,
- marcos grandes,
- sombras pesadas,
- botones enormes,
- saturación visual,
- animaciones llamativas,
- estética “app flotante”.

## 11.3 Sensación buscada

Debe parecer más una **telemetría ambiental del sistema** que un panel tradicional.

Es decir:

- visible,
- útil,
- elegante,
- no invasivo.

---

## 12. Posición, tamaño y presencia en escritorio

## 12.1 Comportamiento esperado

El plugin debe vivir **en el escritorio**, como si formara parte del wallpaper.

No debe depender de estar en la barra de panel como elemento principal.

## 12.2 Posición sugerida

La zona preferente es el lateral derecho o derecha-superior, donde:

- no tape demasiado el fondo,
- no interfiera con iconos,
- no compita con ventanas centradas.

## 12.3 Tamaño orientativo

Dado el equipo objetivo y el escalado, el tamaño debe ser contenido.

Orientativamente:

- ancho moderado,
- alto aproximado equivalente a 1/3 vertical,
- suficiente para varias filas legibles,
- no tan grande como para dominar el escritorio.

## 12.4 Intrusión visual

El objetivo es una presencia **baja o media-baja**.

El usuario debe poder tenerlo siempre visible sin sentir que ocupa la pantalla.

---

## 13. Arquitectura propuesta

## 13.1 Principio de separación

Separar de forma estricta:

- **backend**: recopila, filtra, clasifica y decide,
- **frontend KDE**: muestra, resalta, permite clics y copia.

## 13.2 Regla clave

El plugin KDE **no debe rehacer el backend**.

Debe consumir un estado ya preparado, idealmente el mismo que alimenta la web.

## 13.3 Flujo conceptual

1. `mbp_watch.sh` recopila datos.
2. El backend genera estado estructurado.
3. La web actual lo consume y representa.
4. El plugin KDE consume ese mismo modelo o un derivado fiel.
5. El plugin solo compacta y pinta.

## 13.4 Beneficios

- una sola fuente de verdad,
- menos errores,
- menos divergencias,
- mantenimiento más sencillo,
- consistencia entre web y escritorio.

---

## 14. Tecnología objetivo en KDE Plasma

## 14.1 Tipo de integración

La solución adecuada es un **plasmoid/widget de escritorio para Plasma**, no una página web embebida ni una app de navegador incrustada.

## 14.2 Motivos

Un widget nativo Plasma permite:

- mejor integración estética,
- menor consumo,
- mejor comportamiento en escritorio,
- interacción natural con Plasma,
- sensación de componente del sistema.

## 14.3 Lo que no se recomienda

No se recomienda como solución principal:

- incrustar la web en una mini webview,
- un navegador embebido permanente,
- un dashboard HTML completo dentro del escritorio.

Eso sería más pesado, menos elegante y menos coherente con el objetivo visual.

---

## 15. Alcance funcional recomendado para v1

## 15.1 Debe incluir

- estado general (`severity`),
- contadores (`counters`),
- telemetría compacta (`snapshot`),
- indicadores de evento reciente,
- popup con detalle y copia,
- apertura de la web completa como acción opcional,
- estilo visual integrado con el escritorio.

## 15.2 Puede incluir si cabe bien

- estado de leído/no leído,
- pequeño TTL visual del evento,
- refresco configurable,
- opacidad configurable,
- selección de bloques visibles,
- cambio de tamaño dentro de unos márgenes.

## 15.3 Debe quedar fuera de v1

- editor complejo de configuración,
- histórico completo dentro del overlay,
- `daily_history` completo dentro del plugin,
- `inventory` completo visible siempre,
- controles peligrosos del sistema,
- lógica de backend duplicada.

---

## 16. Configuración recomendada del plugin

En la configuración del plasmoid tendría sentido permitir:

- posición y tamaño,
- opacidad,
- modo más compacto o más detallado,
- mostrar/ocultar razón de severidad,
- mostrar/ocultar ciertos bloques secundarios,
- tiempo de refresco,
- comportamiento del rojo de eventos recientes,
- acción por clic en título (abrir web / expandir / nada).

No debería permitir alterar:

- los rangos semafóricos,
- la lógica de severidad,
- la clasificación de backend,

porque eso debe permanecer centralizado.

---

## 17. Riesgos del proyecto

## 17.1 Riesgo de divergencia con la web

Si el plugin acaba reimplementando su propia lógica, puede mostrar estados inconsistentes.

Mitigación:

- reutilizar exactamente el modelo de datos,
- documentar el mapeo web → plugin,
- minimizar lógica propia del frontend.

## 17.2 Riesgo de sobrecarga visual

Si se intenta meter demasiado contenido, el overlay dejará de parecer parte del wallpaper.

Mitigación:

- limitar bloques visibles,
- evitar texto largo,
- usar popup para detalle.

## 17.3 Riesgo de mala legibilidad en portátil

En 13" Retina a 150% es fácil que algo se vea grande o, si se compacta demasiado, ilegible.

Mitigación:

- diseñar pensando primero en ese portátil,
- no fiarse de mockups a tamaño grande,
- priorizar contraste, jerarquía y densidad baja.

## 17.4 Riesgo de consumo innecesario

Si el plugin recalcula demasiado o usa técnicas pesadas, perderá elegancia práctica.

Mitigación:

- refresco razonable,
- sin web embebida,
- sin lógica duplicada,
- sin gráficos pesados persistentes.

---

## 18. Decisiones de diseño ya tomadas

A partir de esta conversación, estas decisiones quedan bastante claras:

1. Debe ser un **plugin/widget de escritorio de KDE Plasma**.
2. Debe sentirse como **parte del wallpaper**.
3. El estilo debe ser **fósforo verde + cyberpunk sobrio**.
4. Debe ser **poco intrusivo visualmente**.
5. No debe usar **cajas fuertes**.
6. Debe usar **barras finas** y color semafórico.
7. Los datos deben ser **exactamente los de la web**.
8. Los rangos deben ser **exactamente los de la web**.
9. Los eventos recientes deben resaltarse en rojo, **sin mostrar el texto hasta hacer clic**.
10. El popup debe permitir **copiar el texto**.
11. La vista principal no debe mostrar logs largos.
12. Debe funcionar pensando en un **MBP 13" Retina 2015 con escalado 150%**.

---

## 19. Especificación funcional mínima antes de empezar a implementar

Antes de escribir código del plugin, conviene dejar cerrado un documento de mapeo exacto con esta estructura:

### Por cada elemento visible del plugin

- nombre visible,
- origen exacto en el JSON,
- regla de color,
- regla de barra,
- criterio de resaltado por evento,
- acción al hacer clic,
- si entra o no en la vista compacta.

Ejemplo de plantilla conceptual:

- **Elemento**: Battery
- **Origen**: `snapshot.battery`
- **Valor visible**: porcentaje + estado
- **Barra**: sí
- **Color**: el definido por la web
- **Evento relacionado**: `power` si aplica
- **Popup**: solo si hay evento reciente
- **Vista compacta**: sí

Este paso evitará desviaciones entre la web y el overlay.

---

## 20. Propuesta de entregables del proyecto

## 20.1 Entregable 1 — Especificación visual/funcional

Documento con:

- mapeo web → plugin,
- wireframe,
- reglas visuales,
- reglas de interacción,
- bloques incluidos y excluidos.

## 20.2 Entregable 2 — Plasmoid v1

Plugin funcional que:

- se coloca en escritorio Plasma,
- consume el estado correcto,
- pinta el overlay,
- resalta eventos,
- abre popup,
- permite copiar,
- abre la web completa si se quiere.

## 20.3 Entregable 3 — Ajuste fino para uso real

Pruebas en el MBP real para ajustar:

- tamaño,
- opacidad,
- legibilidad,
- refresco,
- peso visual,
- claridad de alertas.

---

## 21. Resumen ejecutivo

Este proyecto consiste en construir un **overlay/plasmoid de escritorio para KDE Plasma** que actúe como una **vista compacta, persistente y no intrusiva del dashboard MBP Watch ya existente**.

Las ideas clave son:

- no reinventar el modelo,
- no duplicar la lógica,
- no convertirlo en una app flotante,
- mantener fidelidad total a la web,
- usar una estética técnica verde discreta,
- mostrar el estado del sistema de forma continua,
- usar el clic solo para revelar detalles y copiar eventos.

La forma correcta de entenderlo es:

> **No es una nueva app.**  
> **Es una capa de telemetría ambiental del escritorio basada en la web actual.**

