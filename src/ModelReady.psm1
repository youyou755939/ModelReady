Set-StrictMode -Version Latest

function Get-ModelReadyManifest {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'config\profiles.json'
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-ProfileClosure {
    param($Manifest, [string]$Profile)
    $seen = [ordered]@{}
    function Visit([string]$name) {
        if ($seen.Contains($name)) { return }
        $node = $Manifest.profiles.$name
        if ($null -eq $node) { throw "未知配置档：$name" }
        $extendsProperty = $node.PSObject.Properties['extends']
        $parents = if ($extendsProperty) { @($extendsProperty.Value) } else { @() }
        foreach ($parent in $parents) { Visit $parent }
        $seen[$name] = $true
    }
    Visit $Profile
    @($seen.Keys)
}

function Get-ProfileRequirements {
    param($Manifest, [string]$Profile)
    $packages = [System.Collections.Generic.List[string]]::new()
    $tools = [System.Collections.Generic.List[string]]::new()
    foreach ($name in (Get-ProfileClosure $Manifest $Profile)) {
        foreach ($item in @($Manifest.profiles.$name.pythonPackages)) {
            if (-not $packages.Contains($item)) { $packages.Add($item) }
        }
        foreach ($item in @($Manifest.profiles.$name.systemTools)) {
            if (-not $tools.Contains($item)) { $tools.Add($item) }
        }
    }
    [pscustomobject]@{ PythonPackages = $packages.ToArray(); SystemTools = $tools.ToArray() }
}

function Test-CommandAny {
    param([string[]]$Names)
    foreach ($name in $Names) {
        $found = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { return [pscustomobject]@{ Found = $true; Name = $name; Path = $found.Source } }
    }
    [pscustomobject]@{ Found = $false; Name = ($Names -join ' / '); Path = $null }
}

function Get-UsablePython {
    foreach ($name in @('py', 'python')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) { continue }
        & $command.Source -c "import sys; print(sys.executable)" *> $null
        if ($LASTEXITCODE -eq 0) {
            return [pscustomobject]@{ Found = $true; Name = $name; Path = $command.Source }
        }
    }
    [pscustomobject]@{ Found = $false; Name = 'Python'; Path = $null }
}

function New-CheckResult {
    param([string]$Area, [string]$Item, [string]$Status, [string]$Detail, [bool]$Required = $true)
    [pscustomobject]@{
        Area = $Area; Item = $Item; Status = $Status; Required = $Required; Detail = $Detail
    }
}

function Get-EnvironmentPython {
    param([string]$EnvironmentRoot, [string]$Profile)
    $candidate = Join-Path $EnvironmentRoot "$Profile\Scripts\python.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $null
}

