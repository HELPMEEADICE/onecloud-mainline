#!/usr/bin/env bash
# Fast structural packaging test. Uses fake kernel objects; never flashes or mounts.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST=$(mktemp -d)
trap 'rm -rf "$TEST"' EXIT
REPO="$TEST/repo"
KVER=7.3.1
KREL="$KVER-onecloud"
mkdir -p "$REPO/scripts" "$REPO/tmp" "$REPO/build/linux-$KVER-gcc15/arch/arm/boot/dts/amlogic" \
         "$REPO/build/linux-$KVER-gcc15/arch/arm/boot" "$REPO/rootfs/modules-full/lib/modules/$KREL/kernel" \
         "$REPO/config"
cp "$ROOT/scripts/"{activate-kernel.sh,build-upgrade-packages.sh,verify-upgrade-packages.sh} "$REPO/scripts/"
printf 'module dep\n' > "$REPO/rootfs/modules-full/lib/modules/$KREL/modules.dep"
printf 'module alias\n' > "$REPO/rootfs/modules-full/lib/modules/$KREL/modules.alias"
printf 'dummy module\n' > "$REPO/rootfs/modules-full/lib/modules/$KREL/kernel/test.ko"
printf 'uImage test\n' > "$REPO/build/uImage"
printf 'initrd test\n' > "$REPO/build/uInitrd"
printf 'kernel test\n' > "$REPO/build/linux-$KVER-gcc15/arch/arm/boot/zImage"
printf 'device-tree test\n' > "$REPO/build/linux-$KVER-gcc15/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb"
printf 'System.map test\n' > "$REPO/build/linux-$KVER-gcc15/System.map"
printf 'config test\n' > "$REPO/config/onecloud-$KVER.config"
KVER="$KVER" bash "$REPO/scripts/build-upgrade-packages.sh"
KVER="$KVER" bash "$REPO/scripts/verify-upgrade-packages.sh"
echo "Synthetic Debian and Arch package smoke test passed."
