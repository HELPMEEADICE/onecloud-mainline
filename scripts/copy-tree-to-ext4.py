#!/usr/bin/env python3
"""Copy a host directory tree into an ext2/3/4 image using debugfs.

No root privileges or loop devices are required.  File modes are set to
0644 for regular files and 0755 for directories; kernel modules only need
to be readable.  Symlinks are skipped (the modules_install build/source
links are not wanted inside the image).
"""
import os
import subprocess
import sys

if len(sys.argv) != 4:
    print("usage: copy-tree-to-ext4.py <image> <host-dir> <image-dir>", file=sys.stderr)
    sys.exit(2)

image, host_dir, image_dir = sys.argv[1], sys.argv[2].rstrip("/"), sys.argv[3].rstrip("/")
commands = []

def image_has(path):
    p = subprocess.run(["debugfs", "-R", f"stat {path}", image],
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return "Inode:" in p.stdout

for dirpath, dirnames, filenames in os.walk(host_dir):
    dirnames.sort()
    rel = os.path.relpath(dirpath, host_dir)
    dest = image_dir if rel == "." else f"{image_dir}/{rel}"
    if not image_has(dest):
        commands.append(f"mkdir {dest}")
    for name in sorted(filenames):
        src = os.path.join(dirpath, name)
        if os.path.islink(src) or not os.path.isfile(src):
            continue
        if image_has(f"{dest}/{name}"):
            commands.append(f"rm {dest}/{name}")
        commands.append(f"write {src} {dest}/{name}")
        commands.append(f"sif {dest}/{name} mode 0100644")
        commands.append(f"sif {dest}/{name} uid 0")
        commands.append(f"sif {dest}/{name} gid 0")

script = "\n".join(commands) + "\n"
proc = subprocess.run(["debugfs", "-w", "-f", "-", image], input=script,
                      text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(proc.stdout[-3000:])
if proc.returncode != 0:
    print(f"debugfs failed with {proc.returncode}", file=sys.stderr)
    sys.exit(proc.returncode)
print(f"copied {sum(1 for c in commands if c.startswith('write '))} files to {image}:{image_dir}")