function Get-DoctorResults {
    param($Manifest, [string]$Profile, [string]$EnvironmentRoot)
    $requirements = Get-ProfileRequirements $Manifest $Profile
    $results = [System.Collections.Generic.List[object]]::new()

    $isWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $osDetail = "$([Environment]::OSVersion.VersionString); $([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    $results.Add((New-CheckResult '系统' 'Windows' ($(if ($isWindows) { 'PASS' } else { 'MISSING' })) $osDetail $true))
    try {
        $rootPath = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($EnvironmentRoot))
        $driveName = $rootPath.TrimEnd('\').TrimEnd(':')
        $drive = Get-PSDrive -Name $driveName -ErrorAction Stop
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        $requiredGB = [double]$Manifest.profiles.$Profile.estimatedDiskGB
        $diskStatus = if ($freeGB -ge $requiredGB) { 'PASS' } else { 'MISSING' }
        $results.Add((New-CheckResult '系统' '磁盘空间' $diskStatus "可用 ${freeGB} GB；建议至少 ${requiredGB} GB" $true))
    } catch {
        $results.Add((New-CheckResult '系统' '磁盘空间' 'WARN' "无法读取：$($_.Exception.Message)" $true))
    }

    foreach ($name in @('winget', 'uv', 'code')) {
        $check = Test-CommandAny @($name)
        $required = $false
        $status = if ($check.Found) { 'PASS' } else { 'INFO' }
        $results.Add((New-CheckResult '基础工具' $name $status ($(if ($check.Found) { $check.Path } else { '未检测到' })) $required))
    }
    $pythonRuntime = Get-UsablePython
    $results.Add((New-CheckResult '基础工具' 'Python runtime' ($(if ($pythonRuntime.Found) { 'PASS' } else { 'INFO' })) ($(if ($pythonRuntime.Found) { "$($pythonRuntime.Name): $($pythonRuntime.Path)" } else { '未检测到可运行的 Python' })) $false))
    $hasLocalBootstrap = (Test-CommandAny @('winget')).Found -or (Test-CommandAny @('uv')).Found -or $pythonRuntime.Found
    $bootstrapStatus = if ($hasLocalBootstrap) { 'PASS' } else { 'WARN' }
    $bootstrapDetail = if ($hasLocalBootstrap) { 'winget、uv 或 Python 至少一项可用' } else { '安装时将从 astral.sh 下载固定版本的官方 uv 引导脚本（需要网络）' }
    $results.Add((New-CheckResult '基础工具' '安装引擎' $bootstrapStatus $bootstrapDetail $true))

    foreach ($toolName in $requirements.SystemTools) {
        $spec = $Manifest.systemTools.$toolName
        $commandsAnyProperty = $spec.PSObject.Properties['commandsAny']
        $names = if ($commandsAnyProperty) { @($commandsAnyProperty.Value) } else { @($spec.commands) }
        $check = Test-CommandAny $names
        $status = if ($check.Found) { 'PASS' } else { 'MISSING' }
        $detail = if ($check.Found) { "$($check.Name): $($check.Path)" } else { "可通过 winget 安装 $($spec.wingetId)" }
        $results.Add((New-CheckResult '系统工具' $toolName $status $detail ([bool]$spec.required)))
    }

    $environmentPython = Get-EnvironmentPython $EnvironmentRoot $Profile
    $results.Add((New-CheckResult '隔离环境' "$Profile Python" ($(if ($environmentPython) { 'PASS' } else { 'MISSING' })) ($(if ($environmentPython) { $environmentPython } else { '尚未创建' })) $true))

    foreach ($property in $Manifest.optionalCommercialTools.PSObject.Properties) {
        $check = Test-CommandAny @($property.Value)
        $results.Add((New-CheckResult '商业软件（可选）' $property.Name ($(if ($check.Found) { 'PASS' } else { 'INFO' })) ($(if ($check.Found) { $check.Path } else { '未检测到；不会自动安装' })) $false))
    }
    $results.ToArray()
}

function Write-ConsoleReport {
    param([object[]]$Results)
    $colors = @{ PASS = 'Green'; MISSING = 'Red'; WARN = 'Yellow'; INFO = 'DarkGray'; FAIL = 'Red' }
    foreach ($row in $Results) {
        $label = '[{0,-7}]' -f $row.Status
        Write-Host $label -ForegroundColor $colors[$row.Status] -NoNewline
        Write-Host " $($row.Area) / $($row.Item) — $($row.Detail)"
    }
}

