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
$tarPath = Join-Path $outputFull "ModelReady-$version-linux-x64.tar.gz"
$tarChecksumPath = "$tarPath.sha256"

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    $files = @(
        'modelready.ps1', 'ModelReady.cmd', 'Install-ModelReady.cmd',
        'Doctor-ModelReady.cmd', 'modelready.sh', 'README.md', 'CHANGELOG.md', 'SECURITY.md', 'LICENSE'
    )
    foreach ($file in $files) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $packageRoot
    }
    $runtimeFiles = @(
        'config\profiles.json',
        'scripts\manifest_query.py',
        'scripts\render_report.py',
        'scripts\verify_environment.py',
        'scripts\verify_system.py',
        'scripts\write_install_state.py',
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
    & tar.exe -czf $tarPath -C $stageFull "ModelReady-$version"
    if ($LASTEXITCODE -ne 0) { throw "无法生成 Linux tar.gz：$tarPath" }
    $tarHash = (Get-FileHash -LiteralPath $tarPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath $tarChecksumPath -Value "$tarHash  $(Split-Path -Leaf $tarPath)" -Encoding ASCII
} finally {
    if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
}

Write-Host "发行包：$zipPath" -ForegroundColor Green
Write-Host "校验值：$checksumPath"
Write-Host "Linux 包：$tarPath" -ForegroundColor Green
Write-Host "校验值：$tarChecksumPath"
