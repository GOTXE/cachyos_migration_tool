[Leer en español 🇪🇸](README.md)

# YouTube Force H264

Local extension for Chromium, Brave and derivatives that prevents YouTube from choosing VP8, VP9 or AV1 when H.264/AVC is available.

## Installation

1. Open `brave://extensions`, `chrome://extensions` or `chromium://extensions`.
2. Enable `Developer mode`.
3. Click `Load unpacked`.
4. Select this folder.

## Toggle

The extension includes an internal toggle in the extensions bar icon.

- `ON`: applies the YouTube patch.
- `OFF`: keeps the extension installed but without touching codecs.

Reload the YouTube tab after switching.

## Path installed by the script

When you run `bootstrap`, the package is copied to:

```text
~/extensions/youtube-force-h264/
```

## Verification

1. Open a YouTube video.
2. Open `Stats for nerds`.
3. Check `Codecs`.

The goal is to see `avc1...`.

## Notes

- The extension only influences codec selection.
- GPU decoding still depends on the browser, driver and VA-API.
- Does not use global permissions or external dependencies.
