# YouTube Force H264 para Chromium / Brave

Paquete real incluido en el repo:

```text
assets/youtube-force-h264/
```

El bootstrap lo copia a:

```text
~/extensions/youtube-force-h264/
```

La extensión incluye un slide interno para activar o desactivar el parche sin desinstalarla.

Guía práctica para dejar listo un proyecto de extensión local, mínima y auditable para Chromium/Brave que fuerce YouTube a evitar `VP8`, `VP9` y `AV1`, favoreciendo `H.264/AVC` (`avc1`) cuando esté disponible.

Está pensada para equipos antiguos como MacBook Pro 2015 con Intel Iris 6100, donde `H.264` suele tener mejor encaje con decodificación por GPU que `VP9/AV1`.

La prioridad aquí es:

- compatibilidad con Chromium/Brave actuales
- simplicidad
- cero dependencias
- permisos mínimos
- carga mínima para equipos viejos
- poder revisar todo el código en unos minutos

---

## 1. Objetivo real

La extensión debe hacer solo una cosa:

- impedir que YouTube seleccione `VP8`, `VP9` o `AV1` para vídeo
- dejar disponible `H.264/AVC`

Resultado esperado en YouTube:

```text
Codecs: avc1...
```

Códigos que se quieren evitar:

```text
vp8...
vp09...
av01...
```

Importante:

- la extensión solo influye en la selección de códec
- no garantiza por sí sola decodificación por GPU
- la aceleración real sigue dependiendo de Brave/Chromium, VA-API, driver Intel y del stream concreto

---

## 2. Diseño recomendado

Para este caso conviene una extensión:

- local, cargada como `Load unpacked`
- sin publicar en la store
- sin `popup`
- sin `background service worker`
- sin analytics
- sin librerías externas
- sin permisos de historial, cookies, pestañas o descargas

También conviene evitar soluciones demasiado modernas o sofisticadas si no aportan valor real en un MacBook Pro viejo.

Por compatibilidad se mantiene el patrón clásico:

- `content.js` en `document_start`
- inyección de `inject.js` en el contexto real de la página

No es la opción más elegante, pero sí una de las más compatibles entre Chromium/Brave y fácil de auditar.

---

## 3. Qué hay que parchear de verdad

No basta con tocar solo:

```js
MediaSource.isTypeSupported(...)
```

Para no dejar huecos innecesarios, la versión mínima seria debe cubrir:

- `MediaSource.isTypeSupported(...)`
- `HTMLMediaElement.prototype.canPlayType(...)`
- `navigator.mediaCapabilities.decodingInfo(...)` si existe

Esto reduce la probabilidad de que YouTube siga detectando `VP9/AV1` por otra ruta.

No conviene:

- bloquear todo `video/webm`
- bloquear `audio/webm`
- tocar APIs de grabación
- meter lógica agresiva que rompa audio o reproducción adaptativa

Bloquear todo `webm` sería un error, porque puede perjudicar audio o combinaciones válidas de reproducción.

---

## 4. Qué no debe llevar la extensión

No debería incluir:

- `tabs`
- `history`
- `cookies`
- `downloads`
- `webRequest`
- `nativeMessaging`
- `<all_urls>`
- permisos globales
- código remoto
- dependencias npm
- build step

Si el proyecto necesita algo de eso, ya dejó de ser una extensión mínima para este problema.

---

## 5. Estructura final del proyecto

Carpeta propuesta:

```text
youtube-force-h264/
├── manifest.json
├── content.js
├── inject.js
└── README.md
```

---

## 6. `manifest.json`

Versión recomendada:

