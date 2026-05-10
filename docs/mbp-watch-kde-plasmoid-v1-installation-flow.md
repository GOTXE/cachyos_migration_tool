# MBP Watch KDE Plasmoid v1 — Flujo oficial de instalación y despliegue

## 1. Objetivo

Definir el flujo exacto de instalación, actualización, registro y añadido automático al escritorio del plasmoid `mbp-watch` en KDE Plasma 6, de forma que:

- siga la vía oficial de Plasma,
- pueda integrarse en `bootstrap`,
- no dependa de pasos manuales del usuario tras aceptar la instalación,
- y deje claro qué parte ocurre como `root` y qué parte debe ejecutarse como usuario de escritorio.

Este documento complementa:

- [mbp-watch-kde-plasmoid-v1-spec.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-spec.md:1)
- [mbp-watch-kde-plasmoid-v1-mapping.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-mapping.md:1)
- [mbp-watch-kde-plasmoid-v1-task-plan.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-task-plan.md:1)
- [mbp-watch-kde-plasmoid-v1-file-structure.md](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/mbp-watch-kde-plasmoid-v1-file-structure.md:1)

---

## 2. Fuentes oficiales y verificación local

Base oficial usada:

- KDE Developer, Plasma 6 porting:
  - `metadata.json` obligatorio
  - `"X-Plasma-API-Minimum-Version": "6.0"`
  - `"KPackageStructure": "Plasma/Applet"`
  - entrada fija en `contents/ui/main.qml`
- KDE Developer, Plasma Desktop Scripting:
  - ejecución programática con `qdbus ... evaluateScript`
  - API de `desktops()`, `desktopForScreen()`, `addWidget(...)`, `knownWidgetTypes`
- KDE Developer, Plasma Widget Testing:
  - widgets de usuario instalados en `~/.local/share/plasma/plasmoids`
  - prueba rápida con `plasmawindowed`

Verificación local realizada en esta máquina:

- `kpackagetool6` existe
- `qdbus6` existe
- `plasmawindowed` existe

Inferencia explícita:

- aunque la documentación oficial habla de las rutas de usuario de Plasma y del uso de `kpackagetool6`, no detalla textualmente “sin `--global` instala en `~/.local/share/plasma/plasmoids`”.
- esa conclusión se toma de forma razonable a partir de la estructura estándar de Plasma y del comportamiento esperado de `kpackagetool6`.

---

## 3. Principios operativos

## 3.1 Instalación por usuario, no global

Para v1, el plasmoid debe instalarse por usuario:

- alcance: sólo el usuario de escritorio que aceptó el overlay
- ubicación esperada: árbol de datos de Plasma del usuario
- motivo:
  - evita escribir en rutas globales de Plasma sin necesidad
  - encaja con la aceptación individual del usuario en `bootstrap`
  - simplifica actualización, pruebas y rollback

No usar `kpackagetool6 --global` en v1.

## 3.2 Instalación del paquete y añadido al escritorio son pasos distintos

Hay dos operaciones separadas:

1. instalar o actualizar el paquete del plasmoid
2. crear una instancia visible en el escritorio Plasma

Instalar el paquete no garantiza que el widget aparezca en el escritorio.

## 3.3 El añadido al escritorio debe ejecutarse en la sesión gráfica del usuario

La parte de `evaluateScript` sobre `org.kde.plasmashell` requiere:

- sesión Plasma activa
- acceso al bus D-Bus de usuario
- entorno correcto del usuario de escritorio

Esto no debe ejecutarse como `root` “a pelo”.

---

## 4. Requisitos previos para `bootstrap`

Antes de intentar instalar el plasmoid, `bootstrap` debe comprobar:

1. el usuario aceptó instalar el overlay KDE
2. el entorno objetivo es KDE Plasma
3. existen:
   - `kpackagetool6`
   - `qdbus6`
4. existe una sesión gráfica del usuario objetivo
5. el repo contiene el plasmoid en la ruta esperada

### 4.1 Señales mínimas de entorno KDE válido

V1 debe considerar instalación automática sólo si se cumple al menos esto:

- `XDG_CURRENT_DESKTOP` contiene `KDE` o `plasma`
- existe `/run/user/<uid>/bus`
- `org.kde.plasmashell` está accesible desde la sesión del usuario

Si falla cualquiera de esos puntos:

- instalar el paquete puede seguir siendo válido
- pero el auto-add al escritorio debe degradarse con mensaje claro

---

## 5. Identificadores y rutas fijas de v1

Estos valores deben quedar centralizados y no dispersos por scripts:

```text
PLUGIN_ID=io.github.gtx.mbpwatch
PLUGIN_PACKAGE_TYPE=Plasma/Applet
PLUGIN_SOURCE_DIR=<repo>/assets/plasmoids/mbp-watch
PLUGIN_MAIN_QML=contents/ui/main.qml
```

