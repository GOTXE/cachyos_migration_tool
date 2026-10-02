#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Tests de shell, en orden alfabético; el primer fallo corta la ejecución.
for test_file in "$ROOT"/tests/test_*.sh; do
    [[ -e "$test_file" ]] || continue
    if ! bash "$test_file"; then
        printf 'FAIL %s\n' "$(basename "$test_file")" >&2
        exit 1
    fi
done

# 2. Comprobación de sintaxis de todos los scripts.
mapfile -t SYNTAX_FILES < <(
    {
        printf '%s\n' "$ROOT/migration.sh"
        find "$ROOT/src" "$ROOT/assets" -type f -name '*.sh'
    } | sort
)
for script in "${SYNTAX_FILES[@]}"; do
    if ! bash -n "$script"; then
        printf 'FAIL bash -n %s\n' "$script" >&2
        exit 1
    fi
done
printf 'OK bash -n (%d scripts)\n' "${#SYNTAX_FILES[@]}"

# 3. Compilación de la TUI Python.
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -m py_compile "$ROOT/src/lib/tui.py"; then
        printf 'FAIL py_compile src/lib/tui.py\n' >&2
        exit 1
    fi
    printf 'OK py_compile tui.py\n'
else
    printf 'SKIP py_compile (python3 no disponible)\n'
fi

# 4. ShellCheck con severidad error sobre src/ y migration.sh.
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -t SHELLCHECK_FILES < <(
        {
            printf '%s\n' "$ROOT/migration.sh"
            find "$ROOT/src" -type f -name '*.sh'
        } | sort
    )
    if ! shellcheck -S error "${SHELLCHECK_FILES[@]}"; then
        printf 'FAIL shellcheck\n' >&2
        exit 1
    fi
    printf 'OK shellcheck -S error\n'
else
    printf 'SKIP shellcheck\n'
fi