```json
{
  "manifest_version": 3,
  "name": "YouTube Force H264",
  "version": "0.2.0",
  "description": "Forces YouTube to avoid VP8, VP9 and AV1 so H.264/AVC can be selected.",
  "content_scripts": [
    {
      "matches": [
        "*://www.youtube.com/*",
        "*://youtube.com/*",
        "*://m.youtube.com/*",
        "*://www.youtube-nocookie.com/*"
      ],
      "js": ["content.js"],
      "run_at": "document_start"
    }
  ],
  "web_accessible_resources": [
    {
      "resources": ["inject.js"],
      "matches": [
        "*://www.youtube.com/*",
        "*://youtube.com/*",
        "*://m.youtube.com/*",
        "*://www.youtube-nocookie.com/*"
      ]
    }
  ]
}
```

Decisiones importantes:

- `manifest_version: 3`: formato actual de Chromium/Brave
- sin `permissions`
- sin `host_permissions`
- sin `background`
- sin `action`
- `matches` cubre mejor YouTube que limitarse a `/watch`

Aunque YouTube sea una SPA, el parche queda cargado en el documento y sigue activo mientras navegas dentro del mismo proceso de página.

---

## 7. `content.js`

Archivo recomendado:

```js
(() => {
  "use strict";

  const root = document.head || document.documentElement;

  if (!root) {
    return;
  }

  const script = document.createElement("script");

  script.src = chrome.runtime.getURL("inject.js");
  script.onload = () => script.remove();

  root.appendChild(script);
})();
```

Por qué hace falta:

- los content scripts de Chromium viven en un entorno aislado
- si parcheas APIs allí, la página real puede no verlo
- por eso el parche real se hace desde `inject.js`

---

## 8. `inject.js`

Versión recomendada:

```js
(() => {
  "use strict";

  if (window.__ytForceH264Installed__) {
    return;
  }

  Object.defineProperty(window, "__ytForceH264Installed__", {
    value: true,
    configurable: false,
    enumerable: false,
    writable: false
  });

  const blockedVideoCodecMarkers = [
    "vp8",
    "vp8.0",
    "vp9",
    "vp09",
    "av1",
    "av01"
  ];

  function normalizeType(value) {
    return typeof value === "string" ? value.toLowerCase() : "";
  }

  function isBlockedVideoType(type) {
    const normalized = normalizeType(type);

    if (!normalized || !normalized.includes("video/")) {
      return false;
    }

    return blockedVideoCodecMarkers.some((marker) => normalized.includes(marker));
  }

  function patchMediaSource(ctor) {
    if (!ctor || typeof ctor.isTypeSupported !== "function") {
      return;
    }

    const original = ctor.isTypeSupported.bind(ctor);

    Object.defineProperty(ctor, "isTypeSupported", {
      configurable: true,
      value(type) {
        if (isBlockedVideoType(type)) {
          return false;
        }

        return original(type);
      }
    });
  }

  function patchCanPlayType() {
    if (!window.HTMLMediaElement) {
      return;
    }

    const proto = window.HTMLMediaElement.prototype;

    if (!proto || typeof proto.canPlayType !== "function") {
      return;
    }

    const original = proto.canPlayType;

    Object.defineProperty(proto, "canPlayType", {
      configurable: true,
      value(type) {
        if (isBlockedVideoType(type)) {
          return "";
        }

        return original.call(this, type);
      }
    });
  }

  function patchMediaCapabilities() {
    const mediaCapabilities = navigator.mediaCapabilities;

    if (!mediaCapabilities || typeof mediaCapabilities.decodingInfo !== "function") {
      return;
    }

    const original = mediaCapabilities.decodingInfo.bind(mediaCapabilities);

    Object.defineProperty(mediaCapabilities, "decodingInfo", {
      configurable: true,
      value: async function decodingInfoPatched(config) {
        const videoType =
          config &&
          config.video &&
          typeof config.video.contentType === "string"
            ? config.video.contentType
            : "";

        if (isBlockedVideoType(videoType)) {
          return {
            supported: false,
            smooth: false,
            powerEfficient: false,
            keySystemAccess: null
          };
        }

        return original(config);
      }
    });
  }

  patchMediaSource(window.MediaSource);
  patchMediaSource(window.ManagedMediaSource);
  patchCanPlayType();
  patchMediaCapabilities();
})();
```

### Decisiones clave

