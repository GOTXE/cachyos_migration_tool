#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"

fail() {
    printf 'TEST FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if ! printf '%s\n' "$haystack" | grep -Fq "$needle"; then
        fail "$label: missing '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if printf '%s\n' "$haystack" | grep -Fq "$needle"; then
        fail "$label: unexpected '$needle'"
    fi
}

detect_facetimehd_camera() {
    printf 'yes\n'
}

detect_gpu_profile() {
    printf 'intel-only\n'
}

MACBOOK_MODEL="MacBookPro12,1"
CATALOG_2015="$(get_bootstrap_checklist_items)"
assert_contains "$CATALOG_2015" "mbpwatch|MBP Watch diagnóstico (systemd)|OFF" "catalog 12,1 mbpwatch"
assert_contains "$CATALOG_2015" "plasmoid|Plasmoid KDE MBP Watch|OFF" "catalog 12,1 plasmoid"
assert_contains "$CATALOG_2015" "apple|Apple laptop extras|ON" "catalog 12,1 apple"
assert_contains "$CATALOG_2015" "facetime|FaceTime HD camera (AUR)|ON" "catalog 12,1 facetime"
assert_contains "$CATALOG_2015" "vaapi|VA-API Brave/Chromium (Intel Broadwell)|OFF" "catalog 12,1 vaapi"
assert_contains "$CATALOG_2015" "talk2ai|talk2ai (descarga/actualiza desde GitHub)|OFF" "catalog 12,1 talk2ai"
assert_contains "$CATALOG_2015" "restic|Restic para backup/restore por repositorio|ON" "catalog 12,1 restic"
assert_contains "$CATALOG_2015" "filezilla|FileZilla (cliente SFTP/FTP gráfico)|OFF" "catalog 12,1 filezilla"
assert_contains "$CATALOG_2015" "markdownpart|MarkdownPart para vista previa Markdown en Kate|OFF" "catalog 12,1 markdownpart"
assert_contains "$CATALOG_2015" "libreoffice|LibreOffice Fresh ES|OFF" "catalog 12,1 libreoffice"
assert_contains "$CATALOG_2015" "ipscan|Angry IP Scanner (AUR)|OFF" "catalog 12,1 ipscan"
assert_contains "$CATALOG_2015" "tea|tea CLI para Gitea|OFF" "catalog 12,1 tea"
assert_contains "$CATALOG_2015" "obsidian|Obsidian (Markdown knowledge base)|OFF" "catalog 12,1 obsidian"
assert_contains "$CATALOG_2015" "sshpass|sshpass para contraseñas SSH no interactivas|OFF" "catalog 12,1 sshpass"
assert_contains "$CATALOG_2015" "codexbar_tray|codexBar Tray KDE (instala desde repo local restaurado)|OFF" "catalog 12,1 codexbar tray"
assert_not_contains "$CATALOG_2015" "hwaccel|Aceleración HW Chromium/Brave|OFF" "catalog 12,1 hwaccel hidden"

MACBOOK_MODEL="MacBookPro8,1"
CATALOG_2011="$(get_bootstrap_checklist_items)"
assert_contains "$CATALOG_2011" "mbpwatch|MBP Watch diagnóstico (systemd)|OFF" "catalog 8,1 mbpwatch"
assert_contains "$CATALOG_2011" "apple|Apple laptop extras|ON" "catalog 8,1 apple"
assert_not_contains "$CATALOG_2011" "facetime|FaceTime HD camera (AUR)|ON" "catalog 8,1 facetime hidden"
assert_contains "$CATALOG_2011" "vaapi|VA-API Brave/Chromium (Intel Sandy Bridge)|OFF" "catalog 8,1 vaapi"

MACBOOK_MODEL="MacBookPro9,2"
CATALOG_GENERIC="$(get_bootstrap_checklist_items)"
assert_not_contains "$CATALOG_GENERIC" "mbpwatch|MBP Watch diagnóstico (systemd)|OFF" "catalog generic mbpwatch hidden"
assert_not_contains "$CATALOG_GENERIC" "apple|Apple laptop extras|ON" "catalog generic apple hidden"
assert_contains "$CATALOG_GENERIC" "talk2ai|talk2ai (descarga/actualiza desde GitHub)|OFF" "catalog generic talk2ai"
assert_contains "$CATALOG_GENERIC" "restic|Restic para backup/restore por repositorio|ON" "catalog generic restic"
assert_contains "$CATALOG_GENERIC" "filezilla|FileZilla (cliente SFTP/FTP gráfico)|OFF" "catalog generic filezilla"
assert_contains "$CATALOG_GENERIC" "markdownpart|MarkdownPart para vista previa Markdown en Kate|OFF" "catalog generic markdownpart"
assert_contains "$CATALOG_GENERIC" "libreoffice|LibreOffice Fresh ES|OFF" "catalog generic libreoffice"
assert_contains "$CATALOG_GENERIC" "ipscan|Angry IP Scanner (AUR)|OFF" "catalog generic ipscan"
assert_contains "$CATALOG_GENERIC" "tea|tea CLI para Gitea|OFF" "catalog generic tea"
assert_contains "$CATALOG_GENERIC" "obsidian|Obsidian (Markdown knowledge base)|OFF" "catalog generic obsidian"
assert_contains "$CATALOG_GENERIC" "sshpass|sshpass para contraseñas SSH no interactivas|OFF" "catalog generic sshpass"
assert_contains "$CATALOG_GENERIC" "codexbar_tray|codexBar Tray KDE (instala desde repo local restaurado)|OFF" "catalog generic codexbar tray"

printf 'OK bootstrap catalog\n'