function Export-ModelReadyReport {
    param([object[]]$Results, [string]$ProjectRoot, [string]$Profile, [string]$Kind)
    $reportDir = Join-Path $ProjectRoot 'reports'
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $base = Join-Path $reportDir "$Kind-$Profile-$stamp"
    $payload = [ordered]@{
        schemaVersion = 1
        generatedAt = (Get-Date).ToString('o')
        computerName = $env:COMPUTERNAME
        profile = $Profile
        kind = $Kind
        results = $Results
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$base.json" -Encoding UTF8
    $rows = $Results | ForEach-Object {
        $encodedDetail = [System.Net.WebUtility]::HtmlEncode([string]$_.Detail)
        $encodedArea = [System.Net.WebUtility]::HtmlEncode([string]$_.Area)
        $encodedItem = [System.Net.WebUtility]::HtmlEncode([string]$_.Item)
        "<tr><td class='$($_.Status.ToLower())'>$($_.Status)</td><td>$encodedArea</td><td>$encodedItem</td><td>$encodedDetail</td></tr>"
    }
    $passCount = @($Results | Where-Object Status -eq 'PASS').Count
    $problemCount = @($Results | Where-Object Status -in @('MISSING', 'FAIL')).Count
    $noticeCount = @($Results | Where-Object Status -in @('WARN', 'INFO')).Count
    $html = @"
<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>ModelReady 报告</title>
<style>body{font-family:Segoe UI,Microsoft YaHei,sans-serif;max-width:1100px;margin:40px auto;color:#1f2937}.summary{display:flex;gap:12px;margin:24px 0}.card{padding:14px 20px;border-radius:8px;background:#f8fafc}.card b{font-size:22px}table{border-collapse:collapse;width:100%}th,td{padding:10px;border-bottom:1px solid #ddd;text-align:left}.pass{color:#15803d}.missing,.fail{color:#b91c1c}.warn{color:#a16207}.info{color:#64748b}code{background:#f1f5f9;padding:2px 5px}</style></head>
<body><h1>ModelReady $Kind 报告</h1><p>配置档：<code>$Profile</code>　生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')</p>
<div class="summary"><div class="card"><b class="pass">$passCount</b><br>通过</div><div class="card"><b class="fail">$problemCount</b><br>问题</div><div class="card"><b class="info">$noticeCount</b><br>提示</div></div>
<table><thead><tr><th>状态</th><th>区域</th><th>项目</th><th>详情</th></tr></thead><tbody>$($rows -join "`n")</tbody></table></body></html>
"@
    Set-Content -LiteralPath "$base.html" -Value $html -Encoding UTF8
    Write-Host "报告：$base.html"
    [pscustomobject]@{ Json = "$base.json"; Html = "$base.html" }
}

function Invoke-External {
    param([string]$FilePath, [string[]]$Arguments, [bool]$DryRun = $false)
    $display = "$FilePath " + (($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    if ($DryRun) { Write-Host "[DRY-RUN] $display" -ForegroundColor Cyan; return 0 }
    Write-Host "> $display" -ForegroundColor DarkCyan
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "命令失败（退出码 $LASTEXITCODE）：$display" }
    0
}

function Confirm-Install {
    param([bool]$Yes, [bool]$DryRun, [string]$Profile)
    if ($Yes -or $DryRun) { return }
    $answer = Read-Host "将安装配置档 '$Profile' 并可能修改用户环境。输入 YES 继续"
    if ($answer -cne 'YES') { throw '用户取消安装。' }
}

function Resolve-UvCommand {
    param([bool]$DryRun, [string]$Version, [string]$ExpectedSha256)
    function Find-Uv {
        $command = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\uv.exe'),
            (Join-Path $env:USERPROFILE '.local\bin\uv.exe')
        )
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
        $null
    }

    $uvPath = Find-Uv
    if ($uvPath) { return [pscustomobject]@{ File = $uvPath; Prefix = @() } }

    $winget = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($winget) {
        Invoke-External $winget.Source @('install', '--id', 'astral-sh.uv', '--exact', '--accept-source-agreements', '--accept-package-agreements') $DryRun | Out-Null
        if ($DryRun) { return [pscustomobject]@{ File = 'uv'; Prefix = @() } }
        $uvPath = Find-Uv
        if ($uvPath) { return [pscustomobject]@{ File = $uvPath; Prefix = @() } }
        throw 'winget 已完成 uv 安装，但当前进程未找到 uv.exe。请重新打开 PowerShell 后再次运行。'
    }

    $launcher = Get-UsablePython
    if (-not $launcher.Found) {
        $installerUrl = "https://astral.sh/uv/$Version/install.ps1"
        if ($DryRun) {
            Write-Host "[DRY-RUN] 下载并运行官方 uv $Version 安装脚本：$installerUrl" -ForegroundColor Cyan
            return [pscustomobject]@{ File = 'uv'; Prefix = @() }
        }
        $temporaryInstaller = Join-Path ([System.IO.Path]::GetTempPath()) "modelready-uv-$Version-install.ps1"
        Write-Host "> 下载官方 uv $Version 安装脚本" -ForegroundColor DarkCyan
        try {
            Invoke-WebRequest -Uri $installerUrl -OutFile $temporaryInstaller -UseBasicParsing
            $actualSha256 = (Get-FileHash -LiteralPath $temporaryInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
                throw "uv 安装脚本 SHA-256 不匹配；期望 $ExpectedSha256，实际 $actualSha256。已拒绝执行。"
            }
            Write-Host "uv 安装脚本 SHA-256 验证通过。" -ForegroundColor Green
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $temporaryInstaller
            if ($LASTEXITCODE -ne 0) { throw "uv 官方安装程序失败（退出码 $LASTEXITCODE）" }
        } finally {
            if (Test-Path -LiteralPath $temporaryInstaller) { Remove-Item -LiteralPath $temporaryInstaller -Force }
        }
        $uvPath = Find-Uv
        if ($uvPath) { return [pscustomobject]@{ File = $uvPath; Prefix = @() } }
        throw 'uv 安装程序已结束，但未找到 uv.exe。请重新打开 PowerShell 后重试。'
    }
    Invoke-External $launcher.Path @('-m', 'pip', 'install', '--user', 'uv') $DryRun | Out-Null
    if ($DryRun) { return [pscustomobject]@{ File = $launcher.Path; Prefix = @('-m', 'uv') } }
    $uvPath = Find-Uv
    if ($uvPath) { return [pscustomobject]@{ File = $uvPath; Prefix = @() } }
    [pscustomobject]@{ File = $launcher.Path; Prefix = @('-m', 'uv') }
}

function Install-SystemTools {
    param($Manifest, [string[]]$ToolNames, [bool]$DryRun)
    if ($ToolNames.Count -eq 0) { return }
    $winget = Get-Command winget -ErrorAction SilentlyContinue | Select-Object -First 1
    foreach ($toolName in $ToolNames) {
        $spec = $Manifest.systemTools.$toolName
        $commandsAnyProperty = $spec.PSObject.Properties['commandsAny']
        $names = if ($commandsAnyProperty) { @($commandsAnyProperty.Value) } else { @($spec.commands) }
        if ((Test-CommandAny $names).Found) { Write-Host "[SKIP] $toolName 已安装"; continue }
        if (-not $winget) {
            Write-Warning "$toolName 未安装，且未找到 winget。请安装 Windows App Installer 后重试。建议包：$($spec.wingetId)"
            continue
        }
        Invoke-External $winget.Source @('install', '--id', [string]$spec.wingetId, '--exact', '--accept-source-agreements', '--accept-package-agreements') $DryRun | Out-Null
    }
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Get-PaperFunctionalResults {
    param([string]$OutputDir)
    $results = [System.Collections.Generic.List[object]]::new()
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    $pandoc = Get-Command pandoc -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pandoc) {
        try {
            $markdownPath = Join-Path $OutputDir 'modelready-paper-check.md'
            $docxPath = Join-Path $OutputDir 'modelready-pandoc-check.docx'
            Set-Content -LiteralPath $markdownPath -Value "# ModelReady`n`n数学建模文档转换验证。" -Encoding UTF8
            & $pandoc.Source $markdownPath '-o' $docxPath *> $null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $docxPath)) { throw "Pandoc 退出码 $LASTEXITCODE" }
            $results.Add((New-CheckResult '论文功能' 'Pandoc 转换' 'PASS' "生成 $(Split-Path -Leaf $docxPath)" $true))
        } catch {
            $results.Add((New-CheckResult '论文功能' 'Pandoc 转换' 'FAIL' $_.Exception.Message $true))
        }
    }

    $dot = Get-Command dot -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dot) {
        try {
            $dotPath = Join-Path $OutputDir 'modelready-graph-check.dot'
            $pngPath = Join-Path $OutputDir 'modelready-graph-check.png'
            Set-Content -LiteralPath $dotPath -Value 'digraph G { data -> model -> result; }' -Encoding ASCII
            & $dot.Source '-Tpng' $dotPath '-o' $pngPath *> $null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pngPath)) { throw "Graphviz 退出码 $LASTEXITCODE" }
            $results.Add((New-CheckResult '论文功能' 'Graphviz 绘图' 'PASS' "生成 $(Split-Path -Leaf $pngPath)" $true))
        } catch {
            $results.Add((New-CheckResult '论文功能' 'Graphviz 绘图' 'FAIL' $_.Exception.Message $true))
        }
    }

    $xelatex = Get-Command xelatex -ErrorAction SilentlyContinue | Select-Object -First 1
    $typst = Get-Command typst -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($xelatex) {
        try {
            $texPath = Join-Path $OutputDir 'modelready-tex-check.tex'
            $pdfPath = Join-Path $OutputDir 'modelready-tex-check.pdf'
            $tex = '\documentclass{ctexart}\begin{document}ModelReady 中文论文编译验证。\end{document}'
            Set-Content -LiteralPath $texPath -Value $tex -Encoding UTF8
            & $xelatex.Source '-interaction=nonstopmode' '-halt-on-error' "-output-directory=$OutputDir" $texPath *> $null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pdfPath)) { throw "XeLaTeX 退出码 $LASTEXITCODE；请确认 ctex 宏包可用" }
            $results.Add((New-CheckResult '论文功能' '中文 PDF 编译' 'PASS' "XeLaTeX 生成 $(Split-Path -Leaf $pdfPath)" $true))
        } catch {
            $results.Add((New-CheckResult '论文功能' '中文 PDF 编译' 'FAIL' $_.Exception.Message $true))
        }
    } elseif ($typst) {
        try {
            $typPath = Join-Path $OutputDir 'modelready-typst-check.typ'
            $pdfPath = Join-Path $OutputDir 'modelready-typst-check.pdf'
            Set-Content -LiteralPath $typPath -Value "= ModelReady`n中文论文编译验证。" -Encoding UTF8
            & $typst.Source 'compile' $typPath $pdfPath *> $null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pdfPath)) { throw "Typst 退出码 $LASTEXITCODE" }
            $results.Add((New-CheckResult '论文功能' '中文 PDF 编译' 'PASS' "Typst 生成 $(Split-Path -Leaf $pdfPath)" $true))
        } catch {
            $results.Add((New-CheckResult '论文功能' '中文 PDF 编译' 'FAIL' $_.Exception.Message $true))
        }
    }
    $results.ToArray()
}

