$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

foreach ($relativePath in @('modelready.ps1', 'build.ps1', 'src\ModelReady.psm1', 'tests\smoke.ps1')) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root $relativePath), [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) { throw "PowerShell 语法错误（$relativePath）：$($parseErrors.Message -join '; ')" }
}

$manifest = Get-Content -LiteralPath (Join-Path $root 'config\profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'profiles.json schemaVersion 不正确' }
if ($manifest.productVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'productVersion 不是语义化版本' }
if ($manifest.uvInstallerSha256 -notmatch '^[a-f0-9]{64}$') { throw 'uvInstallerSha256 格式不正确' }

Import-Module (Join-Path $root 'src\ModelReady.psm1') -Force
$full = Get-ProfileRequirements $manifest 'full'
foreach ($required in @('numpy>=2.0,<3', 'cvxpy>=1.5,<2', 'scikit-learn>=1.5,<2', 'python-docx>=1.1,<2')) {
    if ($required -notin $full.PythonPackages) { throw "full 配置档缺少 $required" }
}
foreach ($required in @('pandoc', 'graphviz', 'latex-or-typst')) {
    if ($required -notin $full.SystemTools) { throw "full 配置档缺少 $required" }
}

& (Join-Path $root 'modelready.ps1') doctor -Profile full -NoReport
if ($LASTEXITCODE -notin @(0, $null)) { throw 'doctor 命令失败' }

& (Join-Path $root 'modelready.ps1') install -Profile full -DryRun -NoReport
if ($LASTEXITCODE -notin @(0, $null)) { throw 'install -DryRun 命令失败' }

$smokeEnvironmentRoot = Join-Path $root 'reports\smoke-envs'
$smokeProfilePath = Join-Path $smokeEnvironmentRoot 'base'
New-Item -ItemType Directory -Path (Join-Path $smokeProfilePath 'Scripts') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $smokeProfilePath 'Scripts\python.exe') -Value 'test placeholder' -Encoding ASCII
& (Join-Path $root 'modelready.ps1') launch -Profile base -EnvironmentRoot $smokeEnvironmentRoot -DryRun -NoReport
& (Join-Path $root 'modelready.ps1') uninstall -Profile base -EnvironmentRoot $smokeEnvironmentRoot -DryRun -Yes -NoReport
if (-not (Test-Path -LiteralPath $smokeProfilePath)) { throw 'uninstall -DryRun 不应删除环境' }
& (Join-Path $root 'modelready.ps1') uninstall -Profile base -EnvironmentRoot $smokeEnvironmentRoot -Yes -NoReport
if (Test-Path -LiteralPath $smokeProfilePath) { throw 'uninstall 未删除指定的测试环境' }

$driveRoot = [IO.Path]::GetPathRoot($root)
& pwsh -NoProfile -File (Join-Path $root 'modelready.ps1') uninstall -Profile base -EnvironmentRoot $driveRoot -DryRun -Yes -NoReport
if ($LASTEXITCODE -eq 0) { throw 'uninstall 必须拒绝过于宽泛的环境根目录' }

Write-Host 'ModelReady smoke tests passed.' -ForegroundColor Green
$global:LASTEXITCODE = 0
