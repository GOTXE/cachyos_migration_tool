# Sistema TUI

El script selecciona automáticamente el motor de interfaz de usuario al arrancar. El orden de prioridad es:

1. **Python + curses** (`src/lib/tui.py`) — interfaz gráfica en terminal, sin dependencias externas. Es la opción preferida.
2. **whiptail** (`src/lib/tui.sh`) — diálogos ncurses clásicos. Se usa si Python no está disponible.
3. **Texto plano** — menú numerado en stdout. Fallback final sin dependencias.

## Selección automática

```bash
./migration.sh       # detecta el mejor motor disponible
```

El script comprueba en orden: `python3` + módulo `curses`, luego `whiptail`. Si ninguno existe, entra en modo texto.

## Variable TUI_BACKEND

Permite forzar un motor concreto sin modificar el script:

```bash
TUI_BACKEND=python    ./migration.sh   # fuerza Python/curses
TUI_BACKEND=whiptail  ./migration.sh   # fuerza whiptail
TUI_BACKEND=text      ./migration.sh   # fuerza modo texto
TUI_BACKEND=auto      ./migration.sh   # comportamiento por defecto
```

## Python/curses (`src/lib/tui.py`)

- Solo stdlib — sin `pip install` ni paquetes externos.
- Widgets implementados: `menu`, `checklist`, `radiolist`, `inputbox`, `yesno`, `msgbox`.
- Navegación: flechas o `j`/`k`, `SPACE` para marcar en checklist, `ENTER` para confirmar, `Q`/`ESC` para cancelar.
- El bootstrap muestra un checklist con los bloques disponibles; las preguntas adicionales (país Wi-Fi, navegador para HW accel) se recogen antes de lanzar el proceso.
- Al ejecutar una operación, suspende curses, muestra el output en terminal crudo con cabecera ANSI y espera `ENTER` al terminar.

## Whiptail (`src/lib/tui.sh`)

- Requiere el paquete `whiptail` (normalmente incluido en `libnewt`).
- Esquema de colores personalizado via `NEWT_COLORS`.
- Función `_tui_run_with_output` muestra el output en terminal directo (sin pipes) y al terminar vuelve al menú.
- `tui_backup` detecta discos montados con `lsblk` y verifica espacio disponible antes de proceder.
- `tui_op` envuelve cualquier función del script pasándole `AUTO_CONFIRM=true`.

## Modo texto

Menú numerado del 1 al 11 impreso con `log`. Todas las mismas operaciones que los modos gráficos, sin dependencias.
