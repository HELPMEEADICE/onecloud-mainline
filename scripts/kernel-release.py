#!/usr/bin/env python3
"""Choose the newest released upstream Linux kernel, excluding RCs and EOL trees.

Outputs KVER for the Actions build job. No third-party Python dependencies.
"""
import argparse
import json
import os
import re
import sys
import urllib.request

VERSION = re.compile(r"^[0-9]+\.[0-9]+(?:\.[0-9]+)?$")

def version_tuple(value):
    if not VERSION.fullmatch(value):
        raise ValueError(f"not a final Linux kernel version: {value!r}")
    pieces = tuple(map(int, value.split(".")))
    return pieces + (0,) * (3 - len(pieces))

def newest_release(data, minimum="7.3.1"):
    candidates = []
    for entry in data.get("releases", []):
        if entry.get("moniker") not in ("stable", "mainline"):
            continue
        value = str(entry.get("version", ""))
        if VERSION.fullmatch(value) and not entry.get("iseol", False):
            candidates.append(value)
    latest = data.get("latest_stable", {})
    if isinstance(latest, dict):
        value = str(latest.get("version", ""))
        if VERSION.fullmatch(value):
            candidates.append(value)
    candidates = [v for v in candidates if version_tuple(v) >= version_tuple(minimum)]
    if not candidates:
        raise ValueError(f"kernel.org reports no final kernel >= {minimum}")
    return max(candidates, key=version_tuple)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--minimum", default="7.3.1")
    parser.add_argument("--version", help="build this final version instead of auto-detecting")
    parser.add_argument("--releases-url", default="https://www.kernel.org/releases.json")
    args = parser.parse_args()
    version_tuple(args.minimum)
    if args.version:
        version_tuple(args.version)
        if version_tuple(args.version) < version_tuple(args.minimum):
            parser.error("requested kernel predates supported baseline")
        version = args.version
    else:
        req = urllib.request.Request(args.releases_url, headers={"User-Agent": "onecloud-mainline-ci/1.0"})
        with urllib.request.urlopen(req, timeout=30) as response:
            version = newest_release(json.load(response), args.minimum)
    print(version)
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"version={version}\n")
            out.write(f"tag=onecloud-linux-v{version}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as out:
            out.write(f"Selected Linux kernel: **{version}** (final release)\n")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, json.JSONDecodeError) as error:
        sys.exit(f"Kernel release discovery failed: {error}")
