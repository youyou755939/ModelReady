# 更新记录

## 0.3.0 - 2026-09-09

- 增加 Ubuntu 22.04/24.04、Debian 12 和对应 WSL2 支持。
- 新增 Bash CLI，并覆盖体检、安装、修复、验证、启动和安全卸载。
- Linux 使用 `apt` 安装 Pandoc、Graphviz、TeX Live 与 Noto CJK 字体。
- Windows 和 Linux 共用配置档、Python 功能验证及 HTML/JSON 报告格式。
- uv Linux 固定版本引导脚本增加 SHA-256 校验。
- CI 增加 Ubuntu 22.04/24.04 的真实基础环境安装验证。
- 增加 Linux 生命周期烟雾测试和危险卸载路径拒绝测试。
- 本地构建同时生成 Windows ZIP 和 Linux `tar.gz`。
- Release 发布前检查 Git 标签与产品版本是否一致。

## 0.2.0 - 2026-09-09

- 增加双击启动的统一菜单 `ModelReady.cmd`。
- 增加 `repair`、`launch` 和 `uninstall` 命令。
- 增加 Windows、CPU 架构和配置档磁盘空间检查。
- 已有隔离环境在修复时不再重新创建。
- 安装后保存产品版本、时间、镜像源和环境路径等状态信息。
- 安装后通过 `uv pip freeze` 记录精确依赖版本。
- 固定版本的 uv 官方引导脚本增加 SHA-256 执行前校验。
- 卸载增加目标路径边界校验，仅删除选定配置档环境。
- 增加本地发行包构建脚本，并在 CI 中验证打包流程。

## 0.1.0 - 2026-09-09

- 首个可用版本。
- 提供五种数学建模配置档、环境体检、一键安装和功能验证。
- 支持 Excel、科学计算、优化、机器学习、中文绘图及论文工具链验证。
- 提供 HTML/JSON 报告、GitHub Actions 测试和 Release 自动打包。
