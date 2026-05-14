[Leer en español 🇪🇸](README.md)

# Documentation — Linux Migration Tool

## Migration tool

- [migration.md](migration.md) — Full usage guide: backup, bootstrap, restore, postcheck and CLI commands
- [migration-bootstrap.md](migration-bootstrap.md) — Bootstrap blocks, supported hardware profiles and initial tests
- [linux-migration-tool.conf.example](linux-migration-tool.conf.example) — User configuration template
- [tui.md](tui.md) — TUI system: Python/curses (primary), whiptail (fallback), plain text and `TUI_BACKEND` variable

## Wi-Fi Firmware

- [firmware-bcm43602.md](firmware-bcm43602.md) — Broadcom BCM43602 bundle in `firmware/brcm/` and extraction tool

## Hardware — initial Apple profiles

Apple profiles already covered by the bootstrap:

- `MacBookPro12,1` — MacBook Pro Retina 13" 2015
- `MacBookPro8,1` — MacBook Pro 13" Early 2011

Specific documentation currently available for MacBook Pro Retina 13" 2015 on CachyOS:

- [hardware/vaapi-brave-broadwell.md](hardware/vaapi-brave-broadwell.md) — VA-API fix for Brave/Chromium on Intel Broadwell (libva-intel-driver-irql, i965, flags)
- [hardware/vaapi-testing-notes.md](hardware/vaapi-testing-notes.md) — Testing log and VA-API acceleration verification
- [hardware/mbp2015-cachyos-setup.md](hardware/mbp2015-cachyos-setup.md) — General CachyOS installation adjustments on MBP 2015

## MBP Watch

Hardware monitor for MBP 2015 (systemd daemon + local web):

- [diagnostics.md](diagnostics.md) — Daemon scripts, systemd service, local web and plasmoid management from CLI
- [plasmoid-mbp-watch.md](plasmoid-mbp-watch.md) — KDE Plasma 6 package (`assets/plasmoids/mbp-watch/`): structure, installation and usage
- [mbp-watch/refactor.md](mbp-watch/refactor.md) — Monitor refactoring plan
- [mbp-watch/wifi-monitor.md](mbp-watch/wifi-monitor.md) — Wi-Fi analysis integrated into the dashboard
- [mbp-watch/mockup.pen](mbp-watch/mockup.pen) — Pencil mockup of the web redesign

### KDE Plasmoid

- [mbp-watch/plasmoid/index.md](mbp-watch/plasmoid/index.md) — Index and v1 implementation traceability
- [mbp-watch/plasmoid/spec.md](mbp-watch/plasmoid/spec.md) — Functional specification
- [mbp-watch/plasmoid/overlay-spec.md](mbp-watch/plasmoid/overlay-spec.md) — Plasma desktop overlay spec
- [mbp-watch/plasmoid/file-structure.md](mbp-watch/plasmoid/file-structure.md) — Package file structure
- [mbp-watch/plasmoid/mapping.md](mbp-watch/plasmoid/mapping.md) — Daemon data to plasmoid mapping
- [mbp-watch/plasmoid/installation-flow.md](mbp-watch/plasmoid/installation-flow.md) — Installation and auto-add to desktop flow
- [mbp-watch/plasmoid/bootstrap-integration.md](mbp-watch/plasmoid/bootstrap-integration.md) — Integration with script bootstrap
- [mbp-watch/plasmoid/autoload-script.md](mbp-watch/plasmoid/autoload-script.md) — Auto-load script via qdbus6
- [mbp-watch/plasmoid/task-plan.md](mbp-watch/plasmoid/task-plan.md) — Implementation task plan
- [mbp-watch/plasmoid/commit-plan.md](mbp-watch/plasmoid/commit-plan.md) — Commit plan
- [mbp-watch/plasmoid/ai-implementation-guide.md](mbp-watch/plasmoid/ai-implementation-guide.md) — AI-assisted implementation guide

### AI Digest (development notes)

- [mbp-watch/digest/improvements.md](mbp-watch/digest/improvements.md)
- [mbp-watch/digest/final-summary.md](mbp-watch/digest/final-summary.md)
- [mbp-watch/digest/parsing-fixes.md](mbp-watch/digest/parsing-fixes.md)
- [mbp-watch/digest/performance-guide.md](mbp-watch/digest/performance-guide.md)
- [mbp-watch/digest/token-optimization.md](mbp-watch/digest/token-optimization.md)

## Browser extensions

- [extensions/youtube-force-h264.md](extensions/youtube-force-h264.md) — Extension to force H.264 on YouTube (Brave/Chromium)
