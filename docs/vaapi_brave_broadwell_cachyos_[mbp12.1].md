# VA-API Hardware Decode en Brave — MBP 2015 (Broadwell/CachyOS)

## Hardware

- MacBook Pro 13" 2015 (MBP 12,1)
- GPU: Intel Iris 6100 / Broadwell Gen8
- OS: CachyOS (Arch-based)

## Problema

Brave/Chromium seleccionaba `VaapiVideoDecoder` pero fallaba con:
`failed Initialize()ing the frame pool` → fallback a `FFmpegVideoDecoder` (CPU)

## Solución: driver VA-API parcheado

### 1. Instalar `libva-intel-driver-irql` (AUR)

Reemplaza `libva-intel-driver` con un fork que corrige la inicialización del frame pool en Chromium.

~~~bash
paru -S libva-intel-driver-irql
~~~

Verificar:

~~~bash
LIBVA_DRIVER_NAME=i965 vainfo
# Debe mostrar: Intel i965 driver for Intel(R) Broadwell - 2.4.5+
~~~

### 2. Variable de entorno permanente

Crear `~/.config/environment.d/vaapi.conf`:

~~~bash
LIBVA_DRIVER_NAME=i965
~~~

### 3. Flags de Brave

`~/.config/brave-flags.conf`:

~~~bash
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL
--ozone-platform-hint=x11
~~~

### 4. Extensión para forzar H.264 en YouTube

Instalar **enhanced-h264ify** → bloquear AV1 y VP9, dejar solo `avc1`.

## Verificación

~~~bash
sudo intel_gpu_top
# Motor Video activo (1.5-2.5% sostenido en 720p)
~~~

En `brave://media-internals` durante reproducción:

~~~
kVideoDecoderName       = "VaapiVideoDecoder"
kIsPlatformVideoDecoder = true
# Sin errores de frame pool, sin fallback a FFmpegVideoDecoder
~~~

## Notas

- Si `ZeroCopyGL` causa microcortes (`kVideoPlaybackRoughness` alto), retirarlo y dejar solo `AcceleratedVideoDecodeLinuxGL`
- `mpv --hwdec=vaapi archivo.mp4` sigue siendo la opción más eficiente para vídeo local pesado
