#!/usr/bin/env bash
# Use distro-provided tools on Ubuntu/Arch; build pinned AmlImg and extract ARMHF busybox.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/tools/localroot/usr/bin" "$ROOT/src" "$ROOT/logs"
for cmd in bc mcopy mdir mtype mmd mkimage dumpimage img2simg simg2img; do
    exe=$(command -v "$cmd" || true)
    [ -n "$exe" ] || { echo "missing host tool $cmd" >&2; exit 1; }
    ln -sfn "$exe" "$ROOT/tools/localroot/usr/bin/$cmd"
done
command -v go >/dev/null || { echo "Go compiler missing" >&2; exit 1; }
if [ ! -d "$ROOT/src/AmlImg/.git" ]; then
    git clone --filter=blob:none https://github.com/hzyitc/AmlImg.git "$ROOT/src/AmlImg"
fi
git -C "$ROOT/src/AmlImg" checkout -q 5ede4ed30b27c10187af5258f7e2f61f9ad71e1e
if [ ! -x "$ROOT/tools/AmlImg" ]; then
    ( cd "$ROOT/src/AmlImg" && go build -o "$ROOT/tools/AmlImg" . )
fi
if [ ! -x "$ROOT/tools/busybox/usr/bin/busybox" ]; then
    curl -fL --retry 3 https://deb.debian.org/debian/pool/main/b/busybox/busybox-static_1.38.0-3+b1_armhf.deb -o "$ROOT/tools/busybox-static.deb"
    mkdir -p "$ROOT/tools/busybox"
    ( cd "$ROOT/tools/busybox" && ar p "$ROOT/tools/busybox-static.deb" data.tar.xz | tar -xJf - )
fi
[ -x "$ROOT/tools/busybox/usr/bin/busybox" ] || { echo "ARMHF busybox missing" >&2; exit 1; }
