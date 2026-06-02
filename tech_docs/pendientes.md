# Pendientes

Estado:
- `[ ]` pendiente
- `[x]` completado

## Bootstrap: nuevos bloques seleccionables

- `[ ]` Añadir bloque seleccionable para `ipscan` en el bootstrap y exponerlo en ambas TUI.
- `[ ]` Añadir bloque seleccionable para `libreoffice-fresh-es` en el bootstrap y exponerlo en ambas TUI.

## Bootstrap: apps locales restauradas

- `[x]` Añadir bloque seleccionable para `talk2ai` en el bootstrap y hacer que instale `handy-bin` como dependencia.
- `[x]` Añadir bloque seleccionable para `codexBar Tray` en el bootstrap y exponerlo en ambas TUI.

Comandos de referencia para validar la implementación:

```bash
yay -S ipscan
yay -S webapp-manager
sudo pacman -S libreoffice-fresh-es
```

## Criterio de cierre

- `[ ]` El bloque aparece en `bootstrap-catalog`.
- `[ ]` El bloque se puede marcar desde la TUI Python.
- `[ ]` El bloque se puede marcar desde `whiptail`.
- `[ ]` El bloque queda documentado en README y/o docs si cambia el flujo visible.
