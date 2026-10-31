#!/usr/bin/env python3
"""Select latest official final Linux release, or requested active version."""
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
    if requested:
        if requested not in valid:
            raise ValueError("requested kernel is not an active stable/mainline release")
        return requested
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
