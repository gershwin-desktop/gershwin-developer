#!/bin/sh
# Run the DriveUI UI test suite against a built desktop.
#
# Requires the full Gershwin desktop built and installed to /System
# (make all), and the DriveUI tooling installed (make tooling) so that
# run_uitest, drive_ui and the uitest_tests harness are in /System/Library/Tools.
#
# Two session modes, selected with UITEST_SESSION:
#
#   session   (default)  run against the already-running desktop session of the
#                        current user, on its existing $DISPLAY.  This is the
#                        classic local workflow: the desktop is up, DriveUI is
#                        loaded, the tests just drive it.
#
#   isolated             run as a dedicated test user on a fresh virtual X
#                        display (Xvfb) with its own dbus bus and home, fully
#                        isolated from any logged-in session.  This is what CI
#                        and reproducible local runs use; the logged-in user's
#                        desktop is never touched.  The test user is created on
#                        demand (UITEST_ISOLATED_USER, default "uitest"); root
#                        (or passwordless sudo) is required to create it.
#
# Exit status is the harness's.
set -u

# Let the isolated test user dump core (its own hard limit is 0) so a crash in
# a desktop component produces a core we can backtrace.
ulimit -Hc unlimited 2>/dev/null || true
ulimit -c unlimited 2>/dev/null || true

WORKDIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPOS_DIR="${UITEST_REPOS_DIR:-$WORKDIR/Library/Sources}"
XVFB_PID=""

UITEST_SESSION="${UITEST_SESSION:-session}"
UITEST_ISOLATED_USER="${UITEST_ISOLATED_USER:-uitest}"
UITEST_ISOLATED_DISPLAY="${UITEST_ISOLATED_DISPLAY:-:99}"

# Where the JUnit report lands. Default is the spec's conventional location
# (uitest.md section 19/23) inside the repository; CI uploads this file.
JUNIT_OUTPUT="${UITEST_JUNIT_OUTPUT:-$WORKDIR/build/test-results/junit.xml}"

# Start a background process that must outlive this shell.
start_bg()
{
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >/dev/null 2>&1 < /dev/null &
  else
    "$@" >/dev/null 2>&1 &
  fi
}

# 0. Fonts.  The Gershwin desktop fonts live in /System/Library/Fonts and are
#    indexed through fontconfig via /System/Library/Preferences/fonts.conf (the
#    same setup gershwin-system's Gershwin.sh exports).  A stock CI container's
#    fontconfig does not look there, so without this the desktop apps cannot
#    resolve any font and the UI tests fail on rendering/text.
ensure_fonts()
{
  export FONTCONFIG_PATH=/System/Library/Preferences
  export FONTCONFIG_FILE=$FONTCONFIG_PATH/fonts.conf
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -f /System/Library/Fonts >/dev/null 2>&1
  fi
}

# The desktop apps expose a DriveUI socket only when the DriveUI bundle is
# loaded into every app at startup (the GSAppKitUserBundles user default).
# Enable it for the run - preserving any prior value - and restore that value
# at the end so the user defaults are left as they were found.
APPKIT_BUNDLES_PRIOR=""
APPKIT_BUNDLES_HAD=0
enable_appkit_bundles()
{
  if ! command -v defaults >/dev/null 2>&1; then
    return
  fi
  if defaults read NSGlobalDomain GSAppKitUserBundles >/dev/null 2>&1; then
    APPKIT_BUNDLES_HAD=1
    _raw=$(defaults read NSGlobalDomain GSAppKitUserBundles)
    _arg="("
    for _p in $(printf '%s\n' "$_raw" | sed -n 's/^[[:space:]]*"\([^"]*\)",*[[:space:]]*$/\1/p')
    do
      _arg="$_arg\"$_p\","
    done
    APPKIT_BUNDLES_PRIOR="${_arg%,})"
  fi
  if printf '%s' "$APPKIT_BUNDLES_PRIOR" | grep -q 'DriveUI.bundle'; then
    _new="$APPKIT_BUNDLES_PRIOR"
  elif [ -n "$APPKIT_BUNDLES_PRIOR" ]; then
    _new="${APPKIT_BUNDLES_PRIOR%)},\"/System/Library/Bundles/DriveUI.bundle\")"
  else
    _new='("/System/Library/Bundles/DriveUI.bundle")'
  fi
  defaults write NSGlobalDomain GSAppKitUserBundles "$_new" >/dev/null 2>&1
}

