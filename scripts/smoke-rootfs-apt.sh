#!/usr/bin/env bash
# Standalone CI test of ARMHF apt-secure before the 30-minute kernel build.
set -euo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BASE_NAME=Armbian_26.08.0_Onecloud_bookworm_current_6.12.28_minimal
BASE_URL="https://github.com/upleung/armbian-onecloud/releases/download/v2026.08.03-2135/$BASE_NAME.img.xz"
BASE_SHA=cf9ef8e58037eccc51c29b846c5cd9be2fdadea6241323ed3565f4c3096dac20
mkdir -p "$ROOT/baseline" "$ROOT/logs" "$ROOT/tmp"
archive="$ROOT/baseline/$BASE_NAME.img.xz"
part="$ROOT/baseline/part26-root.img"
if [ ! -s "$archive" ]; then
    curl -fL --retry 3 --connect-timeout 20 -o "$archive.part" "$BASE_URL"
    mv "$archive.part" "$archive"
fi
printf '%s  %s\n' "$BASE_SHA" "$archive" | sha256sum -c -
echo "Extract only the 1336 MiB rootfs partition (offset 272 MiB)"
xz -dc "$archive" | dd bs=1M iflag=fullblock skip=272 count=1336 of="$part" status=progress
test "$(stat -c%s "$part")" -eq 1400897536
df -h "$ROOT"
ROOTFS_APT_SMOKE=1 ROOTFS_EXECUTOR=chroot "$ROOT/scripts/update-rootfs.sh"
