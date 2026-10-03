#!/bin/sh
# windows-wine-test.sh - run the Windows build of the Workspace under Wine.
#
# A lightweight check of the Windows build on a Unix machine, with no
# Windows anywhere: Wine runs the mingw-w64 binaries directly, and the
# self-contained /System tree brings everything else. Usage:
#
#   windows-wine-test.sh <System directory or Gershwin-*-Windows-*.zip> [seconds] [screenshot.png]
#
# Needs a 64-bit wine; without a DISPLAY it runs itself under xvfb-run when
# that is installed. The screenshot needs ImageMagick's "import". Exit 0
# when the Workspace is still running after the given seconds (45 by
# default), 1 otherwise, with the app's output in <screenshot dir>/wine-*.log.
#
# Two things differ from a real Windows: Wine's mailslots do not carry
# GNUstep's Distributed Objects, so the Wine prefix is set to socket ports
# (NSPortIsMessagePort NO) and gdomap is started for them; and the prefix
# has no Tahoma or Arial, which is why the Windows defaults name the
# bundled fonts.
set -e

[ $# -ge 1 ] || { echo "usage: $0 <System dir or zip> [seconds] [screenshot.png]" >&2; exit 2; }
SRC="$1"
SECONDS_TO_WAIT="${2:-45}"
SHOT="${3:-$PWD/workspace-wine.png}"
OUT="$(cd "$(dirname "$SHOT")" && pwd)"

command -v wine >/dev/null 2>&1 || { echo "wine is not installed" >&2; exit 2; }
if [ -z "$DISPLAY" ]; then
  if command -v xvfb-run >/dev/null 2>&1; then
    exec xvfb-run -a -s "-screen 0 1280x800x24" "$0" "$@"
  fi
  echo "No DISPLAY and no xvfb-run; the Workspace needs a display." >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'wineserver -k 2>/dev/null; rm -rf "$WORK"' EXIT

case "$SRC" in
  *.zip)
    mkdir -p "$WORK/System"
    unzip -qo "$SRC" -d "$WORK/System"
    SYSTEM="$WORK/System" ;;
  *)
    SYSTEM="$(cd "$SRC" && pwd)" ;;
esac
[ -x "$SYSTEM/Applications/Workspace.app/Workspace.exe" ] || { echo "No Workspace.exe under $SYSTEM" >&2; exit 2; }

export WINEPREFIX="$WORK/prefix" WINEARCH=win64 WINEDEBUG="${WINEDEBUG:--all}"
# No Mono or Gecko installation prompts on the fresh prefix.
export WINEDLLOVERRIDES="mscoree,mshtml="
wineboot -i >/dev/null 2>&1
export WINEPATH="$(winepath -w "$SYSTEM/Library/Tools")"
cd "$SYSTEM"

# Distributed Objects over TCP: gdomap is the name server, gdnc the
# notification center the Workspace must reach at startup. Both are started
# here rather than left to the Workspace, which would give up on them before
# their registration through Wine's network stack is done.
# gdomap's port 538 is privileged; this override is honoured by gdomap and
# by every process looking it up, so the test needs no root.
export GDOMAP_PORT_OVERRIDE="${GDOMAP_PORT_OVERRIDE:-20538}"
wine Library/Tools/defaults.exe write NSGlobalDomain NSPortIsMessagePort NO >/dev/null 2>&1
# gdomap serves the addresses it is given rather than whatever interfaces
# Wine reports: the loopback, and the machine's own addresses, since a
# lookup of the local host may resolve to either.
{
  printf '127.0.0.1 255.0.0.0\n'
  for a in $(hostname -I 2>/dev/null || true); do
    case "$a" in *.*.*.*) printf '%s 255.255.255.0\n' "$a" ;; esac
  done
} > "$WORK/gdomap-addresses"
wine Library/Tools/gdomap.exe -f -N -d -a "$(winepath -w "$WORK/gdomap-addresses")" > "$OUT/wine-gdomap.log" 2>&1 &
sleep 3
wine Library/Tools/gdnc.exe > "$OUT/wine-gdnc.log" 2>&1 &
sleep 8
echo "gdomap addresses: $(tr '\n' ';' < "$WORK/gdomap-addresses")"
echo "gdomap lookup of gdnc: $(wine Library/Tools/gdomap.exe -L gdnc -H 127.0.0.1 2>&1 | tr -d '\r' | tail -1)"

echo "Starting the Workspace under $(wine --version 2>/dev/null)..."
wine Applications/Workspace.app/Workspace.exe > "$OUT/wine-stdout.log" 2> "$OUT/wine-stderr.log" &
PID=$!
sleep "$SECONDS_TO_WAIT"

if kill -0 "$PID" 2>/dev/null; then
  echo "Workspace is still running after ${SECONDS_TO_WAIT}s."
  if command -v import >/dev/null 2>&1; then
    import -window root "$SHOT" 2>/dev/null && echo "Screenshot: $SHOT"
  fi
  RC=0
else
  wait "$PID" || true
  echo "Workspace exited within ${SECONDS_TO_WAIT}s; last output:" >&2
  tail -20 "$OUT/wine-stderr.log" >&2
  RC=1
fi
exit $RC