- solo se bloquean códecs de vídeo, no audio
- se usa una marca `__ytForceH264Installed__` para evitar doble parcheo
- se intenta cubrir `ManagedMediaSource` si existe
- no se toca nada fuera de lo necesario

---

## 9. `README.md`

Contenido recomendado:

```md
# YouTube Force H264

Minimal local Chromium/Brave extension to make YouTube avoid VP8, VP9 and AV1 for video whenever H.264/AVC is available.

## Goal

Prefer:

`avc1...`

Avoid:

`vp8...`
`vp09...`
`av01...`

## Install

1. Open `brave://extensions`, `chrome://extensions` or `chromium://extensions`.
2. Enable Developer Mode.
3. Click `Load unpacked`.
4. Select this folder.

## Verify

1. Open a YouTube video.
2. Right click the video.
3. Open `Stats for nerds`.
4. Check `Codecs`.

Expected:

`avc1...`

## Notes

- This extension only influences codec choice.
- Hardware decoding still depends on browser, driver and VA-API support.
- Some videos or resolutions may not offer H.264.
```

---

## 10. Instalación en Brave

1. Guarda la carpeta del proyecto, por ejemplo en:

```text
~/extensions/youtube-force-h264/
```

2. Abre:

```text
brave://extensions
```

3. Activa:

```text
Modo desarrollador
```

4. Pulsa:

```text
Cargar descomprimida
```

5. Selecciona:

```text
~/extensions/youtube-force-h264/
```

6. Cierra pestañas antiguas de YouTube y abre una nueva.

Ese último paso importa. Si ya había una pestaña de YouTube abierta antes de cargar la extensión, puedes quedarte con la versión sin parchear.

---

## 11. Instalación en Chromium / Chrome

1. Abre:

```text
chrome://extensions
```

o:

```text
chromium://extensions
```

2. Activa:

```text
Developer mode
```

3. Pulsa:

```text
Load unpacked
```

4. Selecciona la carpeta de la extensión.

---

## 12. Verificación en YouTube

En un vídeo de YouTube:

1. Clic derecho sobre el vídeo.
2. Selecciona `Estadísticas para nerds`.
3. Mira `Codecs`.

Correcto para este objetivo:

```text
avc1...
```

Incorrecto para este objetivo:

```text
vp8...
vp09...
av01...
```

Pruebas recomendadas:

- 720p
- 1080p
- 30 FPS
- 60 FPS
- más de un vídeo

No todos los vídeos ofrecen las mismas combinaciones de códec, resolución y FPS.

---

## 13. Qué esperar en un MacBook Pro 2015

Lo razonable es:

- que `avc1` reduzca bastante la carga de CPU frente a `vp09`
- que 720p y 1080p sean escenarios más realistas que 1440p/4K
- que 60 FPS pueda seguir siendo más exigente que 30 FPS

No esperes milagros:

- si YouTube no ofrece `H.264` para ese vídeo y resolución, la extensión no puede inventarlo
- aunque salga `avc1`, la mejora real depende del soporte de VA-API y del driver Intel

---

## 14. Verificación de aceleración por GPU

La extensión solo fuerza códec. La GPU hay que verificarla aparte.

En Brave/Chromium:

```text
brave://gpu
```

Comprueba al menos:

```text
Video Decode: Hardware accelerated
```

En Linux, herramientas útiles:

```bash
sudo pacman -S libva-utils intel-gpu-tools
```

Comprobar VA-API:

```bash
vainfo
```

Medir actividad real de la iGPU Intel durante reproducción:

```bash
sudo intel_gpu_top
```

Durante la reproducción deberías vigilar actividad en motores tipo:

```text
Video
VideoEnhance
```

Si `Codecs` dice `avc1` pero la CPU sigue muy alta y no hay actividad clara de motor de vídeo, el cuello ya no está en la selección de códec sino en la ruta real de decodificación.

---

## 15. VA-API en Arch / CachyOS

Paquetes útiles:

```bash
sudo pacman -S libva-utils intel-gpu-tools libva-intel-driver intel-media-driver
```

Para Intel Broadwell / Iris 6100:

- puede funcionar mejor `libva-intel-driver`
- en otros casos puede ir bien `intel-media-driver`

No conviene tocar drivers a ciegas. Primero mide:

```bash
vainfo
```

y después prueba reproducción real con `avc1`.

---

## 16. Limitaciones reales

Esta extensión no puede:

- obligar a YouTube a ofrecer `H.264` si no existe para ese stream
- garantizar 4K
- garantizar 60 FPS
- garantizar decodificación por GPU

Sí puede:

- sesgar la selección para evitar `VP8`, `VP9` y `AV1`
- mejorar bastante equipos viejos si YouTube ofrece `avc1`
- reducir dependencia de extensiones de terceros poco auditables

---

## 17. Problemas típicos

### Sigue saliendo `vp09`

Posibles causas:

- la pestaña ya estaba abierta
- la extensión no se recargó
- YouTube aún no tomó el parche en esa sesión
- el vídeo concreto no expone otra alternativa útil

Prueba:

1. Cierra todas las pestañas de YouTube.
2. Recarga la extensión.
3. Abre una pestaña nueva de YouTube.
4. Vuelve a comprobar `Stats for nerds`.

### No aparece `avc1`

Puede significar:

- ese vídeo no ofrece `H.264` en esa resolución/FPS
- estás en una combinación donde YouTube prioriza otros formatos

Prueba con:

- 720p
- 1080p
- 30 FPS
- otro vídeo

### El vídeo funciona pero la mejora es pequeña

Puede pasar si:

- la ruta VA-API no está bien
- el driver no está rindiendo bien en Broadwell
- el vídeo sigue siendo exigente por FPS o composición

---

## 18. Test básico de desarrollo

Si necesitas confirmar inyección, añade temporalmente en `inject.js`:

```js
console.log("[YouTube Force H264] injected");
```

Luego abre DevTools:

```text
F12 > Console
```

Si ves el mensaje, el script llegó al contexto de la página.

Cuando termines, quítalo.

---

## 19. Checklist final

Antes de dar el proyecto por bueno:

- [ ] La extensión carga sin errores en `brave://extensions`
- [ ] No pide permisos innecesarios
- [ ] `inject.js` se ejecuta al abrir YouTube
- [ ] En `Stats for nerds` aparece `avc1` en vídeos compatibles
- [ ] No aparece `vp09` en los casos donde YouTube sí tiene alternativa `H.264`
- [ ] La CPU baja respecto a `VP9/AV1`
- [ ] `intel_gpu_top` muestra actividad útil si VA-API está bien
- [ ] No rompe reproducción normal
- [ ] No afecta a webs fuera de YouTube

---

## 20. Resumen de decisión técnica

Para este proyecto, la versión correcta y equilibrada es:

- extensión local
- Manifest V3
- sin permisos
- sin popup
- sin background
- sin dependencias
- inyección temprana
- parcheo de `MediaSource`, `canPlayType` y `MediaCapabilities`

Eso mantiene el proyecto:

- pequeño
- auditable
- fácil de cargar en Brave/Chromium
- razonablemente compatible con equipos viejos

---

## 21. Fuentes técnicas oficiales

- Chrome Extensions - Content scripts:
  https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts

- Chrome Extensions - Manifest `content_scripts`:
  https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts

- Chrome Extensions - Web Accessible Resources:
  https://developer.chrome.com/docs/extensions/reference/manifest/web-accessible-resources

- MDN - `MediaSource.isTypeSupported()`:
  https://developer.mozilla.org/en-US/docs/Web/API/MediaSource/isTypeSupported

- MDN - `HTMLMediaElement.canPlayType()`:
  https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/canPlayType

- MDN - `MediaCapabilities.decodingInfo()`:
  https://developer.mozilla.org/en-US/docs/Web/API/MediaCapabilities/decodingInfo
