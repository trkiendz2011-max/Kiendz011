# Apply reversible anti-lag / responsiveness tweaks and save a JSON backup.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog 'Ap dung toi uu chong lag...'

$backupPath = Join-Path $Global:VipBackupDir 'optimize-backup.json'
$recording = -not (Test-Path -LiteralPath $backupPath)
if ($recording) {
    Write-VipLog 'Chua co backup - se ghi lai gia tri goc.'
} else {
    Write-VipLog 'Da co backup - ap dung lai ma khong ghi de gia tri goc.' 'INFO'
}

$script:regChanges = @()
$script:svcChanges = @()
$script:powerPlan = $null

function Save-RegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [string]$Type = 'DWord'
    )

    if ($script:recording) {
        $old = Get-VipRegistryValue -Path $Path -Name $Name
        $script:regChanges += [pscustomobject]@{
            Path    = $Path
            Name    = $Name
            Existed = $old.Existed
            Value   = $old.Value
            Kind    = $old.Kind
        }
    }
    Set-VipRegistryValue -Path $Path -Name $Name -Value $Value -Type $Type
}

function Disable-ServiceSafely {
    param([Parameter(Mandatory = $true)][string]$Name)

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        if ($script:recording) {
            $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
            $startType = 'Manual'
            if ($cim) {
                switch ($cim.StartMode) {
                    'Auto' { $startType = 'Automatic' }
                    'Manual' { $startType = 'Manual' }
                    'Disabled' { $startType = 'Disabled' }
                }
            }
            $script:svcChanges += [pscustomobject]@{
                Name      = $Name
                StartType = $startType
                Status    = [string]$service.Status
            }
        }
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        Write-VipLog "Da tat service $Name"
    } catch {
        Write-VipLog "Khong tat duoc service $Name`: $($_.Exception.Message)" 'WARN'
    }
}

# High performance power plan.
try {
    $current = (& powercfg.exe /getactivescheme) -join ' '
    if ($script:recording -and ($current -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')) {
        $script:powerPlan = $Matches[1]
    }
    & powercfg.exe /setactive SCHEME_MIN | Out-Null
    Write-VipLog 'Da bat power plan High Performance.' 'OK'
} catch {
    Write-VipLog "Power plan loi: $($_.Exception.Message)" 'WARN'
}

# Desktop responsiveness.
Save-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 -Type DWord
Save-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type String
Save-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseHoverTime' -Value '0' -Type String
Save-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAnimations' -Value 0 -Type DWord
Save-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value 0 -Type DWord
Save-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type String

# Multimedia scheduling and network throttling.
Save-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value -1 -Type DWord
Save-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 10 -Type DWord
Save-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38 -Type DWord

$gamesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
Save-RegValue -Path $gamesKey -Name 'GPU Priority' -Value 8 -Type DWord
Save-RegValue -Path $gamesKey -Name 'Priority' -Value 6 -Type DWord
Save-RegValue -Path $gamesKey -Name 'Scheduling Category' -Value 'High' -Type String
Save-RegValue -Path $gamesKey -Name 'SFIO Priority' -Value 'High' -Type String

# Telemetry policy.
Save-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0 -Type DWord
Save-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0 -Type DWord

# Services that waste CPU/disk on a small VM.
Disable-ServiceSafely -Name 'DiagTrack'
Disable-ServiceSafely -Name 'dmwappushservice'
Disable-ServiceSafely -Name 'SysMain'

if ($recording) {
    $backup = [ordered]@{
        created  = (Get-Date).ToString('s')
        powerPlan = $script:powerPlan
        registry = $script:regChanges
        services = $script:svcChanges
    }
    $backup | ConvertTo-Json -Depth 6 | Set-Content -Path $backupPath -Encoding UTF8
    Write-VipLog "Da luu backup: $backupPath" 'OK'
}

Write-VipLog 'Toi uu xong. Khoi phuc: restore-defaults.ps1' 'OK'
