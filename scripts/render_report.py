from __future__ import annotations

import argparse
import html
import json
from datetime import datetime
from pathlib import Path


def normalize_json_results(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    area = payload.get("area", "功能验证")
    return [
        {
            "Area": item.get("area", area),
            "Item": item.get("name", item.get("Item", "unknown")),
            "Status": item.get("status", item.get("Status", "INFO")),
            "Required": item.get("required", True),
            "Detail": item.get("detail", item.get("Detail", "")),
        }
        for item in payload.get("results", [])
    ]


def read_tsv(path: Path) -> list[dict]:
    results = []
    for line in path.read_text(encoding="utf-8").splitlines():
        status, area, item, required, detail = line.split("\t", 4)
        results.append(
            {"Status": status, "Area": area, "Item": item, "Required": required == "true", "Detail": detail}
        )
    return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--kind", required=True)
    parser.add_argument("--output-base", type=Path, required=True)
    parser.add_argument("--input-tsv", type=Path)
    parser.add_argument("--json-files", type=Path, nargs="*")
    args = parser.parse_args()

    results: list[dict] = []
    if args.input_tsv:
        results.extend(read_tsv(args.input_tsv))
    for path in args.json_files or []:
        results.extend(normalize_json_results(path))

    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now().astimezone().isoformat(),
        "profile": args.profile,
        "kind": args.kind,
        "results": results,
    }
    args.output_base.parent.mkdir(parents=True, exist_ok=True)
    args.output_base.with_suffix(".json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    counts = {
        "PASS": sum(item["Status"] == "PASS" for item in results),
        "PROBLEM": sum(item["Status"] in {"FAIL", "MISSING"} for item in results),
        "NOTICE": sum(item["Status"] in {"WARN", "INFO"} for item in results),
    }
    rows = "\n".join(
        "<tr><td class='{status_class}'>{status_text}</td><td>{area}</td><td>{item}</td><td>{detail}</td></tr>".format(
            status_class=html.escape(item["Status"].lower()),
            status_text=html.escape(item["Status"]),
            area=html.escape(str(item["Area"])),
            item=html.escape(str(item["Item"])),
            detail=html.escape(str(item["Detail"])),
        )
        for item in results
    )
    document = f"""<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">
<title>ModelReady 报告</title><style>
body{{font-family:system-ui,"Noto Sans CJK SC",sans-serif;max-width:1100px;margin:40px auto;color:#1f2937}}
.summary{{display:flex;gap:12px;margin:24px 0}}.card{{padding:14px 20px;border-radius:8px;background:#f8fafc}}
.card b{{font-size:22px}}table{{border-collapse:collapse;width:100%}}th,td{{padding:10px;border-bottom:1px solid #ddd;text-align:left}}
.pass{{color:#15803d}}.missing,.fail{{color:#b91c1c}}.warn{{color:#a16207}}.info{{color:#64748b}}
</style></head><body><h1>ModelReady {html.escape(args.kind)} 报告</h1>
<p>配置档：<code>{html.escape(args.profile)}</code>　生成时间：{html.escape(payload['generatedAt'])}</p>
<div class="summary"><div class="card"><b class="pass">{counts['PASS']}</b><br>通过</div>
<div class="card"><b class="fail">{counts['PROBLEM']}</b><br>问题</div>
<div class="card"><b class="info">{counts['NOTICE']}</b><br>提示</div></div>
<table><thead><tr><th>状态</th><th>区域</th><th>项目</th><th>详情</th></tr></thead><tbody>{rows}</tbody></table>
</body></html>"""
    args.output_base.with_suffix(".html").write_text(document, encoding="utf-8")
    print(args.output_base.with_suffix(".html"))


if __name__ == "__main__":
    main()
