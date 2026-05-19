# Recordatorio — Pruebas VA-API en Brave/Chromium sobre CachyOS

**Equipo:** MacBook Pro 13" Retina 2015 — MBP 12,1  
**GPU:** Intel Iris Graphics 6100 / Broadwell  
**Sistema:** CachyOS / entorno Arch-like  
**Objetivo:** conseguir decodificación de vídeo por hardware en Brave/Chromium, especialmente YouTube H.264, usando VA-API.

---

## 1. Diagnóstico final resumido

El sistema **sí tiene VA-API funcional**, porque `mpv` consigue usar decodificación hardware con `h264-vaapi`.

El problema no está en:

- el codec de YouTube;
- la extensión H.264;
- que falte VA-API en el sistema;
- que Brave/Chromium no intenten VA-API.

El problema detectado es más concreto:

> Brave/Chromium seleccionan `VaapiVideoDecoder`, pero fallan al inicializar el frame pool y hacen fallback a `FFmpegVideoDecoder`.

Error repetido:

~~~text
VaapiVideoDecoder: failed Initialize()ing the frame pool
~~~

Resultado final observado:

~~~text
kVideoDecoderName = "FFmpegVideoDecoder"
kIsPlatformVideoDecoder = false
Video en intel_gpu_top = 0%
Render/3D activo
~~~

Interpretación:

> En esta combinación de Intel Broadwell / Iris 6100 + Mesa/CachyOS + Brave/Chromium actual, la ruta VA-API de Chromium falla al crear los buffers/superficies de vídeo. No parece una mala configuración básica.

---

## 2. Herramientas usadas

### `mpv`

Usado para comprobar que VA-API funciona fuera del navegador.

Comando:

~~~bash
mpv --hwdec=vaapi --msg-level=vd=debug "Jetma.mp4"
~~~

Resultado relevante:

~~~text
Opening decoder h264
Trying hardware decoding via h264-vaapi.
Requesting pixfmt 'vaapi' from decoder.
Using hardware decoding (vaapi).
Decoder format: 1920x1080 vaapi[nv12]
VO: [gpu-next] 1920x1080 vaapi[nv12]
~~~

Conclusión:

> VA-API funciona en el sistema. El fallo queda acotado a Brave/Chromium.

---

### `ffmpeg`

También se probó VA-API con `ffmpeg`.

Comando usado:

~~~bash
LIBVA_DRIVER_NAME=iHD ffmpeg \
  -hwaccel vaapi \
  -hwaccel_device /dev/dri/renderD128 \
  -hwaccel_output_format vaapi \
  -i "Jetma.mp4" \
  -f null -
~~~

Nota:

- Se probó con `iHD`, aunque para Broadwell suele tener más sentido probar `i965`.
- Esta prueba servía para validar acceso VA-API desde fuera del navegador.

---

### `intel_gpu_top`

Usado para comprobar si la carga iba a:

- `Render/3D`
- `Video`

Resultado persistente en Brave/Chromium:

~~~text
Render/3D: actividad
Video: 0%
~~~

Interpretación:

> La GPU participa en composición/render, pero no en decodificación de vídeo.

---

### `brave://media-internals` / `chrome://media-internals`

Usado para comprobar el decoder real.

Campos mirados:

~~~text
kVideoDecoderName
kIsPlatformVideoDecoder
error
warning
pipeline_state
kVideoTracks
~~~

Patrón repetido:

~~~text
Selected VaapiVideoDecoder
kVideoDecoderName = "VaapiVideoDecoder"
kIsPlatformVideoDecoder = true

error = "VaapiVideoDecoder: failed Initialize()ing the frame pool"
warning = "video decoder fallback after initial decode error."

Selected FFmpegVideoDecoder
kVideoDecoderName = "FFmpegVideoDecoder"
kIsPlatformVideoDecoder = false
~~~

---

## 3. Codec de YouTube

Al principio apareció:

~~~text
kVideoDecoderName = "Dav1dVideoDecoder"
kIsPlatformVideoDecoder = false
~~~

Eso significaba que YouTube estaba usando AV1, no H.264.

Después se confirmó que Brave normal sí estaba usando H.264:

~~~text
avc1.64001f(136)
~~~

Interpretación:

- `avc1` = H.264 / AVC.
- `64001f` = H.264 High Profile, nivel aproximado 3.1.
- `136` = stream de vídeo 720p.

Conclusión:

> El codec quedó corregido. YouTube pasó a servir H.264, pero VA-API siguió fallando en Brave/Chromium.

