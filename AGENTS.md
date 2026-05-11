# Repository Guidelines

## Project Structure & Module Organization

```
ScriptMigrationCachyOS_v1_1/
├── migration.sh                        entrypoint estable, delega en src/main.sh
├── linux-migration-tool.conf.example   plantilla de configuración de usuario
├── src/
│   ├── main.sh                         CLI parsing y menú interactivo
│   ├── lib/common.sh                   helpers y globals compartidos
│   ├── modules/
│   │   ├── backup.sh
│   │   ├── restore.sh
│   │   └── bootstrap.sh
│   └── tools/
│       └── extract_bcm43602_bundle.sh
├── assets/
│   ├── diagnostics/                    scripts instalables en el sistema
│   │   ├── mbp_watch.sh                monitor de hardware MBP (systemd service)
│   │   ├── mbp-watch.service           unit de systemd
│   │   ├── deploy_mbp_watch.sh         instalador/actualizador del watcher
│   │   └── uninstall_mbp_watch.sh
│   └── youtube-force-h264/             extensión Chromium/Brave
│       ├── manifest.json
│       ├── content.js / inject.js / popup.*
│       ├── youtube-force-h264-logo.png
│       └── README.md
├── firmware/
│   └── brcm/                           bundle Broadcom BCM43602 (fuente de verdad)
│       ├── brcmfmac43602-pcie.bin(.zst)
│       ├── brcmfmac43602-pcie.txt
│       ├── brcmfmac43602-pcie.Apple Inc.-MacBookPro12,1.txt
│       └── README.md
└── docs/                               toda la documentación del proyecto
    ├── README.md                       índice navegable de docs/
    ├── migration.md                    guía de uso de la herramienta de migración
    ├── linux-migration-tool.conf.example  plantilla de configuración de usuario
    ├── hardware/                       guías de hardware MBP 2015
    │   ├── vaapi-brave-broadwell.md    corrección VA-API para Brave/Chromium Intel Broadwell
    │   ├── vaapi-testing-notes.md      log de pruebas de aceleración VA-API
    │   └── mbp2015-cachyos-setup.md   ajustes generales de instalación
    ├── mbp-watch/                      monitor de hardware MBP (daemon + web)
    │   ├── refactor.md
    │   ├── wifi-monitor.md
    │   ├── mockup.pen                  mockup Pencil del rediseño web
    │   ├── plasmoid/                   plasmoid KDE MBP Watch
    │   │   ├── index.md               índice y trazabilidad v1
    │   │   ├── spec.md
    │   │   ├── overlay-spec.md
    │   │   ├── file-structure.md
    │   │   ├── mapping.md
    │   │   ├── installation-flow.md
    │   │   ├── bootstrap-integration.md
    │   │   ├── autoload-script.md
    │   │   ├── task-plan.md
    │   │   ├── commit-plan.md
    │   │   └── ai-implementation-guide.md
    │   └── digest/                     notas de desarrollo del AI digest
    └── extensions/
        └── youtube-force-h264.md       guía de la extensión de navegador
```

**Reglas de organización:**
- `src/` — únicamente código fuente Bash del script principal de migración.
- `assets/diagnostics/` — scripts instalables en el sistema (se copian a `/usr/local/bin/` o similar). Sin documentación.
- `assets/youtube-force-h264/` — extensión de navegador completa incluyendo assets gráficos.
- `firmware/brcm/` — única fuente de verdad para el bundle de firmware Broadcom. No duplicar en otro directorio.
- `docs/` — toda la documentación en Markdown organizada por subsistema. Sin scripts ni binarios.

[`migration.sh`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/migration.sh) is the stable entrypoint and delegates into [`src/main.sh`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/main.sh), which handles CLI parsing and the interactive menu. Shared helpers and globals live in [`src/lib/common.sh`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/lib/common.sh). Feature flows are split across [`src/modules/backup.sh`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/backup.sh), [`src/modules/restore.sh`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/restore.sh), and [`src/modules/bootstrap.sh`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/modules/bootstrap.sh). Support tooling lives under [`src/tools/`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/src/tools), installable diagnostics under [`assets/diagnostics/`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/assets/diagnostics), and bundled Broadcom firmware under [`firmware/brcm/`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/firmware/brcm). Documentation lives under [`docs/`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs) (see [`docs/README.md`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/README.md) for the full index), and the optional config template lives at [`docs/linux-migration-tool.conf.example`](/home/gtx/Documentos/Prog_Local/ScriptMigrationCachyOS_v1_1/docs/linux-migration-tool.conf.example). Keep new logic in clearly named Bash functions grouped by responsibility.

## Build, Test, and Development Commands
- `bash migration.sh`: run the interactive tool locally.
- `bash migration.sh --help`: inspect the non-interactive CLI entrypoints added in `1.1`.
- `bash -n migration.sh src/main.sh src/lib/common.sh src/modules/*.sh src/tools/*.sh`: validate Bash syntax across the modular codebase.
- `shellcheck migration.sh src/main.sh src/lib/common.sh src/modules/*.sh src/tools/*.sh`: run static analysis for Bash if `shellcheck` is installed.
- `chmod +x migration.sh && ./migration.sh`: execute through the shebang when validating the menu flow.

## Coding Style & Naming Conventions
Use Bash with `set -euo pipefail` semantics preserved. Follow the existing style: 4-space indentation, uppercase globals (`VERSION`, `LOGFILE`), and snake_case function names (`backup_system`, `bootstrap_cachyos`). Prefer small functions, early validation, and quoted variable expansions. Keep user-facing log messages concise and aligned with the current Spanish tone used by the script.

## Testing Guidelines
There is no automated test suite yet. Minimum validation for changes is:
- `bash -n migration.sh src/main.sh src/lib/common.sh src/modules/*.sh src/tools/*.sh`
- `shellcheck migration.sh src/main.sh src/lib/common.sh src/modules/*.sh src/tools/*.sh`
- a manual dry run of the affected flow, either from the interactive menu or the corresponding CLI command

When adding risky operations (`rsync`, `sudo`, package installs, firmware copies), test against a disposable environment or mounted test directory first. If you add tests later, place them under `tests/` and name files `test_<feature>.sh`.

## Commit & Pull Request Guidelines
This checkout does not contain usable Git history, so no repository-specific commit convention can be inferred here. Use short imperative commit subjects, for example: `Document v1.1 firmware bundle layout`. Keep each commit focused on one behavior change.

PRs should include:
- a short summary of the user-visible change
- commands used for validation
- notes on destructive or privileged operations
- notes on config, backup-path, or firmware-bundle impacts when relevant
- screenshots or terminal snippets only when menu/output changes materially

## Security & Configuration Tips
Treat this script as privileged workstation automation. Review any change touching `sudo`, `curl | bash`, `git clone`, ownership changes, firmware installation, or backup paths with extra care. Do not hardcode machine-specific usernames, mount points, or secrets. Keep the example config generic and ensure optional paths from `linux-migration-tool.conf.example` remain user overridable.
