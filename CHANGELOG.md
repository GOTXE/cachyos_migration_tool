# Changelog

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
