#!/usr/bin/env python3
"""Restore mode/uid/gid metadata from a reference ext4 image into a target image.

The target image is created with `mke2fs -d` as an unprivileged user, which
cannot preserve setuid/setgid bits or group ownership.  This script walks the
reference filesystem with debugfs and applies its metadata to matching paths.
"""
import os, re, subprocess, sys

if len(sys.argv) != 3:
    sys.exit("usage: restore-metadata.py <reference.img> <target.img>")
ref, target = sys.argv[1:3]
line_re = re.compile(r"^\s*(\d+)\s+([0-7]+)\s+\(\d+\)\s+(\d+)\s+(\d+)\s+(\d+)\s+\S+\s+\S+\s+(.+)$")

def list_dir(path):
    cmd = ["debugfs", "-R", f"ls -l {path}", ref]
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    out = []
    for line in p.stdout.splitlines():
        m = line_re.match(line)
        if not m:
            continue
        ino, mode_s, uid, gid, size, name = m.groups()
        if name in (".", ".."):
            continue
        out.append((name, int(mode_s, 8), int(uid), int(gid)))
    return out

meta = {}
stack = ["/"]
while stack:
    d = stack.pop()
    for name, mode, uid, gid in list_dir(d):
        path = (d.rstrip("/") + "/" + name) if d != "/" else "/" + name
        meta[path] = (mode, uid, gid)
        if (mode & 0o170000) == 0o040000:
            stack.append(path)

print(f"reference metadata entries: {len(meta)}", file=sys.stderr)

cmds = []
for dirpath, dirnames, filenames in os.walk("/".join([""]) if False else "."):
    pass
# Walk the extracted rootfs relative to the target image's root.
ROOT = os.environ.get("ROOTFS_TREE")
if not ROOT:
    sys.exit("ROOTFS_TREE is required")
for dirpath, dirnames, filenames in os.walk(ROOT):
    rel = os.path.relpath(dirpath, ROOT)
    paths = [rel] if rel != "." else ["."]
    paths = [("" if p == "." else "/" + p) for p in paths]
    for name in filenames:
        p = (("/" + rel) if rel != "." else "") + "/" + name
        paths.append(p)
    for p in paths:
        if p == ".":
            p = "/"
        if p in meta:
            mode, uid, gid = meta[p]
            cmds.append(f"sif {p} mode 0{mode:o}")
            cmds.append(f"sif {p} uid {uid}")
            cmds.append(f"sif {p} gid {gid}")

print(f"applying {len(cmds)} metadata operations", file=sys.stderr)
p = subprocess.run(["debugfs", "-w", "-f", "-", target], input="\n".join(cmds) + "\n",
                   text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(p.stdout[-3000:])
if p.returncode:
    sys.exit(p.returncode)
