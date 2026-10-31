#!/usr/bin/env bash
# Static verification of the OneCloud Linux 7.3.1 deliverables.
# This never touches a block device and never mounts an image read-write.
set -uo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ ! -d "$ROOT/src" ] && [ -d "$ROOT/../src" ]; then ROOT=$(CDPATH= cd -- "$ROOT/.." && pwd); fi
KVER=${KVER:-7.3.1}
KREL=${KREL:-${KVER}-onecloud}
KERNEL_BUILD=${KERNEL_BUILD:-$ROOT/build/linux-$KVER-gcc15}
OUT="$ROOT/output"
IMG="$OUT/OneCloud-Linux-$KVER-armhf.img"
BURN="$OUT/OneCloud-Linux-$KVER-armhf.burn.img"
KERNEL="$OUT/kernel"
KERNELRELEASE_FILE="$KERNEL_BUILD/include/config/kernel.release"
mkdir -p "$ROOT/tmp"
TMP=$(mktemp -d "$ROOT/tmp/verify.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
ok()   { PASS=$((PASS+1)); printf '  OK   %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$*"; }
check(){ if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
section(){ printf '\n== %s ==\n' "$*"; }

section "artifacts and checksums"
for f in "$IMG" "$BURN" "$IMG.xz" "$BURN.xz" "$KERNEL/zImage" "$KERNEL/uImage" \
         "$KERNEL/uInitrd" "$KERNEL/meson8b-onecloud.dtb" \
         "$KERNEL/config-$KREL" "$KERNEL/System.map-$KREL" \
         "$OUT/modules/modules-$KREL.tar.xz" "$OUT/SHA256SUMS"; do
    [ -s "$f" ] && ok "exists $(basename "$f")" || bad "missing $(basename "$f")"
done
if [ -s "$OUT/SHA256SUMS" ]; then
    ( cd "$OUT" && sha256sum -c SHA256SUMS ) >"$TMP/sha.log" 2>&1 && ok "SHA256SUMS" || bad "SHA256SUMS"
fi
if [ -s "$IMG.xz" ]; then
    xz -t "$IMG.xz" && ok "img.xz integrity" || bad "img.xz integrity"
    xz -t "$BURN.xz" && ok "burn.img.xz integrity" || bad "burn.img.xz integrity"
fi

section "kernel identity and architecture"
check "zImage is ARM zImage" "file '$KERNEL/zImage' | grep -q 'Linux kernel ARM boot executable zImage'"
check "uImage is ARM Linux kernel" "tools/localroot/usr/bin/mkimage -l '$KERNEL/uImage' | grep -q 'ARM Linux Kernel Image'"
check "uImage load address 0x208000" "tools/localroot/usr/bin/mkimage -l '$KERNEL/uImage' | grep -q 'Load Address: 00208000'"
check "uInitrd is ARM ramdisk" "tools/localroot/usr/bin/mkimage -l '$KERNEL/uInitrd' | grep -q 'ARM Linux RAMDisk Image'"
if [ -f "$KERNELRELEASE_FILE" ]; then
    [ "$(cat "$KERNELRELEASE_FILE")" = "$KREL" ] && ok "kernelrelease=$KREL" || bad "kernelrelease mismatch"
fi
check "Local version -onecloud" "grep -q '^CONFIG_LOCALVERSION=\"-onecloud\"' '$KERNEL/config-$KREL'"

section "kernel configuration"
while read -r sym; do
    case "$sym" in
        NVMEM_MESON_MX_EFUSE|MESON_MX_SOCINFO|MESON_WATCHDOG|MESON_SARADC) want='[ym]' ;;
        USB_STORAGE|DRM_LIMA) want='[ym]' ;;
        *) want='y' ;;
    esac
    check "CONFIG_$sym=$want" "grep -Eq '^CONFIG_$sym=$want$' '$KERNEL/config-$KREL'"
done <<'EOF'
ARCH_MESON
MACH_MESON8
SMP
PINCTRL_MESON8B
COMMON_CLK_MESON8B
MMC_MESON_MX_SDHC
MMC_MESON_MX_SDIO
MMC_BLOCK
PWRSEQ_EMMC
EXT4_FS
SERIAL_MESON_CONSOLE
DWMAC_MESON
REALTEK_PHY
PHY_MESON8B_USB2
USB_DWC2
USB_STORAGE
REGULATOR_PWM
PWM_MESON
CPUFREQ_DT
DRM_LIMA
NVMEM_MESON_MX_EFUSE
MESON_MX_SOCINFO
MESON_WATCHDOG
DEVTMPFS_MOUNT
BLK_DEV_INITRD
EOF

