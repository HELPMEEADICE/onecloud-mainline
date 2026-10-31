#!/usr/bin/env bash
# Rebuild the OneCloud U-Boot fork with Arm GNU Toolchain 15.2.Rel1.
# The source is taken from a clean git archive of the pinned commit.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC=${UBOOT_SRC:-$ROOT/src/u-boot-onecloud}
BUILD=${UBOOT_BUILD:-$ROOT/build/u-boot-gcc15}
COMMIT=0038d741ed1c77a77570c3a6bf88fe6189c11733
TOOLCHAIN=$ROOT/tools/arm-gnu-toolchain-15.2.rel1-x86_64-arm-none-linux-gnueabihf
OUT=$ROOT/output/uboot
LOG=$ROOT/logs/uboot-build.log
JOBS=${JOBS:-$(nproc)}

[ -d "$SRC/.git" ] || { echo "missing U-Boot git source: $SRC" >&2; exit 1; }
[ -x "$TOOLCHAIN/bin/arm-none-linux-gnueabihf-gcc" ] || { echo "missing toolchain" >&2; exit 1; }
rm -rf "$BUILD"
mkdir -p "$BUILD" "$OUT" "$ROOT/logs"
git -C "$SRC" archive "$COMMIT" | tar -x -C "$BUILD"
for p in "$ROOT"/patches-uboot/*.patch; do
    [ -e "$p" ] || continue
    patch -d "$BUILD" -p1 --silent <"$p"
done
export PATH="$TOOLCHAIN/bin:$ROOT/tools/localroot/usr/bin:$PATH"
{
    echo "=== U-Boot build $(date -u +%FT%TZ) ==="
    echo "source=$SRC commit=$COMMIT toolchain=$TOOLCHAIN"
    cd "$BUILD"
    make distclean >/dev/null 2>&1 || true
    make m8b_onecloud_config
    make -j"$JOBS" CROSS_COMPILE=arm-none-linux-gnueabihf-
} >"$LOG" 2>&1
cp "$BUILD/build/u-boot.bin" "$OUT/u-boot.bin"
cp "$BUILD/build/u-boot-comp.bin" "$OUT/u-boot-comp.bin"
cp "$BUILD/build/ddr_init.bin" "$OUT/ddr_init.bin"
echo "U-Boot artifacts written to $OUT"
ls -lh "$OUT/u-boot.bin" "$OUT/u-boot-comp.bin" "$OUT/ddr_init.bin"
