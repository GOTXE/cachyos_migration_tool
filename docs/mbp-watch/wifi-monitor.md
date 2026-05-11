# Wi-Fi Analysis En MBP Watch

La parte de analisis Wi-Fi ya no se sirve en un puerto separado. Queda integrada en la web principal de `mbp_watch` y se abre como modal dentro de `http://localhost:7070/report.html`.

## Requisitos

- `iw` para datos de enlace y escaneo cercano
- `ping` de `iputils` para latencia y perdida
- `python3` para servir la web de `mbp_watch`

Instalacion minima:

```bash
sudo pacman -S iw iputils python
```

## Despliegue

Instala o actualiza todo desde el despliegue principal:

```bash
sudo bash assets/diagnostics/deploy_mbp_watch.sh
```

El instalador:

- actualiza `mbp_watch`
- publica la web en `http://localhost:7070/report.html`
- retira el servicio legado `wifi-monitor` si seguia instalado

## Uso

1. Abre `http://localhost:7070/report.html`
2. Pulsa `📶 Wi-Fi Details`
3. Se abre el modal integrado con el analisis Wi-Fi

## Datos Que Muestra

El modal usa el `data.json` principal de `mbp_watch` y combina:

- snapshot del enlace Wi-Fi actual
- latencia y perdida de paquetes con `ping`
- escaneo cercano cacheado de redes visibles
- eventos recientes de Wi-Fi detectados en journal

Campos principales:

- SSID
- canal derivado de la frecuencia
- potencia de senal en dBm
- TX/RX bitrate
- TX retries
- power save
- latencia media
- perdida de paquetes
- numero de redes en el mismo canal
- lista de redes cercanas detectadas

## Modelo De Captura

`mbp_watch` sigue generando snapshots frecuentes, pero el escaneo de redes cercanas no se ejecuta en cada refresco:

- `ping`: se recalcula en cada snapshot
- nearby scan: se cachea con TTL para evitar castigar la radio Wi-Fi

Variables relacionadas:

```bash
MBP_WATCH_WIFI_PING_TARGET=8.8.8.8
MBP_WATCH_WIFI_SCAN_CACHE_TTL=120
MBP_WATCH_WIFI_SIGNAL_WARN_DBM=-72
MBP_WATCH_WIFI_INTERFERENCE_SIGNAL_DBM=-75
```

## Ficheros Relevantes

```text
assets/diagnostics/mbp_watch.sh
assets/diagnostics/deploy_mbp_watch.sh
assets/diagnostics/web/report.html
assets/diagnostics/web/report.css
assets/diagnostics/web/report.js
```

## Solucion De Problemas

Verifica estado del watcher:

```bash
sudo /usr/local/bin/mbp_watch.sh status
sudo journalctl -u mbp-watch -n 50
```

Verifica que el JSON principal ya incluye Wi-Fi:

```bash
grep -n '"wifi_analysis"' /var/lib/mbp-watch/data.json
grep -n '"wifi_link"' /var/lib/mbp-watch/data.json
```

Si el modal no refleja cambios recientes:

```bash
sudo bash assets/diagnostics/deploy_mbp_watch.sh
```

y recarga el navegador con limpieza de cache.
