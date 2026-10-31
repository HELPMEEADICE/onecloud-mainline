#!/usr/bin/env bash
# Assemble the boot partition, root filesystem, normal disk image and the
# Amlogic USB Burning Tool image from the artifacts produced by build.sh.
# The downloaded Armbian baseline is never modified: all edits happen on
# copies under build/ and rootfs/.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -d "$ROOT/src" ] && [ -d "$ROOT/../src" ]; then ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd); fi
KVER=${KVER:-7.3.1}
KREL=${KREL:-${KVER}-onecloud}
KERNEL_BUILD=${KERNEL_BUILD:-$ROOT/build/linux-$KVER-gcc15}
ARCH=arm
SELF="$ROOT/package.sh"
LOGFILE="$ROOT/logs/package-$KREL.log"
BASE_NAME=Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal
BASE_IMG="$ROOT/baseline/$BASE_NAME.img"
BASE_BURN="$ROOT/baseline/$BASE_NAME.burn.img"
BASE_IMG_XZ="$BASE_IMG.xz"
BASE_BURN_XZ="$BASE_BURN.xz"
BASE_IMG_XZ_SHA=cf9ef8e58037eccc51c29b846c5cd9be2fdadea6241323ed3565f4c3096dac20
BASE_BURN_XZ_SHA=a02c00898a16b1543d6ef052d21128b16ca127ad2a3d12f54e5337d80bdcec17
BASE_IMG_URL=https://github.com/upleung/armbian-onecloud/releases/download/v2026.08.03-2135/Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.img.xz
BASE_BURN_URL=https://github.com/upleung/armbian-onecloud/releases/download/v2026.08.03-2135/Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal.burn.img.xz

export PATH="$ROOT/tools/localroot/usr/bin:$PATH"
mkdir -p "$ROOT/logs" "$ROOT/build" "$ROOT/rootfs" "$ROOT/output"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== OneCloud packaging $(date -u +%FT%TZ) ==="

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing host command: $1"; }
for c in cp dd debugfs depmod mkimage mcopy mdir img2simg simg2img sha1sum sha256sum xz tar; do need "$c"; done
[ -x "$ROOT/tools/AmlImg" ] || die "missing tools/AmlImg; run scripts/bootstrap-tools.sh"
[ -d "$ROOT/rootfs/modules-full/lib/modules/$KREL" ] || die "missing modules; run build.sh first"
[ -f "$ROOT/build/uImage" ] && [ -f "$ROOT/build/uInitrd" ] || die "missing uImage/uInitrd; run build.sh first"
[ -f "$KERNEL_BUILD/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb" ] || die "missing DTB"

fetch_baseline() {
    local url=$1 dest=$2 sha=$3
    if [ ! -f "$dest" ]; then
        echo "downloading baseline $url"
        curl -fL --retry 3 --connect-timeout 20 -o "$dest.part" "$url"
        echo "$sha  $dest.part" | sha256sum -c --status -
        mv "$dest.part" "$dest"
    else
        echo "$sha  $dest" | sha256sum -c --status -
    fi
}
mkdir -p "$ROOT/baseline"
fetch_baseline "$BASE_IMG_URL" "$BASE_IMG_XZ" "$BASE_IMG_XZ_SHA"
fetch_baseline "$BASE_BURN_URL" "$BASE_BURN_XZ" "$BASE_BURN_XZ_SHA"
[ -f "$BASE_IMG" ] || xz -dk "$BASE_IMG_XZ"
[ -f "$BASE_BURN" ] || xz -dk "$BASE_BURN_XZ"

# 16 MiB reserved area + 256 MiB FAT boot + 1336 MiB ext4 rootfs.
PART_BOOT="$ROOT/baseline/part26-boot.img"
PART_ROOT="$ROOT/baseline/part26-root.img"
BURN_UNPACKED="$ROOT/baseline/burn-unpacked-26.08"
BOOTFILES="$ROOT/baseline/bootfiles26"
if [ ! -f "$PART_BOOT" ]; then
    dd if="$BASE_IMG" of="$PART_BOOT" bs=1M skip=16 count=256 status=none
fi
if [ ! -f "$PART_ROOT" ]; then
    dd if="$BASE_IMG" of="$PART_ROOT" bs=1M skip=272 count=1336 status=none
