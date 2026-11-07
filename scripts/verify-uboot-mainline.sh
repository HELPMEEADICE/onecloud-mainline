#!/usr/bin/env bash
# Static checks for the experimental mainline-U-Boot OneCloud image.
#
# The image keeps the known-good vendor SPL/DDR firmware (the first 32 KiB of
# 4.bootloader.PARTITION) and the baseline 1.UBOOT_COMP.USB, and replaces only
# the U-Boot proper payload with a mainline v2026.10 build.  The vendor SPL
# checks for the word 0x12345678 at offset 60 of the decompressed payload, so
# the payload is validated for that magic as well.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMG=${1:-$ROOT/output/OneCloud-Linux-7.3.1-armhf-uboot-mainline.burn.img}
MAIN=${MAIN_IMG:-$ROOT/output/OneCloud-Linux-7.3.1-armhf.burn.img}
AML="$ROOT/tools/AmlImg"
UB="$ROOT/output/uboot-mainline"
BASE="$ROOT/baseline/burn-unpacked-26.08"
TMP=$(mktemp -d "$ROOT/tmp/verify-uboot-mainline.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
fail=0
ok() { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

[ -f "$IMG" ] || { echo "missing $IMG" >&2; exit 1; }
[ -f "$MAIN" ] || { echo "missing $MAIN" >&2; exit 1; }
[ -s "$UB/u-boot-dtb.bin" ] || { echo "missing $UB/u-boot-dtb.bin" >&2; exit 1; }
"$AML" unpack "$IMG" "$TMP/unpack" >/dev/null
"$AML" unpack "$MAIN" "$TMP/main" >/dev/null

# The USB recovery path must stay on the known-good baseline.
cmp -s "$TMP/unpack/1.UBOOT_COMP.USB" "$BASE/1.UBOOT_COMP.USB" && \
    ok "UBOOT_COMP stays on baseline" || bad "UBOOT_COMP differs from baseline"

# Only the payload-size fields in the vendor SPL header may differ.  The SPL
# code, the 0x12345678 check and the ROM checksum must stay byte-identical.
head -c 32768 "$TMP/unpack/4.bootloader.PARTITION" >"$TMP/spl.bin"
head -c 32768 "$BASE/4.bootloader.PARTITION" >"$TMP/base-spl.bin"
if cmp -s "$TMP/spl.bin" "$TMP/base-spl.bin"; then
    ok "bootloader SPL/DDR firmware from baseline"
elif cmp -l "$TMP/spl.bin" "$TMP/base-spl.bin" 2>/dev/null | \
     awk '{ o=$1; if (!((o>=32225 && o<=32232))) { print; bad=1 } } END { exit bad }'; then
    ok "bootloader SPL/DDR firmware from baseline"
else
    bad "bootloader SPL differs outside the payload size fields"
fi

# The payload must be the mainline build and carry the vendor SPL magic.
tail -c +32769 "$TMP/unpack/4.bootloader.PARTITION" >"$TMP/payload.bin"
cmp -s "$TMP/payload.bin" "$UB/u-boot-comp.bin" && \
    ok "bootloader payload is the mainline build" || bad "bootloader payload mismatch"
want="sha1sum $(sha1sum "$TMP/unpack/4.bootloader.PARTITION" | cut -d' ' -f1)"
[ "$(cat "$TMP/unpack/5.bootloader.VERIFY")" = "$want" ] && \
    ok "bootloader VERIFY sha1" || bad "bootloader VERIFY"

"$ROOT/build/u-boot-gcc15/build/tools/uclpack" -d "$TMP/payload.bin" "$TMP/decomp.bin" >/dev/null
cmp -s "$TMP/decomp.bin" "$UB/u-boot-dtb.bin" && \
    ok "payload decompresses to u-boot-dtb.bin" || bad "payload decompression mismatch"
magic=$(python3 - "$TMP/decomp.bin" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read(64)
print(d[60:64].hex())
PY
)
[ "$magic" = "78563412" ] && \
    ok "vendor SPL magic at offset 60" || bad "missing vendor SPL magic (got $magic)"

for f in 0.DDR.USB 2.aml_sdc_burn.ini 3.platform.conf 6.resource.PARTITION 7.resource.VERIFY; do
    cmp -s "$TMP/unpack/$f" "$BASE/$f" && ok "$f unchanged" || bad "$f changed"
done
for f in 8.boot.PARTITION.sparse 9.boot.VERIFY 10.rootfs.PARTITION.sparse 11.rootfs.VERIFY; do
    cmp -s "$TMP/unpack/$f" "$TMP/main/$f" && ok "$f matches main" || bad "$f differs from main"
done

# The build configuration must keep the port and the bootm limits in place.
cfg="$UB/onecloud_defconfig.final"
for opt in CONFIG_MESON_M8B=y CONFIG_MMC_MESON_MX_SDIO=y CONFIG_MESON6_TIMER=y \
           CONFIG_MESON_SERIAL=y CONFIG_SYS_BOOTM_LEN=0x02000000; do
    grep -qx "$opt" "$cfg" && ok "config $opt" || bad "config missing: $opt"
done

"$AML" pack "$TMP/repack.img" "$TMP/unpack" >/dev/null
cmp -s "$TMP/repack.img" "$IMG" && ok "AmlImg repack byte-identical" || bad "repack differs"
[ "$(stat -c%s "$IMG")" -lt 8589934592 ] && ok "image < 8 GB eMMC" || bad "image too large"
[ "$fail" = 0 ] && echo "== mainline U-Boot image: all checks passed =="
exit "$fail"
