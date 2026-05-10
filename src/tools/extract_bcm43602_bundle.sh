#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEST_DIR="$PROJECT_ROOT/firmware/brcm"
SOURCE_ROOT="/"
APPLE_MODEL="${1:-MacBookPro12,1}"
COPIED_NOW=()
ALREADY_PRESENT=()
MISSING_FILES=()

copy_if_exists() {
    local SOURCE_FILE="$1"
    local TARGET_NAME="$2"

    if [ -f "$SOURCE_FILE" ]; then
        if [ -f "$DEST_DIR/$TARGET_NAME" ]; then
            ALREADY_PRESENT+=("$TARGET_NAME")
            printf 'ya existia: %s\n' "$DEST_DIR/$TARGET_NAME"
        else
            cp "$SOURCE_FILE" "$DEST_DIR/$TARGET_NAME"
            COPIED_NOW+=("$TARGET_NAME")
            printf 'copiado ahora: %s -> %s\n' "$SOURCE_FILE" "$DEST_DIR/$TARGET_NAME"
        fi
        return 0
    fi

    return 1
}

copy_first_match() {
    local TARGET_NAME="$1"
    shift

    local CANDIDATE=""

    for CANDIDATE in "$@"; do
        if copy_if_exists "$CANDIDATE" "$TARGET_NAME"; then
            return 0
        fi
    done

    MISSING_FILES+=("$TARGET_NAME")
    printf 'faltante en sistema actual: %s\n' "$TARGET_NAME"
    return 0
}

printf 'Origen: %s\n' "$SOURCE_ROOT"
printf 'Destino: %s\n' "$DEST_DIR"
printf 'Modelo Apple: %s\n' "$APPLE_MODEL"

mkdir -p "$DEST_DIR"

copy_first_match "brcmfmac43602-pcie.bin" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.bin" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.bin"

copy_first_match "brcmfmac43602-pcie.bin.zst" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.bin.zst" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.bin.zst"

copy_first_match "brcmfmac43602-pcie.clm_blob" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.clm_blob" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.clm_blob"

copy_first_match "brcmfmac43602-pcie.clm_blob.zst" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.clm_blob.zst" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.clm_blob.zst"

copy_first_match "brcmfmac43602-pcie.txcap_blob" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.txcap_blob" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.txcap_blob"

copy_first_match "brcmfmac43602-pcie.txcap_blob.zst" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.txcap_blob.zst" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.txcap_blob.zst"

copy_first_match "brcmfmac43602-pcie.txt" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.txt" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.txt" \
    "$SOURCE_ROOT/System/Library/Extensions/IO80211Family.kext/Contents/Resources/brcmfmac43602-pcie.txt"

copy_first_match "brcmfmac43602-pcie.Apple Inc.-$APPLE_MODEL.txt" \
    "$SOURCE_ROOT/usr/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-$APPLE_MODEL.txt" \
    "$SOURCE_ROOT/lib/firmware/brcm/brcmfmac43602-pcie.Apple Inc.-$APPLE_MODEL.txt" \
    "$SOURCE_ROOT/System/Library/Extensions/IO80211Family.kext/Contents/Resources/brcmfmac43602-pcie.txt"

printf '\nResumen:\n'

printf 'Copiados ahora:\n'
if [ ${#COPIED_NOW[@]} -eq 0 ]; then
    printf ' - ninguno\n'
else
    printf ' - %s\n' "${COPIED_NOW[@]}" | sort
fi

printf 'Ya presentes en el bundle:\n'
if [ ${#ALREADY_PRESENT[@]} -eq 0 ]; then
    printf ' - ninguno\n'
else
    printf ' - %s\n' "${ALREADY_PRESENT[@]}" | sort -u
fi

printf 'Faltantes en sistema actual:\n'
if [ ${#MISSING_FILES[@]} -eq 0 ]; then
    printf ' - ninguno\n'
else
    printf ' - %s\n' "${MISSING_FILES[@]}" | sort -u
fi
