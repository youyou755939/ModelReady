[CmdletBinding()]
param(
    [ValidateSet('doctor', 'install', 'repair', 'verify', 'launch', 'uninstall', 'profiles', 'version')]
    [string]$Command = 'doctor',

    [ValidateSet('base', 'optimization', 'ml', 'paper', 'full')]
    [string]$Profile = 'base',

    [ValidateSet('official', 'china')]
    [string]$Source = 'official',

    [string]$EnvironmentRoot = (Join-Path $env:LOCALAPPDATA 'ModelReady\envs'),

    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoReport
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\ModelReady.psm1') -Force

$options = @{
    ProjectRoot    = $projectRoot
    Profile        = $Profile
    Source         = $Source
    EnvironmentRoot = $EnvironmentRoot
    DryRun         = $DryRun.IsPresent
    Yes            = $Yes.IsPresent
    NoReport       = $NoReport.IsPresent
}

try {
    switch ($Command) {
        'doctor'  { Invoke-ModelReadyDoctor @options }
        'install' { Invoke-ModelReadyInstall @options }
        'repair'  { Invoke-ModelReadyInstall @options }
        'verify'  { Invoke-ModelReadyVerify @options }
        'launch'  { Start-ModelReadyJupyter @options }
        'uninstall' { Uninstall-ModelReadyEnvironment @options }
        'profiles' { Show-ModelReadyProfiles -ProjectRoot $projectRoot }
        'version' { Show-ModelReadyVersion -ProjectRoot $projectRoot }
    }
} catch {
    Write-Host "ModelReady 失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# A failed native probe (for example an empty Python launcher) must not leak its
# exit code after a successful doctor or dry-run command.
$global:LASTEXITCODE = 0
