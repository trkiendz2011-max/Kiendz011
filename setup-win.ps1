# WinVM Codespaces VIP - first logon orchestrator.
# Runs every guest step, logs to C:\VIP\setup.log and never blocks OOBE.
[CmdletBinding()]
param(
    [ValidateSet('win10', 'win11', 'win11-ltsc', 'server2022')]
    [string]$OS = 'win11'
)

$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) {
    $commonPath = 'C:\VIP\scripts\_common.ps1'
}
if (-not (Test-Path -LiteralPath $commonPath)) {
    Write-Host 'Khong tim thay _common.ps1 - bo qua setup.'
    exit 0
}
. $commonPath

Initialize-VipEnvironment
Write-VipLog "===== WinVM Codespaces VIP - bat dau setup (OS=$OS) ====="

# Show a desktop note immediately so the user is never left guessing.
$earlyNote = @(
    'WINVM CODESPACES VIP - DANG CAI DAT',
    '',
    'Vui long cho, khong tat may.',
    'Lan dau co the mat 10-30 phut vi Codespaces khong co KVM.',
    '',
    'Tai khoan: VIP',
    'Mat khau : Vip@2026',
    'Doi mat khau ngay sau khi vao Windows: net user VIP "MatKhauMoi"',
    '',
    'Log: C:\VIP\setup.log'
)
Write-VipNote -Lines $earlyNote

if (-not (Test-VipAdmin)) {
    Write-VipLog 'Khong co quyen Administrator. Thu mo lai voi UAC...' 'WARN'
    try {
        $arguments = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"' + $PSCommandPath + '"'),
            '-OS', $OS
        )
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments | Out-Null
    } catch {
        Write-VipLog "Khong the tu nang quyen: $($_.Exception.Message)" 'ERROR'
    }
    exit 0
}

# Keep a writable copy so the desktop shortcut keeps working after Setup cleanup.
$vipScripts = Join-Path $Global:VipRoot 'scripts'
if (-not (Test-Path -LiteralPath $vipScripts)) {
    New-Item -ItemType Directory -Path $vipScripts -Force | Out-Null
}
Copy-Item -Path (Join-Path $PSScriptRoot '*.ps1') -Destination $vipScripts -Force -ErrorAction SilentlyContinue
Copy-Item -Path (Join-Path $PSScriptRoot 'README.txt') -Destination $vipScripts -Force -ErrorAction SilentlyContinue

$steps = @(
    @{ Name = 'Tieng Viet'; File = 'install-vi.ps1' },
    @{ Name = 'Mesa GPU'; File = 'install-mesa.ps1' },
    @{ Name = 'Vulkan runtime'; File = 'install-vulkan.ps1' },
    @{ Name = 'DXVK'; File = 'install-dxvk.ps1' },
    @{ Name = 'Toi uu chong lag'; File = 'optimize.ps1' },
    @{ Name = 'Boot VIP'; File = 'boot-vip.ps1' }
)

$failed = @()
foreach ($step in $steps) {
    $path = Join-Path $PSScriptRoot $step.File
    if (-not (Test-Path -LiteralPath $path)) {
        $path = Join-Path $vipScripts $step.File
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Write-VipLog "Thieu script: $($step.File)" 'ERROR'
        $failed += $step.Name
        continue
    }

    $ok = Invoke-VipStep -Name $step.Name -Action { & $path }
    if (-not $ok) {
        $failed += $step.Name
    }
}

if ($failed.Count -eq 0) {
    Write-VipLog 'Tat ca buoc da hoan tat.' 'OK'
} else {
    Write-VipLog ('Cac buoc loi: ' + ($failed -join ', ') + '. Xem log va chay lai sau.') 'WARN'
}

$manual = @()
$manualPath = Join-Path $Global:VipRoot 'manual-steps.txt'
if (Test-Path -LiteralPath $manualPath) {
    $manual = @(Get-Content -LiteralPath $manualPath -ErrorAction SilentlyContinue)
}

$note = @(
    'WINVM CODESPACES VIP',
    '',
    'Tai khoan: VIP',
    'Mat khau : Vip@2026',
    '',
    'Doi mat khau ngay: net user VIP "MatKhauMoi"',
    '',
    'Log setup: C:\VIP\setup.log',
    'Chay lai setup: powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\setup-win.ps1 -OS ' + $OS,
    'Menu tien ich: C:\VIP\scripts\vip-tools.ps1',
    '',
    'Luu y: GitHub Codespaces khong co KVM nen Windows chay bang TCG,',
    'toc do cham hon may that. Mesa/Vulkan/DXVK deu la gia lap phan mem.'
)

if ($failed.Count -gt 0) {
    $note += ''
    $note += ('Cac buoc loi: ' + ($failed -join ', '))
    $note += 'Xem C:\VIP\setup.log de biet chi tiet.'
}
if ($manual.Count -gt 0) {
    $note += ''
    $note += 'VIEC CAN LAM TAY:'
    $note += $manual
}
Write-VipNote -Lines $note

try {
    New-VipShortcut -Name 'VIP Tools' -TargetPath 'powershell.exe' `
        -Arguments '-NoProfile -ExecutionPolicy Bypass -File C:\VIP\scripts\vip-tools.ps1' `
        -WorkingDirectory 'C:\VIP'
} catch {
    Write-VipLog "Khong tao duoc shortcut VIP Tools: $($_.Exception.Message)" 'WARN'
}

Write-VipLog '===== Ket thuc setup =====' 'OK'
exit 0
