[Read in English 🇬🇧](README.en.md)

# CachyOS Migration Tool

Script de migración y bootstrap para workstations Linux. Orientado al flujo de migración hacia **CachyOS / Arch** con entornos de desarrollo Python/Web, IA tooling y workflows terminal-heavy.

> **Probado únicamente en CachyOS.** El bootstrap usa `pacman` y `yay` (AUR) — no es compatible con distribuciones basadas en apt/rpm sin adaptación.

Incluye soporte específico para perfiles **MacBook Pro Intel** detectados por modelo, con una primera base validada para:

- **MacBookPro12,1** — MacBook Pro Retina 13" 2015
- **MacBookPro8,1** — MacBook Pro 13" Early 2011

---

## Qué hace

| Operación | Descripción |
|---|---|
| **Backup** | Exporta configuraciones, repos Git, datos de usuario y metadata (SSH, VSCode, ZSH, IA tooling) |
| **Bootstrap** | Instala y configura una workstation CachyOS desde cero: KDE Plasma, dev tooling, Docker, Syncthing |
| **Restore** | Restaura el backup en la nueva instalación, adaptando UID/GID y permisos |
| **Post-check** | Valida el estado del sistema tras el primer reinicio post-bootstrap |
| **MBP Watch** | Daemon systemd de monitorización de hardware + dashboard web + plasmoid KDE |
| **Extras** | Hyprland opcional, YouTube Force H264, VA-API Brave/Chromium según perfil Intel detectado, BTRFS snapshots |

---

## Novedades actuales

- Detección de hardware Apple por modelo y perfil aplicado
- Bootstrap con checklist dinámico: solo muestra bloques compatibles con el equipo detectado
- TUI Python y `whiptail` adaptadas al contexto del dispositivo
- Backup TUI con exploración de destino, selección real de elementos de `/home/usuario` y verificación final del backup
- Comandos de test para validar perfiles, catálogo y sintaxis antes de tocar el sistema

---

## Uso rápido

```bash
# Interfaz interactiva (selecciona automáticamente el mejor motor TUI)
./migration.sh

# Flujo recomendado tras instalar CachyOS
./migration.sh bootstrap
# → reiniciar
./migration.sh postcheck
./migration.sh restore --source /ruta/del/backup

# Comprobaciones rápidas
./migration.sh test profiles
./migration.sh test catalog
./migration.sh test syntax
./migration.sh test
```

El script selecciona el motor TUI en este orden: **Python + curses** (sin dependencias externas) → **whiptail** → menú de texto plano. Se puede forzar con `TUI_BACKEND=python|whiptail|text`.

---

## Comandos CLI

```bash
./migration.sh backup    [--target RUTA] [--dry-run]
./migration.sh bootstrap [--dry-run] [--hyprland yes|no] [--apple-laptop yes|no]
./migration.sh postcheck
./migration.sh restore   [--source RUTA] [--force] [--dry-run]

./migration.sh install-youtube-force-h264  [--dry-run]
./migration.sh install-talk2ai            [--dry-run]
./migration.sh install-codexbar-tray      [--dry-run]
./migration.sh configure-vaapi-brave       [--dry-run]

./migration.sh install-mbp-watch           [--dry-run]
./migration.sh add-mbp-plasmoid            [--target primary|screen:N] [--dry-run]
./migration.sh move-mbp-plasmoid           [--target primary|screen:N] [--dry-run]
./migration.sh reinstall-mbp-plasmoid      [--target primary|screen:N] [--dry-run]
./migration.sh uninstall-mbp-plasmoid      [--dry-run]
./migration.sh uninstall-mbp-watch         [--dry-run]
```

`install-youtube-force-h264` y `configure-vaapi-brave` siguen disponibles por CLI, pero en la interfaz interactiva normal viven dentro de `bootstrap`, no como opciones sueltas del menú principal.

---

## Bootstrap — bloques seleccionables

En la TUI se presentan como checklist dinámico según el hardware detectado. Activos por defecto en el perfil inicial actual: `sync`, `yay`, `flatpak`, `official`, `kde`, `aur`, `zsh`, `node` y `apple` cuando aplica.

| Bloque | Qué instala |
|---|---|
| `base` | KDE Plasma, zsh, kitty, tmux, neovim, ripgrep, fd, bat, eza, docker, syncthing… |
| `zsh` | Oh My Zsh + Powerlevel10k |
| `node` | nvm, Node LTS, pnpm, bun |
| `ai` | Codex CLI, Claude Code |
| `mbpwatch` | Daemon MBP Watch (systemd) |
| `plasmoid` | Plasmoid KDE MBP Watch |
| `youtube` | Extensión YouTube Force H264 |
| `apple` | thermald, powertop (extras Apple laptop Intel) |
| `facetime` | facetimehd-dkms + firmware (cámara PCIe MBP 2013+) |
| `talk2ai` | Descarga o actualiza `talk2ai` desde GitHub e instala `handy-bin` como dependencia |
| `obsidian` | Obsidian desde repositorio oficial |
| `sshpass` | `sshpass` para SSH con contraseña no interactiva |
| `codexbar_tray` | Instala `codexBar Tray` desde un repo local restaurado/detectado |
| `iwd` | iwd backend para NetworkManager |
| `hyprland` | Hyprland + waybar, rofi, hyprpaper, grim, mako |
| `wifi` | wireless-regdb + dominio regulatorio por país |
| `globalmenu` | Global Menu KDE para GTK y VS Code |
| `hwaccel` | Flags de aceleración HW para Brave/Chrome |
| `vaapi` | VA-API Brave/Chromium ajustado al perfil Intel detectado |
| `btrfs` | Snapper + grub-btrfs + snap-pac |

