[Leer en español 🇪🇸](README.md)

# CachyOS Migration Tool

Migration and bootstrap script for Linux workstations. Focused on the migration workflow to **CachyOS / Arch** with Python/Web development environments, AI tooling and terminal-heavy workflows.

> **Tested on CachyOS only.** The bootstrap uses `pacman` and `yay` (AUR) — not compatible with apt/rpm-based distributions without adaptation.

Includes model-aware support for **Intel MacBook Pro** profiles, with an initial validated base for:

- **MacBookPro12,1** — MacBook Pro Retina 13" 2015
- **MacBookPro8,1** — MacBook Pro 13" Early 2011

---

## What it does

| Operation | Description |
|---|---|
| **Backup** | Exports configurations, Git repos, user data and metadata (SSH, VSCode, ZSH, AI tooling) |
| **Bootstrap** | Installs and configures a CachyOS workstation from scratch: KDE Plasma, dev tooling, Docker, Syncthing |
| **Restore** | Restores the backup on the new installation, adapting UID/GID and permissions |
| **Post-check** | Validates system state after the first reboot post-bootstrap |
| **MBP Watch** | systemd hardware monitoring daemon + web dashboard + KDE plasmoid |
| **Extras** | Optional Hyprland, YouTube Force H264, VA-API Brave/Chromium Intel Broadwell, BTRFS snapshots |

---

## Current highlights

- Apple hardware detection by model and applied profile
- Dynamic bootstrap checklist: only compatible blocks are shown for the detected machine
- Python and `whiptail` TUIs adapted to the detected device context
- TUI backup flow with destination browser, real `/home/user` item selection and final backup verification
- Test commands to validate profiles, catalog and syntax before changing the system

---

## Quick start

```bash
# Interactive interface (automatically selects the best TUI engine)
./migration.sh

# Recommended flow after installing CachyOS
./migration.sh bootstrap
# → reboot
./migration.sh postcheck
./migration.sh restore --source /path/to/backup

# Quick checks
./migration.sh test profiles
./migration.sh test catalog
./migration.sh test syntax
./migration.sh test
```

The script selects the TUI engine in this order: **Python + curses** (no external dependencies) → **whiptail** → plain text menu. Can be forced with `TUI_BACKEND=python|whiptail|text`.

---

## CLI Commands

```bash
./migration.sh backup    [--target PATH] [--dry-run]
./migration.sh bootstrap [--dry-run] [--hyprland yes|no] [--apple-laptop yes|no]
./migration.sh postcheck
./migration.sh restore   [--source PATH] [--force] [--dry-run]

./migration.sh install-youtube-force-h264  [--dry-run]
./migration.sh configure-vaapi-brave       [--dry-run]

./migration.sh add-mbp-plasmoid            [--target primary|screen:N] [--dry-run]
./migration.sh move-mbp-plasmoid           [--target primary|screen:N] [--dry-run]
./migration.sh reinstall-mbp-plasmoid      [--target primary|screen:N] [--dry-run]
./migration.sh uninstall-mbp-plasmoid      [--dry-run]
./migration.sh uninstall-mbp-watch         [--dry-run]
```

---

## Bootstrap — selectable blocks

Presented as a checklist in the TUI. Active by default: `base`, `zsh`, `node`, `mbpwatch`, `plasmoid`.

| Block | What it installs |
|---|---|
| `base` | KDE Plasma, zsh, kitty, tmux, neovim, ripgrep, fd, bat, eza, docker, syncthing… |
| `zsh` | Oh My Zsh + Powerlevel10k |
| `node` | nvm, Node LTS, pnpm, bun |
| `ai` | Codex CLI, Claude Code |
| `mbpwatch` | MBP Watch daemon (systemd) |
| `plasmoid` | KDE MBP Watch plasmoid |
| `youtube` | YouTube Force H264 extension |
| `apple` | thermald, powertop (Intel Apple laptop extras) |
| `facetime` | facetimehd-dkms + firmware (PCIe camera MBP 2013+) |
| `iwd` | iwd backend for NetworkManager |
| `hyprland` | Hyprland + waybar, rofi, hyprpaper, grim, mako |
| `wifi` | wireless-regdb + country regulatory domain |
| `globalmenu` | KDE Global Menu for GTK and VS Code |
| `hwaccel` | HW acceleration flags for Brave/Chrome |
| `vaapi` | Intel Broadwell VA-API (libva-intel-driver-irql, i965) |
| `btrfs` | Snapper + grub-btrfs + snap-pac |

