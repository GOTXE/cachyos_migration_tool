# MBP Watch KDE Plasmoid v1 — Contrato de integración en `bootstrap.sh`

## 1. Objetivo

Definir cómo debe integrarse el plasmoid `mbp-watch` en [src/modules/bootstrap.sh](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/bootstrap.sh:1) sin ambigüedad:

- funciones nuevas,
- orden de ejecución,
- límites de responsabilidad,
- comportamiento ante error,
- y criterios de validación.

Este documento no implementa el plasmoid. Define el contrato exacto para que luego pueda codificarse de forma mecánica.

Documentos base:

- [mbp-watch-kde-plasmoid-v1-spec.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)
- [mbp-watch-kde-plasmoid-v1-mapping.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)
- [mbp-watch-kde-plasmoid-v1-file-structure.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-file-structure.md:1)
- [mbp-watch-kde-plasmoid-v1-installation-flow.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-installation-flow.md:1)

---

## 2. Principio general

`bootstrap.sh` debe encargarse sólo de la orquestación.

No debe contener:

- lógica QML,
- JSON del plasmoid,
- bloques grandes de JavaScript inline,
- parsing complejo de `metadata.json`,
- ni lógica de negocio del overlay.

Sí debe contener:

- detección de entorno KDE,
- resolución del usuario de escritorio,
- prompts de aceptación,
- invocación de instalación,
- invocación de auto-add,
- logging,
- y degradación segura.

---

## 3. Punto de integración en el flujo actual

La integración del plasmoid debe vivir dentro del flujo de `bootstrap`, después de:

1. instalación base del sistema,
2. instalación de dependencias necesarias para KDE,
3. e instalación de `mbp_watch` backend.

Orden v1 recomendado:

1. paquetes comunes
2. paquetes KDE
3. herramientas auxiliares
4. instalación `mbp_watch`
5. instalación opcional del plasmoid KDE

Motivo:

- el plasmoid depende de Plasma
- y conceptualmente depende de que exista `mbp_watch` sirviendo `data.json` y la web

---

## 4. Nuevas funciones requeridas

La implementación en [bootstrap.sh](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/bootstrap.sh:1) debe añadir estas funciones.

## 4.1 `is_kde_plasma_session()`

Responsabilidad:

- detectar si el entorno objetivo es KDE Plasma

Entrada:

- ninguna

Salida:

- código `0` si el entorno es KDE Plasma
- código distinto de `0` si no lo es

Reglas:

- usar señales simples y robustas
- no depender de una sola variable frágil

Chequeos mínimos:

- `XDG_CURRENT_DESKTOP`
- `KDE_FULL_SESSION`
- presencia de `plasmashell` o herramientas Plasma

## 4.2 `resolve_desktop_target_user()`

Responsabilidad:

- resolver el usuario real sobre el que debe instalarse el plasmoid

Entrada:

- ninguna

Salida:

- imprimir usuario objetivo

Prioridad:

1. `SUDO_USER` si existe y no es `root`
2. `$USER` si no es `root`
3. fallback explícito a error si sólo queda `root`

Motivo:

- el plasmoid es per-user
- no debe instalarse en el perfil de `root`

## 4.3 `resolve_desktop_target_uid()`

Responsabilidad:

- obtener el UID del usuario objetivo del escritorio

Entrada:

- nombre de usuario

Salida:

- UID numérico

## 4.4 `has_plasma_session_bus()`

Responsabilidad:

- comprobar si existe un bus de sesión utilizable para Plasma

Entrada:

- UID objetivo

Salida:

- código `0` si existe `/run/user/<uid>/bus`

## 4.5 `has_required_plasmoid_tools()`

Responsabilidad:

- validar binarios mínimos

Debe comprobar:

- `kpackagetool6`
- `qdbus6`

Opcional para validación posterior:

- `plasmawindowed`

## 4.6 `get_mbp_plasmoid_source_dir()`

Responsabilidad:

- resolver la ruta absoluta del plasmoid dentro del repo

Salida esperada:

