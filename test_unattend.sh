#!/usr/bin/env bash
# Validate autounattend files and the tools ISO layout.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; failures=$((failures + 1)); }

has() {
  local file="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" "$file"; then
    pass "$label"
  else
    fail "$label (missing: $needle)"
  fi
}

hasnt() {
  local file="$1" needle="$2" label="$3"
  if grep -qF -- "$needle" "$file"; then
    fail "$label (unexpected: $needle)"
  else
    pass "$label"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { fail "missing command: $1"; return 1; }
}

require_cmd xmllint

check_os() {
  local os="$1" index="$2" tpm="$3" key="$4"
  local file="$ROOT_DIR/guest/autounattend/$os.xml"

  if [[ -f "$file" ]]; then
    pass "$os autounattend exists"
  else
    fail "$os autounattend missing: $file"
    return
  fi

  if xmllint --noout "$file" 2>/dev/null; then
    pass "$os XML is well-formed"
  else
    fail "$os XML is not well-formed"
  fi

  has "$file" "<Value>$index</Value>" "$os edition index $index"
  has "$file" "vi-VN" "$os Vietnamese locale"
  has "$file" "Vip@2026" "$os default password"
  has "$file" "<Name>VIP</Name>" "$os local account VIP"
  has "$file" "<Group>Administrators</Group>" "$os admin group"
  has "$file" "<AutoLogon>" "$os auto logon"
  has "$file" "FirstLogonCommands" "$os first logon hook"
  has "$file" "setup-win.ps1 -OS $os" "$os setup script argument"
  has "$file" "SE Asia Standard Time" "$os Vietnam timezone"
  has "$file" "<AcceptEula>true</AcceptEula>" "$os EULA accepted"
  has "$file" "<WillWipeDisk>true</WillWipeDisk>" "$os wipes target disk"
  has "$file" "<Type>EFI</Type>" "$os UEFI partition"

  if [[ "$tpm" == "yes" ]]; then
    has "$file" "BypassTPMCheck" "$os TPM bypass"
    has "$file" "BypassSecureBootCheck" "$os Secure Boot bypass"
  else
    hasnt "$file" "BypassTPMCheck" "$os has no TPM bypass"
  fi

  if [[ "$key" == "yes" ]]; then
    has "$file" "VK7JG-NPHTM-C97JM-9MPGT-3V66T" "$os generic Pro setup key"
  else
    hasnt "$file" "VK7JG-NPHTM-C97JM-9MPGT-3V66T" "$os does not use retail key"
  fi
}

check_os win10 6 no yes
check_os win11 6 yes yes
check_os win11-ltsc 1 yes no
check_os server2022 4 no no

# Build a tools ISO from a temporary guest tree.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/guest/autounattend" "$tmp/guest/scripts"
cp "$ROOT_DIR/guest/autounattend/win11.xml" "$tmp/guest/autounattend/win11.xml"
printf 'Write-Host "dummy setup"\n' > "$tmp/guest/scripts/setup-win.ps1"
printf 'Write-Host "dummy common"\n' > "$tmp/guest/scripts/_common.ps1"

if GUEST_DIR="$tmp/guest" bash "$ROOT_DIR/scripts/build-tools-iso.sh" win11 "$tmp/tools.iso" >/tmp/vip-tools-build.log 2>&1; then
  pass "build-tools-iso exits 0"
else
  fail "build-tools-iso failed: $(tail -n 3 /tmp/vip-tools-build.log)"
fi

if [[ -s "$tmp/tools.iso" ]]; then
  pass "tools ISO is not empty"
else
  fail "tools ISO missing or empty"
fi

listing=""
if command -v isoinfo >/dev/null 2>&1; then
  listing="$(isoinfo -J -f -i "$tmp/tools.iso" 2>/dev/null || true)"
elif command -v bsdtar >/dev/null 2>&1; then
  listing="$(bsdtar -tf "$tmp/tools.iso" 2>/dev/null || true)"
fi

if [[ -n "$listing" ]]; then
  if [[ "$listing" == *"autounattend.xml"* ]]; then
    pass "tools ISO contains autounattend.xml"
  else
    fail "tools ISO is missing autounattend.xml"
  fi
  if [[ "$listing" == *"setup-win.ps1"* ]]; then
    pass "tools ISO contains setup-win.ps1"
  else
    fail "tools ISO is missing setup-win.ps1"
  fi
  if [[ "$listing" == *"OEM"*"Setup/Scripts"* ]]; then
    pass "tools ISO contains the OEM Setup Scripts path"
  else
    fail "tools ISO is missing the OEM Setup Scripts path"
  fi
else
  printf 'SKIP tools ISO listing (isoinfo/bsdtar not available)\n'
fi

# Missing XML must fail before writing the output.
if GUEST_DIR="$tmp/guest" bash "$ROOT_DIR/scripts/build-tools-iso.sh" win10 "$tmp/nope.iso" >/dev/null 2>&1; then
  fail "build-tools-iso accepts a missing XML"
else
  pass "build-tools-iso rejects a missing XML"
fi
if [[ ! -e "$tmp/nope.iso" ]]; then
  pass "failed tools ISO build writes no output"
else
  fail "failed tools ISO build wrote output"
fi

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll unattend tests passed\n'
