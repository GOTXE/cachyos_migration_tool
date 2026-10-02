#!/usr/bin/env bash
# Stubs de comandos externos para tests. Se cargan con `source`.

stub_setup() {
    STUB_ORIG_PATH="$PATH"
    STUB_DIR="$(mktemp -d)"
    STUB_LOG="$STUB_DIR/calls.log"
    : >"$STUB_LOG"
    PATH="$STUB_DIR:$PATH"
    export STUB_DIR STUB_LOG
}

# stub_cmd <nombre> [código_salida] [stdout]
stub_cmd() {
    local name="$1"
    local code="${2:-0}"
    local out="${3:-}"
    local file="$STUB_DIR/$name"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'printf "%%s\\n" "%s $*" >>%q\n' "$name" "$STUB_LOG"
        if [[ -n "$out" ]]; then
            printf 'printf "%%s\\n" %q\n' "$out"
        fi
        printf 'exit %d\n' "$code"
    } >"$file"
    chmod +x "$file"
}

stub_teardown() {
    if [[ -n "${STUB_DIR:-}" ]]; then
        rm -rf "$STUB_DIR"
    fi
    if [[ -n "${STUB_ORIG_PATH:-}" ]]; then
        PATH="$STUB_ORIG_PATH"
    fi
    unset STUB_DIR STUB_LOG STUB_ORIG_PATH
}