```text
<repo>/assets/plasmoids/mbp-watch
```

## 4.7 `is_mbp_plasmoid_installed()`

Responsabilidad:

- detectar si el plasmoid ya está instalado para el usuario objetivo

Estrategia:

- ejecutar `kpackagetool6 --type Plasma/Applet --list`
- buscar `io.github.gtx.mbpwatch`

## 4.8 `install_or_upgrade_mbp_plasmoid()`

Responsabilidad:

- instalar o actualizar el paquete del plasmoid

Entrada:

- usuario objetivo
- ruta del plasmoid

Lógica:

1. si ya está instalado, usar `--upgrade`
2. si no, usar `--install`

Regla:

- siempre ejecutar como usuario objetivo
- nunca usar `--global` en v1

## 4.9 `build_mbp_plasmoid_autoload_script()`

Responsabilidad:

- generar el JavaScript exacto para `evaluateScript`

Entrada:

- ninguna o plugin id centralizado

Salida:

- script JS en stdout

Regla:

- esta función debe contener el script de forma legible
- no debe dejar el JS disperso por varias funciones

## 4.10 `auto_add_mbp_plasmoid_to_desktop()`

Responsabilidad:

- invocar `qdbus6 ... evaluateScript` contra `org.kde.plasmashell`

Entrada:

- usuario objetivo
- UID objetivo

Debe:

1. exportar `XDG_RUNTIME_DIR`
2. exportar `DBUS_SESSION_BUS_ADDRESS`
3. ejecutar como usuario objetivo
4. usar script idempotente

## 4.11 `install_mbp_plasmoid_if_accepted()`

Responsabilidad:

- ser el orquestador principal del bloque de plasmoid en bootstrap

Debe:

1. comprobar si estamos en KDE
2. preguntar al usuario si desea instalarlo
3. validar herramientas
4. resolver usuario y uid
5. instalar o actualizar
6. intentar auto-add
7. loggear resultado final

---

## 5. Variables y constantes nuevas

Deben centralizarse al principio del módulo o en bloque de constantes claramente visible:

```bash
MBP_PLASMOID_ID="io.github.gtx.mbpwatch"
MBP_PLASMOID_PACKAGE_TYPE="Plasma/Applet"
MBP_PLASMOID_RELATIVE_DIR="assets/plasmoids/mbp-watch"
MBP_PLASMOID_WEB_URL="http://127.0.0.1:7070/report.html"
MBP_PLASMOID_POPUP_TTL_MS="30000"
```

Regla:

- no repetir strings mágicos por el archivo

---

## 6. Contrato del prompt al usuario

La instalación del plasmoid debe ser opt-in.

Texto esperado de intención:

- explicar que instala un overlay de escritorio KDE para `mbp_watch`
- explicar que abre la web completa cuando haya avisos o clic del usuario
- explicar que se añadirá automáticamente al escritorio si Plasma está activo

La negativa del usuario:

- no debe tratarse como error
- sólo como `skip`

---

## 7. Flujo exacto de ejecución

El bloque de integración debe seguir este orden:

1. `is_kde_plasma_session`
2. si no es KDE:
   - log informativo
   - return 0
3. prompt de aceptación
4. si usuario rechaza:
   - log informativo
   - return 0
5. `has_required_plasmoid_tools`
6. `resolve_desktop_target_user`
7. `resolve_desktop_target_uid`
8. `get_mbp_plasmoid_source_dir`
9. validar que la ruta existe
10. `install_or_upgrade_mbp_plasmoid`
11. `has_plasma_session_bus`
12. si no hay bus:
   - log warning
   - terminar con paquete instalado pero sin auto-add
13. `auto_add_mbp_plasmoid_to_desktop`
14. si falla auto-add:
   - log warning
   - terminar con paquete instalado
15. log success final

---

## 8. Script exacto de auto-add que debe construirse

La implementación debe generar un JS equivalente a este contrato:

