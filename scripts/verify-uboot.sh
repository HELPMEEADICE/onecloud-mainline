#!/usr/bin/env bash
# Static checks for the optional GCC15 U-Boot payload experimental image.
#
# The variant keeps the known-good baseline SPL/DDR firmware (first 32 KiB of
# 4.bootloader.PARTITION) and the baseline 1.UBOOT_COMP.USB, and replaces only
# the U-Boot proper payload with the binary rebuilt by Arm GNU Toolchain 15.2.
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
[ -f "$MAIN" ] || { echo "missing $MAIN" >&2; exit 1; }
"$AML" unpack "$IMG" "$TMP/unpack" >/dev/null
"$AML" unpack "$MAIN" "$TMP/main" >/dev/null

# 1.UBOOT_COMP.USB is used by the USB burning tool before flashing.  Keep the
# known-good baseline copy so a broken experiment can always be re-flashed.
cmp -s "$TMP/unpack/1.UBOOT_COMP.USB" "$BASE/1.UBOOT_COMP.USB" && \
    ok "UBOOT_COMP stays on baseline" || bad "UBOOT_COMP differs from baseline"

# The experiment replaces only the U-Boot proper payload.  The first 32 KiB
# (SPL + DDR init + header) must match the baseline except for the two header
# fields that describe the new payload size (the checksum is not affected).
head -c 32768 "$TMP/unpack/4.bootloader.PARTITION" >"$TMP/spl.bin"
head -c 32768 "$BASE/4.bootloader.PARTITION" >"$TMP/base-spl.bin"
if cmp -s "$TMP/spl.bin" "$TMP/base-spl.bin"; then
    ok "bootloader SPL/DDR firmware from baseline"
elif cmp -l "$TMP/spl.bin" "$TMP/base-spl.bin" 2>/dev/null | \
     awk '{ o=$1; if (!((o>=441 && o<=448) || (o>=32225 && o<=32232))) { print; bad=1 } } END { exit bad }'; then
    ok "bootloader SPL/DDR firmware from baseline"
else
    bad "bootloader SPL differs outside header size fields"
fi
tail -c +32769 "$TMP/unpack/4.bootloader.PARTITION" >"$TMP/payload.bin"
cmp -s "$TMP/payload.bin" "$UB/u-boot-comp.bin" && \
    ok "bootloader payload is the GCC15 build" || bad "bootloader payload mismatch"
want="sha1sum $(sha1sum "$TMP/unpack/4.bootloader.PARTITION" | cut -d' ' -f1)"
[ "$(cat "$TMP/unpack/5.bootloader.VERIFY")" = "$want" ] && \
    ok "bootloader VERIFY sha1" || bad "bootloader VERIFY"

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