---

## Estructura del repositorio

```text
migration.sh                    # punto de entrada
src/
├── main.sh                     # lógica de comandos y menú
├── lib/
│   ├── common.sh               # helpers compartidos
│   ├── tui.py                  # TUI Python/curses (primario)
│   └── tui.sh                  # TUI whiptail (fallback)
└── modules/
    ├── backup.sh
    ├── bootstrap.sh
    └── restore.sh
src/tools/
└── extract_bcm43602_bundle.sh  # extrae firmware Wi-Fi desde el sistema actual
assets/
├── diagnostics/                # daemon mbp_watch, servicio systemd, scripts de plasmoid
│   └── web/                    # frontend HTML/JS/CSS del dashboard local
└── plasmoids/
    └── mbp-watch/              # paquete KDE Plasma 6 (kpackagetool6)
firmware/
└── brcm/                       # bundle BCM43602 para no depender de Wi-Fi en post-install
docs/                           # documentación completa
```

---

## Perfiles MacBook contemplados

El script detecta automáticamente hardware Apple vía DMI, aplica un perfil de compatibilidad y adapta la TUI y el bootstrap a ese modelo.

Perfiles contemplados ahora mismo:

- **MacBookPro12,1** — MacBook Pro Retina 13" 2015
- **MacBookPro8,1** — MacBook Pro 13" Early 2011

En función del perfil detectado:

- se muestran solo los bloques de bootstrap compatibles
- la corrección de VA-API cambia según la GPU Intel del equipo
- el resumen de hardware visible en la TUI indica modelo detectado, perfil aplicado y características principales

Extras específicos ya cubiertos para `MacBookPro12,1`:

- **Wi-Fi BCM43602** — copia firmware local desde `firmware/brcm/` y aplica workaround `brcmfmac`. Para actualizar el bundle desde el sistema actual: `bash src/tools/extract_bcm43602_bundle.sh`
- **Cámara FaceTime HD PCIe** (`14e4:1570`) — instala `facetimehd-dkms` + firmware, configura módulo persistente y blacklist de `bdc_pci`
- **MBP Watch** — daemon systemd que monitoriza temperatura, batería, Wi-Fi, drivers y eventos de kernel; genera dashboard web en `http://localhost:7070/report.html` y AI digest en `/var/lib/mbp-watch/report.txt`
- **VA-API Intel Broadwell** — flags `--use-gl=angle --use-angle=opengl` para Brave/Chromium

Para `MacBookPro8,1`, el perfil inicial ya ajusta el catálogo de bootstrap y la ruta de VA-API para Intel Sandy Bridge.

## Backup TUI

El flujo interactivo de backup ahora:

- permite elegir el destino desde montajes típicos del sistema o navegar manualmente
- deja profundizar por directorios antes de confirmar la ruta final
- permite seleccionar elementos reales dentro de `/home/usuario`
- mantiene la ejecución dentro de la propia TUI
- verifica el resultado al finalizar y guarda logs útiles en la carpeta del backup

---

## Requisitos

- CachyOS (probado) o Arch Linux — requiere `pacman` y `yay` para paquetes AUR
- `bash` 4+
- `python3` con módulo `curses` (TUI primaria, ya incluido en stdlib)
- `sudo` para bootstrap y operaciones del daemon

El script funciona sin TUI gráfica: el modo texto no requiere dependencias adicionales.

---

## Licencia

Distribuido bajo la [GNU General Public License v3.0](LICENSE). Sin garantía de ningún tipo — úsalo bajo tu propia responsabilidad.

---

## Documentación

→ [`docs/`](docs/README.md)

- [Guía completa de uso](docs/migration.md)
- [Sistema TUI](docs/tui.md)
- [Firmware Wi-Fi BCM43602](docs/firmware-bcm43602.md)
- [Scripts de diagnóstico y MBP Watch](docs/diagnostics.md)
- [Plasmoid KDE MBP Watch](docs/plasmoid-mbp-watch.md)
- [Hardware MBP 2015 en CachyOS](docs/hardware/mbp2015-cachyos-setup.md)
- [Logitech Craft + MX Master 3 en CachyOS](docs/logitech-cachyos.md)
- [Extensión YouTube Force H264](docs/extensions/youtube-force-h264.md)
