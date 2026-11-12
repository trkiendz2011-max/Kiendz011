# Small Vietnamese menu for the guest VM.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment

if (-not (Test-VipAdmin)) {
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"')
        ) | Out-Null
    } catch {
        Write-Host "Khong the nang quyen: $($_.Exception.Message)"
    }
    exit 0
}

function Read-VipOS {
    Write-Host ''
    Write-Host '  1) Windows 10 Pro'
    Write-Host '  2) Windows 11 Pro'
    Write-Host '  3) Windows 11 Enterprise LTSC 2024'
    Write-Host '  4) Windows Server 2022'
    $choice = Read-Host 'Chon Windows (1-4)'
    switch ($choice) {
        '1' { return 'win10' }
        '2' { return 'win11' }
        '3' { return 'win11-ltsc' }
        '4' { return 'server2022' }
        default { return 'win11' }
    }
}

while ($true) {
    Clear-Host
    Write-Host '=========================================='
    Write-Host '        WINVM CODESPACES VIP TOOLS'
    Write-Host '=========================================='
    Write-Host '  1) Chay lai toan bo setup'
    Write-Host '  2) Cai tieng Viet'
    Write-Host '  3) Cai Mesa GPU (OpenGL + Vulkan lavapipe)'
    Write-Host '  4) Cai Vulkan runtime'
    Write-Host '  5) Cai DXVK / deploy vao game'
    Write-Host '  6) Toi uu chong lag'
    Write-Host '  7) Khoi phuc cau hinh mac dinh'
    Write-Host '  8) Mo thu muc C:\VIP'
    Write-Host '  9) Xem log setup'
    Write-Host '  0) Thoat'
    Write-Host ''

    $choice = Read-Host 'Chon'
    try {
        switch ($choice) {
            '1' {
                $os = Read-VipOS
                & (Join-Path $PSScriptRoot 'setup-win.ps1') -OS $os
            }
            '2' { & (Join-Path $PSScriptRoot 'install-vi.ps1') }
            '3' { & (Join-Path $PSScriptRoot 'install-mesa.ps1') }
            '4' { & (Join-Path $PSScriptRoot 'install-vulkan.ps1') }
            '5' {
                $game = Read-Host 'Thu muc game (de trong neu chi muon giai nen DXVK)'
                if ($game) {
                    & (Join-Path $PSScriptRoot 'install-dxvk.ps1') -GameDir $game
                } else {
                    & (Join-Path $PSScriptRoot 'install-dxvk.ps1')
                }
            }
            '6' { & (Join-Path $PSScriptRoot 'optimize.ps1') }
            '7' {
                $confirm = Read-Host 'Khoi phuc toan bo? (y/N)'
                if ($confirm -eq 'y') { & (Join-Path $PSScriptRoot 'restore-defaults.ps1') }
            }
            '8' { Start-Process explorer.exe 'C:\VIP' }
            '9' { Start-Process notepad.exe 'C:\VIP\setup.log' }
            '0' { exit 0 }
            default { Write-Host 'Lua chon khong hop le.' }
        }
    } catch {
        Write-Host "Loi: $($_.Exception.Message)"
        Write-VipLog "vip-tools loi: $($_.Exception.Message)" 'ERROR'
    }

    Write-Host ''
    Read-Host 'Nhan Enter de tiep tuc'
}
