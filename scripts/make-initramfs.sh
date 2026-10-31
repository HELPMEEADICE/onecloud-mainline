#!/bin/sh
# Build a small, self-contained initramfs for OneCloud.
# The eMMC (meson-mx-sdhc) and ext4 drivers are built into the kernel, so
# the initramfs only needs a static busybox and a root-by-UUID mount script.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ ! -d "$ROOT_DIR/src" ] && [ -d "$ROOT_DIR/../src" ]; then ROOT_DIR=$(CDPATH= cd -- "$ROOT_DIR/.." && pwd); fi
if [ ! -d "$ROOT_DIR/src" ] && [ -d "$ROOT_DIR/../../src" ]; then ROOT_DIR=$(CDPATH= cd -- "$ROOT_DIR/../.." && pwd); fi
KREL=${1:-7.3.1-onecloud}
ROOT_UUID=${2:-8a03b678-0b46-4f41-bb09-3a2d154439bc}
OUT=${3:-$ROOT_DIR/build/initramfs-$KREL.cpio.gz}
BUSYBOX=${BUSYBOX:-$ROOT_DIR/tools/busybox/usr/bin/busybox}
GEN_INIT_CPIO=${GEN_INIT_CPIO:-$ROOT_DIR/tools/gen_init_cpio}
mkdir -p "$ROOT_DIR/tmp" "$(dirname "$OUT")"
WORK=$(mktemp -d "$ROOT_DIR/tmp/initramfs.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

[ -x "$BUSYBOX" ] || { echo "missing static busybox: $BUSYBOX" >&2; exit 1; }
[ -x "$GEN_INIT_CPIO" ] || { echo "missing gen_init_cpio: $GEN_INIT_CPIO" >&2; exit 1; }

cat >"$WORK/init" <<EOF
#!/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
/bin/busybox mkdir -p /dev/pts /newroot /run
/bin/busybox mount -t devpts devpts /dev/pts 2>/dev/null || true

ROOT=""
for arg in \$(/bin/busybox cat /proc/cmdline); do
	case "\$arg" in
		root=*) ROOT="\${arg#root=}" ;;
	esac
done
[ -n "\$ROOT" ] || ROOT="UUID=$ROOT_UUID"

echo "OneCloud initramfs: waiting for root=\$ROOT"
DEV=""
i=0
while [ \$i -lt 100 ]; do
	DEV=\$(/bin/busybox findfs "\$ROOT" 2>/dev/null || true)
	[ -n "\$DEV" ] && break
	/bin/busybox sleep 0.1
	i=\$((i + 1))
done

if [ -z "\$DEV" ]; then
	echo "OneCloud initramfs: root device not found, starting rescue shell"
	exec /bin/busybox sh
fi

echo "OneCloud initramfs: mounting \$DEV on /newroot"
if ! /bin/busybox mount -t ext4 -o rw,noatime "\$DEV" /newroot; then
	echo "OneCloud initramfs: failed to mount root, starting rescue shell"
	exec /bin/busybox sh
fi

exec /bin/busybox switch_root /newroot /sbin/init
EOF
chmod 0755 "$WORK/init"

cat >"$WORK/list" <<EOF
dir /dev 0755 0 0
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /run 0755 0 0
dir /newroot 0755 0 0
dir /bin 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
nod /dev/zero 0666 0 0 c 1 5
nod /dev/tty 0666 0 0 c 5 0
file /init $WORK/init 0755 0 0
file /bin/busybox $BUSYBOX 0755 0 0
slink /bin/sh busybox 0777 0 0
slink /sbin/mount busybox 0777 0 0
slink /sbin/switch_root busybox 0777 0 0
slink /sbin/findfs busybox 0777 0 0
slink /bin/cat busybox 0777 0 0
slink /bin/mkdir busybox 0777 0 0
slink /bin/sleep busybox 0777 0 0
slink /bin/dmesg busybox 0777 0 0
slink /sbin/poweroff busybox 0777 0 0
slink /sbin/reboot busybox 0777 0 0
EOF

"$GEN_INIT_CPIO" "$WORK/list" | gzip -9n >"$OUT"
echo "initramfs: $OUT"
ls -l "$OUT"