function Invoke-ModelReadyDoctor {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$Profile, [string]$Source, [string]$EnvironmentRoot, [bool]$DryRun, [bool]$Yes, [bool]$NoReport)
    $manifest = Get-ModelReadyManifest $ProjectRoot
    $results = @(Get-DoctorResults $manifest $Profile $EnvironmentRoot)
    Write-ConsoleReport $results
    if (-not $NoReport) { Export-ModelReadyReport $results $ProjectRoot $Profile 'doctor' | Out-Null }
    $missing = @($results | Where-Object { $_.Required -and $_.Status -eq 'MISSING' }).Count
    if ($missing -gt 0) { Write-Warning "$missing 项必需组件尚未就绪。" }
}

function Invoke-ModelReadyInstall {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$Profile, [string]$Source, [string]$EnvironmentRoot, [bool]$DryRun, [bool]$Yes, [bool]$NoReport)
    Confirm-Install $Yes $DryRun $Profile
    $manifest = Get-ModelReadyManifest $ProjectRoot
    $requirements = Get-ProfileRequirements $manifest $Profile
    Write-Host "配置档：$Profile；Python 包：$($requirements.PythonPackages.Count)；系统工具：$($requirements.SystemTools.Count)"
    Install-SystemTools $manifest $requirements.SystemTools $DryRun
    if (-not $DryRun) { Update-ProcessPath }

    $uv = Resolve-UvCommand -DryRun $DryRun -Version ([string]$manifest.uvVersion) -ExpectedSha256 ([string]$manifest.uvInstallerSha256)
    $environment = Join-Path $EnvironmentRoot $Profile
    $pythonVersion = [string]$manifest.pythonVersion
    Invoke-External $uv.File (@($uv.Prefix) + @('python', 'install', $pythonVersion)) $DryRun | Out-Null
    $environmentPython = Join-Path $environment 'Scripts\python.exe'
    if ($DryRun -or -not (Test-Path -LiteralPath $environmentPython)) {
        Invoke-External $uv.File (@($uv.Prefix) + @('venv', '--python', $pythonVersion, $environment)) $DryRun | Out-Null
    } else {
        Write-Host "[SKIP] 隔离环境已存在：$environment"
    }

    $indexUrl = [string]$manifest.indexUrls.$Source
    $arguments = @($uv.Prefix) + @('pip', 'install', '--python', $environmentPython, '--index-url', $indexUrl) + @($requirements.PythonPackages)
    Invoke-External $uv.File $arguments $DryRun | Out-Null

    if ($DryRun) {
        Write-Host "[DRY-RUN] 生成精确版本清单：$(Join-Path $environment 'modelready.lock.txt')" -ForegroundColor Cyan
        Write-Host '预演完成：未修改系统。' -ForegroundColor Cyan
        return
    }
    $lockPath = Join-Path $environment 'modelready.lock.txt'
    $freezeArguments = @($uv.Prefix) + @('pip', 'freeze', '--python', $environmentPython)
    & $uv.File @freezeArguments | Set-Content -LiteralPath $lockPath -Encoding UTF8
    if ($LASTEXITCODE -ne 0) { throw "无法生成精确版本清单：$lockPath" }
    Write-Host "精确版本清单：$lockPath"
    $installationState = [ordered]@{
        schemaVersion = 1
        productVersion = [string]$manifest.productVersion
        installedAt = (Get-Date).ToString('o')
        profile = $Profile
        source = $Source
        pythonVersion = $pythonVersion
        environment = $environment
        lockFile = $lockPath
    }
    $installationState | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $environment 'modelready-installation.json') -Encoding UTF8
    Invoke-ModelReadyVerify -ProjectRoot $ProjectRoot -Profile $Profile -Source $Source -EnvironmentRoot $EnvironmentRoot -DryRun:$false -Yes:$true -NoReport:$NoReport
}

