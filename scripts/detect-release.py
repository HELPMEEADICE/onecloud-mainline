#!/usr/bin/env python3
"""Select the latest active kernel or an explicitly requested signed release."""
import json
import os
import re
import sys
from urllib.request import urlopen

def parse(v):
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", v):
        raise ValueError("invalid final kernel version: " + v)
    return tuple(map(int, v.split("."))) + (0,) * (3 - len(v.split(".")))

def select(data, requested=""):
    # Explicit versions may be older than the current releases.json entries.
    # fetch-kernel.sh still authenticates the archive via SHA256 and PGP.
    if requested:
        if parse(requested) < (7, 3, 1):
            raise ValueError("requested version must be at least 7.3.1")
        return requested
    valid = {}
    for release in data["releases"]:
        v = release.get("version", "")
        if release.get("moniker") not in ("stable", "mainline") or release.get("iseol", False):
            continue
        try:
            n = parse(v)
        except ValueError:
            continue
        if n >= (7, 3, 1):
            valid[v] = n
    if not valid:
        raise ValueError("no supported stable/mainline release")
    return max(valid, key=valid.get)

if __name__ == "__main__":
    try:
        with urlopen("https://www.kernel.org/releases.json", timeout=30) as r:
            version = select(json.load(r), os.environ.get("REQUESTED_VERSION", ""))
        tag = "linux-" + version + "-onecloud"
        print("Selected", tag)
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write("version=" + version + "\ntag=" + tag + "\n")
    except (ValueError, OSError, KeyError) as e:
        sys.exit(str(e))