section "device tree"
DTC="$KERNEL_BUILD/scripts/dtc/dtc"
[ -x "$DTC" ] || DTC=$(command -v dtc || true)
if [ -n "$DTC" ]; then
    "$DTC" -I dtb -O dts "$KERNEL/meson8b-onecloud.dtb" -o "$TMP/onecloud.dts" 2>"$TMP/dtc.err"
    # The legacy "/memory" node intentionally triggers a dtc
    # unit_address_vs_reg warning; only the resulting DTS matters.
    check "dtc decompile" "test -s '$TMP/onecloud.dts'"
    check "model Xunlei OneCloud" "grep -q 'model = \"Xunlei OneCloud\"' '$TMP/onecloud.dts'"
    check "compatible xunlei,onecloud" "grep -q 'compatible = \"xunlei,onecloud\"' '$TMP/onecloud.dts'"
    check "legacy /memory node for U-Boot fixup" "grep -q '^	memory {' '$TMP/onecloud.dts'"
    check "no memory@40000000 node" "! grep -q 'memory@40000000' '$TMP/onecloud.dts'"
    check "/memory reg 1 GiB at 0x40000000" "grep -A4 '^	memory {' '$TMP/onecloud.dts' | grep -q 'reg = <0x40000000 0x40000000>'"
    check "eMMC sdhc enabled" "grep -A10 'mmc@8e00' '$TMP/onecloud.dts' | grep -q 'status = \"okay\"'"
    check "SDIO enabled" "grep -A10 'mmc@8c20' '$TMP/onecloud.dts' | grep -q 'status = \"okay\"'"
    check "Ethernet enabled" "grep -A20 'ethernet@c9410000' '$TMP/onecloud.dts' | grep -q 'status = \"okay\"'"
    check "USB0 OTG with host role switch" "grep -A24 'usb@c9040000' '$TMP/onecloud.dts' | grep -q 'dr_mode = \"otg\"' && grep -A24 'usb@c9040000' '$TMP/onecloud.dts' | grep -q 'usb-role-switch' && grep -A24 'usb@c9040000' '$TMP/onecloud.dts' | grep -q 'role-switch-default-mode = \"host\"'"
    check "USB1 host" "grep -A14 'usb@c90c0000' '$TMP/onecloud.dts' | grep -q 'dr_mode = \"host\"'"
    check "PWM C/D enabled" "grep -A8 'pwm@8650' '$TMP/onecloud.dts' | grep -q 'status = \"okay\"'"
    check "serial0 console" "grep -A3 'chosen' '$TMP/onecloud.dts' | grep -q 'stdout-path = \"serial0:115200n8\"'"
    check "Mali-450 GPU node" "grep -A8 'gpu@c0000' '$TMP/onecloud.dts' | grep -q 'arm,mali-450'"
    check "Mali GPU node enabled" "! grep -A20 'gpu@c0000' '$TMP/onecloud.dts' | grep -q 'status = \"disabled\"'"
else
    bad "no dtc available"
fi

section "modules and rootfs"
check "module tree present" "test -d '$ROOT/rootfs/modules-full/lib/modules/$KREL'"
check "modules.dep present" "test -s '$ROOT/rootfs/modules-full/lib/modules/$KREL/modules.dep'"
check "modules.alias present" "test -s '$ROOT/rootfs/modules-full/lib/modules/$KREL/modules.alias'"
check "lima GPU module present" "find '$ROOT/rootfs/modules-full/lib/modules/$KREL' -path '*/gpu/drm/lima/lima.ko*' | grep -q ."
MOD=$(find "$ROOT/rootfs/modules-full/lib/modules/$KREL" -name 'usb-storage.ko*' | head -1)
if [ -n "$MOD" ]; then
    check "usb-storage vermagic" "modinfo -F vermagic '$MOD' | grep -q '^$KREL '"
else
    bad "usb-storage module missing"
fi
check "rootfs ext4 clean" "e2fsck -fn '$ROOT/rootfs/onecloud-rootfs.ext4'"
check "rootfs Debian bookworm" "debugfs -R 'cat /etc/os-release' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'VERSION_CODENAME=bookworm'"
check "rootfs systemd present" "debugfs -R 'stat /lib/systemd/systemd' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'regular'"
check "rootfs module path" "debugfs -R 'stat /lib/modules/$KREL/kernel/drivers/usb/storage/usb-storage.ko' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'Size:'"
check "rootfs module database" "debugfs -R 'stat /lib/modules/$KREL/modules.dep' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'Size:'"
check "rootfs loads lima at boot" "debugfs -R 'cat /etc/modules-load.d/onecloud.conf' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -qx lima"
check "rootfs eth0 DHCP" "debugfs -R 'cat /etc/systemd/network/10-ethernet.network' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'DHCP=yes'"
debugfs -R "dump /lib/systemd/systemd $TMP/systemd" "$ROOT/rootfs/onecloud-rootfs.ext4" >/dev/null 2>&1
check "rootfs systemd is ARM EABI5" "file '$TMP/systemd' | grep -q 'ELF 32-bit LSB.*ARM.*EABI5'"
check "rootfs fstab UUID" "debugfs -R 'cat /etc/fstab' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'UUID=8a03b678-0b46-4f41-bb09-3a2d154439bc / ext4'"

