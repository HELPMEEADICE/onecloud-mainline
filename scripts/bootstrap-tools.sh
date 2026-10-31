#!/usr/bin/env bash
# Provision host-side helper tools without root.
# These are statically pinned versions used for this project; the kernel
# cross toolchain and the kernel source are handled by build.sh.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ ! -d "$ROOT/src" ] && [ -d "$ROOT/../src" ]; then ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd); fi
if [ ! -d "$ROOT/src" ] && [ -d "$ROOT/../../src" ]; then ROOT=$(CDPATH= cd -- "$ROOT/../.." && pwd); fi
LOCAL="$ROOT/tools/localroot"
mkdir -p "$ROOT/tools" "$LOCAL" "$ROOT/logs"

fetch() {
    local url=$1 dest=$2
    [ -s "$dest" ] && return 0
    echo "fetch $url"
    curl -fL --retry 3 --connect-timeout 20 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
}

arch_pkg() {
    local name=$1 url=$2 marker="$LOCAL/.$1" file
    [ -e "$marker" ] && return 0
    file=$(basename "$url")
    fetch "$url" "$ROOT/tools/$file"
    tar -xf "$ROOT/tools/$file" -C "$LOCAL"
    touch "$marker"
}

# bc is needed by the kernel timeconst rules.
arch_pkg bc https://archive.archlinux.org/packages/b/bc/bc-1.08.2-1-x86_64.pkg.tar.zst
# mtools: edit the FAT boot partition without mounting it.
arch_pkg mtools https://archive.archlinux.org/packages/m/mtools/mtools-4.0.28-1-x86_64.pkg.tar.zst
# mkimage/dumpimage built against OpenSSL 3 (the host has libssl.so.3).
arch_pkg uboot-tools https://archive.archlinux.org/packages/u/uboot-tools/uboot-tools-2025.10-1-x86_64.pkg.tar.zst
# img2simg/simg2img for Amlogic/Android sparse images.
arch_pkg android-tools https://archive.archlinux.org/packages/a/android-tools/android-tools-37.0.0.p1-1-x86_64.pkg.tar.zst

if [ ! -x "$ROOT/tools/go/bin/go" ]; then
    fetch https://go.dev/dl/go1.27.3.linux-amd64.tar.gz "$ROOT/tools/go1.27.3.linux-amd64.tar.gz"
    rm -rf "$ROOT/tools/go"
    tar -xzf "$ROOT/tools/go1.27.3.linux-amd64.tar.gz" -C "$ROOT/tools"
fi

if [ ! -d "$ROOT/src/AmlImg/.git" ]; then
    git clone --filter=blob:none https://github.com/hzyitc/AmlImg.git "$ROOT/src/AmlImg"
fi
git -C "$ROOT/src/AmlImg" checkout -q 5ede4ed30b27c10187af5258f7e2f61f9ad71e1e
if [ ! -x "$ROOT/tools/AmlImg" ]; then
    ( cd "$ROOT/src/AmlImg" && PATH="$ROOT/tools/go/bin:$PATH" GOFLAGS=-mod=mod \
        go build -o "$ROOT/tools/AmlImg" . )
fi

if [ ! -x "$ROOT/tools/busybox/usr/bin/busybox" ]; then
    fetch https://deb.debian.org/debian/pool/main/b/busybox/busybox-static_1.38.0-3+b1_armhf.deb \
        "$ROOT/tools/busybox-static.deb"
    rm -rf "$ROOT/tools/busybox"
    mkdir -p "$ROOT/tools/busybox"
    ( cd "$ROOT/tools/busybox" && ar x ../busybox-static.deb && tar -xf data.tar.xz )
fi

if [ ! -x "$ROOT/tools/gen_init_cpio" ]; then
    gcc -O2 -o "$ROOT/tools/gen_init_cpio" "$ROOT/src/linux-7.3.1-upstream/usr/gen_init_cpio.c" 2>/dev/null || true
fi

echo "host helper tools are ready in $ROOT/tools"
