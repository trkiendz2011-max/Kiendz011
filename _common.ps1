# Shared helpers for the WinVM Codespaces VIP guest toolkit.
# Windows PowerShell 5.1 compatible. ASCII only on purpose.

$Global:VipRoot = 'C:\VIP'
$Global:VipLog = Join-Path $Global:VipRoot 'setup.log'
$Global:VipDownloadDir = Join-Path $Global:VipRoot 'downloads'
$Global:VipBackupDir = Join-Path $Global:VipRoot 'backup'
$Global:VipToolsDir = Join-Path $Global:VipRoot 'tools'

function Initialize-VipEnvironment {
    foreach ($dir in @($Global:VipRoot, $Global:VipDownloadDir, $Global:VipBackupDir, $Global:VipToolsDir)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Host "Khong dat duoc TLS 1.2: $($_.Exception.Message)"
    }

    $Global:ProgressPreference = 'SilentlyContinue'
}

function Write-VipLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line

    try {
        if (-not (Test-Path -LiteralPath $Global:VipRoot)) {
            New-Item -ItemType Directory -Path $Global:VipRoot -Force | Out-Null
        }
        Add-Content -LiteralPath $Global:VipLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Logging must never break setup.
    }
}

function Invoke-VipStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    $watch = [Diagnostics.Stopwatch]::StartNew()
    Write-VipLog "=== BAT DAU: $Name ==="
    try {
        & $Action
        $watch.Stop()
        Write-VipLog ("=== XONG: {0} ({1}s) ===" -f $Name, [int]$watch.Elapsed.TotalSeconds) 'OK'
        return $true
    } catch {
        $watch.Stop()
        Write-VipLog ("=== LOI: {0} - {1} ===" -f $Name, $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Test-VipAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-VipInternet {
    param([int]$TimeoutSec = 20)

    if ($null -ne $Global:VipInternet) {
        return [bool]$Global:VipInternet
    }

    try {
        $response = Invoke-WebRequest -Uri 'https://www.microsoft.com/' -Method Head `
            -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        $Global:VipInternet = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        Write-VipLog "Kiem tra internet that bai: $($_.Exception.Message)" 'WARN'
        $Global:VipInternet = $false
    }

    return [bool]$Global:VipInternet
}

function Write-VipNote {
    param([Parameter(Mandatory = $true)][string[]]$Lines)

    $targets = @()
    try {
        $common = [Environment]::GetFolderPath('CommonDesktopDirectory')
        if ($common) { $targets += (Join-Path $common 'WINVM-VIP-DOC-TRUOC.txt') }
    } catch {
    }
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) { $targets += (Join-Path $desktop 'WINVM-VIP-DOC-TRUOC.txt') }
    } catch {
    }
    $targets += (Join-Path $Global:VipRoot 'DOC-TRUOC.txt')
    $targets = @($targets | Select-Object -Unique)

    foreach ($path in $targets) {
        try {
            $parent = Split-Path -Parent $path
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Set-Content -LiteralPath $path -Value $Lines -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-VipLog "Khong ghi duoc note ${path}: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Add-VipManualStep {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-VipLog "CAN LAM TAY: $Message" 'WARN'
    try {
        $path = Join-Path $Global:VipRoot 'manual-steps.txt'
        Add-Content -LiteralPath $path -Value ('- ' + $Message) -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # A note must never break setup.
    }
}

function Invoke-VipDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [int]$Retries = 2,
        [int]$TimeoutSec = 300
    )

    if (-not (Test-VipInternet)) {
        throw "Khong co internet. Bo qua tai: $Url"
    }

    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Write-VipLog "Tai ($attempt/$Retries): $Url"
            Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
            if ((Test-Path -LiteralPath $Destination) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
                return $Destination
            }
            throw 'File tai ve rong.'
        } catch {
            Write-VipLog "Tai loi: $($_.Exception.Message)" 'WARN'
            Start-Sleep -Seconds (2 * $attempt)
        }
    }

    throw "Khong tai duoc: $Url"
}

function Get-VipGitHubAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if (-not (Test-VipInternet)) {
        throw "Khong co internet. Bo qua GitHub API: $Repo"
    }

    $api = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{
        'User-Agent' = 'WinVM-Codespaces-VIP'
        'Accept'     = 'application/vnd.github+json'
    }

    $release = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 60 -ErrorAction Stop
    $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    if (-not $asset) {
        throw "Khong tim thay asset '$Pattern' trong $Repo $($release.tag_name)"
    }

    return [pscustomobject]@{
        Name    = $asset.name
        Url     = $asset.browser_download_url
        Version = $release.tag_name
    }
}

function Expand-VipArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($extension -eq '.zip') {
        Expand-Archive -LiteralPath $Path -DestinationPath $Destination -Force -ErrorAction Stop
        return
    }

    # Windows 10/11/Server 2022 ship bsdtar, which reads tar.gz and 7z.
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path -LiteralPath $tar) {
        try {
            & $tar '-xf' $Path '-C' $Destination 2>$null
            if ($LASTEXITCODE -eq 0) {
                return
            }
        } catch {
            Write-VipLog "tar.exe khong giai nen duoc: $($_.Exception.Message)" 'WARN'
        }
    }

    $sevenZip = Join-Path $Global:VipToolsDir '7zr.exe'
    if (-not (Test-Path -LiteralPath $sevenZip)) {
        Invoke-VipDownload -Url 'https://www.7-zip.org/a/7zr.exe' -Destination $sevenZip | Out-Null
    }

    & $sevenZip 'x' $Path ("-o" + $Destination) '-y' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Giai nen that bai: $Path"
    }
}

function Copy-VipSystemFile {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$BackupName = ''
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Khong thay file nguon: $Source"
    }

    if (Test-Path -LiteralPath $Destination) {
        if (-not $BackupName) {
            $BackupName = Split-Path -Leaf $Destination
        }
        $backup = Join-Path (Join-Path $Global:VipBackupDir 'system32') $BackupName
        if (-not (Test-Path -LiteralPath $backup)) {
            $backupParent = Split-Path -Parent $backup
            if (-not (Test-Path -LiteralPath $backupParent)) {
                New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $Destination -Destination $backup -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    } catch {
        & takeown.exe /f $Destination /a | Out-Null
        & icacls.exe $Destination /grant 'Administrators:F' | Out-Null
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -ErrorAction Stop
    }
}

function Get-VipRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) {
            return [pscustomobject]@{ Existed = $false; Value = $null; Kind = 'String' }
        }
        return [pscustomobject]@{
            Existed = $true
            Value   = $value
            Kind    = $key.GetValueKind($Name).ToString()
        }
    } catch {
        return [pscustomobject]@{ Existed = $false; Value = $null; Kind = 'String' }
    }
}

function Set-VipRegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [string]$Type = 'DWord'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function New-VipShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = ''
    )

    $desktop = [Environment]::GetFolderPath('Desktop')
    $link = Join-Path $desktop ($Name + '.lnk')
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($link)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    $shortcut.Save()
    Write-VipLog "Da tao shortcut: $link"
}