restore_appkit_bundles()
{
  if ! command -v defaults >/dev/null 2>&1; then
    return
  fi
  if [ "$APPKIT_BUNDLES_HAD" = 1 ]; then
    defaults write NSGlobalDomain GSAppKitUserBundles "$APPKIT_BUNDLES_PRIOR" >/dev/null 2>&1 || true
  else
    defaults delete NSGlobalDomain GSAppKitUserBundles >/dev/null 2>&1 || true
  fi
}

# Run a command as another user.  Prefer sudo; CI containers and BSD hosts
# run as root without sudo installed, so fall back to su -m there.  Requires
# root (or passwordless sudo) either way.
run_as_user()
{
  _u="$1"; shift
  if command -v sudo >/dev/null 2>&1; then
    sudo -u "$_u" "$@"
    return $?
  fi
  if [ "$(id -u)" = "0" ]; then
    # su -c takes a single command string; quote each argument.
    _cmd=""
    for _a in "$@"; do
      _esc=$(printf '%s' "$_a" | sed "s/'/'\\\\''/g")
      _cmd="$_cmd '$_esc'"
    done
    su -m "$_u" -c "$_cmd"
    return $?
  fi
  echo "error: need root or sudo to run as $_u" >&2
  return 1
}

# Start a desktop component (Menu / WindowManager / Workspace) if it is not
# already running.  $1 = the user the session runs as (empty = current user).
# Restarting an already-running instance is avoided in session mode so the
# logged-in desktop is not disturbed.
start_desktop_component()
{
  run_user="$1"
  name="$2"
  bin="$3"
  if pgrep -x "$name" >/dev/null 2>&1; then
    return 0
  fi
  if [ -x "$bin" ]; then
    if [ -n "$run_user" ]; then
      start_bg run_as_user "$run_user" "$bin"
    else
      start_bg "$bin"
    fi
  else
    echo "Warning: $name binary not found at $bin" >&2
  fi
}

# Run a command in the session.  In isolated mode this is sudo to the test
# user with the isolated environment.  GNUstep.sh is sourced inside the
# isolated shell (not just for the desktop components) so every process the
# tests spawn - the harness, run_uitest, apps it launches, and their children
# such as the Build app's `make` - sees the GNUstep build env (GNUSTEP_MAKEFILES
# and friends).  Without it the Build test's `make` could not find common.make.
#
# The display and home are passed as positional arguments, NOT via the
# environment: sudo/su reset the environment, so a $UITEST_ISOLATED_DISPLAY
# reference inside the inner shell would expand empty and the Workspace would
# fail with 'Unable to connect to X Server ""'.
session_run()
{
  if [ "$UITEST_SESSION" = "isolated" ]; then
    run_as_user "$UITEST_ISOLATED_USER" sh -c '
      ulimit -c unlimited 2>/dev/null || true
      _disp="$1"; _home="$2"; shift 2
      . /System/Library/Makefiles/GNUstep.sh
      exec env DISPLAY="$_disp" \
        HOME="$_home" \
        GNUSTEP_SYSTEM_ROOT=/System GNUSTEP_LOCAL_ROOT=/Local \
        GNUSTEP_NETWORK_ROOT=/Network \
        GNUSTEP_USER_ROOT="$_home/.GNUstep" \
        FONTCONFIG_FILE=/System/Library/Preferences/fonts.conf \
        FONTCONFIG_PATH=/System/Library/Preferences \
        PATH=/System/Library/Tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        "$@"
    ' _ "$UITEST_ISOLATED_DISPLAY" "/home/$UITEST_ISOLATED_USER" "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Crash diagnostics (UITEST_CRASH_DIAGNOSTICS=1, set by CI)
# ---------------------------------------------------------------------------

# A desktop component or run_uitest that crashes mid-suite otherwise shows up
# only as "exit 11" or "application not running" on every later test; its
# core gives the stack.  Opt-in because it changes a system-wide kernel
# setting, which a developer's machine must not get as a side effect.
CORE_DIR=/tmp/uitest-cores

as_root()
{
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo "$@"
  fi
}

setup_core_dumps()
{
  command -v gdb >/dev/null 2>&1 || {
    echo "error: UITEST_CRASH_DIAGNOSTICS=1 needs gdb to backtrace cores" >&2
    exit 1
  }
  as_root rm -rf "$CORE_DIR"
  as_root mkdir -m 1777 "$CORE_DIR" || exit 1
  case "$(uname -s)" in
    Linux)
      # %E is the executable's path with '/' written as '!', so the report
      # can hand gdb the matching binary.  Writing it needs a privileged
      # container (see build.yml).
      as_root sh -c "echo '$CORE_DIR/core.%E.%p' > /proc/sys/kernel/core_pattern" || {
        echo "error: cannot set kernel.core_pattern (container not privileged?)" >&2
        exit 1
      }
      ;;
    FreeBSD|NextBSD)
      as_root sysctl kern.corefile="$CORE_DIR/%N.%P.core" >/dev/null || exit 1
      ;;
    *)
      echo "error: UITEST_CRASH_DIAGNOSTICS is not supported on $(uname -s)" >&2
      exit 1
      ;;
  esac
}

