# Download DXVK and optionally deploy it into a game directory.
[CmdletBinding()]
param(
    [string]$GameDir = '',
    [ValidateSet('x64', 'x86')][string]$Arch = 'x64'
)

$ErrorActionPreference = 'Continue'

$commonPath = Join-Path $PSScriptRoot '_common.ps1'
if (-not (Test-Path -LiteralPath $commonPath)) { $commonPath = 'C:\VIP\scripts\_common.ps1' }
. $commonPath

Initialize-VipEnvironment
Write-VipLog "Cai DXVK (arch=$Arch)..."

$release = Get-VipGitHubAsset -Repo 'doitsujin/dxvk' -Pattern '^dxvk-.*\.tar\.gz$'
$archive = Join-Path $Global:VipDownloadDir $release.Name
Invoke-VipDownload -Url $release.Url -Destination $archive | Out-Null

$extract = Join-Path $Global:VipRoot 'DXVK'
if (Test-Path -LiteralPath $extract) {
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $extract -Force | Out-Null
Write-VipLog "Giai nen DXVK $($release.Version)..."
Expand-VipArchive -Path $archive -Destination $extract

$source = Get-ChildItem -Path $extract -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq $Arch -and (Test-Path -LiteralPath (Join-Path $_.FullName 'd3d11.dll')) } |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $source) {
    throw "Khong tim thay thu muc $Arch/d3d11.dll trong goi DXVK."
}

$dlls = @('d3d8.dll', 'd3d9.dll', 'd3d10core.dll', 'd3d11.dll', 'dxgi.dll')

if ($GameDir) {
    if (-not (Test-Path -LiteralPath $GameDir)) {
        throw "GameDir khong ton tai: $GameDir"
    }

    $gameName = Split-Path -Leaf $GameDir
    $backup = Join-Path (Join-Path $Global:VipBackupDir 'dxvk') $gameName
    if (-not (Test-Path -LiteralPath $backup)) {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
    }

    $deployed = 0
    foreach ($dll in $dlls) {
        $sourceFile = Join-Path $source $dll
        if (-not (Test-Path -LiteralPath $sourceFile)) { continue }
        $target = Join-Path $GameDir $dll
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination (Join-Path $backup $dll) -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -LiteralPath $sourceFile -Destination $target -Force -ErrorAction Stop
        $deployed++
    }
    Write-VipLog "Da deploy $deployed DLL DXVK vao $GameDir" 'OK'
    Write-VipLog "Ban sao DLL goc: $backup" 'INFO'
} else {
    Write-VipLog "DXVK da giai nen tai $extract" 'OK'
    Write-VipLog "De deploy vao game: powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-dxvk.ps1 -GameDir 'C:\duong\dan\game'" 'INFO'
}

$note = @(
    'DXVK - WINVM CODESPACES VIP',
    '',
    "Phien ban: $($release.Version)",
    "Thu muc: $extract",
    "Ban: $Arch",
    '',
    'Cach deploy vao game:',
    "  powershell -ExecutionPolicy Bypass -File C:\VIP\scripts\install-dxvk.ps1 -GameDir 'C:\Games\TenGame'",
    '',
    'DXVK chuyen Direct3D 9/10/11 sang Vulkan. Can Vulkan runtime va Mesa lavapipe.',
    'Hieu nang phu thuoc CPU vi day la GPU phan mem.'
)
Set-Content -Path (Join-Path $extract 'README-DXVK.txt') -Value $note -Encoding UTF8
