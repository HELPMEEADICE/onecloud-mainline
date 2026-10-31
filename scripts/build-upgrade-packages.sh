#!/usr/bin/env bash
# Package already-built OneCloud Linux outputs for Debian/Armbian and Arch Linux ARM.
# Cross-packages without emulating ARM or recompiling anything.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KVER=${KVER:-7.3.1}
[[ "$KVER" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "invalid final Linux version: $KVER" >&2; exit 2; }
KREL="$KVER-onecloud"
KBUILD=${KERNEL_BUILD:-"$ROOT/build/linux-$KVER-gcc15"}
MODSRC="$ROOT/rootfs/modules-full/lib/modules/$KREL"
OUT="$ROOT/output/packages"
PKGNAME="onecloud-linux"
VERSION="$KVER-1"

for cmd in dpkg-deb bsdtar zstd sha256sum du stat; do
    command -v "$cmd" >/dev/null || { echo "missing packaging tool: $cmd" >&2; exit 1; }
done
[ -s "$MODSRC/modules.dep" ] && [ -s "$MODSRC/modules.alias" ] ||
    { echo "missing module tree / depmod database: $MODSRC" >&2; exit 1; }
mkdir -p "$ROOT/tmp" "$OUT"
WORK=$(mktemp -d "$ROOT/tmp/upgrade-packages.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Both formats install the same files. Their post-install scripts apply the
# already-compiled boot files; no writes to /boot happen during archive build.
DATA="$WORK/data"
PAYLOAD="$DATA/usr/lib/onecloud-kernel/$KREL"
mkdir -p "$DATA/usr/lib/modules" "$PAYLOAD"
cp -a "$MODSRC" "$DATA/usr/lib/modules/"
# Strip build-host symlinks added by modules_install; they are not usable on target.
for link in build source; do
    if [ -L "$DATA/usr/lib/modules/$KREL/$link" ]; then
        rm "$DATA/usr/lib/modules/$KREL/$link"
    fi
done
install -m 0644 "$ROOT/build/uImage" "$PAYLOAD/uImage"
install -m 0644 "$ROOT/build/uInitrd" "$PAYLOAD/uInitrd"
install -m 0644 "$KBUILD/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb" "$PAYLOAD/meson8b-onecloud.dtb"
install -m 0644 "$KBUILD/arch/arm/boot/zImage" "$PAYLOAD/zImage"
install -m 0644 "$KBUILD/System.map" "$PAYLOAD/System.map"
install -m 0644 "$ROOT/config/onecloud-$KVER.config" "$PAYLOAD/config"
install -m 0755 "$ROOT/scripts/activate-kernel.sh" "$PAYLOAD/activate.sh"
(
    cd "$PAYLOAD"
    sha256sum uImage uInitrd meson8b-onecloud.dtb > SHA256SUMS
    sha256sum -c SHA256SUMS
)

DEBROOT="$WORK/deb"
mkdir -p "$DEBROOT"
cp -a "$DATA/." "$DEBROOT/"
mkdir -p "$DEBROOT/DEBIAN"
cat > "$DEBROOT/DEBIAN/control" <<EOF
Package: $PKGNAME
Version: $VERSION
Section: kernel
Priority: optional
Architecture: armhf
Maintainer: OneCloud Mainline contributors <noreply@github.com>
Depends: bash, coreutils, kmod, util-linux
Homepage: https://github.com/HELPMEEADICE/onecloud-mainline
Description: Linux $KVER kernel for Xunlei OneCloud S805
 Precompiled kernel modules and U-Boot legacy uImage/uInitrd/DTB.
 Only install on an existing OneCloud system with the supported FAT /boot layout.
EOF
cat > "$DEBROOT/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
case "\$1" in
    configure) exec /usr/lib/onecloud-kernel/$KREL/activate.sh "$KREL" ;;
    abort-upgrade|abort-remove|abort-deconfigure) exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod 0755 "$DEBROOT/DEBIAN/postinst"
DEB="$OUT/${PKGNAME}_${VERSION}_armhf.deb"
dpkg-deb --root-owner-group --build "$DEBROOT" "$DEB"

ARCHROOT="$WORK/arch"
mkdir -p "$ARCHROOT"
cp -a "$DATA/." "$ARCHROOT/"
cat > "$ARCHROOT/.PKGINFO" <<EOF
pkgname = $PKGNAME
pkgbase = $PKGNAME
pkgver = $VERSION
pkgdesc = Linux $KVER kernel for Xunlei OneCloud S805
url = https://github.com/HELPMEEADICE/onecloud-mainline
builddate = $(date +%s)
packager = OneCloud Mainline contributors
size = $(du -sb "$DATA" | cut -f1)
arch = armv7h
license = GPL2
depend = bash
depend = coreutils
depend = kmod
depend = util-linux
EOF
cat > "$ARCHROOT/.INSTALL" <<EOF
post_install() {
    /usr/lib/onecloud-kernel/$KREL/activate.sh "$KREL"
}
post_upgrade() {
    post_install
}
EOF
ARCHPKG="$OUT/${PKGNAME}-${VERSION}-armv7h.pkg.tar.zst"
( cd "$ARCHROOT" && bsdtar -cf - --format=pax --uid 0 --gid 0 --uname root --gname root \
    .PKGINFO .INSTALL usr ) | zstd -T0 -6 -o "$ARCHPKG"
[ -s "$DEB" ] && [ -s "$ARCHPKG" ]
printf 'Created:\n  %s\n  %s\n' "$DEB" "$ARCHPKG"
