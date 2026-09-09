from __future__ import annotations

import argparse
import json
import platform
import shutil
import subprocess
from pathlib import Path


def check_result(name: str, function, *, area: str = "系统功能") -> dict:
    try:
        detail = function()
        return {"area": area, "name": name, "status": "PASS", "required": True, "detail": str(detail)}
    except Exception as exc:
        return {"area": area, "name": name, "status": "FAIL", "required": True, "detail": f"{type(exc).__name__}: {exc}"}


def require_command(*names: str) -> str:
    for name in names:
        path = shutil.which(name)
        if path:
            return path
    raise RuntimeError(f"未找到命令：{' / '.join(names)}")


def run_checked(arguments: list[str]) -> None:
    completed = subprocess.run(arguments, capture_output=True, text=True, errors="replace", timeout=180)
    if completed.returncode:
        message = (completed.stderr or completed.stdout).strip().splitlines()
        raise RuntimeError(message[-1] if message else f"退出码 {completed.returncode}")


def verify_pandoc(output_dir: Path) -> str:
    command = require_command("pandoc")
    source = output_dir / "modelready-paper-check.md"
    target = output_dir / "modelready-pandoc-check.docx"
    source.write_text("# ModelReady\n\n数学建模文档转换验证。", encoding="utf-8")
    run_checked([command, str(source), "-o", str(target)])
    if not target.exists() or target.stat().st_size < 5_000:
        raise RuntimeError("Pandoc 未生成有效 DOCX")
    return f"生成 {target.name}"


def verify_graphviz(output_dir: Path) -> str:
    command = require_command("dot")
    source = output_dir / "modelready-graph-check.dot"
    target = output_dir / "modelready-graph-check.png"
    source.write_text("digraph G { data -> model -> result; }", encoding="ascii")
    run_checked([command, "-Tpng", str(source), "-o", str(target)])
    if not target.exists() or target.stat().st_size < 500:
        raise RuntimeError("Graphviz 未生成有效 PNG")
    return f"生成 {target.name}"


def verify_pdf(output_dir: Path) -> str:
    xelatex = shutil.which("xelatex")
    typst = shutil.which("typst")
    if xelatex:
        source = output_dir / "modelready-tex-check.tex"
        target = output_dir / "modelready-tex-check.pdf"
        source.write_text(
            r"\documentclass{ctexart}\begin{document}ModelReady 中文论文编译验证。\end{document}",
            encoding="utf-8",
        )
        run_checked([xelatex, "-interaction=nonstopmode", "-halt-on-error", f"-output-directory={output_dir}", str(source)])
        if not target.exists():
            raise RuntimeError("XeLaTeX 未生成 PDF")
        return f"XeLaTeX 生成 {target.name}"
    if typst:
        source = output_dir / "modelready-typst-check.typ"
        target = output_dir / "modelready-typst-check.pdf"
        source.write_text("= ModelReady\n中文论文编译验证。", encoding="utf-8")
        run_checked([typst, "compile", str(source), str(target)])
        if not target.exists():
            raise RuntimeError("Typst 未生成 PDF")
        return f"Typst 生成 {target.name}"
    raise RuntimeError("未找到 xelatex 或 typst")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--paper", action="store_true")
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    results = [
        check_result("操作系统", lambda: f"{platform.system()} {platform.release()} ({platform.machine()})", area="平台"),
    ]
    if args.paper:
        results.extend(
            [
                check_result("Pandoc 转换", lambda: verify_pandoc(args.output_dir)),
                check_result("Graphviz 绘图", lambda: verify_graphviz(args.output_dir)),
                check_result("中文 PDF 编译", lambda: verify_pdf(args.output_dir)),
            ]
        )
    payload = {"schemaVersion": 1, "profile": args.profile, "area": "系统功能", "results": results}
    output = args.output_dir / f"verify-system-{args.profile}.json"
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output)
    return 0 if all(item["status"] == "PASS" for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