fi
[ "$(stat -c%s "$PART_BOOT")" -eq 268435456 ] || die "boot partition size mismatch"
[ "$(stat -c%s "$PART_ROOT")" -eq 1400897536 ] || die "rootfs partition size mismatch"
if [ ! -d "$BURN_UNPACKED" ]; then
    "$ROOT/tools/AmlImg" unpack "$BASE_BURN" "$BURN_UNPACKED"
fi
if [ ! -d "$BOOTFILES" ]; then
    mkdir -p "$BOOTFILES"
    for f in boot.scr boot.cmd armbianEnv.txt; do
        "$ROOT/tools/localroot/usr/bin/mcopy" -o -i "$PART_BOOT" "::/$f" "$BOOTFILES/$f"
    done
fi

# ---- root filesystem -------------------------------------------------------
echo "preparing rootfs"
ROOTFS_IMAGE=${ROOTFS_IMAGE:-$ROOT/rootfs/onecloud-rootfs.ext4}
if [ ! -f "$ROOTFS_IMAGE" ]; then
    echo "WARNING: $ROOTFS_IMAGE missing; falling back to baseline rootfs without apt upgrade" >&2
    ROOTFS_IMAGE="$PART_ROOT"
fi
rm -f "$ROOT/rootfs/onecloud-rootfs.work.ext4"
cp --reflink=auto "$ROOTFS_IMAGE" "$ROOT/rootfs/onecloud-rootfs.work.ext4" 2>/dev/null || \
    cp "$ROOTFS_IMAGE" "$ROOT/rootfs/onecloud-rootfs.work.ext4"
rm -f "$ROOT/rootfs/onecloud-rootfs.ext4"
mv "$ROOT/rootfs/onecloud-rootfs.work.ext4" "$ROOT/rootfs/onecloud-rootfs.ext4"
MODLIB="$ROOT/rootfs/modules-full/lib/modules/$KREL"
if [ ! -s "$MODLIB/modules.dep" ] || [ ! -s "$MODLIB/modules.alias" ]; then
    echo "module dependency database missing; running depmod"
    depmod -ae -F "$KERNEL_BUILD/System.map" -b "$ROOT/rootfs/modules-full" "$KREL"
fi
[ -s "$MODLIB/modules.dep" ] || die "missing $MODLIB/modules.dep; rebuild modules (build.sh)"
[ -s "$MODLIB/modules.alias" ] || die "missing $MODLIB/modules.alias; rebuild modules (build.sh)"
python3 "$ROOT/scripts/copy-tree-to-ext4.py" \
    "$ROOT/rootfs/onecloud-rootfs.ext4" \
    "$ROOT/rootfs/modules-full/lib/modules/$KREL" \
    "/lib/modules/$KREL"
if ! debugfs -R 'stat /etc/modules-load.d' "$ROOT/rootfs/onecloud-rootfs.ext4" 2>/dev/null | grep -q 'Inode:'; then
    debugfs -w -R 'mkdir /etc/modules-load.d' "$ROOT/rootfs/onecloud-rootfs.ext4" >/dev/null
fi
for f in /etc/systemd/network/10-ethernet.network /etc/modules-load.d/onecloud.conf; do
    debugfs -w -R "rm $f" "$ROOT/rootfs/onecloud-rootfs.ext4" >/dev/null 2>&1 || true
done
debugfs -w -R "write $ROOT/config/rootfs/10-ethernet.network /etc/systemd/network/10-ethernet.network" \
    "$ROOT/rootfs/onecloud-rootfs.ext4" >/dev/null
debugfs -w -R "write $ROOT/config/rootfs/onecloud-modules.conf /etc/modules-load.d/onecloud.conf" \
    "$ROOT/rootfs/onecloud-rootfs.ext4" >/dev/null

# ---- boot partition --------------------------------------------------------
echo "preparing boot partition"
rm -f "$ROOT/rootfs/onecloud-boot.vfat"
cp --reflink=auto "$PART_BOOT" "$ROOT/rootfs/onecloud-boot.vfat" 2>/dev/null || \
    cp "$PART_BOOT" "$ROOT/rootfs/onecloud-boot.vfat"
