# Logitech Craft + MX Master 3 en CachyOS (KDE/Wayland)

Guia revisada contra hardware real y contrastada con la documentacion upstream disponible en mayo de 2026.  
Receptor Unifying en `/dev/hidraw0` · MX Master 3 en `/dev/hidraw1` · Craft en `/dev/hidraw2`

---

## Hardware detectado

| Dispositivo | Codename | WPID | Protocolo | Serial |
|---|---|---|---|---|
| MX Master 3 Wireless Mouse | MX Master 3 | 4082 | HID++ 4.5 | 073E2E5E |
| Craft Advanced Keyboard | Craft | 4066 | HID++ 4.5 | 7A765471 |
| Receptor Unifying | — | C52B | — | ECF3A185 |

---

## Reparto recomendado de herramientas

| Herramienta | Responsabilidad |
|---|---|
| **Solaar** | Crown del Craft, bateria, iluminacion, emparejado y ajustes HID++ |
| **logiops** | Gestos del MX Master 3, SmartShift, hires scroll y rueda lateral |

Las dos conviven bien si no intentan capturar la misma feature al mismo tiempo. Si ambas tocan el mismo boton o evento, la ultima en engancharlo suele ganar.

---

## Permisos en CachyOS: sin `plugdev`

En Arch y CachyOS no hace falta crear ni usar `plugdev`. Solaar usa reglas `udev` modernas con `uaccess`, que aplican ACL automaticamente al usuario de la sesion grafica activa.

```text
# /usr/lib/udev/rules.d/42-logitech-unify-permissions.rules
LABEL="solaar_apply"
TAG+="uaccess"
```

Verificacion local:

```bash
getfacl /dev/hidraw0 /dev/hidraw1 /dev/hidraw2
```

Si aparece una entrada `user:<tu_usuario>:rw-`, el acceso esta bien.

---

## Instalacion

### Solaar

```bash
sudo pacman -S solaar
```

Paquete opcional util para la bandeja:

```bash
sudo pacman -S libayatana-appindicator
```

En Arch/CachyOS, `solaar` declara `libayatana-appindicator` como dependencia opcional para mostrar el icono de tray.

### logiops

`logiops` no esta en repos oficiales de Arch/CachyOS. Se instala desde AUR:

```bash
paru -S logiops
sudo systemctl enable --now logid
```

---

## Solaar en KDE Wayland

### Opcion segura y verificada

En Plasma Wayland, la forma mas segura para conservar el tray icon es arrancar Solaar con backend X11:

```bash
GDK_BACKEND=x11 solaar --window=hide
```

Autostart recomendado:

```ini
[Desktop Entry]
Type=Application
Name=Solaar
Exec=env GDK_BACKEND=x11 solaar --window=hide
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
```

### Opcion nativa en Wayland

Si quieres probar Solaar nativo en Wayland, instala antes `libayatana-appindicator` y prueba:

```bash
solaar --window=hide
```

Si el icono aparece bien en la bandeja de Plasma y no hay regresiones visuales, puedes usar este autostart:

```ini
[Desktop Entry]
Type=Application
Name=Solaar
Exec=solaar --window=hide
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
```

Importante:

- Esto es una mejora posible, no una sustitucion garantizada del modo X11.
- Upstream recomienda la libreria de appindicator para el tray, pero sigue documentando que Solaar funciona mejor en X11.
- En Wayland, algunas reglas de Solaar no funcionan igual que en X11.

---

## Crown del Craft: que se puede esperar en Wayland

Solaar incluye Rule Editor y puede capturar eventos HID++ del Crown. Eso sirve para reglas simples y automatizaciones basicas.

Pero en KDE Wayland hay limites reales:

- Las reglas basadas en proceso o ventana enfocada no tienen soporte completo.
- El comportamiento contextual por aplicacion no esta tan garantizado como en X11.
- La advertencia local de Solaar lo deja claro: acceso a proceso enfocado en Wayland solo funciona plenamente en GNOME con la extension especifica de Solaar.

Conclusion practica:

- Usa Solaar para el Crown, bateria, iluminacion y ajustes del teclado.
- Si una automatizacion depende de saber con precision que ventana esta activa, tratala como experimental en KDE Wayland.

---

## Configuracion de `logiops` en `/etc/logid.cfg`

### Paso 1: confirmar el nombre exacto del dispositivo

El campo `name` debe coincidir con el nombre que `logid` detecta realmente:

```bash
sudo journalctl -u logid -f
# o
sudo logid --verbose 2>&1 | grep -i "found device\|device name"
```

En este hardware, el valor mas habitual es:

```text
Wireless Mouse MX Master 3
```

### Paso 2: configuracion base segura

