from __future__ import annotations

import argparse
import json
from pathlib import Path


def profile_closure(manifest: dict, profile: str) -> list[str]:
    seen: list[str] = []

    def visit(name: str) -> None:
        if name in seen:
            return
        node = manifest["profiles"].get(name)
        if node is None:
            raise SystemExit(f"unknown profile: {name}")
        for parent in node.get("extends", []):
            visit(parent)
        seen.append(name)

    visit(profile)
    return seen


def unique_profile_values(manifest: dict, profile: str, key: str) -> list[str]:
    values: list[str] = []
    for name in profile_closure(manifest, profile):
        for value in manifest["profiles"][name].get(key, []):
            if value not in values:
                values.append(value)
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--profile", default="base")
    parser.add_argument(
        "--field",
        required=True,
        choices=["packages", "tools", "closure", "version", "python-version", "disk", "uv-version", "uv-linux-sha256"],
    )
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))

    if args.field == "packages":
        values = unique_profile_values(manifest, args.profile, "pythonPackages")
    elif args.field == "tools":
        values = unique_profile_values(manifest, args.profile, "systemTools")
    elif args.field == "closure":
        values = profile_closure(manifest, args.profile)
    elif args.field == "version":
        values = [manifest["productVersion"]]
    elif args.field == "python-version":
        values = [manifest["pythonVersion"]]
    elif args.field == "disk":
        values = [str(manifest["profiles"][args.profile]["estimatedDiskGB"])]
    elif args.field == "uv-version":
        values = [manifest["uvVersion"]]
    else:
        values = [manifest["uvInstallerSha256Linux"]]
    print("\n".join(values))


if __name__ == "__main__":
    main()

