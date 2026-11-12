# Restore the tweaks recorded by optimize.ps1 and remove Mesa system files.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog 'Khoi phuc cau hinh mac dinh...'

$backupPath = Join-Path $Global:VipBackupDir 'optimize-backup.json'
if (Test-Path -LiteralPath $backupPath) {
    try {
        $data = Get-Content -LiteralPath $backupPath -Raw | ConvertFrom-Json

        if ($data.powerPlan) {
            & powercfg.exe /setactive $data.powerPlan | Out-Null
            Write-VipLog "Da khoi phuc power plan $($data.powerPlan)." 'OK'
        }

        foreach ($item in @($data.registry)) {
            if ($null -eq $item) { continue }
            try {
                if ($item.Existed) {
                    Set-VipRegistryValue -Path $item.Path -Name $item.Name -Value $item.Value -Type $item.Kind
                } else {
                    Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction SilentlyContinue
                }
            } catch {
                Write-VipLog "Khoi phuc registry loi ($($item.Path)\$($item.Name)): $($_.Exception.Message)" 'WARN'
            }
        }

        foreach ($service in @($data.services)) {
            if ($null -eq $service) { continue }
            try {
                Set-Service -Name $service.Name -StartupType $service.StartType -ErrorAction Stop
                if ($service.Status -eq 'Running') {
                    Start-Service -Name $service.Name -ErrorAction SilentlyContinue
                }
                Write-VipLog "Da khoi phuc service $($service.Name) ($($service.StartType))." 'OK'
            } catch {
                Write-VipLog "Khoi phuc service $($service.Name) loi: $($_.Exception.Message)" 'WARN'
            }
        }
    } catch {
        Write-VipLog "Doc backup toi uu loi: $($_.Exception.Message)" 'ERROR'
    }
} else {
    Write-VipLog 'Khong thay optimize-backup.json - bo qua phan toi uu.' 'WARN'
}

# Remove the lavapipe ICD and anti-lag layer registrations.
try {
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers' -Name (Join-Path $env:SystemRoot 'System32\lvp_icd.x86_64.json') -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Khronos\Vulkan\ImplicitLayers' -Name (Join-Path $env:SystemRoot 'System32\VkLayer_MESA_anti_lag.json') -ErrorAction SilentlyContinue
    [Environment]::SetEnvironmentVariable('ENABLE_LAYER_MESA_ANTI_LAG', $null, 'Machine')
} catch {
    Write-VipLog "Go dang ky Vulkan loi: $($_.Exception.Message)" 'WARN'
}

# Restore Mesa files from the manifest, or remove files that did not exist before.
$manifestPath = Join-Path $Global:VipBackupDir 'mesa-files.json'
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        foreach ($item in @($manifest)) {
            if ($null -eq $item) { continue }
            $destination = Join-Path $env:SystemRoot ('System32\' + $item.Name)
            try {
                if ($item.Existed -and $item.Backup -and (Test-Path -LiteralPath $item.Backup)) {
                    Copy-VipSystemFile -Source $item.Backup -Destination $destination -BackupName $item.Name
                } else {
                    Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-VipLog "Khoi phuc $($item.Name) loi: $($_.Exception.Message)" 'WARN'
            }
        }
        Write-VipLog 'Da khoi phuc file Mesa.' 'OK'
    } catch {
        Write-VipLog "Doc manifest Mesa loi: $($_.Exception.Message)" 'WARN'
    }
} else {
    Write-VipLog 'Khong thay mesa-files.json - bo qua phan Mesa.' 'WARN'
}

Write-VipLog 'Khoi phuc xong. Khoi dong lai Windows de ap dung.' 'OK'