Notas:

- `PLUGIN_ID` debe coincidir con `KPlugin.Id` en `metadata.json`
- el directorio del paquete debe ser coherente con ese id, aunque Plasma resuelve por metadata

---

## 6. Contrato de empaquetado Plasma 6

El paquete del plasmoid v1 debe cumplir como mínimo:

1. `metadata.json` en la raíz del plasmoid
2. `"X-Plasma-API-Minimum-Version": "6.0"`
3. `"KPackageStructure": "Plasma/Applet"`
4. `contents/ui/main.qml` como punto de entrada
5. raíz QML basada en `PlasmoidItem`

Esto no es una preferencia del proyecto; es el contrato mínimo esperado por Plasma 6.

---

## 7. Flujo oficial de instalación del paquete

## 7.1 Comando base

Instalación por usuario:

```bash
kpackagetool6 --type Plasma/Applet --install /ruta/al/plasmoid
```

Actualización por usuario:

```bash
kpackagetool6 --type Plasma/Applet --upgrade /ruta/al/plasmoid
```

## 7.2 Política v1

`bootstrap` debe seguir esta lógica:

1. si el paquete no está instalado, usar `--install`
2. si ya está instalado, usar `--upgrade`

No se debe hacer `remove + install` como flujo normal.

Motivo:

- conserva mejor el estado de configuración del widget
- encaja con la semántica oficial de `kpackagetool6`

## 7.3 Usuario de ejecución

El comando debe ejecutarse como el usuario final de Plasma, no como `root`.

Si `bootstrap` corre con `sudo`, debe delegar a `SUDO_USER` o al usuario objetivo explícito.

Ejemplo conceptual:

```bash
sudo -u "$target_user" \
    kpackagetool6 --type Plasma/Applet --upgrade "$PLUGIN_SOURCE_DIR"
```

---

## 8. Flujo oficial de añadido automático al escritorio

## 8.1 Mecanismo oficial

El añadido automático debe realizarse usando Plasma Desktop Scripting vía:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "<script>"
```

Ese script JavaScript debe:

1. comprobar que el plasmoid está instalado
2. comprobar que no existe ya una instancia en ningún desktop
3. elegir un desktop objetivo
4. crear la instancia con `addWidget(...)`
5. colocarla en una posición inicial razonable

## 8.2 Regla de idempotencia

El auto-add debe ser idempotente.

Si ya existe una instancia del plasmoid:

- no crear otra
- no mover la existente
- no reescribir su geometría

Esta regla es importante para no romper personalizaciones del usuario después del primer despliegue.

## 8.3 Desktop objetivo de v1

V1 usará una regla determinista y simple:

- intentar `desktopForScreen(0)`
- si no devuelve desktop válido, usar `desktops()[0]`

Inferencia explícita:

- la documentación consultada expone `screen` y `screenGeometry()`, pero no una API de alto nivel claramente documentada para “pantalla primaria preferida”.
- por eso v1 fija `screen 0` como criterio inicial estable.

## 8.4 Posición inicial recomendada

Como el estilo objetivo es panel lateral HUD a la derecha, la instancia inicial debe crearse con geometría explícita.

Valores base v1:

```text
widget width: 360
widget margin: 24
widget top offset: 24
widget height: min(screenHeight - 48, 920)
widget x: screenX + screenWidth - widgetWidth - 24
widget y: screenY + 24
```

La creación debe usar la variante oficial:

```js
desktop.addWidget(pluginId, x, y, width, height)
```

No debe intentarse una colocación “inteligente” más compleja en v1.

---

## 9. Script lógico de auto-add

El comportamiento esperado del script de Plasma debe ser este:

```text
1. pluginId = "io.github.gtx.mbpwatch"
2. comprobar knownWidgetTypes.includes(pluginId)
3. recorrer desktops()
4. en cada desktop, comprobar si ya existe widgets(pluginId)
5. si ya existe alguna instancia:
   - terminar sin cambios
6. resolver desktop objetivo:
   - desktopForScreen(0)
   - fallback a desktops()[0]
7. obtener screenGeometry(targetDesktop.screen)
8. calcular x, y, width, height
9. targetDesktop.addWidget(pluginId, x, y, width, height)
10. terminar
```

Nota de implementación:

- si `widgets(pluginId)` no devolviera un resultado fiable en alguna build concreta, el fallback aceptable es recorrer `widgetIds` y resolver cada widget con `widgetById(id)` comprobando `type === pluginId`.

---

## 10. Entorno exacto para ejecutar `qdbus6`

Como `bootstrap` puede correr fuera de la sesión del usuario, antes de invocar `qdbus6` debe fijar:

```text
XDG_RUNTIME_DIR=/run/user/<uid>
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus
```

Y luego ejecutar como usuario final:

```bash
sudo -u "$target_user" env \
    XDG_RUNTIME_DIR="/run/user/$target_uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$target_uid/bus" \
    qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script"
