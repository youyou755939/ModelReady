from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("--path", type=Path, required=True)
parser.add_argument("--product-version", required=True)
parser.add_argument("--profile", required=True)
parser.add_argument("--source", required=True)
parser.add_argument("--python-version", required=True)
parser.add_argument("--environment", required=True)
parser.add_argument("--lock-file", required=True)
args = parser.parse_args()

payload = {
    "schemaVersion": 1,
    "productVersion": args.product_version,
    "installedAt": datetime.now().astimezone().isoformat(),
    "profile": args.profile,
    "source": args.source,
    "pythonVersion": args.python_version,
    "environment": args.environment,
    "lockFile": args.lock_file,
}
args.path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

