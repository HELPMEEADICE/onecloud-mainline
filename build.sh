#!/usr/bin/env bash
# Build Linux 7.3.1 + OneCloud (Amlogic S805 / Meson8b) kernel, modules,
# DTB, initramfs and uImage.  Run as an ordinary user; no root required.
#
# Environment:
#   JOBS=36             parallel make jobs (default: nproc)
#   KVER=7.3.1          upstream stable version
#   PACKAGE=1           call package.sh after the kernel build
#   SKIP_DOWNLOAD=0     fail instead of downloading missing sources
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -d "$ROOT/src" ] && [ -d "$ROOT/../src" ]; then ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd); fi
KVER=${KVER:-7.3.1}
KREL=${KREL:-${KVER}-onecloud}
JOBS=${JOBS:-$(nproc)}
ARCH=arm
CROSS_COMPILE=arm-none-linux-gnueabihf-
TOOLCHAIN=arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
TOOLCHAIN_TAR="$ROOT/tools/$TOOLCHAIN.tar.xz"
TOOLCHAIN_SHA256=3c65d820a6b8f677f8f6fbfc749fe00a4f16dde12341436c9df5b7092a47c0fb
KERNEL_TAR="$ROOT/tools/linux-$KVER.tar.xz"
SRC="$ROOT/src/linux-$KVER-upstream"
BUILD=${BUILD_DIR:-"$ROOT/build/linux-$KVER-gcc15"}
LOGFILE="$ROOT/logs/build-$KREL.log"
export ARCH CROSS_COMPILE
export PATH="$ROOT/tools/$TOOLCHAIN/bin:$ROOT/tools/localroot/usr/bin:$PATH"

mkdir -p "$ROOT/logs" "$ROOT/build" "$ROOT/src" "$ROOT/config" "$ROOT/tools" "$ROOT/tmp"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== OneCloud kernel build $(date -u +%FT%TZ) ==="
echo "kernel=$KVER release=$KREL jobs=$JOBS"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing host command: $1"; }
for c in curl tar gzip xz make gcc flex bison perl openssl patch cpio debugfs dd depmod; do
    need "$c"
done

fetch_verify() {
    local url=$1 dest=$2 sha=$3
    if [ -s "$dest" ]; then
        echo "$sha  $dest" | sha256sum -c --status - && return 0
        die "existing file has wrong checksum: $dest"
    fi
    [ "${SKIP_DOWNLOAD:-0}" = 1 ] && die "missing $dest (SKIP_DOWNLOAD=1)"
    echo "downloading $url"
    curl -fL --retry 3 --connect-timeout 20 -o "$dest.part" "$url"
    echo "$sha  $dest.part" | sha256sum -c --status -
    mv "$dest.part" "$dest"
}

"$ROOT/scripts/fetch-kernel.sh" "$KVER" "$KERNEL_TAR"
fetch_verify "https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/$TOOLCHAIN.tar.xz" "$TOOLCHAIN_TAR" "$TOOLCHAIN_SHA256"

if [ ! -x "$ROOT/tools/$TOOLCHAIN/bin/${CROSS_COMPILE}gcc" ]; then
    echo "extracting cross toolchain"
    tar -xf "$TOOLCHAIN_TAR" -C "$ROOT/tools"
fi
"$ROOT/tools/$TOOLCHAIN/bin/${CROSS_COMPILE}gcc" --version | head -1

# Extract the pristine upstream tree once.  It is deliberately left unpacked
# so that patches can be inspected and re-applied.
if [ ! -d "$SRC" ]; then
    echo "extracting linux-$KVER"
    tar -xf "$KERNEL_TAR" -C "$ROOT/src"
    mv "$ROOT/src/linux-$KVER" "$SRC"
fi

apply_patch() {
    local p=$1
    local report="$ROOT/logs/patch-$(basename "$p").log"
    if patch -d "$SRC" --batch --forward -p1 --dry-run <"$p" >"$report" 2>&1; then
        echo "apply $(basename "$p")"
        patch -d "$SRC" --batch --forward -p1 <"$p" >>"$report" 2>&1 || {
            cat "$report" >&2
            die "failed to apply $(basename "$p")"
        }
    elif patch -d "$SRC" --batch -R -p1 --dry-run <"$p" >"$report.reverse" 2>&1; then
        echo "already applied: $(basename "$p")"
    else
        echo "=== patch dry-run failure: $(basename "$p") ===" >&2
        cat "$report" >&2
        echo "=== reverse dry-run failure ===" >&2
        cat "$report.reverse" >&2
        die "cannot apply or reverse $(basename "$p")"
    fi
}

