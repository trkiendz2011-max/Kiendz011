# Install the official Vulkan loader/runtime from LunarG.
# Uses the standalone VulkanRT installer (small) instead of the full SDK.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog 'Cai Vulkan runtime (LunarG)...'

if (-not (Test-VipInternet)) {
    throw 'Khong co internet. Bo qua cai Vulkan runtime.'
}

function Test-VipUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400)
    } catch {
        return $false
    }
}

# Discover the current SDK version, then build runtime-installer candidates.
$sdkVersion = ''
try {
    $latest = Invoke-RestMethod -Uri 'https://vulkan.lunarg.com/sdk_latest/versions.json' -TimeoutSec 60 -ErrorAction Stop
    if ($latest.windows) { $sdkVersion = [string]$latest.windows }
} catch {
    Write-VipLog "Khong lay duoc phien ban moi: $($_.Exception.Message)" 'WARN'
}

$candidates = @()
if ($sdkVersion) {
    $candidates += $sdkVersion
    $parts = $sdkVersion.Split('.')
    if ($parts.Count -ge 3) {
        $candidates += (($parts[0..2] -join '.') + '.0')
    }
}
$candidates += '1.4.363.0'
$candidates = @($candidates | Where-Object { $_ } | Select-Object -Unique)

$runtimeVersion = ''
$runtimeUrl = ''
foreach ($candidate in $candidates) {
    $url = "https://sdk.lunarg.com/sdk/download/$candidate/windows/VulkanRT-X64-$candidate-Installer.exe"
    if (Test-VipUrl -Url $url) {
        $runtimeVersion = $candidate
        $runtimeUrl = $url
        break
    }
    Write-VipLog "Khong thay VulkanRT $candidate, thu ban khac..." 'WARN'
}

$system32 = Join-Path $env:SystemRoot 'System32'
$loader = Join-Path $system32 'vulkan-1.dll'
$installed = $false

if ($runtimeUrl) {
    try {
        $installer = Join-Path $Global:VipDownloadDir "VulkanRT-X64-$runtimeVersion-Installer.exe"
        Invoke-VipDownload -Url $runtimeUrl -Destination $installer | Out-Null
        Write-VipLog "Chay VulkanRT $runtimeVersion installer (silent)..."
        $process = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru -ErrorAction Stop
        Write-VipLog "Installer exit code: $($process.ExitCode)"
        if (Test-Path -LiteralPath $loader) { $installed = $true }
    } catch {
        Write-VipLog "VulkanRT installer loi: $($_.Exception.Message)" 'WARN'
    }
}

if (-not $installed -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-VipLog 'Thu cai Vulkan Runtime bang winget...' 'WARN'
    try {
        & winget install --id KhronosGroup.VulkanRT -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
        if (Test-Path -LiteralPath $loader) { $installed = $true }
    } catch {
        Write-VipLog "winget loi: $($_.Exception.Message)" 'WARN'
    }
}

if (-not $installed) {
    $sdkDll = Get-ChildItem -Path 'C:\VulkanSDK' -Recurse -Filter 'vulkan-1.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sdkDll) {
        Copy-VipSystemFile -Source $sdkDll.FullName -Destination $loader -BackupName 'vulkan-1.dll'
        $installed = $true
    }
}

if (-not $installed) {
    throw 'Khong cai duoc Vulkan loader (vulkan-1.dll).'
}

Write-VipLog "Vulkan runtime da cai: $loader" 'OK'
