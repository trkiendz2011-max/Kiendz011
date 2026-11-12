#!/usr/bin/env bash
# Tests for pack.sh: zip layout, exclusions, checksum and idempotency.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "missing command: $1"; return 1; }
}
require_cmd zip
require_cmd unzip
require_cmd sha256sum

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if DEST_DIR="$tmp" bash "$ROOT_DIR/pack.sh" >/tmp/vip-pack.log 2>&1; then
  pass "pack.sh exits 0"
else
  fail "pack.sh failed: $(tail -n 5 /tmp/vip-pack.log)"
fi

zip="$tmp/winvm-codespaces-vip.zip"
sha="$tmp/winvm-codespaces-vip.zip.sha256.txt"

if [[ -s "$zip" ]]; then
  pass "zip exists and is not empty"
else
  fail "zip missing or empty: $zip"
fi

if [[ -s "$sha" ]]; then
  pass "checksum file exists"
else
  fail "checksum file missing or empty: $sha"
fi

if unzip -tqq "$zip" >/dev/null 2>&1; then
  pass "zip integrity check passes"
else
  fail "zip integrity check failed"
fi

listing="$(unzip -Z1 "$zip" 2>/dev/null || true)"

check_present() {
  local needle="$1" label="$2"
  if [[ "$listing" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

check_absent() {
  local needle="$1" label="$2"
  if [[ "$listing" == *"$needle"* ]]; then
    fail "$label (unexpected: $needle)"
  else
    pass "$label"
  fi
}

check_present "winvm-codespaces-vip/README.md" "zip contains README"
check_present "winvm-codespaces-vip/scripts/boot-menu.sh" "zip contains boot-menu.sh"
check_present "winvm-codespaces-vip/scripts/run-vm.sh" "zip contains run-vm.sh"
check_present "winvm-codespaces-vip/guest/autounattend/win11.xml" "zip contains win11 autounattend"
check_present "winvm-codespaces-vip/guest/scripts/setup-win.ps1" "zip contains guest setup"
check_present "winvm-codespaces-vip/docs/huong-dan.md" "zip contains Vietnamese guide"
check_present "winvm-codespaces-vip/pack.sh" "zip contains pack.sh"

check_absent "winvm-codespaces-vip/.git/" "zip excludes .git"
check_absent "winvm-codespaces-vip/iso/" "zip excludes iso"
check_absent "winvm-codespaces-vip/vm/" "zip excludes vm"
check_absent "winvm-codespaces-vip/.tools/" "zip excludes .tools"
check_absent "winvm-codespaces-vip/.superpowers/" "zip excludes .superpowers"

if (cd "$tmp" && sha256sum -c "winvm-codespaces-vip.zip.sha256.txt" >/dev/null 2>&1); then
  pass "checksum matches the zip"
else
  fail "checksum does not match the zip"
fi

if DEST_DIR="$tmp" bash "$ROOT_DIR/pack.sh" >/tmp/vip-pack2.log 2>&1; then
  pass "pack.sh can overwrite an existing zip"
else
  fail "pack.sh second run failed: $(tail -n 5 /tmp/vip-pack2.log)"
fi
if unzip -tqq "$zip" >/dev/null 2>&1; then
  pass "zip still valid after a second run"
else
  fail "zip corrupted after a second run"
fi

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll pack tests passed\n'