```javascript
const pluginId = "io.github.gtx.mbpwatch";
if (!knownWidgetTypes.includes(pluginId)) {
    throw new Error("plasmoid-not-installed");
}

const allDesktops = desktops();
for (const desktop of allDesktops) {
    const existing = desktop.widgets(pluginId);
    if (existing && existing.length > 0) {
        "already-present";
    }
}

let targetDesktop = null;
if (typeof desktopForScreen === "function") {
    targetDesktop = desktopForScreen(0);
}
if (!targetDesktop && allDesktops.length > 0) {
    targetDesktop = allDesktops[0];
}
if (!targetDesktop) {
    throw new Error("no-desktop");
}

const geom = screenGeometry(targetDesktop.screen >= 0 ? targetDesktop.screen : 0);
const width = 360;
const margin = 24;
const top = 24;
const height = Math.min(Math.max(geom.height - 48, 480), 920);
const x = geom.x + geom.width - width - margin;
const y = geom.y + top;

targetDesktop.addWidget(pluginId, x, y, width, height);
"created";
```

Notas:

- la implementación final puede refinar sintaxis o fallbacks
- pero no debe cambiar la semántica

---

## 9. Gestión de errores

Los errores deben clasificarse así:

## 9.1 Error bloqueante del bloque plasmoid

Casos:

- no existe el directorio del plasmoid en el repo
- no existe `kpackagetool6`
- no se puede resolver usuario objetivo válido

Comportamiento:

- warning claro
- no tumbar todo el bootstrap

## 9.2 Error no bloqueante tras instalar paquete

Casos:

- no hay bus de sesión
- `qdbus6` no conecta a `org.kde.plasmashell`
- auto-add falla por sesión no activa

Comportamiento:

- dejar paquete instalado
- mostrar recuperación manual

## 9.3 No error

Casos:

- usuario rechaza instalación
- no es entorno KDE
- el widget ya estaba presente en escritorio

---

## 10. Integración con logging existente

Este bloque debe usar el sistema de logging ya presente en `bootstrap.sh`:

- `log`
- `log_info`
- `log_warn`
- `log_success`

No introducir otro sistema paralelo.

Mensajes mínimos:

- KDE detectado o no detectado
- usuario objetivo resuelto
- instalación o actualización del paquete
- auto-add realizado o degradado
- instrucción manual si procede

---

## 11. No responsabilidades de `bootstrap.sh`

No debe hacer en v1:

- editar `plasma-org.kde.plasma.desktop-appletsrc` a mano
- matar o reiniciar `plasmashell` a la fuerza
- tocar layout de otros widgets del usuario
- duplicar estado del plasmoid fuera de Plasma
- instalar dependencias de desarrollo del SDK sólo para el plasmoid

Esto es importante: el único mecanismo admitido para añadir la instancia es scripting oficial sobre `org.kde.plasmashell`.

---

## 12. Validación mínima tras implementación

La implementación en `bootstrap.sh` se dará por buena si cumple:

1. en KDE Plasma con sesión activa:
   - instala el paquete
   - añade una única instancia al escritorio
2. en segundo despliegue:
   - actualiza sin duplicar instancia
3. fuera de KDE:
   - hace `skip` limpio
4. con paquete instalado pero sin sesión D-Bus:
   - instala y deja warning
5. si el usuario rechaza:
   - no hace nada más

---

## 13. Secuencia recomendada de implementación

Para codificar esto con bajo riesgo, el orden recomendable es:

1. constantes del plasmoid
2. helpers de detección de entorno y usuario
3. helper de instalación/upgrade
4. helper de construcción del JS
5. helper de auto-add
6. orquestador `install_mbp_plasmoid_if_accepted`
7. llamada al orquestador en el flujo principal

---

## 14. Estado final esperado

Cuando esta integración esté implementada, `bootstrap.sh` debe poder:

- ofrecer el plasmoid como opción clara
- instalarlo correctamente para el usuario real
- añadirlo automáticamente al escritorio cuando Plasma esté disponible
- y degradar sin romper el resto del bootstrap si sólo falla la parte gráfica