```

Esto es especialmente importante si `bootstrap` se ejecuta:

- desde terminal con `sudo`
- desde tty
- o desde un contexto no heredado de Plasma

---

## 11. Flujo exacto recomendado para `bootstrap`

## 11.1 Orden

El flujo recomendado de v1 es:

1. instalar backend `mbp_watch`
2. detectar KDE Plasma
3. preguntar al usuario si quiere instalar el overlay
4. validar binarios requeridos
5. instalar o actualizar el plasmoid con `kpackagetool6`
6. intentar auto-add con `qdbus6` en la sesión del usuario
7. informar del resultado:
   - instalado y añadido
   - instalado pero no añadido automáticamente
   - omitido por decisión del usuario

## 11.2 Comportamiento ante error

Si falla el auto-add, `bootstrap` no debe considerar fallida toda la instalación del sistema.

Debe:

- dejar el plasmoid instalado si la instalación del paquete sí funcionó
- registrar el error
- mostrar instrucción de recuperación manual

Motivo:

- el fallo puede ser sólo de sesión D-Bus o de entorno gráfico
- no debe tumbar el resto del bootstrap

---

## 12. Recuperación manual definida

Si el añadido automático falla, la recuperación manual v1 debe ser esta:

1. verificar que el paquete está instalado
2. abrir Plasma y asegurarse de que `plasmashell` corre en sesión
3. reintentar el script de `evaluateScript`
4. si sigue fallando, el usuario puede añadir el widget manualmente desde Plasma

Comprobación de paquete:

```bash
kpackagetool6 --type Plasma/Applet --list
```

Prueba rápida en ventana:

```bash
plasmawindowed io.github.gtx.mbpwatch
```

---

## 13. Flujo de actualización

Para redeploys posteriores:

1. `bootstrap` o script de deploy detecta plasmoid ya instalado
2. ejecutar `kpackagetool6 --type Plasma/Applet --upgrade "$PLUGIN_SOURCE_DIR"`
3. no crear instancia nueva si ya existe
4. no tocar posición ni tamaño si la instancia ya estaba en escritorio

Regla v1:

- `upgrade` actualiza el paquete
- la presencia en escritorio se trata como estado del usuario y se preserva

---

## 14. Flujo de desinstalación

La desinstalación debe contemplar dos niveles:

1. quitar instancia del escritorio
2. quitar paquete instalado

Paquete:

```bash
kpackagetool6 --type Plasma/Applet --remove io.github.gtx.mbpwatch
```

La eliminación automática de instancias desde scripting puede definirse más adelante, pero no es requisito bloqueante de v1 si existe un desinstalador claro.

---

## 15. Validación de terminado

Se considerará correcta la integración de instalación cuando se cumpla todo esto:

1. `metadata.json` es válido para Plasma 6
2. `kpackagetool6 --type Plasma/Applet --install/upgrade` reconoce el paquete
3. `kpackagetool6 --type Plasma/Applet --list` muestra el plasmoid
4. `plasmawindowed <pluginId>` puede abrirlo en modo ventana
5. el auto-add crea exactamente una instancia en el escritorio
6. un segundo deploy no duplica la instancia
7. si el widget ya existía, `upgrade` no rompe su presencia ni su geometría

---

## 16. Decisiones finales ya cerradas

Quedan fijadas para implementación:

- instalación por usuario
- uso de `kpackagetool6`
- uso de `qdbus6` sobre `org.kde.plasmashell`
- añadido automático al escritorio
- apertura posterior de la web desde plasmoid y notificaciones
- comportamiento idempotente
- degradación segura si falla el auto-add

---

## 17. Qué queda pendiente después de este documento

Con esto queda cerrada la parte operativa de despliegue.

Lo siguiente ya es implementación concreta:

1. crear el paquete real del plasmoid
2. escribir el script JS exacto de auto-add
3. integrar la lógica en `src/modules/bootstrap.sh`
4. añadir un flujo de uninstall opcional para el plasmoid

---

## 18. Referencias

Fuentes oficiales consultadas:

- KDE Developer, Plasma Desktop scripting:
  - https://develop.kde.org/docs/plasma/scripting/
  - https://develop.kde.org/docs/plasma/scripting/api/
- KDE Developer, Plasma widget testing:
  - https://develop.kde.org/docs/plasma/widget/testing/
- KDE Developer, Porting Plasmoids to KF6:
  - https://develop.kde.org/docs/plasma/widget/porting_kf6/
