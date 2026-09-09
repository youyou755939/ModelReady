[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config\profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$manifest.productVersion
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputFull -Force | Out-Null

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$stage = Join-Path $temporaryRoot ("ModelReady-package-" + [guid]::NewGuid().ToString('N'))
$stageFull = [IO.Path]::GetFullPath($stage)
$expectedPrefix = $temporaryRoot + [IO.Path]::DirectorySeparatorChar
if (-not $stageFull.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw '临时打包目录不在系统临时目录内。'
}

$packageRoot = Join-Path $stageFull "ModelReady-$version"
$zipPath = Join-Path $outputFull "ModelReady-$version-windows-x64.zip"
$checksumPath = "$zipPath.sha256"

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    $files = @(
        'modelready.ps1', 'ModelReady.cmd', 'Install-ModelReady.cmd',
        'Doctor-ModelReady.cmd', 'README.md', 'CHANGELOG.md', 'SECURITY.md', 'LICENSE'
    )
    foreach ($file in $files) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $packageRoot
    }
    $runtimeFiles = @(
        'config\profiles.json',
        'scripts\verify_environment.py',
        'src\ModelReady.psm1'
    )
    foreach ($relativePath in $runtimeFiles) {
        $destinationDirectory = Join-Path $packageRoot (Split-Path -Parent $relativePath)
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination $destinationDirectory
    }
    Compress-Archive -Path $packageRoot -DestinationPath $zipPath -CompressionLevel Optimal -Force
    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $checksumPath -Value "$hash  $(Split-Path -Leaf $zipPath)" -Encoding ASCII
} finally {
    if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
}

Write-Host "发行包：$zipPath" -ForegroundColor Green
Write-Host "校验值：$checksumPath"
