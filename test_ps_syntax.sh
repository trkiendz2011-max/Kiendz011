#!/usr/bin/env bash
# Parse every guest PowerShell script and check required entry points.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/guest/scripts"
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

if ! command -v pwsh >/dev/null 2>&1; then
  printf 'SKIP PowerShell tests (pwsh not installed)\n'
  exit 0
fi

required=(
  _common.ps1
  setup-win.ps1
  install-vi.ps1
  install-mesa.ps1
  install-vulkan.ps1
  install-dxvk.ps1
  optimize.ps1
  restore-defaults.ps1
  boot-vip.ps1
  vip-tools.ps1
)

for name in "${required[@]}"; do
  file="$SCRIPT_DIR/$name"
  if [[ ! -f "$file" ]]; then
    fail "missing $name"
    continue
  fi

  if FILE="$file" pwsh -NoProfile -NonInteractive -Command '
      $tokens = $null
      $errors = $null
      [System.Management.Automation.Language.Parser]::ParseFile($env:FILE, [ref]$tokens, [ref]$errors) | Out-Null
      if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Host $_.Message }
        exit 1
      }
    ' >/tmp/vip-ps-parse.log 2>&1; then
    pass "$name parses"
  else
    fail "$name parse error: $(tail -n 2 /tmp/vip-ps-parse.log)"
  fi

  if LC_ALL=C grep -qP '[^\x00-\x7F]' "$file"; then
    fail "$name contains non-ASCII (Windows PowerShell 5.1 encoding risk)"
  else
    pass "$name is ASCII-only"
  fi
done

has "$SCRIPT_DIR/setup-win.ps1" "ValidateSet('win10', 'win11', 'win11-ltsc', 'server2022')" "setup-win validates OS"
has "$SCRIPT_DIR/setup-win.ps1" "setup.log" "setup-win writes setup.log"
for step in install-vi.ps1 install-mesa.ps1 install-vulkan.ps1 install-dxvk.ps1 optimize.ps1 boot-vip.ps1; do
  has "$SCRIPT_DIR/setup-win.ps1" "$step" "setup-win calls $step"
done

has "$SCRIPT_DIR/_common.ps1" "function Write-VipLog" "_common has Write-VipLog"
has "$SCRIPT_DIR/_common.ps1" "function Invoke-VipStep" "_common has Invoke-VipStep"
has "$SCRIPT_DIR/_common.ps1" "function Get-VipGitHubAsset" "_common has Get-VipGitHubAsset"
has "$SCRIPT_DIR/_common.ps1" "function Expand-VipArchive" "_common has Expand-VipArchive"
has "$SCRIPT_DIR/_common.ps1" "function Invoke-VipDownload" "_common has Invoke-VipDownload"
has "$SCRIPT_DIR/_common.ps1" "function Test-VipInternet" "_common has Test-VipInternet"
has "$SCRIPT_DIR/_common.ps1" "function Write-VipNote" "_common has Write-VipNote"
has "$SCRIPT_DIR/_common.ps1" "function Add-VipManualStep" "_common has Add-VipManualStep"
has "$SCRIPT_DIR/_common.ps1" "Retries = 2" "downloads default to 2 retries"
has "$SCRIPT_DIR/_common.ps1" "TimeoutSec = 300" "downloads default to a 5-minute timeout"
has "$SCRIPT_DIR/setup-win.ps1" "Write-VipNote" "setup-win writes a desktop note"
has "$SCRIPT_DIR/setup-win.ps1" "manual-steps.txt" "setup-win includes manual steps"
has "$SCRIPT_DIR/install-vi.ps1" "Add-VipManualStep" "install-vi logs manual fallback steps"
has "$SCRIPT_DIR/install-vi.ps1" "Settings > Time & Language" "install-vi logs the Settings path"

has "$SCRIPT_DIR/install-vi.ps1" "Install-Language" "install-vi uses Install-Language"
has "$SCRIPT_DIR/install-vi.ps1" "Set-WinSystemLocale" "install-vi sets system locale"
has "$SCRIPT_DIR/install-vi.ps1" "Set-WinUserLanguageList" "install-vi sets user language"
has "$SCRIPT_DIR/install-vi.ps1" "SE Asia Standard Time" "install-vi sets Vietnam timezone"
has "$SCRIPT_DIR/install-vi.ps1" "vi-VN" "install-vi targets vi-VN"

has "$SCRIPT_DIR/install-mesa.ps1" "pal1000/mesa-dist-win" "install-mesa uses mesa-dist-win"
has "$SCRIPT_DIR/install-mesa.ps1" "vulkan_lvp.dll" "install-mesa deploys lavapipe"
has "$SCRIPT_DIR/install-mesa.ps1" "lvp_icd" "install-mesa registers lavapipe ICD"
has "$SCRIPT_DIR/install-mesa.ps1" "Khronos\\Vulkan\\Drivers" "install-mesa writes Vulkan registry"

has "$SCRIPT_DIR/install-vulkan.ps1" "vulkan.lunarg.com" "install-vulkan uses LunarG"
has "$SCRIPT_DIR/install-vulkan.ps1" "vulkan-1.dll" "install-vulkan verifies loader"
has "$SCRIPT_DIR/install-vulkan.ps1" "winget" "install-vulkan has winget fallback"

has "$SCRIPT_DIR/install-dxvk.ps1" "doitsujin/dxvk" "install-dxvk uses doitsujin/dxvk"
has "$SCRIPT_DIR/install-dxvk.ps1" "GameDir" "install-dxvk supports -GameDir"
has "$SCRIPT_DIR/install-dxvk.ps1" "d3d11.dll" "install-dxvk deploys d3d11"

has "$SCRIPT_DIR/optimize.ps1" "optimize-backup.json" "optimize writes a backup"
has "$SCRIPT_DIR/optimize.ps1" "DiagTrack" "optimize handles telemetry service"
has "$SCRIPT_DIR/optimize.ps1" "Win32PrioritySeparation" "optimize tunes CPU priority"
has "$SCRIPT_DIR/optimize.ps1" "powercfg" "optimize sets power plan"
has "$SCRIPT_DIR/restore-defaults.ps1" "optimize-backup.json" "restore reads the backup"
has "$SCRIPT_DIR/restore-defaults.ps1" "Remove-ItemProperty" "restore removes added values"
has "$SCRIPT_DIR/boot-vip.ps1" "HiberbootEnabled" "boot-vip enables fast startup"
has "$SCRIPT_DIR/boot-vip.ps1" "bcdedit" "boot-vip sets boot timeout"
has "$SCRIPT_DIR/boot-vip.ps1" "Wallpaper" "boot-vip sets wallpaper"

if (( failures > 0 )); then
  printf '\n%d test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll PowerShell tests passed\n'
