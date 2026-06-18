#!/bin/sh
# prep-image.sh — runs INSIDE the vmactions FreeBSD VM (UFS writes need a
# FreeBSD kernel). Produces ./nbsd-ci/nextbsd.img: NextBSD's latest continuous
# read-write disk image, grown for build headroom, with the gershwin-developer
# tree and a launchd build harness injected. The Linux runner then boots it in
# QEMU, where the harness builds gershwin under the REAL NextBSD kernel
# (uname -s = NextBSD) — which a chroot from a FreeBSD VM can never do.
set -eu

REPO=$(pwd)
WORK=/var/tmp/nbsd-ci
OUT="$REPO/nbsd-ci"
ARCH=${TARGET_ARCH:-amd64}
GROW_GB=${GROW_GB:-10}

rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

echo "==> resolving latest NextBSD .img.zip ($ARCH)"
URL=$(fetch -qo - https://api.github.com/repos/nextbsd-redux/nextbsd/releases/tags/continuous \
      | jq -r '.assets[] | select(.name | test("'"$ARCH"'.*\\.img\\.zip$")) | .browser_download_url' \
      | head -1)
[ -n "$URL" ] || { echo "ERROR: could not resolve NextBSD .img.zip URL" >&2; exit 1; }
echo "    $URL"
fetch -o "$WORK/nextbsd.img.zip"        "$URL"
fetch -o "$WORK/nextbsd.img.zip.sha256" "$URL.sha256"
EXPECT=$(grep -Eo '[0-9a-f]{64}' "$WORK/nextbsd.img.zip.sha256" | head -1)
ACTUAL=$(sha256 -q "$WORK/nextbsd.img.zip")
[ "$EXPECT" = "$ACTUAL" ] || { echo "ERROR: sha256 mismatch ($ACTUAL != $EXPECT)" >&2; exit 1; }
unzip -p "$WORK/nextbsd.img.zip" '*.img' > "$WORK/nextbsd.img"
rm -f "$WORK/nextbsd.img.zip" "$WORK/nextbsd.img.zip.sha256"

echo "==> growing image +${GROW_GB}G and the freebsd-ufs root for build headroom"
truncate -s "+${GROW_GB}G" "$WORK/nextbsd.img"
md=$(mdconfig -a -t vnode -f "$WORK/nextbsd.img")
gpart recover "$md"                                   # fix GPT backup after the grow
ROOTP=$(gpart show "$md" | awk '$4=="freebsd-ufs"{print $3; exit}')
[ -n "$ROOTP" ] || ROOTP=3
gpart resize -i "$ROOTP" "$md"
growfs -y "/dev/${md}p${ROOTP}"

echo "==> injecting gershwin-developer tree + launchd build harness"
mount "/dev/${md}p${ROOTP}" /mnt
mkdir -p /mnt/build
# everything except the image staging dir itself
tar -C "$REPO" --exclude ./nbsd-ci --exclude ./.git -cf - . | tar -C /mnt/build -xpf -
install -m 0755 "$REPO/.ci/nextbsd/ci-build.sh" /mnt/build/ci-build.sh

install -d -m 0755 /mnt/System/Library/LaunchDaemons
install -m 0644 "$REPO/.ci/nextbsd/org.gershwin.ci-build.plist" \
    /mnt/System/Library/LaunchDaemons/org.gershwin.ci-build.plist

# DNS fallback so the first fetch works even before DHCP rewrites resolv.conf.
if [ -d /mnt/private/etc ]; then
    echo "nameserver 8.8.8.8" > /mnt/private/etc/resolv.conf
else
    echo "nameserver 8.8.8.8" > /mnt/etc/resolv.conf
fi

sync
umount /mnt
mdconfig -d -u "${md#md}"

mv "$WORK/nextbsd.img" "$OUT/nextbsd.img"
ls -lh "$OUT/nextbsd.img"
echo "==> prepped: nbsd-ci/nextbsd.img (boot under QEMU to build as uname -s=NextBSD)"
