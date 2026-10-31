#!/usr/bin/env bash
# Reproduce the apt-upgraded OneCloud ARMHF rootfs.
# Supports native sudo+binfmt_misc chroot in CI, or the original unprivileged proot.
# Run from anywhere; paths are resolved relative to the project root.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC_IMG=${SRC_IMG:-$ROOT/baseline/part26-root.img}
OUT_IMG=${OUT_IMG:-$ROOT/rootfs/onecloud-rootfs.ext4}
ROOT_UUID=${ROOT_UUID:-8a03b678-0b46-4f41-bb09-3a2d154439bc}
ROOTFS_BLOCKS=${ROOTFS_BLOCKS:-342016}
ROOTFS_EXECUTOR=${ROOTFS_EXECUTOR:-proot}
ROOTFS_APT_SMOKE=${ROOTFS_APT_SMOKE:-0}
PROOT=${PROOT:-$(command -v proot || true)}
QEMU_ARM=${QEMU_ARM:-$(command -v qemu-arm-static || true)}
mkdir -p "$ROOT/tmp" "$ROOT/rootfs"
WORK=$(mktemp -d "$ROOT/tmp/rootfs-update.XXXXXX")
TREE="$WORK/tree"
ROOT_CMD=()
if [ "$(id -u)" -ne 0 ]; then ROOT_CMD=(sudo -n); fi
CHROOT_MOUNTED=()
RESOLV_BACKUP=0
POLICY_CREATED=0
cleanup() {
    if [ "$ROOTFS_EXECUTOR" = chroot ]; then
        for target in sys proc dev; do
            if mountpoint -q "$TREE/$target"; then
                "${ROOT_CMD[@]}" umount "$TREE/$target" || true
            fi
        done
        for target in sys proc dev; do
            if mountpoint -q "$TREE/$target"; then
                echo "ERROR: $TREE/$target remains mounted; refusing unsafe cleanup" >&2
                return 1
            fi
        done
        if [ "$POLICY_CREATED" = 1 ]; then
            "${ROOT_CMD[@]}" rm -f "$TREE/usr/sbin/policy-rc.d"
        fi
        if [ "$RESOLV_BACKUP" = 1 ]; then
            "${ROOT_CMD[@]}" rm -f "$TREE/etc/resolv.conf"
            "${ROOT_CMD[@]}" mv "$WORK/resolv.conf.saved" "$TREE/etc/resolv.conf"
        fi
        "${ROOT_CMD[@]}" rm -rf -- "$WORK"
    else
        rm -rf -- "$WORK"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$ROOTFS_EXECUTOR" = chroot ] || [ "$ROOTFS_EXECUTOR" = proot ] || {
    echo "ROOTFS_EXECUTOR must be chroot or proot" >&2; exit 1;
}
[ -x "$QEMU_ARM" ] || { echo "missing qemu-arm-static: $QEMU_ARM" >&2; exit 1; }
if [ "$ROOTFS_EXECUTOR" = proot ]; then
    [ -n "$PROOT" ] && [ -x "$PROOT" ] || { echo "missing proot" >&2; exit 1; }
else
    if [ "${#ROOT_CMD[@]}" -gt 0 ]; then
        command -v sudo >/dev/null || { echo "chroot mode needs sudo" >&2; exit 1; }
        sudo -n true || { echo "sudo must work non-interactively" >&2; exit 1; }
    fi
    [ -r /proc/sys/fs/binfmt_misc/qemu-arm ] &&
        grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-arm || {
            echo "qemu-arm binfmt_misc registration is missing; run docker/setup-qemu-action" >&2
            exit 1
        }
    command -v mountpoint >/dev/null || { echo "mountpoint is required" >&2; exit 1; }
fi
[ -x "$ROOT/tools/localroot/usr/bin/mcopy" ] || { echo "run scripts/bootstrap-tools.sh first" >&2; exit 1; }
command -v fakeroot >/dev/null || { echo "fakeroot is required" >&2; exit 1; }
[ -f "$SRC_IMG" ] || { echo "missing source rootfs: $SRC_IMG" >&2; exit 1; }

echo "extract $SRC_IMG"
mkdir -p "$TREE"
if [ "$ROOTFS_EXECUTOR" = chroot ]; then
    # Real root is necessary for apt's _apt sandbox and filesystem permissions.
    "${ROOT_CMD[@]}" debugfs -R "rdump / $TREE" "$SRC_IMG" >/dev/null 2>&1
    "${ROOT_CMD[@]}" mkdir -p "$TREE"/{dev,proc,sys,run,tmp,usr/bin,usr/sbin,etc}
    "${ROOT_CMD[@]}" chmod 1777 "$TREE/tmp"
    "${ROOT_CMD[@]}" install -m 0755 "$QEMU_ARM" "$TREE/usr/bin/qemu-arm-static"

    # The extracted Armbian symlink may point to its old /run resolver.
    if [ -e "$TREE/etc/resolv.conf" ] || [ -L "$TREE/etc/resolv.conf" ]; then
        "${ROOT_CMD[@]}" mv "$TREE/etc/resolv.conf" "$WORK/resolv.conf.saved"
        RESOLV_BACKUP=1
    fi
    "${ROOT_CMD[@]}" cp -L /etc/resolv.conf "$TREE/etc/resolv.conf"
    if [ ! -e "$TREE/usr/sbin/policy-rc.d" ]; then
        printf '#!/bin/sh\nexit 101\n' | "${ROOT_CMD[@]}" tee "$TREE/usr/sbin/policy-rc.d" >/dev/null
        "${ROOT_CMD[@]}" chmod 0755 "$TREE/usr/sbin/policy-rc.d"
        POLICY_CREATED=1
    fi
    "${ROOT_CMD[@]}" mount --bind /dev "$TREE/dev"
    "${ROOT_CMD[@]}" mount --bind /proc "$TREE/proc"
    "${ROOT_CMD[@]}" mount --bind /sys "$TREE/sys"
