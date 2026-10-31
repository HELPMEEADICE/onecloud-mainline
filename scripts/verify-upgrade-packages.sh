#!/usr/bin/env bash
# Check metadata and contents of both binary upgrade formats before Release.
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
KVER=${KVER:-7.3.1}
KREL="$KVER-onecloud"
PKGNAME=onecloud-linux
DEB="$ROOT/output/packages/${PKGNAME}_$KVER-1_armhf.deb"
ARCHPKG="$ROOT/output/packages/${PKGNAME}-$KVER-1-armv7h.pkg.tar.zst"
WORK=$(mktemp -d "$ROOT/tmp/check-packages.XXXXXXXX")
trap 'rm -rf "$WORK"' EXIT
[ -s "$DEB" ] && [ -s "$ARCHPKG" ]

[ "$(dpkg-deb -f "$DEB" Package)" = "$PKGNAME" ]
[ "$(dpkg-deb -f "$DEB" Version)" = "$KVER-1" ]
[ "$(dpkg-deb -f "$DEB" Architecture)" = armhf ]
mkdir -p "$WORK/deb" "$WORK/arch" "$WORK/control"
dpkg-deb -x "$DEB" "$WORK/deb"
dpkg-deb -e "$DEB" "$WORK/control"
[ -x "$WORK/control/postinst" ]
grep -q "/usr/lib/onecloud-kernel/$KREL/activate.sh" "$WORK/control/postinst"

zstd -t -q "$ARCHPKG"
bsdtar -xf "$ARCHPKG" -C "$WORK/arch"
grep -qx "pkgname = $PKGNAME" "$WORK/arch/.PKGINFO"
grep -qx "pkgver = $KVER-1" "$WORK/arch/.PKGINFO"
grep -qx "arch = armv7h" "$WORK/arch/.PKGINFO"
grep -q "/usr/lib/onecloud-kernel/$KREL/activate.sh" "$WORK/arch/.INSTALL"

# The two package payloads must be precisely identical.
diff -qr "$WORK/deb/usr" "$WORK/arch/usr"

for root in "$WORK/deb" "$WORK/arch"; do
    source="$root/usr/lib/onecloud-kernel/$KREL"
    [ -x "$source/activate.sh" ]
    bash -n "$source/activate.sh"
    ( cd "$source" && sha256sum -c SHA256SUMS )
    cmp "$source/uImage" "$ROOT/build/uImage"
    cmp "$source/uInitrd" "$ROOT/build/uInitrd"
    cmp "$source/meson8b-onecloud.dtb" \
        "$ROOT/build/linux-$KVER-gcc15/arch/arm/boot/dts/amlogic/meson8b-onecloud.dtb"
    modules="$root/usr/lib/modules/$KREL"
    [ -s "$modules/modules.dep" ] && [ -s "$modules/modules.alias" ]
    find "$modules" -name '*.ko*' -print -quit | grep -q .
done
echo "Debian armhf and pacman armv7h packages verified for $KREL"
