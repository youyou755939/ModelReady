$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

foreach ($relativePath in @('modelready.ps1', 'src\ModelReady.psm1', 'tests\smoke.ps1')) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root $relativePath), [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) { throw "PowerShell 语法错误（$relativePath）：$($parseErrors.Message -join '; ')" }
}

$manifest = Get-Content -LiteralPath (Join-Path $root 'config\profiles.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw 'profiles.json schemaVersion 不正确' }

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

Write-Host 'ModelReady smoke tests passed.' -ForegroundColor Green
