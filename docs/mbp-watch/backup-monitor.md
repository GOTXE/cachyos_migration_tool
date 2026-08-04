# Monitor de Estado de Backup en Plasmoid MBP Watch

El plasmoid MBP Watch ahora muestra el estado del backup realizado con Restic en tiempo real.

## Visualización

El widget muestra una línea compacta con el estado:

```text
Backup | ✓ OK | 4 snapshots | 37.1 GiB | Última: 21:09:52
```

### Colores de estado

- 🟢 **Verde (OK)**: Backups completos y operacionales
- 🟡 **Amarillo (STALE)**: Sin backup reciente (>24h sin actualización)
- 🔴 **Rojo (FAIL)**: Error en el repositorio o conectividad perdida
- ⚪ **Gris (PENDING)**: Backup en progreso o repositorio inicializado sin snapshots

## Instalación

### 1. Instalar el script de monitoreo

```bash
mkdir -p ~/.local/share/cachyos-migration-tool
cp assets/scripts/backup-monitor.sh ~/.local/share/cachyos-migration-tool/
chmod +x ~/.local/share/cachyos-migration-tool/backup-monitor.sh
```

### 2. Instalar el systemd timer

```bash
mkdir -p ~/.config/systemd/user
cp assets/systemd/cachyos-backup-monitor.service ~/.config/systemd/user/
cp assets/systemd/cachyos-backup-monitor.timer ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable cachyos-backup-monitor.timer
systemctl --user start cachyos-backup-monitor.timer
```

### 3. Verificar estado

```bash
# Ver estado del timer
systemctl --user status cachyos-backup-monitor.timer

# Ver logs
journalctl --user -u cachyos-backup-monitor -f

# Ejecutar manualmente una vez
systemctl --user start cachyos-backup-monitor.service

# Ver archivo de estado
cat ~/.config/cachyos-migration-tool/backup-status.json
```

## Configuración

### Intervalo de actualización

El timer se ejecuta cada 5 minutos por defecto. Para cambiar:

```bash
systemctl --user edit cachyos-backup-monitor.timer
```

Y modificar:

```ini
[Timer]
OnUnitActiveSec=5min    # Cambiar a: 1min, 10min, 1h, etc.
```

Luego:

```bash
systemctl --user daemon-reload
systemctl --user restart cachyos-backup-monitor.timer
```

### Script de backup manual

Para ejecutar el monitoreo manualmente en cualquier momento:

```bash
~/.local/share/cachyos-migration-tool/backup-monitor.sh
cat ~/.config/cachyos-migration-tool/backup-status.json
```

## Estructura de datos

El archivo `~/.config/cachyos-migration-tool/backup-status.json` tiene la estructura:

```json
{
  "status": "ok",
  "snapshot_count": 4,
  "total_size_gb": 37.1,
  "last_snapshot_time": "2026-06-03T21:09:52",
  "last_snapshot_id": "12508a78",
  "error": "",
  "server": "LAN",
  "server_status": "ok"
}
```

`server` indica qué destino respondió (`LAN` o `Internet`). Si ninguno
responde, queda vacío y `server_status` pasa a `fail`.

### Estados

- `"ok"`: Backups completados correctamente
- `"stale"`: Último backup fue hace más de 24 horas
- `"pending"`: Backup en ejecución o repositorio todavía sin snapshots
- `"fail"`: Error en acceso a repositorio

## Requisitos

- `restic` instalado y configurado
- Archivo `~/.config/cachyos-migration-tool/backup.env` correctamente configurado
- Acceso a SSH al servidor de backup (LAN o remoto)
- `systemd` (para ejecución automática)

## Solución de problemas

### El plasmoid muestra "FAIL"

```bash
# Verificar que el archivo de estado existe
ls -la ~/.config/cachyos-migration-tool/backup-status.json

# Ejecutar el script manualmente
bash ~/.local/share/cachyos-migration-tool/backup-monitor.sh

# Ver el contenido del archivo
cat ~/.config/cachyos-migration-tool/backup-status.json

# Verificar conectividad al servidor
ssh -o BatchMode=yes backup-sftp-lan 'echo ok'
ssh -o BatchMode=yes backup-sftp-remote 'echo ok'
```

### El archivo de estado no se actualiza

```bash
# Ver logs del timer
journalctl --user -u cachyos-backup-monitor -n 20

# Verificar que el timer está activo
systemctl --user list-timers cachyos-backup-monitor.timer

# Iniciar manualmente
systemctl --user start cachyos-backup-monitor.service
```

### Permisos denegados

Asegúrate que el script tiene permisos de ejecución:

```bash
chmod +x ~/.local/share/cachyos-migration-tool/backup-monitor.sh
```

## Integración con otros sistemas

El archivo `backup-status.json` es un archivo JSON estándar que puede ser consumido por:

- Scripts de monitoreo personalizados
- Herramientas de alertas
- Dashboards
- Cualquier sistema que lea JSON desde un archivo

Simplemente lee periódicamente el archivo desde `~/.config/cachyos-migration-tool/backup-status.json`.
