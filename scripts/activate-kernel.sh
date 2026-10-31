#!/usr/bin/env bash
# Activate an installed OneCloud kernel package without touching the bootloader.
# Called by dpkg postinst or pacman post_install/post_upgrade, as root.
set -euo pipefail

fail() { printf 'OneCloud kernel activation: %s\n' "$*" >&2; exit 1; }

[[ "${1:-}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?-onecloud$ ]] || fail "invalid kernel release"
KREL=$1
SRC="/usr/lib/onecloud-kernel/$KREL"
BOOT=/boot

[ "$(id -u)" -eq 0 ] || fail "root privileges required"
[ -r /proc/device-tree/compatible ] || fail "no device tree; install on a running OneCloud system"
grep -aq 'xunlei,onecloud' /proc/device-tree/compatible || fail "not a Xunlei OneCloud; refusing to replace boot files"
[ -L /lib ] && [ "$(readlink -f /lib)" = /usr/lib ] || fail "requires a merged-/usr distribution (/lib -> /usr/lib)"
[ -d "/lib/modules/$KREL" ] || fail "kernel modules missing: /lib/modules/$KREL"
for f in uImage uInitrd meson8b-onecloud.dtb SHA256SUMS; do
    [ -s "$SRC/$f" ] || fail "missing package payload $SRC/$f"
done
[ -f "$BOOT/boot.scr" ] && [ -f "$BOOT/armbianEnv.txt" ] || fail "expected OneCloud legacy boot.scr/armbianEnv.txt in /boot"
[ -d "$BOOT/dtb" ] || fail "expected /boot/dtb directory"

command -v findmnt >/dev/null || fail "findmnt (util-linux) required"
[ "$(findmnt -n -o TARGET -T "$BOOT")" = "$BOOT" ] || fail "/boot is not a separate mounted partition"
case "$(findmnt -n -o FSTYPE -T "$BOOT")" in
    vfat|msdos) ;;
    *) fail "expected FAT boot partition at /boot" ;;
esac
[ -w "$BOOT" ] || fail "/boot is read-only"
command -v depmod >/dev/null || fail "depmod (kmod) required"

# Validate the exact objects embedded in the package before changing boot.
(cd "$SRC" && sha256sum -c SHA256SUMS) || fail "payload checksum mismatch"
# Validate kernel modules before making the new kernel the default.
depmod -a "$KREL"
[ -s "/lib/modules/$KREL/modules.dep" ] || fail "depmod failed for $KREL"

BACKUP="/var/backups/onecloud-kernel/${KREL}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
install -d -m 0700 "$BACKUP"
STAGE=$(mktemp -d "$BOOT/.onecloud-stage.XXXXXXXX") || fail "cannot stage on FAT partition"
declare -a TARGETS=("$BOOT/dtb/meson8b-onecloud.dtb" "$BOOT/uInitrd" "$BOOT/uImage")
declare -a PAYLOADS=("meson8b-onecloud.dtb" "uInitrd" "uImage")
declare -a HAD_OLD=()
changed=0

cleanup() {
    local status=$?
    trap - EXIT
    if (( status != 0 && changed != 0 )); then
        echo "OneCloud: activation interrupted; restoring previous boot files from $BACKUP" >&2
        for i in "${!TARGETS[@]}"; do
            if [ "${HAD_OLD[$i]:-0}" = 1 ]; then
                cp -f -- "$BACKUP/$i" "${TARGETS[$i]}" || true
            else
                rm -f -- "${TARGETS[$i]}" || true
            fi
        done
        sync -f "$BOOT" 2>/dev/null || sync
    fi
    rm -rf -- "$STAGE"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Keep all prior boot files in the rootfs for manual recovery.
for i in "${!TARGETS[@]}"; do
    if [ -f "${TARGETS[$i]}" ]; then
        cp -- "${TARGETS[$i]}" "$BACKUP/$i"
        HAD_OLD[$i]=1
    else
        HAD_OLD[$i]=0
    fi
    cp -- "$SRC/${PAYLOADS[$i]}" "$STAGE/${PAYLOADS[$i]}"
    cmp -s -- "$SRC/${PAYLOADS[$i]}" "$STAGE/${PAYLOADS[$i]}" ||
        fail "staging checksum/copy verification failed: ${PAYLOADS[$i]}"
done
sync -f "$STAGE" 2>/dev/null || sync

# FAT has no multi-file atomic transaction. Install DTB and ramdisk first,
# switching uImage last, so most failure windows retain the old kernel.
changed=1
for i in "${!TARGETS[@]}"; do
    mv -f -- "$STAGE/${PAYLOADS[$i]}" "${TARGETS[$i]}"
done
sync -f "$BOOT" 2>/dev/null || sync
for i in "${!TARGETS[@]}"; do
    cmp -s -- "$SRC/${PAYLOADS[$i]}" "${TARGETS[$i]}" ||
        fail "final boot file mismatch: ${PAYLOADS[$i]}"
done
changed=0
echo "OneCloud kernel $KREL activated in /boot. Reboot manually when ready."
echo "Previous boot files backed up in $BACKUP"
