#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT/tests/test_bootstrap_profiles.sh"
bash "$ROOT/tests/test_bootstrap_catalog.sh"
bash "$ROOT/tests/test_restore_permissions.sh"
bash -n "$ROOT/migration.sh" "$ROOT/src/main.sh" "$ROOT/src/lib/common.sh" "$ROOT/src/modules/backup.sh" "$ROOT/src/modules/restore.sh" "$ROOT/src/modules/bootstrap.sh" "$ROOT/src/tools/extract_bcm43602_bundle.sh" "$ROOT/src/lib/tui.sh"

