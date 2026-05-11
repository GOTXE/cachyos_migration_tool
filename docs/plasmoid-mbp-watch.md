# Plasmoid KDE MBP Watch

El directorio `assets/plasmoids/mbp-watch/` contiene el paquete KDE Plasma 6 que actúa como widget de escritorio para el daemon mbp-watch.

## Identificador

```
io.github.gtx.mbpwatch
```

## Estructura del paquete

```text
assets/plasmoids/mbp-watch/
├── metadata.json          # descripción del paquete (id, nombre, versión, autor)
├── README.md
└── contents/
    ├── ui/                # componentes QML del widget
    ├── code/              # lógica JS auxiliar
    ├── config/            # esquema de configuración
    └── images/            # iconos y recursos gráficos
```

## Instalación

El plasmoid se instala por usuario con `kpackagetool6`:

```bash
kpackagetool6 --type Plasma/Applet --install assets/plasmoids/mbp-watch/
```

El bootstrap lo instala automáticamente si se selecciona el bloque `plasmoid` (activo por defecto en la TUI).

Para reinstalarlo o moverlo de pantalla sin pasar por el bootstrap completo:

```bash
./migration.sh reinstall-mbp-plasmoid [--target primary|screen:N]
./migration.sh move-mbp-plasmoid      [--target primary|screen:N]
```

O directamente con el script standalone:

```bash
bash assets/diagnostics/reinstall_mbp_plasmoid.sh [--target screen:1] [--dry-run]
```

## Dependencia con el daemon

El plasmoid consume los datos que expone `mbp-watch.service`. Instalar el plasmoid sin el daemon mostrará el widget vacío o en error. Ver [diagnostics.md](diagnostics.md) para instalar y gestionar el daemon.
