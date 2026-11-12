# Deploy Mesa software OpenGL and the lavapipe Vulkan driver system-wide.
# Uses the mingw build because it contains opengl32.dll + vulkan_lvp.dll.
$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog 'Cai Mesa GPU (OpenGL + lavapipe + anti-lag)...'

$release = $null
try {
    $release = Get-VipGitHubAsset -Repo 'pal1000/mesa-dist-win' -Pattern '^mesa3d-.*-release-mingw\.7z$'
} catch {
    Write-VipLog "Khong thay ban mingw, thu ban msvc: $($_.Exception.Message)" 'WARN'
    $release = Get-VipGitHubAsset -Repo 'pal1000/mesa-dist-win' -Pattern '^mesa3d-.*-release-msvc\.7z$'
}

$archive = Join-Path $Global:VipDownloadDir $release.Name
Invoke-VipDownload -Url $release.Url -Destination $archive | Out-Null

$extract = Join-Path $Global:VipRoot 'mesa'
if (Test-Path -LiteralPath $extract) {
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $extract -Force | Out-Null
Write-VipLog "Giai nen Mesa $($release.Version)..."
Expand-VipArchive -Path $archive -Destination $extract

$source = Join-Path $extract 'x64'
if (-not (Test-Path -LiteralPath (Join-Path $source 'vulkan_lvp.dll'))) {
    $found = Get-ChildItem -Path $extract -Recurse -Filter 'vulkan_lvp.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $source = $found.DirectoryName }
}
if (-not (Test-Path -LiteralPath (Join-Path $source 'vulkan_lvp.dll'))) {
    throw "Goi Mesa khong co vulkan_lvp.dll: $archive"
}

$system32 = Join-Path $env:SystemRoot 'System32'
$backupDir = Join-Path $Global:VipBackupDir 'system32'
if (-not (Test-Path -LiteralPath $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

$files = @(
    'opengl32.dll',
    'libgallium_wgl.dll',
    'libEGL.dll',
    'libGLESv2.dll',
    'dxil.dll',
    'vulkan_lvp.dll',
    'lvp_icd.x86_64.json',
    'libVkLayer_MESA_anti_lag.dll',
    'VkLayer_MESA_anti_lag.json'
)

$manifest = @()
$copied = 0
foreach ($name in $files) {
    $sourceFile = Join-Path $source $name
    if (-not (Test-Path -LiteralPath $sourceFile)) {
        Write-VipLog "Mesa khong co $name - bo qua." 'WARN'
        continue
    }

    $destination = Join-Path $system32 $name
    $existed = Test-Path -LiteralPath $destination
    try {
        Copy-VipSystemFile -Source $sourceFile -Destination $destination -BackupName $name
        $copied++
        $backupPath = ''
        if ($existed) { $backupPath = Join-Path $backupDir $name }
        $manifest += [pscustomobject]@{
            Name    = $name
            Existed = $existed
            Backup  = $backupPath
        }
    } catch {
        Write-VipLog "Khong chep duoc $name`: $($_.Exception.Message)" 'WARN'
    }
}

if ($copied -eq 0) {
    throw 'Khong chep duoc file Mesa nao vao System32.'
}

$manifest | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $Global:VipBackupDir 'mesa-files.json') -Encoding UTF8

# Register lavapipe as a Vulkan ICD.
try {
    $icdKey = 'HKLM:\SOFTWARE\Khronos\Vulkan\Drivers'
    if (-not (Test-Path -LiteralPath $icdKey)) { New-Item -Path $icdKey -Force | Out-Null }
    $icdPath = Join-Path $system32 'lvp_icd.x86_64.json'
    New-ItemProperty -Path $icdKey -Name $icdPath -Value 0 -PropertyType DWord -Force | Out-Null
    Write-VipLog 'Da dang ky lavapipe ICD.' 'OK'
} catch {
    Write-VipLog "Dang ky lavapipe ICD loi: $($_.Exception.Message)" 'WARN'
}

# Register the Mesa anti-lag Vulkan layer and enable it machine-wide.
try {
    $layerKey = 'HKLM:\SOFTWARE\Khronos\Vulkan\ImplicitLayers'
    if (-not (Test-Path -LiteralPath $layerKey)) { New-Item -Path $layerKey -Force | Out-Null }
    $layerPath = Join-Path $system32 'VkLayer_MESA_anti_lag.json'
    New-ItemProperty -Path $layerKey -Name $layerPath -Value 0 -PropertyType DWord -Force | Out-Null
    [Environment]::SetEnvironmentVariable('ENABLE_LAYER_MESA_ANTI_LAG', '1', 'Machine')
    Write-VipLog 'Da bat Mesa anti-lag layer.' 'OK'
} catch {
    Write-VipLog "Bat anti-lag layer loi: $($_.Exception.Message)" 'WARN'
}

$note = @(
    'MESA GPU - WINVM CODESPACES VIP',
    '',
    "Phien ban: $($release.Version)",
    "Thu muc goc: $extract",
    '',
    'Da deploy vao C:\Windows\System32:',
    ($manifest | ForEach-Object { '  - ' + $_.Name }) -join "`r`n",
    '',
    'Go cai dat / khoi phuc: powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\restore-defaults.ps1',
    '',
    'Luu y: day la GPU phan mem. OpenGL/Vulkan chay bang CPU, khong nhanh nhu GPU that.'
)
Set-Content -Path (Join-Path $extract 'README-MESA.txt') -Value $note -Encoding UTF8

Write-VipLog "Mesa $($release.Version) da cai ($copied file)." 'OK'
