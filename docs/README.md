# Documentación — Linux Migration Tool

## Herramienta de migración

- [migration.md](migration.md) — Guía completa de uso: backup, bootstrap, restore, postcheck y comandos CLI
- [linux-migration-tool.conf.example](linux-migration-tool.conf.example) — Plantilla de configuración de usuario

## Hardware — MBP 2015 (MacBookPro12,1)

Guías específicas para MacBook Pro Retina 13" 2015 en CachyOS:

- [hardware/vaapi-brave-broadwell.md](hardware/vaapi-brave-broadwell.md) — Corrección VA-API para Brave/Chromium en Intel Broadwell (libva-intel-driver-irql, i965, flags)
- [hardware/vaapi-testing-notes.md](hardware/vaapi-testing-notes.md) — Log de pruebas y verificación de la aceleración VA-API
- [hardware/mbp2015-cachyos-setup.md](hardware/mbp2015-cachyos-setup.md) — Ajustes generales de instalación CachyOS en MBP 2015

## MBP Watch

Monitor de hardware para MBP 2015 (daemon systemd + web local):

- [mbp-watch/refactor.md](mbp-watch/refactor.md) — Plan de refactorización del monitor
- [mbp-watch/wifi-monitor.md](mbp-watch/wifi-monitor.md) — Análisis Wi-Fi integrado en el dashboard
- [mbp-watch/mockup.pen](mbp-watch/mockup.pen) — Mockup Pencil del rediseño de la web

### Plasmoid KDE

- [mbp-watch/plasmoid/index.md](mbp-watch/plasmoid/index.md) — Índice y trazabilidad de la implementación v1
- [mbp-watch/plasmoid/spec.md](mbp-watch/plasmoid/spec.md) — Especificación funcional
- [mbp-watch/plasmoid/overlay-spec.md](mbp-watch/plasmoid/overlay-spec.md) — Spec del overlay de escritorio Plasma
- [mbp-watch/plasmoid/file-structure.md](mbp-watch/plasmoid/file-structure.md) — Estructura de archivos del paquete
- [mbp-watch/plasmoid/mapping.md](mbp-watch/plasmoid/mapping.md) — Mapeo de datos del daemon al plasmoid
- [mbp-watch/plasmoid/installation-flow.md](mbp-watch/plasmoid/installation-flow.md) — Flujo de instalación y auto-add al escritorio
- [mbp-watch/plasmoid/bootstrap-integration.md](mbp-watch/plasmoid/bootstrap-integration.md) — Integración con el bootstrap del script
- [mbp-watch/plasmoid/autoload-script.md](mbp-watch/plasmoid/autoload-script.md) — Script de auto-carga via qdbus6
- [mbp-watch/plasmoid/task-plan.md](mbp-watch/plasmoid/task-plan.md) — Plan de tareas de implementación
- [mbp-watch/plasmoid/commit-plan.md](mbp-watch/plasmoid/commit-plan.md) — Plan de commits
- [mbp-watch/plasmoid/ai-implementation-guide.md](mbp-watch/plasmoid/ai-implementation-guide.md) — Guía de implementación asistida por IA

### AI Digest (notas de desarrollo)

- [mbp-watch/digest/improvements.md](mbp-watch/digest/improvements.md)
- [mbp-watch/digest/final-summary.md](mbp-watch/digest/final-summary.md)
- [mbp-watch/digest/parsing-fixes.md](mbp-watch/digest/parsing-fixes.md)
- [mbp-watch/digest/performance-guide.md](mbp-watch/digest/performance-guide.md)
- [mbp-watch/digest/token-optimization.md](mbp-watch/digest/token-optimization.md)

## Extensiones de navegador

- [extensions/youtube-force-h264.md](extensions/youtube-force-h264.md) — Extensión para forzar H.264 en YouTube (Brave/Chromium)