---

## Repository structure

```text
migration.sh                    # entry point
src/
├── main.sh                     # command logic and menu
├── lib/
│   ├── common.sh               # shared helpers
│   ├── tui.py                  # Python/curses TUI (primary)
│   └── tui.sh                  # whiptail TUI (fallback)
└── modules/
    ├── backup.sh
    ├── bootstrap.sh
    └── restore.sh
src/tools/
└── extract_bcm43602_bundle.sh  # extracts Wi-Fi firmware from current system
assets/
├── diagnostics/                # mbp_watch daemon, systemd service, plasmoid scripts
│   └── web/                    # local dashboard HTML/JS/CSS frontend
└── plasmoids/
    └── mbp-watch/              # KDE Plasma 6 package (kpackagetool6)
firmware/
└── brcm/                       # BCM43602 bundle to avoid Wi-Fi dependency post-install
docs/                           # full documentation
```

---

## MacBook profiles currently covered

The script automatically detects Apple hardware via DMI, applies a compatibility profile, and adapts both the TUI and the bootstrap to that model.

Profiles currently covered:

- **MacBookPro12,1** — MacBook Pro Retina 13" 2015
- **MacBookPro8,1** — MacBook Pro 13" Early 2011

Depending on the detected profile:

- only compatible bootstrap blocks are shown
- the VA-API fix changes according to the machine's Intel GPU
- the visible TUI summary shows detected model, applied profile and main characteristics

Specific extras already covered for `MacBookPro12,1`:

- **BCM43602 Wi-Fi** — copies local firmware from `firmware/brcm/` and applies `brcmfmac` workaround. To update the bundle from the current system: `bash src/tools/extract_bcm43602_bundle.sh`
- **FaceTime HD PCIe camera** (`14e4:1570`) — installs `facetimehd-dkms` + firmware, configures persistent module and `bdc_pci` blacklist
- **MBP Watch** — systemd daemon that monitors temperature, battery, Wi-Fi, drivers and kernel events; generates web dashboard at `http://localhost:7070/report.html` and AI digest at `/var/lib/mbp-watch/report.txt`
- **Intel Broadwell VA-API** — `--use-gl=angle --use-angle=opengl` flags for Brave/Chromium

For `MacBookPro8,1`, the initial profile already adjusts the bootstrap catalog and the VA-API path for Intel Sandy Bridge.

## Backup TUI

The interactive backup flow now:

- lets you choose the destination from common mounted paths or browse manually
- allows drilling down into directories before confirming the final target path
- lets you select real items inside `/home/user`
- keeps execution inside the TUI
- verifies the result at the end and stores useful logs inside the backup folder

---

## Requirements

- CachyOS (tested) or Arch Linux — requires `pacman` and `yay` for AUR packages
- `bash` 4+
- `python3` with `curses` module (primary TUI, already included in stdlib)
- `sudo` for bootstrap and daemon operations

The script works without a graphical TUI: text mode requires no additional dependencies.

---

## License

Distributed under the [GNU General Public License v3.0](LICENSE). No warranty of any kind — use at your own risk.

---

## Documentation

→ [`docs/`](docs/README.en.md)

- [Full usage guide](docs/migration.md)
- [TUI system](docs/tui.md)
- [BCM43602 Wi-Fi firmware](docs/firmware-bcm43602.md)
- [Diagnostics scripts and MBP Watch](docs/diagnostics.md)
- [KDE MBP Watch plasmoid](docs/plasmoid-mbp-watch.md)
- [MBP 2015 hardware on CachyOS](docs/hardware/mbp2015-cachyos-setup.md)
- [YouTube Force H264 extension](docs/extensions/youtube-force-h264.md)
