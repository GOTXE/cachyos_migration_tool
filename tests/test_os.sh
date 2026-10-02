#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/assert.sh"
# shellcheck disable=SC1091
source "$ROOT/tests/lib/stubs.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; stub_teardown' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LOGFILE="$TMP/test.log"

# shellcheck disable=SC1091
source "$ROOT/src/lib/common.sh"
# shellcheck disable=SC1091
source "$ROOT/src/lib/os.sh"

FIX="$ROOT/tests/fixtures/os-release"

check_family() {
    local fixture="$1"
    local expected="$2"
    OS_RELEASE_FILE="$FIX/$fixture"
    assert_eq "$(os_family)" "$expected" "os_family de $fixture"
}

check_family cachyos arch
check_family arch arch
check_family debian debian
check_family ubuntu debian
check_family fedora fedora
check_family opensuse-tumbleweed suse
check_family unknown unknown

# fichero inexistente
OS_RELEASE_FILE="$TMP/no-existe"
assert_eq "$(os_family)" "unknown" "os_family sin os-release"
assert_eq "$(os_release_value ID)" "" "valor vacío sin fichero"

# valores y comillas
OS_RELEASE_FILE="$FIX/opensuse-tumbleweed"
assert_eq "$(os_release_value ID)" "opensuse-tumbleweed" "ID sin comillas dobles"
assert_eq "$(os_release_value ID_LIKE)" "opensuse suse" "ID_LIKE con espacios"
OS_RELEASE_FILE="$FIX/unknown"
assert_eq "$(os_release_value VERSION_ID)" "1.0" "comillas simples eliminadas"
assert_eq "$(os_release_value NO_EXISTE)" "" "clave ausente"

# ID_LIKE sin ID conocido
printf 'ID=rocky\nID_LIKE="rhel centos fedora"\n' >"$TMP/rocky"
OS_RELEASE_FILE="$TMP/rocky"
assert_eq "$(os_family)" "fedora" "rocky es fedora"
printf 'ID=garuda\nID_LIKE="arch"\n' >"$TMP/garuda"
OS_RELEASE_FILE="$TMP/garuda"
assert_eq "$(os_family)" "arch" "ID_LIKE=arch"
printf 'ID=sles\n' >"$TMP/sles"
OS_RELEASE_FILE="$TMP/sles"
assert_eq "$(os_family)" "suse" "sles es suse"

# no hay ejecución de código del fichero
printf 'ID=evil\nNAME="$(touch %s/pwned)"\n' "$TMP" >"$TMP/evil"
OS_RELEASE_FILE="$TMP/evil"
os_release_value NAME >/dev/null
assert_no_file "$TMP/pwned"

# sugerencias de instalación
OS_RELEASE_FILE="$FIX/cachyos"
assert_eq "$(os_pkg_install_cmd rsync)" "sudo pacman -S --needed rsync" "pacman"
OS_RELEASE_FILE="$FIX/debian"
assert_eq "$(os_pkg_install_cmd rsync)" "sudo apt-get install -y rsync" "apt"
OS_RELEASE_FILE="$FIX/fedora"
assert_eq "$(os_pkg_install_cmd rsync)" "sudo dnf install -y rsync" "dnf"
OS_RELEASE_FILE="$FIX/opensuse-tumbleweed"
assert_eq "$(os_pkg_install_cmd rsync)" "sudo zypper --non-interactive install rsync" "zypper"
OS_RELEASE_FILE="$FIX/unknown"
assert_eq "$(os_pkg_install_cmd rsync)" "" "familia desconocida"

# require_commands
stub_setup
stub_cmd present_cmd
OS_RELEASE_FILE="$FIX/debian"
rc=0
out="$(require_commands present_cmd missing_one missing_two 2>&1)" || rc=$?
assert_eq "$rc" "1" "require_commands devuelve 1 si falta alguno"
assert_contains "$out" "[ERROR] Falta missing_one. Instálalo con: sudo apt-get install -y missing_one" "mensaje missing_one"
assert_contains "$out" "[ERROR] Falta missing_two." "mensaje missing_two"
assert_not_contains "$out" "Falta present_cmd" "no reporta el presente"
rc=0
require_commands present_cmd >/dev/null 2>&1 || rc=$?
assert_eq "$rc" "0" "require_commands devuelve 0 si están todos"

# require_bash_44 (BASH_VERSINFO es de solo lectura: se prueba el comparador)
assert_eq "$(require_bash_44 && echo ok)" "ok" "bash actual cumple 4.4"
bash_version_at_least 4 4 5 0 || fail "5.0 >= 4.4"
bash_version_at_least 4 4 4 4 || fail "4.4 >= 4.4"
bash_version_at_least 4 4 4 3 && fail "4.3 < 4.4"
bash_version_at_least 4 4 3 2 && fail "3.2 < 4.4"
rc=0
out="$(_os_report_old_bash 4 3 2>&1)" || rc=$?
assert_eq "$rc" "1" "bash 4.3 no cumple"
assert_contains "$out" "4.4" "mensaje de bash 4.4"

printf 'OK os\n'
