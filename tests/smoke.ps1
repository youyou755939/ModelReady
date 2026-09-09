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
if ($manifest.uvInstallerSha256Linux -notmatch '^[a-f0-9]{64}$') { throw 'uvInstallerSha256Linux 格式不正确' }

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

$previousStateRoot = $env:MODELREADY_STATE_ROOT
$rollbackRoot = Join-Path $root 'reports\smoke-rollback'
$rollbackState = Join-Path $rollbackRoot 'state'
$rollbackTarget = Join-Path $rollbackRoot 'payload\environment'
try {
    $env:MODELREADY_STATE_ROOT = $rollbackState
    New-Item -ItemType Directory -Path $rollbackTarget -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $rollbackTarget 'marker.txt') -Value 'temporary rollback fixture' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path (Split-Path -Parent $rollbackTarget) 'user-file.txt') -Value 'must survive rollback' -Encoding ASCII
    New-Item -ItemType Directory -Path $rollbackState -Force | Out-Null
    $journal = [ordered]@{
        schemaVersion = 1
        productVersion = '0.4.0'
        createdAt = (Get-Date).ToString('o')
        modelReadyRoot = (Join-Path $env:LOCALAPPDATA 'ModelReady')
        modelReadyRootCreated = $false
        operations = @(
            [ordered]@{
                kind = 'empty-directory'; target = (Join-Path $rollbackRoot 'payload'); manager = ''
                boundary = $rollbackRoot; details = ''; registeredAt = (Get-Date).ToString('o')
            },
            [ordered]@{
                kind = 'environment'; target = $rollbackTarget; manager = ''
                boundary = (Join-Path $rollbackRoot 'payload'); details = ''; registeredAt = (Get-Date).ToString('o')
            }
        )
    }
    $journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rollbackState 'rollback-journal.json') -Encoding UTF8
    & (Join-Path $root 'modelready.ps1') rollback -DryRun -Yes -NoReport
    if (-not (Test-Path -LiteralPath $rollbackTarget)) { throw 'rollback -DryRun 不应删除测试目标' }
    & (Join-Path $root 'modelready.ps1') rollback -Yes -NoReport
    if (Test-Path -LiteralPath $rollbackTarget) { throw 'rollback 未删除日志内的测试目标' }
    if (-not (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $rollbackTarget) 'user-file.txt'))) { throw 'rollback 不应删除用户后来加入的文件' }
    if (Test-Path -LiteralPath (Join-Path $rollbackState 'rollback-journal.json')) { throw '成功回滚后应删除日志' }

    New-Item -ItemType Directory -Path $rollbackState -Force | Out-Null
    $unsafeJournal = [ordered]@{
        schemaVersion = 1; productVersion = '0.4.0'; createdAt = (Get-Date).ToString('o')
        modelReadyRoot = (Join-Path $env:LOCALAPPDATA 'ModelReady'); modelReadyRootCreated = $false
        operations = @([ordered]@{
            kind = 'directory'; target = $driveRoot; manager = ''; boundary = $driveRoot
            details = ''; registeredAt = (Get-Date).ToString('o')
        })
    }
    $unsafeJournal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $rollbackState 'rollback-journal.json') -Encoding UTF8
    & pwsh -NoProfile -File (Join-Path $root 'modelready.ps1') rollback -Yes -NoReport
    if ($LASTEXITCODE -eq 0) { throw 'rollback 必须拒绝根目录目标' }
    if (-not (Test-Path -LiteralPath (Join-Path $rollbackState 'rollback-journal.json'))) { throw '危险回滚被拒绝后必须保留日志' }
} finally {
    if ($null -eq $previousStateRoot) { Remove-Item Env:MODELREADY_STATE_ROOT -ErrorAction SilentlyContinue }
    else { $env:MODELREADY_STATE_ROOT = $previousStateRoot }
    if (Test-Path -LiteralPath $rollbackRoot) { Remove-Item -LiteralPath $rollbackRoot -Recurse -Force }
}

Write-Host 'ModelReady smoke tests passed.' -ForegroundColor Green
$global:LASTEXITCODE = 0