# Workspace also dies without a core when one of its X connections has its
# descriptor closed by other code in the process (Xlib then just reports
# "X connection broken").  xfdwatch.c, preloaded into Workspace only, prints
# the backtrace of whoever closes an X server socket outside libxcb.
WS_PRELOAD=""

setup_xfd_watch()
{
  _lib=/tmp/uitest-xfdwatch.so
  # backtrace() lives in libexecinfo on the BSDs and in libc on Linux.
  case "$(uname -s)" in
    Linux) _libs="-ldl" ;;
    *)     _libs="-lexecinfo" ;;
  esac
  cc -shared -fPIC -O1 -Wall -o "$_lib" "$WORKDIR/Library/Scripts/xfdwatch.c" $_libs || {
    echo "error: cannot build $_lib" >&2
    exit 1
  }
  chmod 755 "$_lib"
  WS_PRELOAD="$_lib"
}

# Backtrace every core the suite left behind; crash-backtraces.txt next to the
# JUnit report puts them into the CI artifact as well.
report_cores()
{
  _bt="$(dirname "$JUNIT_OUTPUT")/crash-backtraces.txt"
  mkdir -p "$(dirname "$_bt")"
  for _core in "$CORE_DIR"/*; do
    [ -f "$_core" ] || continue
    _base=$(basename "$_core")
    case "$_base" in
      core.*)
        _exe=$(echo "$_base" | sed -e 's/^core\.//' -e 's/\.[0-9]*$//' | tr '!' '/')
        ;;
      *.core)
        # FreeBSD's %N is only the process name: find the binary in /System.
        _name=$(echo "$_base" | sed -e 's/\.[0-9]*\.core$//')
        _exe=$(find /System/Applications /System/Library/CoreServices \
          /System/Library/Tools -type f -name "$_name" -perm -111 2>/dev/null | head -1)
        ;;
    esac
    {
      echo "=== UITEST CRASH: $_base (${_exe:-executable not found}) ==="
      as_root gdb -q -batch -ex 'thread apply all bt 40' ${_exe:+"$_exe"} \
        --core="$_core" 2>&1 | head -300
    } | tee -a "$_bt"
  done
}

# A component that wedged or crashed usually explains every test failing
# after it, and its own output is the only record of why.
print_session_logs()
{
  for _log in /tmp/uitest_ws.log /tmp/uitest_workspace.log /tmp/uitest_menu.log /tmp/uitest_wm.log; do
    [ -f "$_log" ] || continue
    echo "=== UITEST LOG: $_log (last 40 lines) ==="
    tail -n 40 "$_log"
  done
  # The culprit report can be far above the tail printed above.
  if grep -q '^XFDWATCH' /tmp/uitest_ws.log 2>/dev/null; then
    echo "=== UITEST XFDWATCH: X connections closed outside libxcb ==="
    grep -A 40 '^XFDWATCH' /tmp/uitest_ws.log | head -400
  fi
}

# ---------------------------------------------------------------------------
# Session setup
# ---------------------------------------------------------------------------

if [ "$UITEST_SESSION" = "isolated" ]; then
  # Create the test user on demand (root or passwordless sudo required).
  if ! id "$UITEST_ISOLATED_USER" >/dev/null 2>&1; then
    echo "Creating test user '$UITEST_ISOLATED_USER'"
    # /bin/sh is guaranteed on every platform; bash is not (BSD builds).
    # FreeBSD/NextBSD ship pw(8) instead of useradd(8).
    if [ "$(uname -s)" = "FreeBSD" ] || [ "$(uname -s)" = "NextBSD" ]; then
      pw useradd "$UITEST_ISOLATED_USER" -m -s /bin/sh
    else
      useradd -m -s /bin/sh "$UITEST_ISOLATED_USER"
    fi
  fi

  # A killed/previous session leaves a gdnc (DO name server) and the test
  # user's GNUstepSecure temp state behind; a fresh gdnc cannot lock the port
  # names and the desktop components then fail to find each other's DO
  # services (Menu shows no app menus).  SIGKILL the test user's stale
  # processes and drop ONLY this user's name-server state (GNUstepSecure<uid>,
  # NOT other users' dirs) before bringing the desktop up.  This is the same
  # cleanup uitest-session.sh performs.
  pkill -9 -u "$UITEST_ISOLATED_USER" 2>/dev/null || true
  _isolated_uid=$(id -u "$UITEST_ISOLATED_USER" 2>/dev/null || echo 0)
  rm -rf "/tmp/GNUstepSecure${_isolated_uid}" 2>/dev/null || true
  sleep 1

  if [ "${UITEST_CRASH_DIAGNOSTICS:-0}" = "1" ]; then
    setup_core_dumps
    setup_xfd_watch
  fi

  # A fresh virtual display, open to local connections.
  if ! xdpyinfo -display "$UITEST_ISOLATED_DISPLAY" >/dev/null 2>&1; then
    echo "Starting Xvfb on $UITEST_ISOLATED_DISPLAY"
    start_bg Xvfb "$UITEST_ISOLATED_DISPLAY" -screen 0 800x600x24 -nolisten tcp -ac
    XVFB_PID=$!
    i=0
    while [ "$i" -lt 30 ]; do
      xdpyinfo -display "$UITEST_ISOLATED_DISPLAY" >/dev/null 2>&1 && break
      sleep 1
      i=$((i + 1))
    done
    xdpyinfo -display "$UITEST_ISOLATED_DISPLAY" >/dev/null 2>&1 || {
      echo "Xvfb did not come up on $UITEST_ISOLATED_DISPLAY" >&2; exit 1; }
  fi
  export DISPLAY="$UITEST_ISOLATED_DISPLAY"

  # The test user needs the DriveUI bundle default and the fontconfig setup.
  session_run sh -c 'defaults write NSGlobalDomain GSAppKitUserBundles \
    "(\"/System/Library/Bundles/DriveUI.bundle\")" >/dev/null 2>&1'

  # Desktop + dbus session for the test user.
  session_run env WS_PRELOAD="$WS_PRELOAD" sh -c '
    . /System/Library/Makefiles/GNUstep.sh
    eval $(dbus-launch --sh-syntax)
    /System/Library/CoreServices/Applications/Menu.app/Menu >/tmp/uitest_menu.log 2>&1 &
    /System/Library/CoreServices/Applications/WindowManager.app/WindowManager >/tmp/uitest_wm.log 2>&1 &
    ${WS_PRELOAD:+env LD_PRELOAD=$WS_PRELOAD} /System/Applications/Workspace.app/Workspace >/tmp/uitest_ws.log 2>&1 &
  '

else
  # Session mode: use the current display; fail loudly if there is none.
  : "${DISPLAY:?no DISPLAY and UITEST_SESSION=session needs a running X session}"
  xdpyinfo >/dev/null 2>&1 || {
    echo "$DISPLAY is not reachable; use UITEST_SESSION=isolated for a virtual session" >&2
    exit 1
  }
  ensure_fonts
  enable_appkit_bundles
  start_desktop_component "" "Menu" "/System/Library/CoreServices/Applications/Menu.app/Menu"
  start_desktop_component "" "WindowManager" "/System/Library/CoreServices/Applications/WindowManager.app/WindowManager"
  start_desktop_component "" "Workspace" "/System/Applications/Workspace.app/Workspace"
fi

# Let the desktop settle.
sleep 5

# ---------------------------------------------------------------------------
# Collect the Tests/ directories that belong to the built components.
# ---------------------------------------------------------------------------

# A component directory carrying a .DISABLED file is not built (see the
# gershwin-components top-level GNUmakefile), so its app is absent and its
# tests could only fail on "no <App>.app found".  $1 = test dir, $2 = repo.
in_disabled_component()
{
  _d="$1"
  while [ "$_d" != "$2" ] && [ "$_d" != "/" ]; do
    [ -f "$_d/.DISABLED" ] && return 0
    _d=$(dirname "$_d")
  done
  return 1
}

RAW_DIRS=$(for repo in "$REPOS_DIR"/gershwin-*
  do
    if [ -d "$repo" ]; then
      files=$(find "$repo" -name '*.uitest' -type f 2>/dev/null)
      if [ -n "$files" ]; then
        echo "$files" | xargs -n1 dirname | while read -r d; do
          if in_disabled_component "$d" "$repo"; then
            echo "Skipping $d: component is .DISABLED (not built)" >&2
          else
            echo "$d"
          fi
        done
      fi
    fi
  done | sort -u)

UITEST_SEARCH_DIRS=""
for d in $RAW_DIRS
do
  nested=0
  for o in $RAW_DIRS
  do
    [ "$d" = "$o" ] && continue
    case "$d" in
      "$o"/*) nested=1 ;;
    esac
  done
  if [ "$nested" -eq 0 ]; then
    UITEST_SEARCH_DIRS="$UITEST_SEARCH_DIRS${UITEST_SEARCH_DIRS:+:}$d"
  fi
done

# The DriveUI control test ships with the harness.
CONTROL="$WORKDIR/DriveUI/uitest/Tests/control"
if [ -d "$CONTROL" ]; then
  UITEST_SEARCH_DIRS="$UITEST_SEARCH_DIRS${UITEST_SEARCH_DIRS:+:}$CONTROL"
fi

export UITEST_SEARCH_DIRS
export UI_TEST_LEVEL="${UI_TEST_LEVEL:-core}"
echo "UITEST_SEARCH_DIRS=$UITEST_SEARCH_DIRS"

if [ -z "$UITEST_SEARCH_DIRS" ]; then
  echo "No .uitest scripts found" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Run the harness.
# ---------------------------------------------------------------------------
HARNESS=/System/Library/Tools/uitest_tests
if [ ! -x "$HARNESS" ]; then
  echo "uitest_tests harness not installed (run 'make tooling')" >&2
  exit 1
fi

# In isolated mode the harness runs as the test user, which cannot write into
# the (usually root-owned) checkout, so have it write to a world-writable path
# and copy the result back out as the invoking user afterwards.
if [ "$UITEST_SESSION" = "isolated" ]; then
  HARNESS_JUNIT=/tmp/uitest-junit.xml
else
  HARNESS_JUNIT="$JUNIT_OUTPUT"
fi

session_run env UITEST_SEARCH_DIRS="$UITEST_SEARCH_DIRS" UI_TEST_LEVEL="$UI_TEST_LEVEL" \
  UITEST_JUNIT_OUTPUT="$HARNESS_JUNIT" \
  "$HARNESS"
rc=$?

if [ -f "$HARNESS_JUNIT" ]; then
  mkdir -p "$(dirname "$JUNIT_OUTPUT")"
  # In session mode the harness wrote the file directly; only move it out of
  # the isolated sandbox when it landed at a different path.
  if [ "$HARNESS_JUNIT" != "$JUNIT_OUTPUT" ]; then
    cp "$HARNESS_JUNIT" "$JUNIT_OUTPUT"
  fi
  echo "JUnit report: $JUNIT_OUTPUT" >&2
fi

if [ "${UITEST_CRASH_DIAGNOSTICS:-0}" = "1" ]; then
  report_cores
fi
if [ "$rc" -ne 0 ]; then
  print_session_logs
fi

restore_appkit_bundles

# Leave a clean slate: the isolated desktop (Menu, WindowManager, Workspace,
# plus any app the tests launched) stays alive because SIGTERM does not stop
# it (the Workspace ignores it), so without this the next isolated run would
# reuse stale processes and sockets.  SIGKILL the whole test user instead.
if [ "$UITEST_SESSION" = "isolated" ]; then
  # pkill as root needs no sudo (BSD CI runs as root without sudo installed).
  if [ "$(id -u)" = "0" ]; then
    pkill -9 -u "$UITEST_ISOLATED_USER" 2>/dev/null || true
  else
    sudo pkill -9 -u "$UITEST_ISOLATED_USER" 2>/dev/null || true
  fi
  # Drop the test user's name-server state too, so the next isolated run starts
  # from a clean gdnc (only this user's dir - other users are untouched).
  _isolated_uid=$(id -u "$UITEST_ISOLATED_USER" 2>/dev/null || echo 0)
  rm -rf "/tmp/GNUstepSecure${_isolated_uid}" 2>/dev/null || true
  sleep 1
fi

if [ -n "$XVFB_PID" ]; then
  kill "$XVFB_PID" 2>/dev/null
fi
exit $rc