---

## 4. Extensión H.264

Se usó una extensión tipo:

- `h264ify`
- `enhanced-h264ify`
- u otra extensión equivalente para bloquear AV1/VP9 y forzar H.264.

Objetivo:

> Evitar `av01` y `vp09`, dejando `avc1`.

Resultado:

~~~text
avc1
~~~

Conclusión:

> La extensión cumple su función. El fallo posterior ya no es de codec.

---

## 5. Flags iniciales en Brave

Archivo:

~~~bash
~/.config/brave-flags.conf
~~~

Flags que se tenían originalmente:

~~~text
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-zero-copy
--enable-features=AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,CanvasOopRasterization,VaapiIgnoreDriverChecks,UseMultiPlaneFormatForHardwareVideo
--ozone-platform-hint=auto
~~~

Análisis:

- `AcceleratedVideoDecodeLinuxGL`: relevante.
- `AcceleratedVideoDecodeLinuxZeroCopyGL`: puede ayudar, pero también puede romper en Intel antiguo.
- `AcceleratedVideoEncoder`: no sirve para ver YouTube.
- `CanvasOopRasterization`: no afecta directamente al decode.
- `VaapiIgnoreDriverChecks`: fuerza rutas que quizá Chromium bloquearía.
- `UseMultiPlaneFormatForHardwareVideo`: sospechoso en hardware/driver antiguos.

---

## 6. Pruebas realizadas en Brave

### 6.1 Perfil limpio de Brave

Comando:

~~~bash
LIBVA_DRIVER_NAME=i965 brave \
  --user-data-dir=/tmp/brave-vaapi-test \
  --ignore-gpu-blocklist \
  --enable-features=AcceleratedVideoDecodeLinuxGL \
  --ozone-platform-hint=auto
~~~

Resultado inicial:

~~~text
kVideoDecoderName = "Dav1dVideoDecoder"
kIsPlatformVideoDecoder = false
~~~

Conclusión:

> En perfil limpio no estaba activa la extensión H.264, por eso YouTube usaba AV1.

---

### 6.2 Brave normal con H.264 confirmado

Codec confirmado:

~~~text
avc1.64001f(136)
~~~

Resultado en `brave://media-internals`:

~~~text
kVideoDecoderName = "FFmpegVideoDecoder"
kIsPlatformVideoDecoder = false
error = "VaapiVideoDecoder: failed Initialize()ing the frame pool"
warning = "video decoder fallback after initial decode error."
~~~

Conclusión:

> Brave intenta VA-API, falla en frame pool y cae a software.

---

### 6.3 Flags mínimos sin zero-copy ni multiplane

Archivo `~/.config/brave-flags.conf`:

~~~text
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL
--ozone-platform-hint=auto
~~~

Comando:

~~~bash
pkill brave
brave
~~~

Resultado:

~~~text
FFmpegVideoDecoder
kIsPlatformVideoDecoder = false
VaapiVideoDecoder: failed Initialize()ing the frame pool
~~~

Conclusión:

> No era culpa de `zero-copy` ni de `UseMultiPlaneFormatForHardwareVideo`.

---

### 6.4 Forzar driver `i965`

Comando:

~~~bash
pkill brave
LIBVA_DRIVER_NAME=i965 brave
~~~

Resultado:

~~~text
FFmpegVideoDecoder
kIsPlatformVideoDecoder = false
VaapiVideoDecoder: failed Initialize()ing the frame pool
~~~

Conclusión:

> Forzar `i965` no corrigió el fallo.

---

### 6.5 Forzar X11

Archivo `~/.config/brave-flags.conf`:

~~~text
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL
--ozone-platform-hint=x11
~~~

Comando:

~~~bash
pkill brave
LIBVA_DRIVER_NAME=i965 brave
~~~

Resultado:

~~~text
VaapiVideoDecoder
kIsPlatformVideoDecoder = true

después:

VaapiVideoDecoder: failed Initialize()ing the frame pool
FFmpegVideoDecoder
kIsPlatformVideoDecoder = false
~~~

Conclusión:

> X11 no corrige el fallo.

---

### 6.6 Desactivar explícitamente `UseMultiPlaneFormatForHardwareVideo`

Archivo `~/.config/brave-flags.conf`:

~~~text
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL
--disable-features=UseMultiPlaneFormatForHardwareVideo
--ozone-platform-hint=x11
~~~

Comando:

