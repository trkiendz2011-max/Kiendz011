#!/usr/bin/env bash
# Unit tests for scripts/common.sh
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/common.sh
source "$ROOT_DIR/scripts/common.sh"

failures=0

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s: expected=%q actual=%q\n' "$label" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    failures=$((failures + 1))
  fi
}

os_config win10
assert_eq "win10" "$OS_ID" "win10 id"
assert_eq "Windows 10 Pro" "$OS_LABEL" "win10 label"
assert_eq "6" "$OS_EDITION_INDEX" "win10 edition index"
assert_eq "false" "$OS_TPM" "win10 tpm"

os_config win11
assert_eq "win11" "$OS_ID" "win11 id"
assert_eq "Windows 11 Pro" "$OS_LABEL" "win11 label"
assert_eq "6" "$OS_EDITION_INDEX" "win11 edition index"
assert_eq "true" "$OS_TPM" "win11 tpm"

os_config win11-ltsc
assert_eq "win11-ltsc" "$OS_ID" "win11-ltsc id"
assert_eq "1" "$OS_EDITION_INDEX" "win11-ltsc edition index"
assert_eq "true" "$OS_TPM" "win11-ltsc tpm"

os_config server2022
assert_eq "server2022" "$OS_ID" "server id"
assert_eq "4" "$OS_EDITION_INDEX" "server edition index"
assert_eq "false" "$OS_TPM" "server tpm"

# RAM is 4 GB minimum and may be raised on a 16 GB host.
os_config win11
if (( OS_RAM_MB >= 4096 )); then
  printf 'PASS win11 ram >= 4096\n'
else
  printf 'FAIL win11 ram: %s\n' "$OS_RAM_MB" >&2
  failures=$((failures + 1))
fi

accel="$(detect_accel)"
case "$accel" in
  kvm|"tcg,thread=multi") printf 'PASS accel=%s\n' "$accel" ;;
  *) printf 'FAIL accel=%q\n' "$accel" >&2; failures=$((failures + 1)) ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export ISO_DIR="$tmp"

if find_iso win11 >/dev/null 2>&1; then
  printf 'FAIL find_iso should fail on empty dir\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS find_iso empty dir\n'
fi

printf 'dummy' > "$tmp/Win11_24H2_English_x64.iso"
found="$(find_iso win11)"
assert_eq "$tmp/Win11_24H2_English_x64.iso" "$found" "find_iso win11 glob"

# A generic Windows 11 ISO must never be used for the LTSC edition.
if find_iso win11-ltsc >/dev/null 2>&1; then
  printf 'FAIL find_iso win11-ltsc should not use a generic Win11 ISO\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS find_iso win11-ltsc ignores generic Win11 ISO\n'
fi

printf 'dummy' > "$tmp/Win11_Enterprise_LTSC_2024.iso"
found="$(find_iso win11-ltsc)"
assert_eq "$tmp/Win11_Enterprise_LTSC_2024.iso" "$found" "find_iso win11-ltsc glob"

printf 'dummy' > "$tmp/Windows_Server_2022_Eval.iso"
found="$(find_iso server2022)"
assert_eq "$tmp/Windows_Server_2022_Eval.iso" "$found" "find_iso server2022 glob"

export VM_DIR="$tmp/vm"
dir="$(vm_dir win10)"
assert_true "vm_dir creates directory" test -d "$dir"

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll common tests passed\n'