# Several patches touch the same files (for example 0001 adds the OneCloud DTS
# and 0003 extends it).  Once 0003 is applied, 0001 can no longer be reversed,
# so a plain forward/reverse probe cannot tell whether the stack is applied.
# Record a stamp of the patch set after a successful application and skip the
# whole stack when it still matches.
PATCH_STAMP="$SRC/.onecloud-patches.sha256"
patch_set_sha() {
    cat "$ROOT"/patches/*.patch | sha256sum | cut -d' ' -f1
}
if [ -f "$PATCH_STAMP" ] && [ "$(cat "$PATCH_STAMP")" = "$(patch_set_sha)" ]; then
    echo "patch stack already applied (stamp matches)"
else
    if [ -f "$PATCH_STAMP" ]; then
        # The patch set changed.  Several patches touch the same files, so
        # an already patched tree cannot be updated reliably in place.
        # Restore the pristine tree and apply the complete new stack.
        echo "patch set changed, restoring pristine linux-$KVER"
        rm -rf "$SRC"
        tar -xf "$KERNEL_TAR" -C "$ROOT/src"
        mv "$ROOT/src/linux-$KVER" "$SRC"
    fi
    for p in "$ROOT"/patches/*.patch; do apply_patch "$p"; done
    patch_set_sha >"$PATCH_STAMP"
fi

"$ROOT/scripts/bootstrap-tools.sh"
need bc
[ -x "$ROOT/tools/gen_init_cpio" ] || gcc -O2 -o "$ROOT/tools/gen_init_cpio" "$SRC/usr/gen_init_cpio.c"

mkdir -p "$BUILD"
make -C "$SRC" O="$BUILD" multi_v7_defconfig
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" "$BUILD/.config" "$ROOT/config/onecloud.fragment"
make -C "$SRC" O="$BUILD" olddefconfig
cp "$BUILD/.config" "$ROOT/config/onecloud-$KVER.config"

echo "building zImage, modules and DTBs with $JOBS jobs"
make -C "$SRC" O="$BUILD" -j"$JOBS" zImage modules dtbs

KERNELRELEASE=$(make -s -C "$SRC" O="$BUILD" kernelrelease)
[ "$KERNELRELEASE" = "$KREL" ] || die "kernelrelease mismatch: $KERNELRELEASE != $KREL"
echo "kernelrelease=$KERNELRELEASE"

rm -rf "$ROOT/rootfs/modules-full"
make -C "$SRC" O="$BUILD" modules_install INSTALL_MOD_PATH="$ROOT/rootfs/modules-full" INSTALL_MOD_STRIP=1 STRIP=arm-none-linux-gnueabihf-strip

# make modules_install normally runs scripts/depmod.sh, but that step can
# silently create nothing (for example when the host depmod was not found).
# Without modules.dep/modules.alias modprobe and udev cannot load any module,
# which in particular leaves the lima GPU driver unbound.  Regenerate the
# database explicitly and make the build fail if it is missing.
MODLIB="$ROOT/rootfs/modules-full/lib/modules/$KREL"
depmod -ae -F "$BUILD/System.map" -b "$ROOT/rootfs/modules-full" "$KREL"
[ -s "$MODLIB/modules.dep" ] || die "depmod did not create $MODLIB/modules.dep"
[ -s "$MODLIB/modules.alias" ] || die "depmod did not create $MODLIB/modules.alias"

"$ROOT/scripts/make-initramfs.sh" "$KREL" 8a03b678-0b46-4f41-bb09-3a2d154439bc \
    "$ROOT/build/initramfs-$KREL.cpio.gz"

MKIMAGE="$ROOT/tools/localroot/usr/bin/mkimage"
# Use the same load/entry address as the working Armbian baseline uImage.
# boot.scr loads the file at 0x20800000; bootm then relocates it to 0x208000.
# 0x20800000 is also the value the old OneCloud U-Boot expects for a
# non-relocated image, but staying identical to the known-good baseline
# avoids relying on that path.
"$MKIMAGE" -A arm -O linux -T kernel -C none -a 0x208000 -e 0x208000 \
    -n "Linux-$KREL" -d "$BUILD/arch/arm/boot/zImage" "$ROOT/build/uImage"
"$MKIMAGE" -A arm -O linux -T ramdisk -C gzip -n uInitrd \
    -d "$ROOT/build/initramfs-$KREL.cpio.gz" "$ROOT/build/uInitrd"

echo "kernel artifacts:"
ls -lh "$BUILD/arch/arm/boot/zImage" "$ROOT/build/uImage" "$ROOT/build/uInitrd" \
    "$BUILD/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb"

if [ "${BUILD_UBOOT:-1}" = 1 ] && [ -d "$ROOT/src/u-boot-onecloud" ]; then
    "$ROOT/scripts/build-uboot.sh"
fi

if [ "${PACKAGE:-0}" = 1 ]; then
    "$ROOT/package.sh"
fi
echo "=== build complete $(date -u +%FT%TZ) ==="