~~~bash
pkill brave
LIBVA_DRIVER_NAME=i965 brave
~~~

Resultado:

~~~text
VaapiVideoDecoder: failed Initialize()ing the frame pool
video decoder fallback after initial decode error
FFmpegVideoDecoder
kIsPlatformVideoDecoder = false
~~~

Conclusión:

> Desactivar multiplane no corrige el fallo.

---

### 6.7 Forzar OpenGL / ANGLE GL y desactivar Vulkan

Archivo `~/.config/brave-flags.conf`:

~~~text
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL
--disable-features=UseMultiPlaneFormatForHardwareVideo,Vulkan
--use-angle=gl
--ozone-platform-hint=x11
~~~

Comando:

~~~bash
pkill brave
LIBVA_DRIVER_NAME=i965 brave
~~~

Resultado:

~~~text
VaapiVideoDecoder: failed Initialize()ing the frame pool
FFmpegVideoDecoder
kIsPlatformVideoDecoder = false
~~~

Conclusión:

> ANGLE GL sin Vulkan tampoco corrige el frame pool.

---

### 6.8 Forzar Vulkan + ANGLE Vulkan

Comando:

~~~bash
LIBVA_DRIVER_NAME=i965 brave \
  --ignore-gpu-blocklist \
  --enable-gpu-rasterization \
  --enable-zero-copy \
  --enable-features=Vulkan,VaapiVideoDecoder,VaapiIgnoreDriverChecks \
  --use-angle=vulkan \
  --ozone-platform-hint=x11
~~~

Salida al lanzar:

~~~text
No suitable EGL configs found for initialization.
~~~

Conclusión:

> `--use-angle=vulkan` no es viable en este entorno. Falla la inicialización gráfica EGL.

---

### 6.9 Vulkan sin forzar ANGLE Vulkan

Comando:

~~~bash
LIBVA_DRIVER_NAME=i965 brave \
  --ignore-gpu-blocklist \
  --enable-gpu-rasterization \
  --enable-zero-copy \
  --enable-features=Vulkan,VaapiVideoDecoder,VaapiIgnoreDriverChecks \
  --ozone-platform-hint=x11
~~~

Resultado observado:

~~~text
Render/3D activo
Video = 0%
~~~

Conclusión:

> Vulkan sin `--use-angle=vulkan` tampoco consigue decodificación por motor Video.

---

### 6.10 Flag alternativa antigua `VaapiVideoDecodeLinuxGL`

Comando:

~~~bash
LIBVA_DRIVER_NAME=i965 brave \
  --ignore-gpu-blocklist \
  --enable-gpu-rasterization \
  --enable-features=VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
  --disable-features=UseMultiPlaneFormatForHardwareVideo,Vulkan \
  --use-angle=gl \
  --ozone-platform-hint=x11
~~~

Salida relevante:

~~~text
media/gpu/vaapi/vaapi_video_decoder.cc:1224] failed Initialize()ing the frame pool
~~~

Conclusión:

> La flag alternativa tampoco corrige el fallo.

---

## 7. Pruebas en Chromium

Se instaló/probó Chromium para comprobar si el fallo era exclusivo de Brave.

Comando usado:

~~~bash
LIBVA_DRIVER_NAME=i965 chromium \
  --user-data-dir=/tmp/chromium-vaapi-test \
  --ignore-gpu-blocklist \
  --enable-gpu-rasterization \
  --enable-features=AcceleratedVideoDecodeLinuxGL \
  --disable-features=UseMultiPlaneFormatForHardwareVideo,Vulkan \
  --use-angle=gl \
  --ozone-platform-hint=x11
~~~

Se instaló/cargó extensión H.264 en el perfil temporal de Chromium.

Resultado en `chrome://media-internals`:

~~~text
kVideoDecoderName = "VaapiVideoDecoder"
kIsPlatformVideoDecoder = true

error = "VaapiVideoDecoder: failed Initialize()ing the frame pool"
warning = "video decoder fallback after initial decode error."

kVideoDecoderName = "FFmpegVideoDecoder"
kIsPlatformVideoDecoder = false
~~~

Además, ocurrió incluso con:

~~~text
codec: h264
profile: h264 main
coded size: 854x480
~~~

Conclusión:

> Chromium falla igual que Brave. El problema no es específico de Brave, sino de Chromium/VA-API en esta pila.

---

## 8. Mensajes de error vistos

### Crashpad lock

