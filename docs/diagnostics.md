# MBP Watch — Scripts de diagnóstico

El directorio `assets/diagnostics/` contiene el daemon de monitorización de hardware y los scripts de gestión del plasmoid KDE, todos pensados para MacBook Pro Intel en Linux.

## Daemon mbp_watch

### `mbp_watch.sh`

Script principal del daemon. Lee sensores de hardware (temperatura, batería, Wi-Fi, estado de la cámara FaceTime HD) y expone un informe en formato JSON/HTML accesible localmente.

- Configurable via `/etc/mbp-watch.conf` o la variable `MBP_WATCH_CONFIG_FILE`.
- Directorio de estado por defecto: `/var/lib/mbp-watch`.
- Resuelve el directorio de escritorio del usuario vía `XDG_DESKTOP_DIR`.

### `mbp-watch.service`

Unidad systemd para el daemon:

```text
After=network-online.target NetworkManager.service
Restart=on-failure / RestartSec=5
ExecStart=/usr/local/bin/mbp_watch.sh run
```

Se instala en `/etc/systemd/system/` durante el bootstrap o al ejecutar `deploy_mbp_watch.sh`.

### `deploy_mbp_watch.sh`

Instalador standalone del daemon. Copia `mbp_watch.sh` a `/usr/local/bin/`, registra e inicia el servicio systemd. Acepta los subcomandos `deploy` y `desktop`.

```bash
sudo bash assets/diagnostics/deploy_mbp_watch.sh deploy
sudo bash assets/diagnostics/deploy_mbp_watch.sh deploy --clean   # limpia estado previo
```

### `uninstall_mbp_watch.sh`

Desinstalador standalone del daemon. Detiene y elimina el servicio, borra el binario y la configuración.

```bash
sudo bash assets/diagnostics/uninstall_mbp_watch.sh
sudo bash assets/diagnostics/uninstall_mbp_watch.sh --purge   # elimina también /var/lib/mbp-watch
```

## Web local

El subdirectorio `assets/diagnostics/web/` contiene el frontend HTML/JS/CSS del dashboard local de mbp-watch:

```text
web/
├── report.html
├── report.css
└── report.js
```

El daemon sirve estos archivos en el puerto `7070` (configurable via `MBP_WATCH_PORT`).

## Scripts del plasmoid KDE

### `move_mbp_plasmoid.sh`

Recoloca el plasmoid `io.github.cachyosmigrationtool.mbpwatch` en una pantalla objetivo sin reinstalarlo.

```bash
bash assets/diagnostics/move_mbp_plasmoid.sh --target primary
bash assets/diagnostics/move_mbp_plasmoid.sh --target screen:1
bash assets/diagnostics/move_mbp_plasmoid.sh --dry-run --user myuser --target screen:0
```

### `reinstall_mbp_plasmoid.sh`

Desinstala y vuelve a instalar el plasmoid desde `assets/plasmoids/mbp-watch/` usando `kpackagetool6`.

```bash
bash assets/diagnostics/reinstall_mbp_plasmoid.sh
bash assets/diagnostics/reinstall_mbp_plasmoid.sh --target screen:1 --dry-run
```

### `uninstall_mbp_plasmoid.sh`

Elimina el plasmoid KDE del usuario indicado (o del usuario actual por defecto).

```bash
bash assets/diagnostics/uninstall_mbp_plasmoid.sh
bash assets/diagnostics/uninstall_mbp_plasmoid.sh --dry-run --user myuser
```

> Todos los scripts del plasmoid aceptan `--dry-run` (muestra acciones sin aplicarlas) y `--user USUARIO` (aplica al usuario KDE especificado en lugar de `$SUDO_USER`/`$USER`).

## Relación con el script principal

Las operaciones de estos scripts están integradas en `migration.sh` como comandos de primer nivel:

```bash
./migration.sh uninstall-mbp-watch
./migration.sh uninstall-mbp-plasmoid
./migration.sh reinstall-mbp-plasmoid [--target primary|screen:N]
./migration.sh move-mbp-plasmoid      [--target primary|screen:N]
```
