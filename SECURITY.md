# 安全说明

ModelReady 会安装软件和 Python 包，因此安装前应确认代码来源，并优先从本仓库的 GitHub Release 下载带 SHA-256 文件的发行包。

## 下载与执行策略

- 系统软件通过 Windows Package Manager (`winget`) 的精确包 ID 安装。
- Python 和虚拟环境由 `uv` 管理。
- 当系统既没有 `winget`、也没有可用 Python 时，ModelReady 从 `https://astral.sh/uv/<固定版本>/install.ps1` 下载官方安装脚本到临时文件；只有 SHA-256 与清单中的固定值一致才会执行，结束后删除。
- Linux 使用相同策略下载固定版本的 `install.sh`，并在执行前核对独立的 SHA-256。
- 项目不使用 `irm ... | iex` 或其他直接把网络响应送入解释器的管道形式。
- Python 包通过 `config/profiles.json` 中的版本范围和明确索引源安装。
- MATLAB、Gurobi、COPT 等商业软件仅检测，不自动安装，也不处理许可证。
- Windows 和 Linux 的卸载命令都会解析绝对路径并验证目标位于配置的环境根目录内；共享系统软件不会随配置档删除。
- 0.4+ 安装会先记录基线，只将安装前不存在、由 ModelReady 新增的资源加入回滚日志。
- 完整回滚按相反顺序处理日志；文件操作必须通过绝对路径边界校验，日志仅在全部步骤成功后删除。
- Linux 回滚会先模拟 APT 卸载；如果模拟结果包含未登记软件，则拒绝执行系统包卸载，也不会运行 `autoremove`。
- 回滚不会删除仓库源码、用户创建的笔记本、论文或报告；没有 0.4+ 日志时不会猜测并卸载任何资源。

## 报告漏洞

请通过 GitHub Security Advisory 私下报告可能导致任意代码执行、下载劫持或路径越界的问题。不要在公开 Issue 中附带令牌、许可证文件或个人路径。
