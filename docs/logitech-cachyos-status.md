# Estado actual: Logitech en CachyOS (KDE/Wayland)

Documento de estado generado el 20 de mayo de 2026 para dejar constancia de la configuracion aplicada en el sistema, lo validado por terminal y lo que sigue pendiente de comprobacion manual.

---

## Resumen

El sistema queda configurado para usar:

- `Solaar` como gestor principal del receptor Unifying, Craft y telemetria Logitech
- `libayatana-appindicator` como soporte de bandeja para Solaar en Plasma Wayland
- `logiops` como daemon para el MX Master 3

La configuracion actual es conservadora: activa gestos del boton pulgar, `SmartShift`, `hires scroll` y mantiene la rueda lateral en scroll horizontal normal.

---

## Paquetes instalados

Estado confirmado:

```bash
solaar 1.1.19-1
libayatana-appindicator 0.5.94-1.1
logiops 0.3.5-1
```

---

## Entorno grafico

Sesion detectada:

```text
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=KDE
```

Se ha priorizado Plasma Wayland nativo. No se ha dejado forzado `GDK_BACKEND=x11`.

---

## Hardware detectado

Dispositivos confirmados:

- Receptor Unifying `046d:c52b`
- `MX Master 3 Wireless Mouse`
- `Craft Advanced Keyboard`

Permisos confirmados en `/dev/hidraw0-2` mediante ACL `uaccess` para el usuario activo.

---

## Solaar

### Estado aplicado

- `solaar` instalado
- `libayatana-appindicator` instalado
- autostart de usuario creado en `~/.config/autostart/solaar.desktop`

Contenido actual:

```ini
[Desktop Entry]
Type=Application
Name=Solaar
Exec=solaar --window=hide
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
```

### Decision tomada

Se ha dejado Solaar en modo nativo Wayland porque:

- el sistema usa Plasma Wayland
- `libayatana-appindicator` ya esta instalado
- esta era la configuracion que querias priorizar

### Limite conocido

Aunque Solaar arranca y detecta los dispositivos, upstream sigue avisando de limitaciones en Wayland para reglas basadas en modificadores, proceso o ventana activa.

Advertencia observada:

```text
rules cannot access modifier keys in Wayland, accessing process only works on GNOME with Solaar Gnome extension installed
```

Esto no impide el uso normal del hardware, pero si limita automatizaciones contextuales complejas.

---

## logiops / logid

### Estado aplicado

- `logiops` instalado desde AUR
- `logid.service` habilitado y arrancado
- configuracion escrita en `/etc/logid.cfg`

Estado del servicio validado:

```text
Loaded: loaded (/usr/lib/systemd/system/logid.service; enabled)
Active: active (running)
```

`logid` detecta correctamente:

- `Wireless Mouse MX Master 3`
- `Craft Advanced Keyboard`

### Configuracion actual

Configuracion efectiva:

```text
devices: (
  {
    name: "Wireless Mouse MX Master 3";

    smartshift: { on: true; threshold: 20; };
    hiresscroll: { hires: true; invert: false; target: true; };
    dpi: 1000;

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
            { direction: "Up"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTMETA", "KEY_UP"]; }; },
            { direction: "Down"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTMETA", "KEY_DOWN"]; }; },
            { direction: "Left"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTALT", "KEY_LEFT"]; }; },
            { direction: "Right"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_LEFTALT", "KEY_RIGHT"]; }; },
            { direction: "None"; mode: "OnRelease"; action = { type: "Keypress"; keys: ["KEY_F5"]; }; }
          );
        };
      }
    );
  }
);
```

### Efecto practico de esta configuracion

- `SmartShift` activo con `threshold: 20`
- `hires scroll` activo
- DPI fijado a `1000`
- boton pulgar con gestos
- rueda lateral sin desvio: conserva scroll horizontal normal

---

## Verificaciones realizadas

Quedo validado por terminal:

- paquetes instalados
- `logid` activo
- deteccion real de dispositivos por `solaar show`
- deteccion real de dispositivos por `logid`
- autostart creado
- ACL correctas en `hidraw`

---

## Pendiente de validacion manual

Estos puntos siguen pendientes porque requieren comprobacion visual o uso real del periferico en sesion grafica:

- comprobar si el icono de Solaar aparece correctamente en la bandeja de Plasma Wayland
- comprobar si Solaar arranca bien tras reinicio o nueva sesion
- probar los gestos del boton pulgar del MX Master 3 en uso real
- decidir si el DPI `1000` resulta comodo o si conviene volver a `1500`
- decidir si la rueda lateral debe seguir en scroll horizontal normal o remapearse a atajos
- comprobar si `threshold: 20` en `SmartShift` resulta estable en uso diario

---

## Fallback seguro si Solaar falla en Wayland nativo

Si el icono no aparece o el arranque nativo en Wayland da problemas, el fallback seguro es volver a X11 solo para Solaar editando `~/.config/autostart/solaar.desktop`:

```ini
Exec=env GDK_BACKEND=x11 solaar --window=hide
```

Eso no cambia la sesion Plasma Wayland. Solo fuerza Solaar a usar backend X11.

---

## Siguientes ajustes opcionales

Si mas adelante quieres afinar el comportamiento:

- subir `dpi` a `1500`
- probar `threshold: 30` o `40` si la rueda de `SmartShift` no se siente estable
- remapear `thumbwheel` a cambio de pestanas, volumen o escritorios
- experimentar con reglas del Crown en Solaar sabiendo que el contexto por ventana tiene limites en KDE Wayland
