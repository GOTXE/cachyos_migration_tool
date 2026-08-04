# Pendientes

Estado:
- `[ ]` pendiente
- `[x]` completado

## Bootstrap: nuevos bloques seleccionables

- `[x]` Añadir bloque seleccionable para `ipscan` en el bootstrap y exponerlo en ambas TUI.
- `[x]` Añadir bloque seleccionable para `libreoffice-fresh-es` en el bootstrap y exponerlo en ambas TUI.
- `[x]` Añadir bloque seleccionable para `markdownpart` en el bootstrap y exponerlo en ambas TUI.

## Bootstrap: apps locales restauradas

- `[x]` Añadir bloque seleccionable para `talk2ai` en el bootstrap y hacer que instale `handy-bin` como dependencia.
- `[x]` Añadir bloque seleccionable para `codexBar Tray` en el bootstrap y exponerlo en ambas TUI.

## Bootstrap: extras opcionales

- `[x]` Añadir bloque seleccionable para `tea` como CLI opcional de Gitea en el bootstrap y exponerlo en ambas TUI.

## Restic backup: ventana horaria

- `[x]` Limitar el backup automático de Restic para que no ejecute copias entre las 22:00 y las 08:00 por defecto.
- `[x]` Hacer configurable la ventana horaria desde `~/.config/cachyos-migration-tool/backup.env`.

Comandos de referencia para validar la implementación:

```bash
yay -S ipscan
yay -S webapp-manager
sudo pacman -S libreoffice-fresh-es
```

## Criterio de cierre

- `[x]` El bloque aparece en `bootstrap-catalog`.
- `[x]` El bloque se puede marcar desde la TUI Python.
- `[x]` El bloque se puede marcar desde `whiptail`.
- `[x]` El bloque queda documentado en README y/o docs si cambia el flujo visible.
