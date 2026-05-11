# MBP Watch KDE Plasmoid v1 — Script exacto de auto-add para Plasma

## 1. Objetivo

Definir el script JavaScript exacto que debe usar el flujo de auto-add del plasmoid `mbp-watch` vía:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "<script>"
```

Este documento fija:

- la lógica exacta,
- los valores iniciales de geometría,
- los resultados esperados,
- y el formato recomendado para integrarlo en `bootstrap.sh`.

Documentos relacionados:

- [mbp-watch-kde-plasmoid-v1-installation-flow.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-installation-flow.md:1)
- [mbp-watch-kde-plasmoid-v1-bootstrap-integration.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-bootstrap-integration.md:1)

---

## 2. Requisitos funcionales cerrados

El script debe cumplir esto:

1. comprobar que el plasmoid está instalado
2. no duplicar instancias
3. elegir un desktop válido
4. calcular una geometría inicial razonable a la derecha
5. crear exactamente una instancia si no existía
6. devolver un resultado interpretable por el shell llamante

No debe:

- mover instancias ya existentes
- borrar widgets previos
- tocar otros plasmoids
- editar archivos de configuración de Plasma directamente

---

## 3. Plugin id fijo

El script v1 debe trabajar con:

```text
io.github.gtx.mbpwatch
```

Ese valor debe coincidir con `KPlugin.Id` del `metadata.json`.

---

## 4. Script canónico v1

Este es el script canónico que debe usarse como base de implementación:

```javascript
const pluginId = "io.github.gtx.mbpwatch";
const widgetWidth = 360;
const widgetMargin = 24;
const widgetTop = 24;
const widgetMinHeight = 480;
const widgetMaxHeight = 920;

function widgetAlreadyPresent(allDesktops, expectedPluginId) {
    for (const desktop of allDesktops) {
        if (!desktop) {
            continue;
        }

        const typedWidgets = desktop.widgets(expectedPluginId);
        if (typedWidgets && typedWidgets.length > 0) {
            return true;
        }

        const ids = desktop.widgetIds || [];
        for (const id of ids) {
            const widget = desktop.widgetById(id);
            if (widget && widget.type === expectedPluginId) {
                return true;
            }
        }
    }

    return false;
}

if (!knownWidgetTypes.includes(pluginId)) {
    "ERROR:plasmoid-not-installed";
} else {
    const allDesktops = desktops();

    if (widgetAlreadyPresent(allDesktops, pluginId)) {
        "OK:already-present";
    } else {
        let targetDesktop = null;

        if (typeof desktopForScreen === "function") {
            targetDesktop = desktopForScreen(0);
        }

        if (!targetDesktop && allDesktops.length > 0) {
            targetDesktop = allDesktops[0];
        }

        if (!targetDesktop) {
            "ERROR:no-desktop";
        } else {
            const targetScreen = targetDesktop.screen >= 0 ? targetDesktop.screen : 0;
            const geom = screenGeometry(targetScreen);
            const widgetHeight = Math.min(Math.max(geom.height - 48, widgetMinHeight), widgetMaxHeight);
            const widgetX = geom.x + geom.width - widgetWidth - widgetMargin;
            const widgetY = geom.y + widgetTop;

            const widget = targetDesktop.addWidget(
                pluginId,
                widgetX,
                widgetY,
                widgetWidth,
                widgetHeight
            );

            if (!widget) {
                "ERROR:create-failed";
            } else {
                "OK:created";
            }
        }
    }
}
```

---

## 5. Semántica exacta

## 5.1 Comprobación de instalación

Se usa:

```javascript
knownWidgetTypes.includes(pluginId)
```

Motivo:

- es la vía expuesta por la API oficial de Plasma scripting

## 5.2 Comprobación de duplicados

Se hace doble comprobación:

1. `desktop.widgets(pluginId)`
2. fallback recorriendo `widgetIds` y `widgetById(id).type`

Motivo:

- dejar el comportamiento más robusto ante diferencias menores entre builds

## 5.3 Selección de desktop

Orden:

1. `desktopForScreen(0)` si existe
2. `desktops()[0]`

Esto deja una política simple y estable para v1.

## 5.4 Geometría inicial

Los valores de v1 quedan fijados así:

```text
width = 360
margin = 24
top = 24
minHeight = 480
maxHeight = 920
height = clamp(screenHeight - 48, 480, 920)
x = screenX + screenWidth - width - margin
y = screenY + top
```

La geometría sólo aplica cuando se crea la primera instancia.

---

## 6. Contrato de salida al shell

El script debe devolver uno de estos resultados literales:

```text
OK:created
OK:already-present
ERROR:plasmoid-not-installed
ERROR:no-desktop
ERROR:create-failed
```

Esto permite a `bootstrap.sh` mapear fácilmente los outcomes.

Regla:

- no inventar más estados en v1 salvo necesidad real documentada

---

## 7. Mapeo shell recomendado

`bootstrap.sh` debería interpretar el resultado así:

- `OK:created`
  - success
- `OK:already-present`
  - success idempotente
- `ERROR:plasmoid-not-installed`
  - warning o error del bloque
- `ERROR:no-desktop`
  - warning no bloqueante
- `ERROR:create-failed`
  - warning no bloqueante

Si `qdbus6` falla antes de devolver salida:

- tratarlo como fallo de sesión/entorno
- no como fallo del paquete instalado

---

## 8. Embebido seguro en Bash

La implementación Bash no debe intentar montar este script como una sola línea ilegible.

La vía recomendada es:

1. encapsularlo en `build_mbp_plasmoid_autoload_script()`
2. obtenerlo en una variable
3. pasarlo completo a `qdbus6 ... evaluateScript`

Patrón conceptual:

```bash
local script
script="$(build_mbp_plasmoid_autoload_script)"

sudo -u "$target_user" env \
    XDG_RUNTIME_DIR="/run/user/$target_uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$target_uid/bus" \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script"
```

---

## 9. Ajustes permitidos sin cambiar contrato

Se permiten pequeños ajustes de implementación, por ejemplo:

- factorizar helpers JS internos
- usar otro nombre de variables locales
- mejorar el orden visual del bloque JS

No se permite sin actualizar contrato:

- cambiar plugin id
- cambiar la política de desktop objetivo
- cambiar la política de no duplicación
- cambiar la semántica de resultados
- introducir edición directa de config de Plasma

---

## 10. Definition of done

Este script se considera correctamente implementado cuando:

1. si el widget no está instalado, devuelve `ERROR:plasmoid-not-installed`
2. si ya existe una instancia, devuelve `OK:already-present`
3. si no existe, crea una sola instancia y devuelve `OK:created`
4. un segundo lanzamiento no duplica el widget
5. no modifica otros widgets del escritorio