MCP="$ROOT/tools/localroot/usr/bin/mcopy"
IMG="$ROOT/rootfs/onecloud-boot.vfat"
"$MCP" -o -i "$IMG" "$ROOT/build/uImage" ::/uImage
"$MCP" -o -i "$IMG" "$ROOT/build/uInitrd" ::/uInitrd
"$MCP" -o -i "$IMG" "$KERNEL_BUILD/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb" ::/dtb/meson8b-onecloud.dtb
"$MCP" -o -i "$IMG" "$BOOTFILES/boot.scr" ::/boot.scr
"$MCP" -o -i "$IMG" "$BOOTFILES/boot.cmd" ::/boot.cmd
"$MCP" -o -i "$IMG" "$BOOTFILES/armbianEnv.txt" ::/armbianEnv.txt
"$MCP" -o -i "$IMG" "$KERNEL_BUILD/arch/arm/boot/zImage" "::/vmlinuz-$KREL"
"$MCP" -o -i "$IMG" "$KERNEL_BUILD/System.map" "::/System.map-$KREL"
"$MCP" -o -i "$IMG" "$ROOT/config/onecloud-$KVER.config" "::/config-$KREL"
"$ROOT/tools/localroot/usr/bin/mmd" -i "$IMG" "::/dtb-$KREL" >/dev/null 2>&1 || true
"$MCP" -o -i "$IMG" "$KERNEL_BUILD/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb" "::/dtb-$KREL/meson8b-onecloud.dtb"

# ---- normal disk image -----------------------------------------------------
echo "building normal disk image"
NORMAL="$ROOT/build/OneCloud-Linux-$KVER-armhf.img"
rm -f "$NORMAL"
cp --reflink=auto "$BASE_IMG" "$NORMAL" 2>/dev/null || cp "$BASE_IMG" "$NORMAL"
dd if="$ROOT/rootfs/onecloud-boot.vfat" of="$NORMAL" bs=1M seek=16 conv=notrunc status=none
dd if="$ROOT/rootfs/onecloud-rootfs.ext4" of="$NORMAL" bs=1M seek=272 conv=notrunc status=none

# ---- Amlogic burn image ----------------------------------------------------
echo "building Amlogic burn image"
BURN_DIR="$ROOT/build/burn-package"
rm -rf "$BURN_DIR"
cp -a "$BURN_UNPACKED" "$BURN_DIR"
simg2img() { "$ROOT/tools/localroot/usr/bin/simg2img" "$@"; }
img2simg() { "$ROOT/tools/localroot/usr/bin/img2simg" "$@"; }
img2simg "$ROOT/rootfs/onecloud-boot.vfat" "$BURN_DIR/8.boot.PARTITION.sparse" 4096
img2simg "$ROOT/rootfs/onecloud-rootfs.ext4" "$BURN_DIR/10.rootfs.PARTITION.sparse" 4096
printf 'sha1sum %s' "$(sha1sum "$BURN_DIR/8.boot.PARTITION.sparse" | cut -d' ' -f1)" > "$BURN_DIR/9.boot.VERIFY"
printf 'sha1sum %s' "$(sha1sum "$BURN_DIR/10.rootfs.PARTITION.sparse" | cut -d' ' -f1)" > "$BURN_DIR/11.rootfs.VERIFY"
BURN="$ROOT/build/OneCloud-Linux-$KVER-armhf.burn.img"
rm -f "$BURN"
"$ROOT/tools/AmlImg" pack "$BURN" "$BURN_DIR"

