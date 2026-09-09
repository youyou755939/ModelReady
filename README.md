# ModelReady

[![CI](https://github.com/youyou755939/ModelReady/actions/workflows/ci.yml/badge.svg)](https://github.com/youyou755939/ModelReady/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/youyou755939/ModelReady?include_prereleases)](https://github.com/youyou755939/ModelReady/releases)
[![License](https://img.shields.io/github/license/youyou755939/ModelReady)](LICENSE)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Ubuntu%20%7C%20Debian%20%7C%20WSL2-blue)](#平台支持)

面向中文数学建模竞赛的环境安装、体检、修复、验证与完整回滚工具。

ModelReady 不以“依赖安装命令执行完毕”为完成标准。它会实际运行 Excel 读写、科学计算、优化求解、机器学习、中文绘图和论文编译任务，并生成可审计的 HTML/JSON 报告。

## 为什么使用 ModelReady

- 一个工具管理 Python、Jupyter、优化、机器学习和论文工具链。
- 五种配置档按需安装，避免所有队伍都下载完整环境。
- Python 使用独立虚拟环境，不污染系统 Python。
- **可审计的一键回滚**：安装前记录基线，只撤回 ModelReady 实际新增的环境、运行时、缓存、引导工具和系统包。
- 支持体检、预演、安装、修复、验证、启动、安全卸载和完整回滚。
- 固定版本的 uv 引导脚本执行前核验 SHA-256。
- MATLAB、Gurobi、COPT 等商业软件只检测，不下载、不破解、不处理许可证。

## 平台支持

| 平台 | 安装入口 | 系统包管理器 | 自动化测试 |
| --- | --- | --- | --- |
| Windows 10/11 x64 | `modelready.ps1` / `ModelReady.cmd` | winget | Windows Runner |
| Ubuntu 22.04 x64 | `modelready.sh` | apt | Ubuntu 22.04 Runner |
| Ubuntu 24.04 x64 | `modelready.sh` | apt | Ubuntu 24.04 Runner |
| Debian 12 x64 | `modelready.sh` | apt | 兼容路径，待独立 Runner |
| WSL2（Ubuntu/Debian） | `modelready.sh` | apt | 复用对应发行版流程 |

ARM64、macOS、Fedora、Arch Linux 当前不在正式支持范围内。

## 快速开始

建议从 [Releases](https://github.com/youyou755939/ModelReady/releases) 下载对应压缩包，并使用随附的 `.sha256` 文件核对完整性。也可以直接克隆本仓库。

### Windows

解压 Windows ZIP 后，普通用户可直接双击：

- `ModelReady.cmd`：打开统一操作菜单；
- `Doctor-ModelReady.cmd`：只检查完整环境；
- `Install-ModelReady.cmd`：安装并验证 `full` 配置档；
- `Rollback-ModelReady.cmd`：一键撤回所有有记录的 ModelReady 修改。

PowerShell 用户可以精确控制操作：

```powershell
# 只体检，不修改系统
.\modelready.ps1 doctor -Profile full

# 预览所有安装操作
.\modelready.ps1 install -Profile full -DryRun

# 安装并验证完整环境
.\modelready.ps1 install -Profile full -Yes

# 后续维护
.\modelready.ps1 repair -Profile full -Yes
.\modelready.ps1 verify -Profile full
.\modelready.ps1 launch -Profile full
.\modelready.ps1 uninstall -Profile full

# 先预览，再完整撤回 ModelReady 0.4+ 的安装修改
.\modelready.ps1 rollback -DryRun
.\modelready.ps1 rollback -Yes
```

默认环境目录：`%LOCALAPPDATA%\ModelReady\envs\<profile>`；报告写入项目的 `reports/`。

### Ubuntu、Debian 与 WSL2

解压 Linux `tar.gz` 后运行：

```bash
# 只体检，不修改系统
bash ./modelready.sh doctor --profile full

# 预览所有安装操作
bash ./modelready.sh install --profile full --dry-run

# 安装系统包、创建隔离环境并执行验证
bash ./modelready.sh install --profile full --yes

# 后续维护
bash ./modelready.sh repair --profile full --yes
bash ./modelready.sh verify --profile full
bash ./modelready.sh launch --profile full
bash ./modelready.sh uninstall --profile full

# 先预览，再完整撤回 ModelReady 0.4+ 的安装修改
bash ./modelready.sh rollback --dry-run
bash ./modelready.sh rollback --yes
```

Linux 使用 `apt` 安装系统组件，非 root 用户需要 `sudo`。默认位置：

```text
环境：${XDG_DATA_HOME:-$HOME/.local/share}/modelready/envs/<profile>
报告：${XDG_STATE_HOME:-$HOME/.local/state}/modelready/reports
```

## 一键恢复到安装前

从 0.4.0 开始，ModelReady 在执行每项安装操作前都会保存变更日志。回滚时按相反顺序处理，只删除安装前不存在且由本项目新增的资源：

- 隔离的 Python 配置档、ModelReady 专用 Python 运行时与 uv 缓存；
- 由引导程序新增的 uv 文件或用户级 Python 包；
- 由 ModelReady 新装的 winget / APT 系统包。

安装前已经存在的软件不会进入日志。即使安装中途失败，已登记的修改仍可撤回；如果某一步回滚失败，日志会保留供修复后重试。Linux 在卸载 APT 包前还会模拟执行，只要发现可能连带删除未登记软件，就会拒绝继续。

回滚专注于恢复**软件与环境状态**。为避免误删个人成果，它不会删除 ModelReady 源码目录、用户创建的 Notebook、论文或报告，也不会清理包管理器本身的通用下载索引。0.3 及更早版本没有基线日志，因此 0.4 不会猜测哪些旧资源可以安全删除。

日志位置：

```text
Windows：%LOCALAPPDATA%\ModelReady\state\rollback-journal.json
Linux：  ${XDG_STATE_HOME:-$HOME/.local/state}/modelready/rollback-journal.tsv
```

## 配置档

| 配置档 | 主要内容 | 建议空间 |
| --- | --- | ---: |
| `base` | NumPy、Pandas、SciPy、Matplotlib、SymPy、Jupyter、Excel 读写 | 4 GB |
| `optimization` | `base` + CVXPY、PuLP、OR-Tools、NetworkX | 6 GB |
| `ml` | `base` + scikit-learn、statsmodels、XGBoost | 8 GB |
| `paper` | `base` + DOCX/PDF 工具、Pandoc、Graphviz、XeLaTeX/Typst | 7 GB |
| `full` | 上述全部组件 | 12 GB |

查看配置档和版本：

```text
Windows: .\modelready.ps1 profiles
Linux:   bash ./modelready.sh profiles
```

## 验证内容

安装后的验证不是简单的 `import` 检查，而会实际执行：

1. 导入配置档声明的全部 Python 包；
2. 使用 SciPy 求解线性规划；
3. 执行 Excel 写入和读回比对；
4. 使用可覆盖中文字符的字体生成 PNG；
5. 训练并检查线性回归模型；
6. 使用 CVXPY 求解优化问题；
7. 生成 DOCX 并检查 PDF 处理包；
8. 使用 Pandoc 转换文档、Graphviz 生成流程图；
9. 使用 XeLaTeX 或 Typst 编译中文 PDF。

报告同时提供机器可读 JSON 和浏览器可读 HTML，失败项不会被成功项掩盖。

## 镜像源

默认使用官方 PyPI。国内网络可切换到清华 PyPI 镜像：

```powershell
.\modelready.ps1 install -Profile full -Source china -Yes
```

```bash
bash ./modelready.sh install --profile full --source china --yes
```

镜像选项只影响 Python 包；系统包仍由 winget 或 apt 管理。

## 安全与卸载边界

- 默认命令是只读体检，安装必须明确执行 `install`。
- `DryRun` / `--dry-run` 只展示计划，不下载或安装软件。
- 引导脚本固定版本并校验 SHA-256，不使用直接网络管道执行方式。
- 卸载前解析并检查绝对路径，只能删除指定环境根目录下的配置档。
- 卸载配置档不会删除共享的 Pandoc、Graphviz、TeX Live 等系统软件。
- 完整回滚只处理 0.4+ 日志中登记的新增资源；系统包卸载使用精确包 ID。
- Linux 会先模拟 APT 卸载，发现未登记的连带删除项时立即停止，且不会自动运行 `autoremove`。

完整说明参见 [SECURITY.md](SECURITY.md)。

## 项目结构

```text
ModelReady/
├── modelready.ps1              # Windows CLI
├── ModelReady.cmd              # Windows 双击菜单
├── Rollback-ModelReady.cmd     # Windows 一键完整回滚
├── modelready.sh               # Ubuntu/Debian/WSL2 CLI
├── config/profiles.json        # 跨平台配置档清单
├── scripts/                    # 清单、验证、报告与状态脚本
├── src/ModelReady.psm1         # Windows 实现模块
├── tests/                      # Windows/Linux 烟雾测试
└── build.ps1                   # 双平台发行包构建
```

## 开发与打包

Windows 烟雾测试：

```powershell
pwsh -NoProfile -File .\tests\smoke.ps1
```

Linux 烟雾测试：

```bash
bash ./tests/linux-smoke.sh
```

生成 Windows ZIP、Linux `tar.gz` 和对应 SHA-256：

```powershell
.\build.ps1
```

产物写入 `dist/`，不会包含测试报告、Python 缓存或 Git 元数据。

## 路线图

- Docker/Jupyter 预构建镜像；
- macOS Apple Silicon 支持；
- 离线缓存包与校园镜像；
- 图形化安装进度和环境修复建议；
- ARM64 兼容矩阵。

更新历史见 [CHANGELOG.md](CHANGELOG.md)。项目采用 [MIT License](LICENSE)。
