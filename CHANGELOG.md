# Changelog

## Unreleased

- VA-API Intel: generic Intel machines now get `intel-media-driver` + `libva-intel-driver` + `libva-utils` without forcing `LIBVA_DRIVER_NAME=i965` or writing `brave-flags.conf`; a legacy i965-only `vaapi.conf` is moved to `vaapi.conf.bak.<timestamp>`. MacBook Pro 12,1 / 8,1 keep their i965 setup. The block ends with a `vainfo` check (warning only).
- `write_browser_flags_file` no longer overwrites silently: identical content is a no-op, different content is backed up to `<file>.bak.<timestamp>` first.
- **BREAKING:** `bootstrap`, `tui-bootstrap-run`, `configure-vaapi-brave`, `install-mbp-watch`, `install-talk2ai`, `install-codexbar-tray` and `install-youtube-force-h264` now exit with an error on non-Arch distributions. `backup`, `restore`, `restic-backup`, `postcheck`, `test` and plasmoid commands are not blocked.
- Restic runner: snapshots are tagged with `--host <HOST_LABEL>`, `forget` is limited to that host and no longer prunes on every run; pruning plus a partial `check` moved to `restic-backup maintenance` with a new weekly `restic-maintenance.timer`. `install-timer`/`disable-timer` manage both timers.
- Restic runner rotates its logs (`BACKUP_LOG_RETENTION_DAYS`, 14 by default), uses `--one-file-system --exclude-caches`, reuses the shared package inventory and warns to keep the Restic password outside the machine (`init` and `status`).
- `install_restic_package` supports pacman, apt-get, dnf and zypper. Excludes: added `~/Downloads`, removed `**/build`, `**/dist` and `**/target`.
- CI: new `roundtrip` job runs the backup/restore roundtrip and v1 restore tests as a non-root user on Arch, Debian and Fedora containers.
- Both TUIs recognise v2 backups (`metadata/manifest.env`) as well as v1 (`metadata/user_ids.conf`), list them by their real creation date (manifest `CREATED_AT`, or `user_ids.conf` mtime for v1) instead of by folder name, and show the host in the restore picker.
- The Python TUI backup verification uses the v2 layout (`configs/<item>`, `data/home/...`, `data/external/...`), so nested configs are no longer checked against the wrong path; `tests/run.sh` now runs the Python unit tests.
- **BREAKING:** `restore` no longer asks for `sudo` and no longer runs `chown`; it warns about files not owned by you in `.ssh`, `.codex` and `.claude` and prints the exact `sudo chown` command. Use `--fix-ownership` to apply it.
- `restore` understands backup format v2 (relative config paths, `data/home`, `data/external`) and v1 (nested configs are repaired using `logs/backup_selection.txt`); unsupported `FORMAT_VERSION` aborts without touching anything.
- External data is restored under `~/restored-external/<original path>`; `--external-to-original` restores to the original path when its parent exists and is writable.
- **BREAKING:** backups use the portable v2 layout: `configs/` keeps paths relative to `$HOME` (fixes nested configs such as `.config/Code`), user data goes to `data/home/<rel>` or `data/external/<abs>`, and `metadata/manifest.env` (`FORMAT_VERSION=2`) describes the backup. Restoring v2 backups needs the matching restore (next tasks).
- Backup no longer extracts the Broadcom firmware bundle and exports a multi-distro package inventory (`metadata/packages/`) instead of `pacman -Qqe`/`dpkg`/`flatpak` dumps; it also records `os-release`, VS Code extensions and enabled user units.
- Backup preflight checks Bash >= 4.4 and the required commands with distro-specific install hints; repo copies also skip `node_modules` and tool caches.
- Backup folders are now named `<host>_DD_MM_AAAA-HH:mm` (`:` becomes `h` on exFAT/FAT/NTFS/SMB destinations, `_2`, `_3`... on collisions) instead of `linux_backup_YYYY-MM-DD_HH-MM-SS`. Override the host part with `BACKUP_HOST_LABEL`.
- Added `src/lib/os.sh` (`os_release_value`, `os_family`, `os_pkg_install_cmd`, `require_commands`, `require_bash_44`) for distribution detection and portable preflight checks.
- Added `src/lib/inventory.sh` (`inventory_write`): multi-distro package inventory (pacman, apt, dpkg, rpm, dnf, zypper, flatpak, snap) that skips missing managers and records failures in `INVENTORY_WARNINGS`.
- **BREAKING:** `bootstrap` sin `--blocks` ejecuta solo los bloques compatibles marcados por defecto; MBP Watch ya no se instala implícitamente.
- Added single bootstrap block registry (`src/core/blocks.sh`) shared by the CLI and both TUIs, with `bootstrap --blocks a,b,c` and `--list-blocks`.
- Fixed the `appimage` block, which was listed but never executed by the TUI.
- Bootstrap blocks now run isolated with `set -e`; a failing block is reported and the run ends with `BOOTSTRAP COMPLETADO CON ERRORES: <ids>`.
- `select_disk` validates the selection range (`1..N`); `0` no longer picks the last disk.
- Logs now go to `${XDG_STATE_HOME:-~/.local/state}/linux-migration-tool/logs/` instead of the current directory; the directory is created on first write.
- `log`/`tty_log` use `printf '%s\n'` so backslashes in messages are no longer interpreted; ANSI colors are real escape bytes and are stripped from the log file.
- Added `linux-migration-tool.conf.example` (referenced by the main menu intro).
- Test infrastructure: `tests/run.sh` auto-discovers `tests/test_*.sh`, runs `bash -n`, `py_compile` and ShellCheck, and `tests/lib/{assert,stubs}.sh` provide shared helpers.

## 1.11.0

- Restore normalizes new file and directory permissions by default instead of blindly applying backup-wide executable bits.
- Git repositories recover executable permissions only from their tracked `100755` entries.
- Added `--preserve-permissions` for restores that require exact backup modes.

## 1.9.2

- Improved unattended bootstrap and persistent sudo handling.
- Added reliable installation and verification for Node/npm, Codex, Claude, Gemini, OpenCode and Antigravity.
- Added Antigravity CLI, Python SDK, Desktop and IDE installation.
- Added Android Studio/JDK 21 compatibility and LibreOffice Java conflict handling.
- Added Broadcom BCM43602 firmware, Limine kernel parameter and suspend/resume workaround documentation.
- Added detailed audit documentation for the MBP Wi-Fi suspend failure.
