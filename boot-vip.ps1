# Brand the boot experience and generate a VIP wallpaper.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog 'Cau hinh boot VIP...'

# Fast startup needs hibernation enabled.
try {
    & powercfg.exe /hibernate on | Out-Null
    Set-VipRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 1 -Type DWord
    Write-VipLog 'Da bat fast startup.' 'OK'
} catch {
    Write-VipLog "Fast startup loi: $($_.Exception.Message)" 'WARN'
}

# Branded boot menu with a short timeout.
try {
    & bcdedit.exe /timeout 3 | Out-Null
    & bcdedit.exe /set '{bootmgr}' displaybootmenu Yes | Out-Null
    & bcdedit.exe /set '{bootmgr}' description 'WinVM Codespaces VIP Boot' | Out-Null
    & bcdedit.exe /set '{current}' description 'WinVM Codespaces VIP - Windows' | Out-Null
    Write-VipLog 'Da dat boot menu VIP (timeout 3s).' 'OK'
} catch {
    Write-VipLog "BCD loi: $($_.Exception.Message)" 'WARN'
}

# No startup delay for the shell.
try {
    Set-VipRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Name 'StartupDelayInMSec' -Value 0 -Type DWord
    Write-VipLog 'Da tat startup delay.' 'OK'
} catch {
    Write-VipLog "Startup delay loi: $($_.Exception.Message)" 'WARN'
}

# Generate a 1920x1080 VIP wallpaper.
$wallpaper = $null
try {
    Add-Type -AssemblyName System.Drawing
    $wallDir = Join-Path $Global:VipRoot 'wallpaper'
    if (-not (Test-Path -LiteralPath $wallDir)) {
        New-Item -ItemType Directory -Path $wallDir -Force | Out-Null
    }
    $wallpaper = Join-Path $wallDir 'vip-wallpaper.bmp'

    $width = 1920
    $height = 1080
    $bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $rect = New-Object -TypeName System.Drawing.Rectangle -ArgumentList 0, 0, $width, $height
    $colorA = [System.Drawing.Color]::FromArgb(8, 12, 30)
    $colorB = [System.Drawing.Color]::FromArgb(45, 10, 80)
    $gradient = New-Object -TypeName System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList $rect, $colorA, $colorB, 35
    $graphics.FillRectangle($gradient, $rect)

    $accent = New-Object -TypeName System.Drawing.Pen -ArgumentList ([System.Drawing.Color]::FromArgb(0, 210, 255)), 4
    $graphics.DrawLine($accent, 120, 760, 1800, 760)
    $graphics.DrawLine($accent, 120, 780, 620, 780)

    $fontTitle = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 72, ([System.Drawing.FontStyle]::Bold)
    $fontSub = New-Object -TypeName System.Drawing.Font -ArgumentList 'Segoe UI', 30, ([System.Drawing.FontStyle]::Regular)
    $fontSmall = New-Object -TypeName System.Drawing.Font -ArgumentList 'Consolas', 20, ([System.Drawing.FontStyle]::Regular)
    $cyan = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::FromArgb(0, 220, 255))

    $graphics.DrawString('WINVM CODESPACES VIP', $fontTitle, [System.Drawing.Brushes]::White, 120, 390)
    $graphics.DrawString('Windows Virtual Machine - Vietnamese Edition', $fontSub, $cyan, 125, 545)
    $graphics.DrawString('QEMU + Mesa + Vulkan + DXVK', $fontSub, [System.Drawing.Brushes]::White, 125, 610)
    $graphics.DrawString('VIP  |  ' + (Get-Date -Format 'yyyy-MM-dd'), $fontSmall, $cyan, 130, 815)

    $bitmap.Save($wallpaper, [System.Drawing.Imaging.ImageFormat]::Bmp)

    $graphics.Dispose()
    $bitmap.Dispose()
    $gradient.Dispose()
    $accent.Dispose()
    $fontTitle.Dispose()
    $fontSub.Dispose()
    $fontSmall.Dispose()
    $cyan.Dispose()

    Set-VipRegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -Value $wallpaper -Type String
    Set-VipRegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallpaperStyle' -Value '10' -Type String
    Set-VipRegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'TileWallpaper' -Value '0' -Type String

    if (-not ('VipWallpaper' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class VipWallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
'@
    }
    [VipWallpaper]::SystemParametersInfo(20, 0, $wallpaper, 3) | Out-Null
    Write-VipLog "Da tao wallpaper VIP: $wallpaper" 'OK'
} catch {
    Write-VipLog "Wallpaper loi: $($_.Exception.Message)" 'WARN'
}

# OEM branding in Settings > System > About.
try {
    Set-VipRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation' -Name 'Manufacturer' -Value 'WinVM Codespaces VIP' -Type String
    Set-VipRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation' -Name 'Model' -Value 'QEMU Virtual Machine' -Type String
    Set-VipRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation' -Name 'SupportHours' -Value 'GitHub Codespaces' -Type String
} catch {
    Write-VipLog "OEM info loi: $($_.Exception.Message)" 'WARN'
}

try {
    New-VipShortcut -Name 'VIP Tools' -TargetPath 'powershell.exe' `
        -Arguments '-NoProfile -ExecutionPolicy Bypass -File C:\VIP\scripts\vip-tools.ps1' `
        -WorkingDirectory 'C:\VIP'
} catch {
    Write-VipLog "Shortcut loi: $($_.Exception.Message)" 'WARN'
}

Write-VipLog 'Boot VIP xong.' 'OK'
