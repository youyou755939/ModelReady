# ModelReady

面向中文数学建模竞赛的 Windows、Ubuntu、Debian 与 WSL2 环境安装、体检和验证工具。

ModelReady 的目标不是“把包装上就算完成”，而是安装后实际运行一组最小建模任务，证明 Python、数据处理、优化、机器学习、中文绘图和论文工具链能够工作。

## 快速开始

### Windows

普通用户可以直接双击 `ModelReady.cmd` 打开菜单。也可以双击 `Doctor-ModelReady.cmd` 体检，或双击 `Install-ModelReady.cmd` 安装完整配置档。

在 PowerShell 中运行：

```powershell
# 只体检，不修改系统
.\modelready.ps1 doctor -Profile full

# 预览将要执行的安装操作
.\modelready.ps1 install -Profile full -DryRun

# 安装完整环境；系统级软件仍会由 winget 显示安装界面或权限提示
.\modelready.ps1 install -Profile full -Yes

# 运行可复现的功能验证
.\modelready.ps1 verify -Profile full

# 修复缺失或损坏的依赖
.\modelready.ps1 repair -Profile full -Yes

# 启动隔离环境中的 JupyterLab
.\modelready.ps1 launch -Profile full

# 只删除指定配置档的 Python 隔离环境
.\modelready.ps1 uninstall -Profile full

# 查看所有配置档或当前版本
.\modelready.ps1 profiles
.\modelready.ps1 version
```

报告默认写入 `reports/`，Python 虚拟环境默认位于 `%LOCALAPPDATA%\ModelReady\envs\<profile>`。可用 `-EnvironmentRoot` 指定其他位置。

### Ubuntu、Debian 与 WSL2

```bash
# 体检，不修改系统
bash ./modelready.sh doctor --profile full

# 预览安装操作
bash ./modelready.sh install --profile full --dry-run

# 安装并验证完整环境
bash ./modelready.sh install --profile full --yes

# 修复、验证和启动 JupyterLab
bash ./modelready.sh repair --profile full --yes
bash ./modelready.sh verify --profile full
bash ./modelready.sh launch --profile full
```

Linux 默认将隔离环境写入 `${XDG_DATA_HOME:-$HOME/.local/share}/modelready/envs/<profile>`，报告写入 `${XDG_STATE_HOME:-$HOME/.local/state}/modelready/reports`。系统包通过 `apt` 安装，非 root 用户需要 `sudo`。

## 配置档

| 配置档 | 内容 |
| --- | --- |
| `base` | NumPy、Pandas、SciPy、Matplotlib、SymPy、Jupyter、Excel 读写 |
| `optimization` | `base` + CVXPY、PuLP、OR-Tools、NetworkX |
| `ml` | `base` + scikit-learn、statsmodels、XGBoost |
| `paper` | `base` + 文档处理包，并检查 Pandoc、Graphviz、XeLaTeX/Typst |
| `full` | 以上全部 |

## 设计原则

- 默认命令是只读体检；安装必须明确执行 `install`。
- `-DryRun` 输出计划但不下载或安装任何内容。
- Python 包安装在独立虚拟环境，不污染系统 Python，并在安装后记录精确版本清单。
- 优先使用 `winget` 安装 `uv`；没有 `winget` 和 Python 时，使用固定版本的 uv 官方安装脚本引导。
- 支持官方 PyPI 和清华 PyPI 镜像切换。
- 商业软件仅检测，不下载、不破解，也不处理许可证。
- 每次验证生成 JSON 和 HTML 报告，方便队伍成员互相复现。
- `repair` 可重复执行并补齐依赖；已存在的隔离环境不会被无故清空。
- `uninstall` 只允许删除 `EnvironmentRoot` 下对应配置档，不卸载共享系统工具。

## 当前范围

目前支持 Windows 10/11、Ubuntu 22.04/24.04、Debian 12，以及基于这些发行版的 WSL2。Windows 系统软件优先通过 `winget` 安装；Linux/WSL2 使用 `apt`。MATLAB、Gurobi、COPT 等商业工具只进入检测诊断报告。

## 开发验证

```powershell
pwsh -NoProfile -File .\tests\smoke.ps1
```

生成本地发行包及 SHA-256 校验文件：

```powershell
.\build.ps1
```

产物写入 `dist/`，同时生成 Windows ZIP、Linux `tar.gz` 及对应 SHA-256 文件。压缩包内只包含运行所需文件，不包含测试、报告或 Git 元数据。

项目采用 [MIT License](LICENSE)。
