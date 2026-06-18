#!/bin/sh
# boot-and-poll.sh — runs on the Linux runner. Boots the prepped NextBSD .img
# under QEMU (KVM-accelerated when available) and watches the serial console
# for the in-guest harness's verdict. Passes iff gershwin built under the real
# NextBSD kernel (CI_BUILD_RESULT: OK).
set -u

IMG=nbsd-ci/nextbsd.img
SERIAL=nbsd-ci/serial.log
DEADLINE_SECS=${DEADLINE_SECS:-12600}    # 3.5h cap (the job has its own 240m timeout)

[ -f "$IMG" ] || { echo "no image at $IMG"; ls -laR nbsd-ci 2>/dev/null || true; exit 1; }
: > "$SERIAL"

OVMF=/usr/share/ovmf/OVMF.fd
[ -f "$OVMF" ] || OVMF=/usr/share/OVMF/OVMF_CODE.fd
ACCEL="-accel tcg -cpu qemu64"
if [ -e /dev/kvm ]; then sudo chmod 666 /dev/kvm 2>/dev/null || true; fi
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then ACCEL="-accel kvm -cpu host"; fi
echo "[boot] accel=$ACCEL ovmf=$OVMF img=$(ls -lh "$IMG" | awk '{print $5}')"

nohup qemu-system-x86_64 \
    -machine q35 -m 6G -smp 4 $ACCEL -bios "$OVMF" \
    -drive file="$IMG",format=raw,if=virtio \
    -nic user,model=virtio-net-pci \
    -serial file:"$SERIAL" \
    -display none -no-reboot \
    > nbsd-ci/qemu.stdout 2>&1 &
QPID=$!
echo "[boot] qemu pid $QPID"

# stream the guest serial console into the CI log so progress is visible
tail -n +1 -f "$SERIAL" 2>/dev/null | sed 's/^/[serial] /' &
TPID=$!
trap 'kill "$TPID" 2>/dev/null; kill "$QPID" 2>/dev/null' EXIT INT TERM

END=$(( $(date +%s) + DEADLINE_SECS ))
result=""
while [ "$(date +%s)" -lt "$END" ]; do
    if grep -q 'CI_BUILD_RESULT:' "$SERIAL" 2>/dev/null; then
        result=$(grep 'CI_BUILD_RESULT:' "$SERIAL" | tail -1)
        break
    fi
    # if qemu died (guest powered off) without a verdict, stop waiting
    kill -0 "$QPID" 2>/dev/null || { echo "[boot] qemu exited before a verdict"; break; }
    sleep 10
done

echo "[boot] ===== verdict: ${result:-<none>} ====="
case "$result" in
    *"CI_BUILD_RESULT: OK"*)
        echo "[boot] PASS — gershwin built under uname -s=NextBSD"
        exit 0 ;;
    *)
        echo "[boot] FAIL — last 80 serial lines:"
        tail -n 80 "$SERIAL" 2>/dev/null || true
        exit 1 ;;
esac
