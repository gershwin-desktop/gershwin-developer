#!/bin/sh
# ci-build.sh — injected at /build/ci-build.sh and launched at boot by the
# org.gershwin.ci-build launchd job. Runs UNDER the NextBSD kernel (so
# `uname -s` is NextBSD, unlike a chroot from a FreeBSD VM), builds
# gershwin-developer, reports CI_BUILD_RESULT on the serial console for the
# host to read, then powers off so QEMU exits.
exec >/dev/console 2>&1
set -u

echo "================ ci-build start ================"
echo "[ci-build] uname -a : $(uname -a)"
echo "[ci-build] uname -s : $(uname -s)   <-- must be NextBSD"
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

echo "[ci-build] waiting for DHCP networking (<= 180s)"
n=0
while [ "$n" -lt 90 ]; do
    if fetch -qo /dev/null https://pkg.freebsd.org/ 2>/dev/null; then
        echo "[ci-build] network is up"
        break
    fi
    n=$((n + 1))
    sleep 2
done

rc=0
cd /build || rc=1

if [ "$rc" -eq 0 ]; then
    echo "[ci-build] === Bootstrap.sh ==="
    sh Library/Scripts/Bootstrap.sh || rc=$?
fi
if [ "$rc" -eq 0 ]; then
    echo "[ci-build] === pkg install git ==="
    pkg install -y git || rc=$?
fi
if [ "$rc" -eq 0 ]; then
    echo "[ci-build] === Checkout.sh ==="
    sh Library/Scripts/Checkout.sh || rc=$?
fi
if [ "$rc" -eq 0 ]; then
    echo "[ci-build] === make install ==="
    make install || rc=$?
fi

if [ "$rc" -eq 0 ] && [ -d /System/Library ]; then
    echo "CI_BUILD_RESULT: OK"
else
    echo "CI_BUILD_RESULT: FAIL rc=$rc"
fi

echo "================ ci-build end (powering off) ================"
sync
sleep 2
poweroff
