# MBP Watch KDE Plasmoid v1 — Guía de ejecución para IA

## 1. Objetivo

Definir una guía explícita para que una IA implemente el plasmoid `mbp-watch` con el menor margen posible de desviación:

- qué debe hacer,
- qué no debe hacer,
- en qué orden debe trabajar,
- qué documentos son fuente de verdad,
- y cómo usar Git para mantener trazabilidad real.

Esta guía está pensada para ejecución práctica con agentes tipo Codex.

---

## 2. Principio rector

La IA no debe “diseñar de nuevo” el plasmoid.

Debe:

1. leer los contratos ya definidos
2. implementarlos por tareas
3. validar cada bloque
4. dejar commits pequeños y trazables

Si encuentra una ambigüedad real:

- debe parar esa parte
- documentar la ambigüedad
- y no improvisar cambios de producto por su cuenta

---

## 3. Fuentes de verdad obligatorias

Antes de escribir código, la IA debe tomar como referencia obligatoria estos documentos:

1. [mbp-watch-kde-plasmoid-v1-spec.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)
2. [mbp-watch-kde-plasmoid-v1-mapping.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)
3. [mbp-watch-kde-plasmoid-v1-task-plan.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-task-plan.md:1)
4. [mbp-watch-kde-plasmoid-v1-file-structure.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-file-structure.md:1)
5. [mbp-watch-kde-plasmoid-v1-installation-flow.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-installation-flow.md:1)
6. [mbp-watch-kde-plasmoid-v1-bootstrap-integration.md](/path/to/repo/docs/mbp-watch-kde-plasmoid-v1-bootstrap-integration.md:1)

Regla:

- si el código propuesto contradice alguno de esos documentos, el código está mal salvo que antes se actualice el contrato documental

---

## 4. Alcance funcional cerrado de v1

La IA debe implementar sólo esto en v1:

- `severity`
- `counters`
- `snapshot`
- `recent_events` como indicadores sin texto persistente
- `driver_health` en versión compacta
- `daily_history` en versión compacta
- popup temporal de evento
- apertura de la web completa
- notificaciones KDE
- instalación opcional desde `bootstrap`
- añadido automático al escritorio

La IA no debe meter inicialmente:

- `inventory`
- vistas adicionales no especificadas
- settings avanzados no pedidos
- editores de configuración complejos
- layouts alternativos no pactados

---

## 5. Límites estrictos de diseño

La IA debe respetar estas restricciones:

1. no clonar la web 1:1 dentro del plasmoid
2. no convertir el overlay en una mini app genérica
3. no usar tarjetas grandes tipo dashboard estándar si rompen el estilo HUD
4. no introducir una estética que contradiga `docs/plasmoid.jpg`
5. no ampliar alcance visual con “ideas extra” no pedidas

Dirección visual obligatoria:

- cyberpunk sobrio
- verde fósforo como base
- compactación alta
- overlay lateral derecho
- lectura rápida y ambiental

---

## 6. Límites técnicos

La IA debe respetar también estos límites:

1. no modificar el contrato de `data.json` salvo necesidad real documentada
2. no depender de backend nuevo para la v1 del plasmoid
3. no editar manualmente archivos internos de configuración de Plasma como estrategia principal
4. no usar hacks fuera de `kpackagetool6` y `qdbus6` si existe vía oficial
5. no instalar el plasmoid globalmente en v1
6. no introducir dependencias innecesarias del SDK para el usuario final

---

## 7. Orden obligatorio de implementación

La IA debe seguir un orden secuencial parecido a este:

1. estructura base del paquete
2. `metadata.json` y validación Plasma 6
3. `main.qml` y shell visual
4. constantes y lectura segura de `data.json`
5. adaptador de estado
6. bloques visuales principales
7. sistema de eventos local
8. popup de evento
9. notificaciones KDE
10. acción `Open dashboard`
11. instalación/upgrade
12. auto-add en `bootstrap`

Regla:

- no saltar a la integración final si la lectura de datos y el shell básico aún no funcionan

---

## 8. Política de decisiones

