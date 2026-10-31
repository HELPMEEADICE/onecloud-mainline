#!/usr/bin/env bash
# Verify signed kernel.org source: SHA256 and detached signature of uncompressed tar.
set -euo pipefail
KVER=${1:?version required}
[[ "$KVER" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || exit 2
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST=${2:-"$ROOT/tools/linux-$KVER.tar.xz"}
mkdir -p "$ROOT/tools" "$ROOT/tmp" "$ROOT/logs" "$(dirname "$DEST")"
WORK=$(mktemp -d "$ROOT/tmp/kernel-check.XXXX")
trap 'rm -rf "$WORK"' EXIT
BASE="https://cdn.kernel.org/pub/linux/kernel/v${KVER%%.*}.x"
curl -fLsS --retry 3 "$BASE/sha256sums.asc" -o "$WORK/sums"
SUM=$(awk -v name="linux-$KVER.tar.xz" '$2==name {print $1}' "$WORK/sums")
[[ "$SUM" =~ ^[0-9a-f]{64}$ ]] || { echo "missing upstream SHA256" >&2; exit 1; }
if [ ! -s "$DEST" ]; then
    curl -fL --retry 3 "$BASE/linux-$KVER.tar.xz" -o "$DEST.part"
    mv "$DEST.part" "$DEST"
fi
printf '%s  %s\n' "$SUM" "$DEST" | sha256sum -c -
curl -fLsS --retry 3 "$BASE/linux-$KVER.tar.sign" -o "$WORK/kernel.sign"
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
TRUSTED=(ABAF11C65A2970B130ABE3C479BE3E4300411886 647F28654894E3BD457199BE38DBBDC8609293E E27E5D8A3403A2EF66873BBCDEA66FF797772CDC)
for fp in "${TRUSTED[@]}"; do
    gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fp" >/dev/null 2>&1 || true
done
xz -dc "$DEST" | gpg --batch --status-fd 3 --verify "$WORK/kernel.sign" - 3>"$WORK/signature-status"
signer=$(awk '$2=="VALIDSIG" {print $3}' "$WORK/signature-status")
for fp in "${TRUSTED[@]}"; do
    if [ "$signer" = "$fp" ]; then
        printf '%s  linux-%s.tar.xz\n' "$SUM" "$KVER" >"$ROOT/logs/source-$KVER.sha256"
        echo "kernel signature accepted: $signer"
        exit 0
    fi
done
echo "kernel signer not in trusted allowlist: $signer" >&2
exit 1
