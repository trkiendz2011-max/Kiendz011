#!/usr/bin/env bash
# Tests for the interactive VIP boot menu (non-interactive surfaces only).
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

if out="$(bash "$ROOT_DIR/scripts/boot-menu.sh" --help 2>&1)"; then
  pass "boot-menu --help exits 0"
else
  fail "boot-menu --help failed: $out"
fi

for needle in win10 win11 win11-ltsc server2022; do
  if [[ "$out" == *"$needle"* ]]; then
    pass "boot-menu help mentions $needle"
  else
    fail "boot-menu help misses $needle"
  fi
done

for needle in "Tạo" "Bật" "Tắt" "Trạng thái" "Snapshot" "noVNC"; do
  if [[ "$out" == *"$needle"* ]]; then
    pass "boot-menu help mentions $needle"
  else
    fail "boot-menu help misses $needle"
  fi
done

if bash "$ROOT_DIR/scripts/boot-menu.sh" --nonsense >/dev/null 2>&1; then
  fail "boot-menu accepts an invalid option"
else
  pass "boot-menu rejects an invalid option"
fi

if out="$(bash "$ROOT_DIR/scripts/boot-menu.sh" </dev/null 2>&1)"; then
  fail "boot-menu should refuse a non-interactive stdin"
else
  pass "boot-menu refuses non-interactive stdin"
fi
if [[ "$out" == *"boot-menu.sh"* || "$out" == *"Dùng"* ]]; then
  pass "non-interactive message shows usage"
else
  fail "non-interactive message is not usage: $out"
fi

if grep -qF 'codespaces_vnc_url' "$ROOT_DIR/scripts/boot-menu.sh"; then
  pass "boot-menu prints the Codespaces noVNC URL"
else
  fail "boot-menu does not use codespaces_vnc_url"
fi

# A failing child action must not kill the menu: use a PTY, choose create win10
# with no ISO, press Enter, then exit with 0.
if command -v script >/dev/null 2>&1; then
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/iso" "$tmp/vm"
  set +e
  out="$(printf '1\n1\n\n0\n' | ISO_DIR="$tmp/iso" VM_DIR="$tmp/vm" script -qec "bash '$ROOT_DIR/scripts/boot-menu.sh'" /dev/null 2>&1)"
  rc=$?
  set -e
  if (( rc == 0 )); then
    pass "boot-menu survives a failed child action"
  else
    fail "boot-menu exited $rc after a failed child action"
  fi
  if [[ "$out" == *"Chưa có ISO"* ]]; then
    pass "boot-menu shows the child error and continues"
  else
    fail "boot-menu did not show the child error: $out"
  fi
  rm -rf "$tmp"
else
  printf 'SKIP boot-menu PTY test (script not installed)\n'
fi

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll boot-menu tests passed\n'
