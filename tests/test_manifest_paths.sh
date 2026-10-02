#!/usr/bin/env bash
# DATA_ROOTS: codificación de rutas (manifest_path_encode/decode) y lectura en restore.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/backup.sh"
# shellcheck disable=SC1091
source "$ROOT/src/modules/restore.sh"

check_roundtrip() {
    local ORIGINAL="$1"
    local ENCODED

    ENCODED="$(manifest_path_encode "$ORIGINAL")"
    assert_not_contains "$ENCODED" "," "sin comas tras codificar: $ORIGINAL"
    assert_eq "$(manifest_path_decode "$ENCODED")" "$ORIGINAL" "ida y vuelta: $ORIGINAL"
}

check_roundtrip "/data"
check_roundtrip "/mnt/a,b"
check_roundtrip "/mnt/100%"
check_roundtrip "/mnt/lit%2Cral"
check_roundtrip "/mnt/x,%2C,%25,y"

assert_eq "$(manifest_path_encode '/a,b%c')" "/a%2Cb%25c" "codificación exacta"

BM_DATA_ROOTS="home:Doc%2Cs,external:/data,external:/mnt/a%2Cb,external:/mnt/100%25"
assert_eq "$(backup_external_roots)" $'/data\n/mnt/a,b\n/mnt/100%' "raíces externas decodificadas"

BM_DATA_ROOTS=""
assert_eq "$(backup_external_roots)" "" "sin DATA_ROOTS"

printf 'OK manifest paths\n'