# ---- optional GCC15 U-Boot payload variant --------------------------------
# The old OneCloud U-Boot 2011.03 SPL/DDR-init code is timing sensitive and is
# not reliably reproduced by modern GCC.  Keep the baseline SPL (first 32 KiB
# of 4.bootloader.PARTITION) and only replace the compressed U-Boot proper
# payload.  UBOOT_COMP.USB stays on the baseline so the USB burning tool can
# always re-flash a board.
UBOOT_VARIANT=${UBOOT_VARIANT:-1}
BURN_UBOOT=""
if [ "$UBOOT_VARIANT" = 1 ] && [ -s "$ROOT/output/uboot/u-boot-comp.bin" ]; then
    UBOOT_CONVERT="$ROOT/build/u-boot-gcc15/build/tools/convert"
    if [ -x "$UBOOT_CONVERT" ]; then
        echo "building GCC15 U-Boot payload variant"
        UBOOT_DIR="$ROOT/build/burn-package-uboot"
        rm -rf "$UBOOT_DIR"
        cp -a "$BURN_DIR" "$UBOOT_DIR"
        head -c 32768 "$BURN_UNPACKED/4.bootloader.PARTITION" \
            >"$ROOT/build/uboot-baseline-spl.bin"
        "$UBOOT_CONVERT" --soc m8b \
            -s "$ROOT/build/uboot-baseline-spl.bin" \
            -i "$ROOT/output/uboot/u-boot-comp.bin" \
            -o "$ROOT/build/u-boot-hybrid-gcc15.bin"
        cp -f "$ROOT/build/uboot-baseline-spl.bin" "$ROOT/output/uboot/baseline-spl.bin"
        cp -f "$ROOT/build/u-boot-hybrid-gcc15.bin" \
            "$ROOT/output/uboot/u-boot-hybrid-gcc15.bin"
        cp -f "$BURN_UNPACKED/1.UBOOT_COMP.USB" "$UBOOT_DIR/1.UBOOT_COMP.USB"
        cp -f "$ROOT/build/u-boot-hybrid-gcc15.bin" "$UBOOT_DIR/4.bootloader.PARTITION"
        printf 'sha1sum %s' \
            "$(sha1sum "$UBOOT_DIR/4.bootloader.PARTITION" | cut -d' ' -f1)" \
            >"$UBOOT_DIR/5.bootloader.VERIFY"
        BURN_UBOOT="$ROOT/build/OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img"
        rm -f "$BURN_UBOOT"
        "$ROOT/tools/AmlImg" pack "$BURN_UBOOT" "$UBOOT_DIR"
    else
        echo "WARNING: missing $UBOOT_CONVERT; skipping GCC15 U-Boot variant" >&2
    fi
fi

# ---- publish ---------------------------------------------------------------
echo "publishing output"
cp -f "$NORMAL" "$ROOT/output/OneCloud-Linux-$KVER-armhf.img"
cp -f "$BURN" "$ROOT/output/OneCloud-Linux-$KVER-armhf.burn.img"
[ -n "$BURN_UBOOT" ] && \
    cp -f "$BURN_UBOOT" "$ROOT/output/OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img"
mkdir -p "$ROOT/output/kernel" "$ROOT/output/modules" "$ROOT/output/patches"
cp -f "$ROOT/build/uImage" "$ROOT/build/uInitrd" "$ROOT/output/kernel/"
cp -f "$KERNEL_BUILD/arch/arm/boot/zImage" "$ROOT/output/kernel/"
cp -f "$KERNEL_BUILD/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb" "$ROOT/output/kernel/"
cp -f "$ROOT/config/onecloud-$KVER.config" "$ROOT/output/kernel/config-$KREL"
cp -f "$KERNEL_BUILD/System.map" "$ROOT/output/kernel/System.map-$KREL"
cp -f "$ROOT"/patches/*.patch "$ROOT/output/patches/"
tar -C "$ROOT/rootfs/modules-full/lib/modules" -cJf "$ROOT/output/modules/modules-$KREL.tar.xz" "$KREL"

if [ "${COMPRESS:-1}" = 1 ]; then
    echo "compressing images (xz -T0 -${XZ_LEVEL:-6})"
    xz -T0 "-${XZ_LEVEL:-6}" -k -f "$ROOT/output/OneCloud-Linux-$KVER-armhf.img" \
        "$ROOT/output/OneCloud-Linux-$KVER-armhf.burn.img"
    [ -n "$BURN_UBOOT" ] && xz -T0 "-${XZ_LEVEL:-6}" -k -f \
        "$ROOT/output/OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img"
fi

( cd "$ROOT/output"
  for f in OneCloud-Linux-$KVER-armhf.img OneCloud-Linux-$KVER-armhf.burn.img \
           OneCloud-Linux-$KVER-armhf.img.xz OneCloud-Linux-$KVER-armhf.burn.img.xz \
           OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img \
           OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img.xz; do
      [ -f "$f" ] && sha256sum "$f" > "$f.sha256"
  done
  sha256sum OneCloud-Linux-$KVER-armhf.img OneCloud-Linux-$KVER-armhf.burn.img \
      OneCloud-Linux-$KVER-armhf.img.xz OneCloud-Linux-$KVER-armhf.burn.img.xz \
      $( [ -n "$BURN_UBOOT" ] && echo OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img \
      OneCloud-Linux-$KVER-armhf-uboot-gcc15.burn.img.xz ) \
      > SHA256SUMS 2>/dev/null || true
)
ls -lh "$ROOT/output"
echo "=== packaging complete $(date -u +%FT%TZ) ==="
