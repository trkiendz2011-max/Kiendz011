# Install Vietnamese language pack and locale/timezone settings.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog 'Cai dat tieng Viet (vi-VN)...'

$languageInstalled = $false

try {
    if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
        Install-Language -Language 'vi-VN' -CopyToSettings -ErrorAction Stop
        $languageInstalled = $true
        Write-VipLog 'Da cai language pack vi-VN bang Install-Language.' 'OK'
    }
} catch {
    Write-VipLog "Install-Language loi: $($_.Exception.Message)" 'WARN'
}

if (-not $languageInstalled) {
    try {
        $capability = Get-WindowsCapability -Online -Name 'Language.Basic~~~vi-VN~0.0.1.0' -ErrorAction Stop
        if ($capability.State -ne 'Installed') {
            Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop | Out-Null
        }
        $languageInstalled = $true
        Write-VipLog 'Da cai language pack vi-VN bang DISM.' 'OK'
    } catch {
        Write-VipLog "DISM language pack loi: $($_.Exception.Message)" 'WARN'
    }
}

# Locale settings work even when the optional language pack is unavailable.
try { Set-WinSystemLocale -SystemLocale 'vi-VN' -ErrorAction Stop } catch {
    Write-VipLog "Set-WinSystemLocale loi: $($_.Exception.Message)" 'WARN'
}
try { Set-WinUILanguageOverride -Language 'vi-VN' -ErrorAction Stop } catch {
    Write-VipLog "Set-WinUILanguageOverride loi: $($_.Exception.Message)" 'WARN'
}
try { Set-Culture -CultureInfo 'vi-VN' -ErrorAction Stop } catch {
    Write-VipLog "Set-Culture loi: $($_.Exception.Message)" 'WARN'
}
try { Set-WinUserLanguageList -LanguageList 'vi-VN' -Force -ErrorAction Stop } catch {
    Write-VipLog "Set-WinUserLanguageList loi: $($_.Exception.Message)" 'WARN'
}
try { Set-WinHomeLocation -GeoId 239 -ErrorAction Stop } catch {
    Write-VipLog "Set-WinHomeLocation loi: $($_.Exception.Message)" 'WARN'
}

try {
    Set-TimeZone -Id 'SE Asia Standard Time' -ErrorAction Stop
} catch {
    & tzutil.exe /s 'SE Asia Standard Time' | Out-Null
}

# Registry fallbacks for system and user locale.
try {
    Set-VipRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'Default' -Value '042a' -Type String
    Set-VipRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language' -Name 'InstallLanguage' -Value '042a' -Type String
    Set-VipRegistryValue -Path 'HKCU:\Control Panel\International' -Name 'LocaleName' -Value 'vi-VN' -Type String
    Set-VipRegistryValue -Path 'HKCU:\Control Panel\International' -Name 'sShortDate' -Value 'dd/MM/yyyy' -Type String
    Set-VipRegistryValue -Path 'HKCU:\Control Panel\International' -Name 'sLongDate' -Value 'dd MMMM yyyy' -Type String
} catch {
    Write-VipLog "Registry locale loi: $($_.Exception.Message)" 'WARN'
}

if ($languageInstalled) {
    Write-VipLog 'Tieng Viet da cai. Dang xuat/dang nhap lai de giao dien hien thi tieng Viet.' 'OK'
} else {
    Write-VipLog 'Chua cai duoc language pack (co the do mang). Da dat locale/timezone.' 'WARN'
    Add-VipManualStep 'Mo Settings > Time & Language > Language & region > Add a language > Tieng Viet.'
    Add-VipManualStep 'Dang xuat va dang nhap lai de giao dien doi sang tieng Viet.'
    Add-VipManualStep 'Chay lai khi co internet: powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-vi.ps1'
}