function Start-ModelReadyJupyter {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$Profile, [string]$Source, [string]$EnvironmentRoot, [bool]$DryRun, [bool]$Yes, [bool]$NoReport)
    $python = Get-EnvironmentPython $EnvironmentRoot $Profile
    if (-not $python) { throw "未找到配置档 '$Profile'。请先执行 install。" }
    if ($DryRun) {
        Write-Host "[DRY-RUN] $python -m jupyter lab" -ForegroundColor Cyan
        return
    }
    Write-Host "正在启动 $Profile 环境的 JupyterLab；关闭服务请按 Ctrl+C。" -ForegroundColor Green
    & $python -m jupyter lab
    if ($LASTEXITCODE -ne 0) { throw "JupyterLab 退出码 $LASTEXITCODE" }
}

function Uninstall-ModelReadyEnvironment {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$Profile, [string]$Source, [string]$EnvironmentRoot, [bool]$DryRun, [bool]$Yes, [bool]$NoReport)
    $rootFull = [IO.Path]::GetFullPath($EnvironmentRoot).TrimEnd('\', '/')
    $targetFull = [IO.Path]::GetFullPath((Join-Path $rootFull $Profile)).TrimEnd('\', '/')
    $pathRoot = [IO.Path]::GetPathRoot($rootFull).TrimEnd('\', '/')
    if ($rootFull -eq $pathRoot -or $targetFull -eq $rootFull) {
        throw '拒绝删除：环境根目录过于宽泛。'
    }
    $expectedPrefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $targetFull.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw '拒绝删除：目标不在指定的 EnvironmentRoot 内。'
    }
    if (-not (Test-Path -LiteralPath $targetFull)) {
        Write-Host "配置档 '$Profile' 尚未安装：$targetFull"
        return
    }
    if ($DryRun) {
        Write-Host "[DRY-RUN] 删除隔离环境：$targetFull" -ForegroundColor Cyan
        return
    }
    if (-not $Yes) {
        $answer = Read-Host "将永久删除配置档 '$Profile' 的隔离环境。输入 UNINSTALL 继续"
        if ($answer -cne 'UNINSTALL') { throw '用户取消卸载。' }
    }
    Remove-Item -LiteralPath $targetFull -Recurse -Force
    Write-Host "已删除隔离环境：$targetFull" -ForegroundColor Green
    Write-Host '系统级工具（Pandoc、Graphviz、LaTeX）未被删除。'
}

function Show-ModelReadyProfiles {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $manifest = Get-ModelReadyManifest $ProjectRoot
    $rows = foreach ($property in $manifest.profiles.PSObject.Properties) {
        [pscustomobject]@{
            Profile = $property.Name
            DiskGB = $property.Value.estimatedDiskGB
            Description = $property.Value.description
        }
    }
    $rows | Format-Table -AutoSize
}

function Show-ModelReadyVersion {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $manifest = Get-ModelReadyManifest $ProjectRoot
    Write-Host "ModelReady $($manifest.productVersion)"
}

function Invoke-ModelReadyVerify {
    [CmdletBinding()]
    param([string]$ProjectRoot, [string]$Profile, [string]$Source, [string]$EnvironmentRoot, [bool]$DryRun, [bool]$Yes, [bool]$NoReport)
    $manifest = Get-ModelReadyManifest $ProjectRoot
    $results = [System.Collections.Generic.List[object]]::new()
    $python = Get-EnvironmentPython $EnvironmentRoot $Profile
    if (-not $python) {
        $results.Add((New-CheckResult '功能验证' 'Python 环境' 'FAIL' "未找到 $Profile 环境；请先执行 install" $true))
    } else {
        $outputDir = Join-Path $ProjectRoot 'reports\artifacts'
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        $verifyScript = Join-Path $ProjectRoot 'scripts\verify_environment.py'
        & $python $verifyScript --profile $Profile --output-dir $outputDir
        $exitCode = $LASTEXITCODE
        $resultPath = Join-Path $outputDir "verify-$Profile.json"
        if (Test-Path -LiteralPath $resultPath) {
            $pythonResults = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($item in $pythonResults.results) {
                $results.Add((New-CheckResult 'Python 功能' $item.name $item.status $item.detail $true))
            }
        } else {
            $results.Add((New-CheckResult '功能验证' '验证程序' 'FAIL' "退出码 $exitCode，且未生成结果文件" $true))
        }
    }
    foreach ($row in (Get-DoctorResults $manifest $Profile $EnvironmentRoot | Where-Object { $_.Area -eq '系统工具' })) { $results.Add($row) }
    if ('paper' -in (Get-ProfileClosure $manifest $Profile)) {
        $paperOutputDir = Join-Path $ProjectRoot 'reports\artifacts'
        foreach ($row in (Get-PaperFunctionalResults $paperOutputDir)) { $results.Add($row) }
    }
    Write-ConsoleReport $results.ToArray()
    if (-not $NoReport) { Export-ModelReadyReport $results.ToArray() $ProjectRoot $Profile 'verify' | Out-Null }
    if (@($results | Where-Object { $_.Required -and $_.Status -in @('FAIL', 'MISSING') }).Count -gt 0) {
        throw '环境尚未完全通过验证；请根据报告修复后重试。'
    } else {
        Write-Host '环境已通过全部必需验证。' -ForegroundColor Green
    }
}

Export-ModuleMember -Function Invoke-ModelReadyDoctor, Invoke-ModelReadyInstall, Invoke-ModelReadyVerify, Start-ModelReadyJupyter, Uninstall-ModelReadyEnvironment, Show-ModelReadyProfiles, Show-ModelReadyVersion, Get-ProfileClosure, Get-ProfileRequirements