else
    debugfs -R "rdump / $TREE" "$SRC_IMG" >/dev/null 2>&1
fi

APT_SCRIPT=$(cat <<'EOS'
set -e
export DEBIAN_FRONTEND=noninteractive
echo "guest architecture: $(dpkg --print-architecture)"
df -h / /tmp /var/lib/apt/lists
# Do not bypass apt-secure. All InRelease signatures must be validated.
apt-get -o APT::Get::Update::Error-Mode=any update
apt-cache policy libgl1-mesa-dri | head -15
if [ "${ROOTFS_APT_SMOKE:-0}" = 1 ]; then
    echo "ARMHF APT signature smoke test: SUCCESS"
    exit 0
fi
apt-mark hold linux-image-current-meson linux-dtb-current-meson armbian-bsp-cli-onecloud-current
apt-get -y -o Dpkg::Options::=--force-confold \
    -o APT::Keep-Downloaded-Packages=false -o Acquire::Retries=3 full-upgrade
apt-get -y --no-install-recommends -o Dpkg::Options::=--force-confold \
    -o APT::Keep-Downloaded-Packages=false -o Acquire::Retries=3 install \
    libgl1-mesa-dri libegl-mesa0 libegl1 libgles2 libgbm1 mesa-utils
apt-get clean
EOS
)
echo "apt update + full-upgrade (ARMHF via $ROOTFS_EXECUTOR)"
if [ "$ROOTFS_EXECUTOR" = chroot ]; then
    "${ROOT_CMD[@]}" env ROOTFS_APT_SMOKE="$ROOTFS_APT_SMOKE" \
        chroot "$TREE" /bin/bash -c "$APT_SCRIPT"
else
    "$PROOT" -r "$TREE" -q "$QEMU_ARM" -0 \
        -b /proc -b /dev -b /sys -b /etc/resolv.conf -w / \
        /bin/bash -c "$APT_SCRIPT"
fi
if [ "$ROOTFS_APT_SMOKE" = 1 ]; then
    echo "APT smoke finished successfully"
    exit 0
fi
if [ "$ROOTFS_EXECUTOR" = chroot ]; then
    # Remove temporary host bind mounts and bootstrapping executables before packaging.
    for target in sys proc dev; do
        "${ROOT_CMD[@]}" umount "$TREE/$target"
    done
    "${ROOT_CMD[@]}" rm -f "$TREE/usr/bin/qemu-arm-static"
    if [ "$POLICY_CREATED" = 1 ]; then
        "${ROOT_CMD[@]}" rm -f "$TREE/usr/sbin/policy-rc.d"
        POLICY_CREATED=0
    fi
    if [ "$RESOLV_BACKUP" = 1 ]; then
        "${ROOT_CMD[@]}" rm -f "$TREE/etc/resolv.conf"
        "${ROOT_CMD[@]}" mv "$WORK/resolv.conf.saved" "$TREE/etc/resolv.conf"
        RESOLV_BACKUP=0
    fi
fi

# The kernel modules are supplied by build.sh/package.sh, not by this base image.
if [ "$ROOTFS_EXECUTOR" = chroot ]; then
    "${ROOT_CMD[@]}" find "$TREE/lib/modules" -maxdepth 1 -type d -name "*-onecloud" -exec rm -rf -- {} +
else
    find "$TREE/lib/modules" -maxdepth 1 -type d -name "*-onecloud" -exec rm -rf -- {} +
fi

echo "repack $OUT_IMG"
rm -f "$OUT_IMG"
if [ "$ROOTFS_EXECUTOR" = chroot ]; then
    "${ROOT_CMD[@]}" mkfs.ext4 -F -q -b 4096 -L armbi_root -U "$ROOT_UUID" \
        -d "$TREE" "$OUT_IMG" "$ROOTFS_BLOCKS"
    "${ROOT_CMD[@]}" env ROOTFS_TREE="$TREE" python3 "$ROOT/scripts/restore-metadata.py" "$SRC_IMG" "$OUT_IMG"
    "${ROOT_CMD[@]}" chown "$(id -u):$(id -g)" "$OUT_IMG"
else
    fakeroot mkfs.ext4 -F -q -b 4096 -L armbi_root -U "$ROOT_UUID" \
        -d "$TREE" "$OUT_IMG" "$ROOTFS_BLOCKS"
    ROOTFS_TREE="$TREE" python3 "$ROOT/scripts/restore-metadata.py" "$SRC_IMG" "$OUT_IMG"
fi
e2fsck -fn "$OUT_IMG"
echo "wrote $OUT_IMG"