check "Mesa lima_dri.so installed" "debugfs -R 'stat /usr/lib/arm-linux-gnueabihf/dri/lima_dri.so' '$ROOT/rootfs/onecloud-rootfs.ext4' 2>/dev/null | grep -q 'Inode:'"

section "boot partition"
BOOT="$ROOT/rootfs/onecloud-boot.vfat"
check "FAT filesystem" "file '$BOOT' | grep -q 'FAT'"
check "boot FAT UUID preserved" "blkid -p '$BOOT' 2>/dev/null | grep -q 'UUID=\"F937-F6E8\"'"
check "uImage in boot FAT" "tools/localroot/usr/bin/mdir -i '$BOOT' ::/ 2>/dev/null | grep -q 'uImage'"
check "uInitrd in boot FAT" "tools/localroot/usr/bin/mdir -i '$BOOT' ::/ 2>/dev/null | grep -q 'uInitrd'"
check "onecloud DTB in boot FAT" "tools/localroot/usr/bin/mdir -i '$BOOT' ::/dtb 2>/dev/null | grep -q 'meson8b-onecloud.dtb'"
tools/localroot/usr/bin/mtype -i "$BOOT" ::/armbianEnv.txt >"$TMP/armbianEnv.txt" 2>/dev/null
check "armbianEnv root UUID" "grep -q 'rootdev=UUID=8a03b678-0b46-4f41-bb09-3a2d154439bc' '$TMP/armbianEnv.txt'"
tools/localroot/usr/bin/mtype -i "$BOOT" ::/boot.scr >"$TMP/boot.scr" 2>/dev/null
check "boot.scr is U-Boot script" "tools/localroot/usr/bin/mkimage -l '$TMP/boot.scr' | grep -q 'ARM Linux Script'"
tools/localroot/usr/bin/dumpimage -T script -o "$TMP/boot-script" "$TMP/boot.scr" >/dev/null 2>&1
check "boot.scr loads uImage" "grep -aq 'fatload.*uImage' '$TMP/boot-script'"
check "boot.scr loads uInitrd" "grep -aq 'fatload.*uInitrd' '$TMP/boot-script'"
check "boot.scr loads onecloud dtb" "grep -aq 'fatload.*meson8b-onecloud.dtb' '$TMP/boot-script'"
check "boot.scr bootm triplet" "grep -aq 'bootm 0x20800000 0x22000000 0x21800000' '$TMP/boot-script'"

section "normal disk image"
check "MBR partition table" "sfdisk -d '$IMG' 2>/dev/null | grep -q 'label: dos'"
check "boot starts at sector 32768" "sfdisk -d '$IMG' 2>/dev/null | grep -q 'start=       32768, size=      524288'"
check "rootfs starts at sector 557056" "sfdisk -d '$IMG' 2>/dev/null | grep -q 'start=      557056, size=     2736128'"
check "boot partition UUID" "blkid -p -O 16M '$IMG' 2>/dev/null | grep -q 'UUID=\"F937-F6E8\"'"
check "rootfs partition UUID" "blkid -p -O 272M '$IMG' 2>/dev/null | grep -q 'UUID=\"8a03b678-0b46-4f41-bb09-3a2d154439bc\"'"
check "normal boot bytes" "cmp -i 16777216:0 -n 268435456 '$IMG' '$BOOT'"
check "normal rootfs bytes" "cmp -i 285212672:0 -n 1400897536 '$IMG' '$ROOT/rootfs/onecloud-rootfs.ext4'"