La IA puede tomar decisiones menores de implementación, por ejemplo:

- nombres internos de propiedades
- pequeños helpers auxiliares
- factorizar QML o JS
- detalles de estilo dentro del marco definido

La IA no puede decidir unilateralmente:

- cambiar el plugin id
- cambiar la arquitectura de instalación
- cambiar bloques funcionales
- volver a incluir `inventory`
- hacer que el popup o la notificación abran otra cosa distinta de la web
- sustituir el modelo per-user por instalación global

Si alguna de esas decisiones pareciera necesaria, debe documentarse primero y esperar confirmación.

---

## 9. Política de Git y trazabilidad

Sí: usar Git con commits pequeños es lo correcto y debería ser obligatorio para esta implementación.

Motivo:

- permite aislar cada bloque funcional
- facilita rollback
- deja claro qué cambio introdujo cada comportamiento
- ayuda a revisar trabajo de IA por etapas

La IA debe trabajar con esta disciplina:

1. leer contrato
2. implementar un bloque
3. validar ese bloque
4. hacer commit pequeño
5. pasar al siguiente

No debe acumular un cambio masivo sin puntos de control.

---

## 10. Granularidad recomendada de commits

Un commit por bloque lógico cerrado.

Secuencia recomendada:

1. `Scaffold Plasma 6 plasmoid package`
2. `Add data source and state adapter`
3. `Implement severity and counters blocks`
4. `Implement snapshot compact blocks`
5. `Add recent event indicators and popup`
6. `Add KDE notifications and dashboard open action`
7. `Integrate plasmoid install flow into bootstrap`

Regla:

- si un cambio no puede explicarse en una sola frase corta, probablemente el commit es demasiado grande

---

## 11. Validación obligatoria antes de cada commit

Antes de cada commit, la IA debe validar como mínimo lo afectado por ese bloque.

Ejemplos:

- estructura de paquete reconocible
- `kpackagetool6` acepta el paquete
- `plasmawindowed <pluginId>` abre el plasmoid
- imports QML válidos
- el bloque visual renderiza sin romper el conjunto
- el auto-add no duplica instancia

Si no puede validar una parte:

- debe dejarlo explícito en el mensaje final del bloque
- y no fingir que está verificado

---

## 12. Qué debe evitar la IA al usar Git

La IA no debe:

- mezclar cambios de documentación y código sin relación
- reescribir commits previos sin necesidad
- usar un único commit “mega final”
- meter refactors no relacionados durante la implementación
- tocar archivos no implicados sólo por “limpieza”

También debe evitar:

- `git reset --hard`
- borrados destructivos no pedidos
- revertir cambios del usuario

---

## 13. Política de documentación durante la implementación

Si la IA descubre una necesidad real no cubierta por los contratos, debe actualizar primero la documentación relevante y luego implementar.

Orden correcto:

1. detectar hueco real
2. actualizar contrato
3. implementar
4. validar
5. commit

No al revés.

---

## 14. Plantilla mínima de ciclo por tarea

Cada tarea debería seguir este patrón:

1. leer documentos afectados
2. inspeccionar código actual
3. implementar sólo el bloque objetivo
4. validar localmente
5. resumir qué se hizo y qué no
6. hacer commit con mensaje corto e intencional

---

## 15. Definition of done de la IA para este proyecto

La IA sólo debe considerar un bloque “terminado” si:

1. cumple el contrato documental
2. no rompe el alcance cerrado de v1
3. usa la vía oficial de Plasma cuando aplica
4. queda validado localmente en la medida posible
5. queda aislado en Git con trazabilidad útil

---

## 16. Recomendación final

Sí, merece la pena este documento de guía para IA y sí, debe exigirse uso de Git con commits.

Sin esas dos cosas, el riesgo principal no es “que no funcione”, sino:

- que derive del contrato,
- que mezcle demasiadas decisiones a la vez,
- y que luego no sepas qué cambio de la IA introdujo cada comportamiento.

Para este plasmoid, la estrategia correcta es:

- contrato primero
- implementación por bloques
- validación por bloque
- commit por bloque
