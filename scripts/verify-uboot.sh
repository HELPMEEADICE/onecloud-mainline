#!/usr/bin/env bash
# Static checks for the optional U-Boot 15.2 experimental burn image.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMG=${1:-$ROOT/output/OneCloud-Linux-7.3.1-armhf-uboot-gcc15.burn.img}
MAIN=${MAIN_IMG:-$ROOT/output/OneCloud-Linux-7.3.1-armhf.burn.img}
AML="$ROOT/tools/AmlImg"
UB="$ROOT/output/uboot"
BASE="$ROOT/baseline/burn-unpacked-26.08"
TMP=$(mktemp -d "$ROOT/tmp/verify-uboot.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
fail=0
ok() { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }
"$AML" unpack "$IMG" "$TMP/unpack" >/dev/null
"$AML" unpack "$MAIN" "$TMP/main" >/dev/null

cmp -s "$TMP/unpack/1.UBOOT_COMP.USB" "$UB/u-boot-comp.bin" && ok "UBOOT_COMP is 15.2 build" || bad "UBOOT_COMP mismatch"
cmp -s "$TMP/unpack/4.bootloader.PARTITION" "$UB/u-boot.bin" && ok "bootloader is 15.2 build" || bad "bootloader mismatch"
want="sha1sum $(sha1sum "$UB/u-boot.bin" | cut -d' ' -f1)"
[ "$(cat "$TMP/unpack/5.bootloader.VERIFY")" = "$want" ] && ok "bootloader VERIFY sha1" || bad "bootloader VERIFY"
for f in 0.DDR.USB 2.aml_sdc_burn.ini 3.platform.conf 6.resource.PARTITION 7.resource.VERIFY; do
    cmp -s "$TMP/unpack/$f" "$BASE/$f" && ok "$f unchanged" || bad "$f changed"
done
for f in 8.boot.PARTITION.sparse 9.boot.VERIFY 10.rootfs.PARTITION.sparse 11.rootfs.VERIFY; do
    cmp -s "$TMP/unpack/$f" "$TMP/main/$f" && ok "$f matches main" || bad "$f differs from main"
done
"$AML" pack "$TMP/repack.img" "$TMP/unpack" >/dev/null
cmp -s "$TMP/repack.img" "$IMG" && ok "AmlImg repack byte-identical" || bad "repack differs"
[ "$(stat -c%s "$IMG")" -lt 8589934592 ] && ok "image < 8 GB eMMC" || bad "image too large"
[ "$fail" = 0 ] && echo "== U-Boot experimental image: all checks passed =="
exit "$fail"