section "Amlogic burn image"
if "$ROOT/tools/AmlImg" unpack "$BURN" "$TMP/burn" >"$TMP/unpack.log" 2>&1; then
    ok "AmlImg unpack"
    check "manifest order" "diff -q '$TMP/burn/commands.txt' '$ROOT/baseline/burn-unpacked-26.08/commands.txt'"
    check "boot sparse manifest" "grep -q '^PARTITION:boot:sparse:' '$TMP/burn/commands.txt'"
    check "rootfs sparse manifest" "grep -q '^PARTITION:rootfs:sparse:' '$TMP/burn/commands.txt'"
    for f in 0.DDR.USB 1.UBOOT_COMP.USB 2.aml_sdc_burn.ini 3.platform.conf 4.bootloader.PARTITION 6.resource.PARTITION; do
        check "$f unchanged" "cmp -s '$TMP/burn/$f' '$ROOT/baseline/burn-unpacked-26.08/$f'"
    done
    check "boot VERIFY sha1" "test \"\$(cat '$TMP/burn/9.boot.VERIFY')\" = \"sha1sum \$(sha1sum '$TMP/burn/8.boot.PARTITION.sparse' | cut -d' ' -f1)\""
    check "rootfs VERIFY sha1" "test \"\$(cat '$TMP/burn/11.rootfs.VERIFY')\" = \"sha1sum \$(sha1sum '$TMP/burn/10.rootfs.PARTITION.sparse' | cut -d' ' -f1)\""
    "$ROOT/tools/localroot/usr/bin/simg2img" "$TMP/burn/8.boot.PARTITION.sparse" "$TMP/boot.raw"
    "$ROOT/tools/localroot/usr/bin/simg2img" "$TMP/burn/10.rootfs.PARTITION.sparse" "$TMP/rootfs.raw"
    check "boot sparse expands to original" "cmp -s '$TMP/boot.raw' '$BOOT'"
    check "rootfs sparse expands to original" "cmp -s '$TMP/rootfs.raw' '$ROOT/rootfs/onecloud-rootfs.ext4'"
    BOOT_RAW_SIZE=$(stat -c%s "$TMP/boot.raw")
    ROOTFS_RAW_SIZE=$(stat -c%s "$TMP/rootfs.raw")
    check "boot sparse size 256 MiB" "test $BOOT_RAW_SIZE -eq 268435456"
    check "rootfs sparse size 1336 MiB" "test $ROOTFS_RAW_SIZE -eq 1400897536"
    if "$ROOT/tools/AmlImg" pack "$TMP/repacked.burn.img" "$TMP/burn" >"$TMP/repack.log" 2>&1; then
        check "AmlImg repack byte-identical" "cmp -s '$TMP/repacked.burn.img' '$BURN'"
    else
        bad "AmlImg repack"
    fi
else
    bad "AmlImg unpack"
fi

section "capacity and patch reproducibility"
BURN_SIZE=$(stat -c%s "$BURN" 2>/dev/null || echo 0)
IMG_SIZE=$(stat -c%s "$IMG" 2>/dev/null || echo 0)
check "burn image < 8 GB eMMC" "test $BURN_SIZE -lt 8000000000"
check "normal image < 8 GB eMMC" "test $IMG_SIZE -lt 8000000000"
printf '  burn image: %s bytes (%.2f GiB)\n' "$BURN_SIZE" "$(awk -v s="$BURN_SIZE" 'BEGIN{print s/1073741824}')"
printf '  disk image: %s bytes (%.2f GiB)\n' "$IMG_SIZE" "$(awk -v s="$IMG_SIZE" 'BEGIN{print s/1073741824}')"
if [ ! -f "$ROOT/tmp/upstream/arch/arm/boot/dts/amlogic/Makefile" ]; then
    mkdir -p "$ROOT/tmp/upstream/arch/arm/boot/dts/amlogic" "$ROOT/tmp/upstream/Documentation/devicetree/bindings"
    tar -xOf "$ROOT/tools/linux-$KVER.tar.xz" "linux-$KVER/arch/arm/boot/dts/amlogic/Makefile" >"$ROOT/tmp/upstream/arch/arm/boot/dts/amlogic/Makefile"
    tar -xOf "$ROOT/tools/linux-$KVER.tar.xz" "linux-$KVER/Documentation/devicetree/bindings/vendor-prefixes.yaml" >"$ROOT/tmp/upstream/Documentation/devicetree/bindings/vendor-prefixes.yaml"
fi
mkdir -p "$TMP/pristine/arch/arm/boot/dts/amlogic" "$TMP/pristine/Documentation/devicetree/bindings"
cp "$ROOT/tmp/upstream/arch/arm/boot/dts/amlogic/Makefile" "$TMP/pristine/arch/arm/boot/dts/amlogic/Makefile" 2>/dev/null || true
cp "$ROOT/tmp/upstream/Documentation/devicetree/bindings/vendor-prefixes.yaml" "$TMP/pristine/Documentation/devicetree/bindings/vendor-prefixes.yaml" 2>/dev/null || true
if patch -d "$TMP/pristine" -p1 --silent <"$ROOT/patches/0001-ARM-dts-meson8b-add-Xunlei-OneCloud.patch" 2>/dev/null \
   && patch -d "$TMP/pristine" -p1 --silent <"$ROOT/patches/0002-dt-bindings-vendor-prefixes-add-xunlei.patch" 2>/dev/null; then
    ok "patches apply to pristine 7.3.1 files"
else
    bad "patches do not apply"
fi

printf '\n== result: %d passed, %d failed ==\n' "$PASS" "$FAIL"
echo "NOTE: this is static verification only; no OneCloud hardware was used."
[ "$FAIL" -eq 0 ]
