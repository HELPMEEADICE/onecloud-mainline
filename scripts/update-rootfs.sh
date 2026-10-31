#!/usr/bin/env bash
# Reproduce the apt-upgraded OneCloud ARMHF rootfs.
# Requires proot and qemu-arm-static under tools/, plus fakeroot.
# Run from anywhere; paths are resolved relative to the project root.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC_IMG=${SRC_IMG:-$ROOT/baseline/part26-root.img}
OUT_IMG=${OUT_IMG:-$ROOT/rootfs/onecloud-rootfs.ext4}
ROOT_UUID=${ROOT_UUID:-8a03b678-0b46-4f41-bb09-3a2d154439bc}
ROOTFS_BLOCKS=${ROOTFS_BLOCKS:-342016}
PROOT=${PROOT:-$(command -v proot || true)}
QEMU_ARM=${QEMU_ARM:-$(command -v qemu-arm-static || true)}
mkdir -p "$ROOT/tmp" "$ROOT/rootfs"
WORK=$(mktemp -d "$ROOT/tmp/rootfs-update.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

[ -x "$PROOT" ] || { echo "missing $PROOT" >&2; exit 1; }
[ -x "$QEMU_ARM" ] || { echo "missing $QEMU_ARM" >&2; exit 1; }
[ -x "$ROOT/tools/localroot/usr/bin/mcopy" ] || { echo "run scripts/bootstrap-tools.sh first" >&2; exit 1; }
command -v fakeroot >/dev/null || { echo "fakeroot is required" >&2; exit 1; }
[ -f "$SRC_IMG" ] || { echo "missing source rootfs: $SRC_IMG" >&2; exit 1; }

echo "extract $SRC_IMG"
mkdir -p "$WORK/tree"
debugfs -R "rdump / $WORK/tree" "$SRC_IMG" >/dev/null 2>&1

echo "apt update + full-upgrade (ARMHF under qemu-user)"
"$PROOT" -r "$WORK/tree" -q "$QEMU_ARM" -0 \
    -b /proc -b /dev -b /sys -b /etc/resolv.conf -w / /bin/bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-mark hold linux-image-current-meson linux-dtb-current-meson armbian-bsp-cli-onecloud-current
apt-get -y -o Dpkg::Options::=--force-confold \
    -o APT::Keep-Downloaded-Packages=false -o Acquire::Retries=3 full-upgrade
# Mesa userspace for the Mali-450 GPU (lima DRM driver).  The minimal
# Armbian image ships no EGL/GLES stack, so /dev/dri alone cannot render.
apt-get -y --no-install-recommends -o Dpkg::Options::=--force-confold \
    -o APT::Keep-Downloaded-Packages=false -o Acquire::Retries=3 install \
    libgl1-mesa-dri libegl-mesa0 libegl1 libgles2 libgbm1 mesa-utils
apt-get clean
'

# The kernel modules are supplied by build.sh/package.sh, not by this base image.
find "$WORK/tree/lib/modules" -maxdepth 1 -type d -name "*-onecloud" -exec rm -rf -- {} +

echo "repack $OUT_IMG"
rm -f "$OUT_IMG"
fakeroot mkfs.ext4 -F -q -b 4096 -L armbi_root -U "$ROOT_UUID" \
    -d "$WORK/tree" "$OUT_IMG" "$ROOTFS_BLOCKS"
ROOTFS_TREE="$WORK/tree" python3 "$ROOT/scripts/restore-metadata.py" "$SRC_IMG" "$OUT_IMG"
e2fsck -fn "$OUT_IMG"
echo "wrote $OUT_IMG"