~~~text
open /home/<user>/.config/BraveSoftware/Brave-Browser/Crash Reports/pending/...lock: File exists (17)
~~~

Interpretación:

> Ruido secundario de Crashpad. No parece relacionado con VA-API.

---

### systemd app scope

~~~text
Failed to call method: org.freedesktop.systemd1.Manager.GetUnit:
Unit app-org.chromium.Chromium-392305.scope not loaded.
~~~

Interpretación:

> Ruido de integración con systemd/app scope. No parece la causa del fallo VA-API.

---

### EGL con ANGLE Vulkan

~~~text
No suitable EGL configs found for initialization.
~~~

Interpretación:

> La ruta `--use-angle=vulkan` no inicializa correctamente en este entorno.

---

### Error central

~~~text
media/gpu/vaapi/vaapi_video_decoder.cc:1224] failed Initialize()ing the frame pool
~~~

Interpretación:

> Fallo real en la ruta VA-API de Chromium/Brave.

---

## 9. Configuración recomendada final para Brave

No dejar flags demasiado experimentales.

Archivo recomendado:

~~~bash
~/.config/brave-flags.conf
~~~

Contenido:

~~~text
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-features=AcceleratedVideoDecodeLinuxGL
--ozone-platform-hint=auto
~~~

Opcionalmente, si se quiere forzar driver al lanzar desde terminal:

~~~bash
LIBVA_DRIVER_NAME=i965 brave
~~~

Pero como no corrige el fallo, no es imprescindible dejarlo de forma permanente.

---

## 10. Qué NO dejaría activo

No dejaría estas flags permanentemente salvo para pruebas:

~~~text
--enable-zero-copy
--enable-features=Vulkan,VaapiVideoDecoder,VaapiIgnoreDriverChecks
--enable-features=VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks
--disable-features=UseMultiPlaneFormatForHardwareVideo,Vulkan
--use-angle=vulkan
--use-angle=gl
--ozone-platform-hint=x11
~~~

Motivo:

- No han corregido el fallo.
- Algunas pueden causar problemas gráficos.
- `--use-angle=vulkan` produjo error EGL.

---

## 11. Estado práctico actual

### Brave

Estado:

- H.264 / `avc1` funciona.
- La composición/render usa GPU.
- La decodificación de vídeo por motor `Video` no funciona.
- `intel_gpu_top` muestra `Video = 0%`.
- `media-internals` muestra fallback a `FFmpegVideoDecoder`.

Uso recomendado:

> Usar Brave normalmente, pero asumir que YouTube decodifica por CPU. Mantener H.264 forzado para reducir carga frente a AV1/VP9.

---

### mpv

Estado:

- VA-API funciona.
- Es la vía más fiable para reproducción acelerada.

Uso recomendado para vídeos pesados:

~~~bash
mpv --hwdec=vaapi "archivo.mp4"
~~~

---

### Firefox

No quedó probado en esta sesión como control final.

Prueba pendiente sugerida:

~~~bash
LIBVA_DRIVER_NAME=i965 MOZ_LOG="PlatformDecoderModule:5" firefox
~~~

Comprobar:

- YouTube en `avc1`.
- `intel_gpu_top`.
- Motor `Video`.
- Carga CPU.

Si Firefox usa `Video`, entonces la conclusión sería:

> VA-API funciona en navegador, pero no en Chromium/Brave.

---

## 12. Conclusión final

El diagnóstico más sólido tras las pruebas es:

> En este MBP 2015 con Intel Iris 6100/Broadwell y CachyOS, Brave/Chromium actuales sí intentan VA-API para H.264, pero fallan al crear el frame pool y caen a decodificación software. No parece solucionable con flags normales.

Opciones reales:

1. Usar Brave con H.264 forzado, aceptando decode por CPU.
2. Usar `mpv` para vídeo pesado.
3. Probar Firefox como alternativa para vídeo.
4. Revisar periódicamente Brave/Chromium/Mesa/kernel por si se corrige el bug.
5. Probar Brave Beta/Nightly en el futuro, pero no como solución estable ahora.

---

## 13. Resumen ultracorto

~~~text
VA-API sistema: OK con mpv.
YouTube H.264: OK con avc1.
Brave/Chromium: seleccionan VaapiVideoDecoder.
Fallo: failed Initialize()ing the frame pool.
Fallback: FFmpegVideoDecoder.
intel_gpu_top: Render activo, Video 0%.
Conclusión: bug/limitación Chromium VA-API en Broadwell/Mesa/CachyOS.
~~~
