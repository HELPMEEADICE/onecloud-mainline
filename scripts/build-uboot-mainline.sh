#!/usr/bin/env bash
# Build mainline U-Boot v2026.10 for the Xunlei OneCloud (Amlogic S805 /
# Meson8b) and package it as a U-Boot proper payload for the working vendor
# SPL/DDR firmware.
#
# The SPL and DDR training code are deliberately kept from the Armbian/vendor
# baseline: mainline U-Boot has no Meson8b SPL/DDR support, and the vendor
# 2011.03 SPL is the only known-good way to bring up this board's DRAM.
#
# Environment:
#   UBOOT_VER=v2026.10     mainline U-Boot tag to build
#   JOBS=n                 parallel make jobs (default: nproc)
#   SKIP_DOWNLOAD=0        fail instead of downloading/cloning the source
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
UBOOT_VER=${UBOOT_VER:-v2026.10}
UBOOT_REPO=${UBOOT_REPO:-https://github.com/u-boot/u-boot.git}
SRC=${UBOOT_SRC:-$ROOT/src/u-boot-mainline-$UBOOT_VER}
BUILD=${UBOOT_BUILD:-$ROOT/build/u-boot-mainline}
OUT=${UBOOT_OUT:-$ROOT/output/uboot-mainline}
LOG=$ROOT/logs/uboot-mainline-build.log
TOOLCHAIN=$ROOT/tools/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
VENDOR_BUILD=$ROOT/build/u-boot-gcc15
VENDOR_TOOLS=$VENDOR_BUILD/build/tools
BURN_UNPACKED=$ROOT/baseline/burn-unpacked-26.08
BASELINE_BURN=$(ls "$ROOT"/baseline/Armbian_26.08.0_Onecloud_*.burn.img 2>/dev/null | head -1 || true)
JOBS=${JOBS:-$(nproc)}

die() { echo "ERROR: $*" >&2; exit 1; }

[ -x "$TOOLCHAIN/bin/arm-none-linux-gnueabihf-gcc" ] || \
    die "missing toolchain: $TOOLCHAIN"
[ -f "$ROOT/patches-uboot-mainline/0001-mainline-uboot-meson8b-onecloud.patch" ] || \
    die "missing mainline U-Boot patch"

mkdir -p "$ROOT/src" "$ROOT/build" "$ROOT/logs" "$OUT"

if [ ! -d "$SRC/.git" ]; then
    [ "${SKIP_DOWNLOAD:-0}" = 1 ] && die "missing U-Boot source: $SRC"
    echo "cloning U-Boot $UBOOT_VER into $SRC"
    git clone --depth 1 --branch "$UBOOT_VER" "$UBOOT_REPO" "$SRC"
fi

# Refresh the source only when the patch set changed.  This keeps repeated
# builds fast while making patch edits deterministic.
PATCH_STAMP="$SRC/.onecloud-mainline-patches.sha256"
patch_set_sha() {
    cat "$ROOT"/patches-uboot-mainline/*.patch | sha256sum | cut -d' ' -f1
}
if [ -f "$PATCH_STAMP" ] && [ "$(cat "$PATCH_STAMP")" = "$(patch_set_sha)" ]; then
    echo "mainline U-Boot patch stack already applied (stamp matches)"
else
    echo "restoring pristine $UBOOT_VER and applying patches"
    git -C "$SRC" checkout -- .
    git -C "$SRC" clean -fdx >/dev/null
    for p in "$ROOT"/patches-uboot-mainline/*.patch; do
        [ -e "$p" ] || continue
        echo "apply $(basename "$p")"
        patch -d "$SRC" -p1 --silent <"$p"
    done
    patch_set_sha >"$PATCH_STAMP"
fi

# The vendor U-Boot build provides the host-side uclpack/convert utilities.
if [ ! -x "$VENDOR_TOOLS/uclpack" ] || [ ! -x "$VENDOR_TOOLS/convert" ]; then
    echo "building vendor U-Boot host tools first"
    "$ROOT/scripts/build-uboot.sh"
fi

if [ ! -f "$BURN_UNPACKED/4.bootloader.PARTITION" ]; then
    [ -n "$BASELINE_BURN" ] || \
        die "missing baseline burn image and unpacked baseline"
    echo "unpacking baseline burn image"
    "$ROOT/tools/AmlImg" unpack "$BASELINE_BURN" "$BURN_UNPACKED"
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

export PATH="$TOOLCHAIN/bin:$ROOT/tools/localroot/usr/bin:$PATH"
{
    echo "=== mainline U-Boot build $(date -u +%FT%TZ) ==="
    echo "source=$SRC version=$UBOOT_VER toolchain=$TOOLCHAIN"
    make -C "$SRC" O="$BUILD" onecloud_defconfig
    make -C "$SRC" O="$BUILD" -j"$JOBS" CROSS_COMPILE=arm-none-linux-gnueabihf-
} >"$LOG" 2>&1

cp -f "$BUILD/u-boot-dtb.bin" "$OUT/u-boot-dtb.bin"
cp -f "$BUILD/u-boot.bin" "$OUT/u-boot.bin"
cp -f "$BUILD/u-boot.dtb" "$OUT/u-boot.dtb"
cp -f "$BUILD/System.map" "$OUT/System.map"
cp -f "$BUILD/.config" "$OUT/onecloud_defconfig.final"

# The U-Boot proper image must carry the Amlogic vendor SPL's magic word at
# offset 60 (the first padding word after the ARM exception vectors).
python3 - "$OUT/u-boot-dtb.bin" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read(64)
if data[60:64] != bytes.fromhex('78563412'):
    sys.exit("u-boot-dtb.bin is missing the vendor SPL magic at offset 60")
PY

# Keep the SPL (first 32 KiB of the baseline bootloader partition) untouched.
head -c 32768 "$BURN_UNPACKED/4.bootloader.PARTITION" >"$OUT/baseline-spl.bin"
"$VENDOR_TOOLS/uclpack" "$OUT/u-boot-dtb.bin" "$OUT/u-boot-comp.bin" >/dev/null
"$VENDOR_TOOLS/convert" --soc m8b \
    -s "$OUT/baseline-spl.bin" \
    -i "$OUT/u-boot-comp.bin" \
    -o "$OUT/u-boot-hybrid-mainline.bin"

ls -lh "$OUT/u-boot-dtb.bin" "$OUT/u-boot-comp.bin" \
    "$OUT/u-boot-hybrid-mainline.bin"
echo "mainline U-Boot artifacts written to $OUT"