```text
# /etc/logid.cfg
devices: (
  {
    name: "Wireless Mouse MX Master 3";

    smartshift: { on: true; threshold: 20; };
    hiresscroll: { hires: true; invert: false; target: true; };
    dpi: 1500;

    thumbwheel: {
      divert: false;
      invert: false;
    };

    buttons: (
      {
        cid: 0xc3;
        action = {
          type: "Gestures";
          gestures: (
            { direction: "Up";    mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTMETA", "KEY_UP"]; }; },
            { direction: "Down";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTMETA", "KEY_DOWN"]; }; },
            { direction: "Left";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTALT", "KEY_LEFT"]; }; },
            { direction: "Right"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTALT", "KEY_RIGHT"]; }; },
            { direction: "None";  mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_F5"]; }; }
          );
        };
      }
    );
  }
);
```

Esta base deja la rueda lateral en comportamiento normal del sistema, con scroll horizontal por defecto.

### Paso 3: aplicar y comprobar

```bash
sudo systemctl restart logid
sudo journalctl -u logid -n 20
```

---

## SmartShift: nota de estabilidad

La base `threshold: 20` funciona y es un buen punto de partida. Aun asi, si notas que el mecanismo de la rueda queda atascado de forma intermitente en modo libre, merece la pena probar:

- `threshold: 30`
- `threshold: 40`

No lo trataria como fallo general del MX Master 3, sino como ajuste de diagnostico cuando el tacto de la rueda no resulte estable.

---

## Rueda lateral del MX Master 3

La rueda lateral no se configura como `cid: 0x2150` dentro de `buttons:`.  
`0x2150` identifica la feature HID++ `THUMB WHEEL`; en `logiops` se maneja mediante el bloque `thumbwheel`.

### Mantener el scroll horizontal del sistema

```text
thumbwheel: {
  divert: false;
  invert: false;
};
```

### Capturar la rueda lateral en `logiops`

Solo si quieres remapearla a acciones propias:

```text
thumbwheel: {
  divert: true;
  invert: false;
  left: {
    direction: "Left";
    mode: "OnInterval";
    interval: 1;
    action = { type: "Keypress"; keys: ["KEY_LEFTCTRL", "KEY_PAGEUP"]; };
  };
  right: {
    direction: "Right";
    mode: "OnInterval";
    interval: 1;
    action = { type: "Keypress"; keys: ["KEY_LEFTCTRL", "KEY_PAGEDOWN"]; };
  };
};
```

Notas:

- `interval: 1` suele ser mas consistente que valores altos.
- Si activas `divert: true`, la rueda deja de comportarse como scroll horizontal normal y pasa a depender de tus reglas.

---

## Botones del MX Master 3: referencia util

Datos observados con Solaar y hardware real:

| Boton | CID | divertable | Notas |
|---|---|---|---|
| Left Button | — | no | No interceptable |
| Right Button | — | no | No interceptable |
| Middle Button | — | si | Divertable |
| Back Button | — | si | Divertable, grupo 2 |
| Forward Button | — | si | Divertable, grupo 2 |
| Mouse Gesture Button | 0xc3 | si | Boton pulgar, el mas util para gestos |
| Smart Shift | — | si | Rueda smartshift |

---

## Features HID++ confirmadas en el MX Master 3

| Feature | ID HID++ | Version | Soporte |
|---|---|---|---|
| SMART SHIFT | `{2110}` | V0 | `smartshift:` |
| HIRES WHEEL | `{2121}` | V1 | `hiresscroll:` |
| ADJUSTABLE DPI | `{2201}` | V1 | `dpi:` |
| REPROG CONTROLS V4 | `{1B04}` | V4 | `buttons:` |
| THUMB WHEEL | `{2150}` | V0 | `thumbwheel:` |

---

## Diagnostico rapido

```bash
# Solaar
solaar show

# Estado del daemon
sudo systemctl status logid

# Logs en tiempo real
sudo journalctl -u logid -f

# ACL de acceso a hidraw
ls -la /dev/hidraw0 /dev/hidraw1 /dev/hidraw2
getfacl /dev/hidraw1 2>/dev/null
```

Si `solaar show` lanza una advertencia en Wayland sobre reglas y proceso enfocado, es normal en Plasma Wayland y no indica un fallo de emparejado.

---

## Resumen practico

- Mantener `GDK_BACKEND=x11` sigue siendo la opcion mas segura para Solaar en KDE Wayland.
- `libayatana-appindicator` merece la pena instalarlo, pero no garantiza por si solo que ya puedas sustituir X11.
- La Crown del Craft puede usarse desde Solaar, pero las reglas contextuales por ventana en KDE Wayland tienen limites.
- La rueda lateral del MX Master 3 se configura con `thumbwheel`, no con `cid: 0x2150`.
