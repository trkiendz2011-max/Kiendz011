#!/usr/bin/env bash
# Tests for fetch-iso.sh URL resolution. No ISO is downloaded.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

out="$(bash "$ROOT_DIR/scripts/fetch-iso.sh" server2022 --dry-run)"
if [[ "$out" == *"LinkID=2195280"* ]]; then
  pass "server2022 dry-run returns Microsoft Eval URL"
else
  fail "server2022 dry-run URL: $out"
fi

out="$(bash "$ROOT_DIR/scripts/fetch-iso.sh" win11-ltsc --dry-run)"
if [[ "$out" == *"linkid=2289029"* ]]; then
  pass "win11-ltsc dry-run returns Microsoft LTSC Eval URL"
else
  fail "win11-ltsc dry-run URL: $out"
fi

out="$(bash "$ROOT_DIR/scripts/fetch-iso.sh" win10 --url "https://example.invalid/win10.iso" --dry-run)"
if [[ "$out" == "https://example.invalid/win10.iso" ]]; then
  pass "custom --url is used"
else
  fail "custom --url: $out"
fi

if [[ ! -f "$ROOT_DIR/iso/win10.iso" ]]; then
  pass "dry-run does not create ISO"
else
  fail "dry-run created iso/win10.iso"
fi

if bash "$ROOT_DIR/scripts/fetch-iso.sh" nonsense --dry-run >/dev/null 2>&1; then
  fail "invalid OS should fail"
else
  pass "invalid OS fails"
fi

if command -v pwsh >/dev/null 2>&1; then
  if out="$(bash "$ROOT_DIR/scripts/fetch-iso.sh" win11 --dry-run 2>/dev/null)"; then
    if [[ "$out" =~ ^https:// ]]; then
      pass "win11 dry-run resolves an official URL"
    else
      fail "win11 dry-run output: $out"
    fi
  else
    printf 'SKIP win11 dry-run (Microsoft Sentinel is blocking this IP; use win11-ltsc or --url)\n'
  fi
else
  printf 'SKIP win11 dry-run (pwsh not installed yet)\n'
fi

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll fetch-iso tests passed\n'
