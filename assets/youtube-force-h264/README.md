[Read in English 🇬🇧](README.en.md)

# YouTube Force H264

Extensión local para Chromium, Brave y derivados que evita que YouTube elija VP8, VP9 o AV1 cuando H.264/AVC está disponible.

## Instalación

1. Abre `brave://extensions`, `chrome://extensions` o `chromium://extensions`.
2. Activa `Modo desarrollador`.
3. Pulsa `Cargar descomprimida`.
4. Selecciona esta carpeta.

## Interruptor

La extensión incluye un slide interno en el icono de la barra de extensiones.

- `ON`: aplica el parche de YouTube.
- `OFF`: deja la extensión instalada pero sin tocar codecs.

Recarga la pestaña de YouTube después de cambiarlo.

## Ruta instalada por el script

Cuando ejecutas `bootstrap`, el paquete se copia a:

```text
~/extensions/youtube-force-h264/
```

## Verificación

1. Abre un vídeo de YouTube.
2. Abre `Stats for nerds`.
3. Comprueba `Codecs`.

El objetivo es ver `avc1...`.

## Notas

- La extensión solo influye en la selección de códec.
- La decodificación por GPU sigue dependiendo del navegador, del driver y de VA-API.
- No usa permisos globales ni dependencias externas.
