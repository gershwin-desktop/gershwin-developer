#!/bin/sh
set -e

if [ "$FROM_MAKEFILE" != "1" ]; then
    echo "This script must be run from the Makefile."
    exit 1
fi

export PATH="${PATH}:$(cd "$(dirname "$0")" && pwd -P)"
. ./Library/Scripts/functions.sh
detect_platform
export_vars

export REPOS_DIR="$WORKDIR/Library/Sources"

# The Gershwin domain is a clang toolchain end to end: the ng-gnu-gnu library
# combo is built on libobjc2, and the cmake stages already pin
# -DCMAKE_C_COMPILER=clang. The autoconf stages, though, let configure pick its
# own default, which on Linux is gcc. That is not just an inconsistency - on
# Debian bookworm (gcc 12) libs-corebase's AC_CHECK_HEADERS([dispatch/dispatch.h])
# fails against the libdispatch headers we just installed and configure aborts
# with "Could not find the Grand Central Dispatch headers.". On the BSDs cc is
# already clang, so this is a no-op there. An explicit CC/CXX/OBJC in the
# environment still wins, so a deliberate override is unaffected.
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"
export OBJC="${OBJC:-clang}"

# Detect NextBSD - libdispatch is provided by the base system
if [ -d "/usr/lib/system" ]; then
  NEXTBSD=1
  echo "NextBSD detected: base ships a HAVE_MACH libdispatch in /usr/lib/system (daemons);"
  echo "  the Gershwin domain builds its own non-Mach libdispatch into /System/Library/Libraries"
  # config.guess does not recognize NextBSD; tell configure we are FreeBSD
  ARCH=$(uname -m)
  case "$ARCH" in
    amd64) ARCH="x86_64" ;;
  esac
  BUILD_FLAG="--build=${ARCH}-nextbsd-freebsd"
  CMAKE_SYSTEM_FLAG="-DCMAKE_SYSTEM_NAME=FreeBSD"
else
  NEXTBSD=0
  BUILD_FLAG=""
  CMAKE_SYSTEM_FLAG=""
fi

# On OpenBSD, X11 headers/libs live under /usr/X11R6, which clang does not search
# by default. Export the flags once here so they apply to every build stage:
#   - CFLAGS/OBJCFLAGS/CPPFLAGS let the compilers (and autoconf configure scripts)
#     find the X11 headers.
#   - LDFLAGS and LIBRARY_PATH let the linker find libX11 regardless of how a given
#     package's makefiles handle link flags.
if [ "$(uname -s)" = "OpenBSD" ]; then
  export CFLAGS="${CFLAGS:+$CFLAGS }-I/usr/X11R6/include"
  export OBJCFLAGS="${OBJCFLAGS:+$OBJCFLAGS }-I/usr/X11R6/include"
  export CPPFLAGS="${CPPFLAGS:+$CPPFLAGS }-I/usr/X11R6/include"
  export LDFLAGS="${LDFLAGS:+$LDFLAGS }-L/usr/X11R6/lib"
  export LIBRARY_PATH="/usr/X11R6/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
fi

# Windows: the build runs in an MSYS2 MINGW64 shell with the mingw-w64 clang
# toolchain, and /System is a directory inside the MSYS2 root (for the shell
# and make it is /System; for native programs such as cmake and the compiled
# binaries it is <msys2 root>\System).
#   - The gnustep-2.x ABI needs lld, and libobjc2's exception handling defers
#     to the C++ runtime, so both are linked into everything. Exported once so
#     tools-make records them and every later configure inherits them.
#   - PATH gets /System/Library/Tools early: on Windows the DLLs live next to
#     the tools, and configure's link/run tests need to find them before
#     GNUstep.sh exists.
#   - Native tools get the Windows spelling of /System (cygpath -m) because
#     cmake cannot resolve MSYS2 paths.
#   - The library builds get a few clang warnings demoted the way the MSYS2
#     packages of gnustep-base/-gui/-back do: the upstream code has no Windows
#     CI and trips them under a recent clang.
WINDOWS=0
if [ "$PLATFORM" = "windows" ]; then
  WINDOWS=1
  export LDFLAGS="${LDFLAGS:+$LDFLAGS }-fuse-ld=lld -lstdc++ -lgcc_s"
  export PATH="/System/Library/Tools:$PATH"
  SYSTEM_W="$(cygpath -m /System)"
  WIN_OBJCFLAGS="-Wno-error=incompatible-pointer-types -Wno-int-to-pointer-cast -Wno-pointer-to-int-cast -Wno-format"
  mkdir -p /System/Library/Headers /System/Library/Libraries /System/Library/Tools
fi

# Source the GNUstep environment, which is installed by the corelibs stage via
# tools-make.  The corelibs stage sources it itself at the right moment, so this
# is only used by the individual app/component stages when they are run on their
# own (e.g. "make workspace" in CI after "make corelibs").
ensure_gnustep_env() {
  if [ ! -f /System/Library/Makefiles/GNUstep.sh ]; then
    echo "GNUstep environment not found at /System/Library/Makefiles/GNUstep.sh."
    echo "Build the core libraries first:  make corelibs"
    exit 1
  fi
  . /System/Library/Makefiles/GNUstep.sh
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"
}

# --- corelibs, split into one build_<repo>/install_<repo> pair per
# repository so Software Update can run "build-repo <name>" then
# "install-repo <name>" with a rollback point in between. build_corelibs/
# install_corelibs (below) call these in the original order for the existing
# "make corelibs"/"make all" entry points, so nothing here changes what CI runs
# - only how finely it can be driven.
#
# GNUstep itself does not exist yet until tools-make is installed, so the
# functions up to and including tools-make export GNUSTEP_INSTALLATION_DOMAIN
# by hand instead of sourcing GNUstep.sh; everything from libobjc2 onward
# calls ensure_gnustep_env like every other top-level target.

build_gershwin_system() {
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"
  cd "$REPOS_DIR/gershwin-system"
  $MAKE_CMD
}

install_gershwin_system() {
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"
  cd "$REPOS_DIR/gershwin-system"
  $MAKE_CMD install
}

build_gershwin_assets() {
  : # nothing to build; gershwin-assets is a plain copy, done on install
}

install_gershwin_assets() {
  cd "$REPOS_DIR/gershwin-assets"
  cp -R Library/* /System/Library/
}

build_libdispatch() {
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"

  # Patch libdispatch (FreeBSD timer-spin fix; harmless on other platforms).
  echo "Patching libdispatch..."
  patch.sh swift-corelibs-libdispatch

  # Gershwin apps must link the portable, NON-Mach libdispatch. On stock
  # FreeBSD/Linux this happens automatically (no <mach/mach.h> present, so the
  # HAVE_MACH code is never compiled). NextBSD, however, ships libmach's
  # <mach/mach.h> system-wide, so libdispatch's `#if __has_include(<mach/mach.h>)`
  # guards auto-enable the Darwin Mach/QoS (direct-knote) event backend. That
  # backend is wrong for FreeBSD's kqueue (0x0100 == EV_FORCEONESHOT; udata is not
  # part of knote identity) and breaks GNUstep's fd-based dispatch sources - most
  # visibly, the global menu's WindowMonitor never tracks the frontmost app.
  # So on NextBSD we force those guards off to reproduce the stock non-Mach build
  # and install it to /System/Library/Libraries, which Gershwin binaries' RUNPATH
  # resolves ahead of /usr/lib/system. The NextBSD base's HAVE_MACH libdispatch in
  # /usr/lib/system is left in place for the system daemons (launchd/XPC/notifyd).
  DISPATCH_EXTRA_FLAGS=""
  if [ "$NEXTBSD" -eq 1 ]; then
    echo "NextBSD: forcing non-Mach libdispatch for the Gershwin domain"
    ( cd "$REPOS_DIR/swift-corelibs-libdispatch" && \
      grep -rl "__has_include(<mach/mach.h>)" . 2>/dev/null | grep -vE "/\.git/|/Build/" | \
      xargs -r sed -i.nbsdbak "s#__has_include(<mach/mach.h>)#0#g" )
    DISPATCH_EXTRA_FLAGS="-DHAVE_MACH=OFF"
  fi

  echo "Building libdispatch..."
  if [ -d "$REPOS_DIR/swift-corelibs-libdispatch/Build" ] ; then
    rm -rf "$REPOS_DIR/swift-corelibs-libdispatch/Build"
  fi
  mkdir -p "$REPOS_DIR/swift-corelibs-libdispatch/Build"

  cd "$REPOS_DIR/swift-corelibs-libdispatch/Build"

  # $CMAKE_SYSTEM_FLAG (-DCMAKE_SYSTEM_NAME=FreeBSD on NextBSD, empty elsewhere):
  # without it CMake can't match NextBSD's uname to a platform module, so it never
  # sets CMAKE_SHARED_LIBRARY_SONAME_C_FLAG and emits libBlocksRuntime.so with no
  # SONAME - which makes libdispatch record a build-relative NEEDED
  # (../libBlocksRuntime.so) that fails to load. Telling CMake it's FreeBSD lets it
  # set the soname itself, exactly like the base and libobjc2 builds do.
  cmake .. \
    $CMAKE_SYSTEM_FLAG \
    -DCMAKE_INSTALL_PREFIX=/System/Library \
    -DCMAKE_INSTALL_LIBDIR=Libraries \
    -DINSTALL_DISPATCH_HEADERS_DIR=/System/Library/Headers/dispatch \
    -DINSTALL_BLOCK_HEADERS_DIR=/System/Library/Headers \
    -DINSTALL_OS_HEADERS_DIR=/System/Library/Headers/os \
    -DINSTALL_PRIVATE_HEADERS=ON \
    -DCMAKE_INSTALL_MANDIR=Documentation/man \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    $DISPATCH_EXTRA_FLAGS

  "$MAKE_CMD" -j"$CPUS" || exit 1
}

install_libdispatch() {
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"
  cd "$REPOS_DIR/swift-corelibs-libdispatch/Build"
  "$MAKE_CMD" install || exit 1
}

build_toolsmake() {
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"

  # Build tools-make - can now find _Block_copy in libdispatch's BlocksRuntime
  # Use libobjc_LIBS=" " to prevent configure from adding -lobjc to link tests
  echo "Building tools-make..."
  cd "$REPOS_DIR/tools-make"
  $MAKE_CMD distclean 2>/dev/null || true
  if [ "$WINDOWS" -eq 1 ]; then
    # libobjc2 is already installed here (see build_libobjc2_windows), so no
    # need to keep -lobjc out of the configure link tests. The gershwin layout
    # and its POSIX /System paths are what tools-make wants on Windows too:
    # it requires unix-style paths in GNUstep.conf, and libs-base rewrites
    # them relative to its DLL for the native programs at its configure time.
    ./configure \
      --with-config-file=/System/Library/Preferences/GNUstep.conf \
      --with-layout=gershwin \
      --with-library-combo=ng-gnu-gnu \
      CC=clang CXX=clang++ \
      LDFLAGS="-L/System/Library/Libraries $LDFLAGS" \
      CPPFLAGS="-I/System/Library/Headers"
    $MAKE_CMD || exit 1
    return
  fi
  # $BUILD_FLAG is --build=<arch>-nextbsd-freebsd on NextBSD (config.guess can't
  # recognize NextBSD's uname), empty elsewhere - harmless on FreeBSD/Linux.
  ./configure \
    $BUILD_FLAG \
    --with-config-file=/System/Library/Preferences/GNUstep.conf \
    --with-layout=gershwin \
    --with-library-combo=ng-gnu-gnu \
    --with-objc-lib-flag=" " \
    LDFLAGS="-L/System/Library/Libraries" \
    CPPFLAGS="-I/System/Library/Headers" \
    libobjc_LIBS=" "
  $MAKE_CMD || exit 1
}

install_toolsmake() {
  export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"
  cd "$REPOS_DIR/tools-make"
  $MAKE_CMD install
}

build_libobjc2() {
  if [ "$WINDOWS" -eq 1 ]; then
    build_libobjc2_windows
    return
  fi
  ensure_gnustep_env

  echo "Building libobjc2..."
  if [ -d "$REPOS_DIR/libobjc2/Build" ] ; then
    rm -rf "$REPOS_DIR/libobjc2/Build"
  fi
  mkdir -p "$REPOS_DIR/libobjc2/Build"

  cd "$REPOS_DIR/libobjc2/Build"

  cmake .. \
    -DGNUSTEP_INSTALL_TYPE=SYSTEM \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DEMBEDDED_BLOCKS_RUNTIME=OFF \
    -DBlocksRuntime_INCLUDE_DIR=/System/Library/Headers \
    -DBlocksRuntime_LIBRARIES=/System/Library/Libraries/libBlocksRuntime.so

  "$MAKE_CMD" -j"$CPUS" || exit 1
}

install_libobjc2() {
  if [ "$WINDOWS" -eq 1 ]; then
    cd "$REPOS_DIR/libobjc2/Build"
    ninja install || exit 1
    # libobjc2 installs its headers under include/ when it is not told the
    # GNUstep layout (it cannot be: tools-make does not exist yet). GNUstep
    # looks in Headers, so move them there.
    if [ -d /System/Library/include ]; then
      cp -R /System/Library/include/. /System/Library/Headers/
      rm -rf /System/Library/include
    fi
    return
  fi
  ensure_gnustep_env
  cd "$REPOS_DIR/libobjc2/Build"
  "$MAKE_CMD" install || exit 1
}

# On Windows there is no libdispatch, so libobjc2 keeps its embedded blocks
# runtime, and it is built before tools-make (whose configure needs an
# Objective-C runtime and _Block_copy to link its tests) - the reverse of the
# other platforms, where libdispatch's BlocksRuntime comes first. Ninja and
# explicit install directories, because without tools-make there is no
# gnustep-config for the GNUSTEP_INSTALL_TYPE=SYSTEM lookup. The DLL goes to
# Tools (that is where tools-make puts DLLs on Windows and what GNUstep.sh
# puts on PATH), the import library to Libraries.
build_libobjc2_windows() {
  echo "Building libobjc2 (Windows)..."
  rm -rf "$REPOS_DIR/libobjc2/Build"
  mkdir -p "$REPOS_DIR/libobjc2/Build"
  cd "$REPOS_DIR/libobjc2/Build"
  cmake .. -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DGNUSTEP_INSTALL_TYPE=NONE \
    -DCMAKE_INSTALL_PREFIX="$SYSTEM_W/Library" \
    -DCMAKE_INSTALL_LIBDIR=Libraries \
    -DCMAKE_INSTALL_BINDIR=Tools \
    -DTESTS=OFF
  ninja || exit 1
}

build_libsbase() {
  ensure_gnustep_env
  cd "$REPOS_DIR/libs-base"

  # Patch libs-base (64-bit _4CF main-queue handle fix for Apple libdispatch;
  # run loop performers queued behind one that runs a nested run loop, such
  # as a modal panel, still fire, so windows keep redrawing).
  echo "Patching libs-base..."
  patch.sh libs-base

  if [ "$WINDOWS" -eq 1 ]; then
    # No libdispatch on Windows (upstream does not use it there either).
    ./configure --disable-libdispatch
    $MAKE_CMD -j"$CPUS" OBJCFLAGS="$WIN_OBJCFLAGS" || exit 1
    return
  fi
  if [ "$NEXTBSD" -eq 1 ]; then
    # NextBSD ships libdns_sd (the mDNSResponder DNS-SD client) in
    # /usr/lib/system, which is on binaries' runtime RUNPATH but is NOT a
    # default link-time search dir. Without -L/usr/lib/system, libs-base
    # configure's AC_CHECK_LIB(dns_sd, DNSServiceBrowse) link test fails, so
    # HAVE_MDNS is set to 0 and NSNetServiceBrowser/NSNetService are built with
    # NO zeroconf backend: their +allocWithZone: then returns nil and the
    # [[NSNetServiceBrowser alloc] init] in the Network view SIGSEGVs
    # (Workspace, NetworkBrowser, RemoteDesktop). Adding the -L makes the mDNS
    # backend detect+link. /System/Library/Libraries is listed FIRST so
    # dispatch/objc/BlocksRuntime keep linking from the Gershwin (non-Mach)
    # domain; /usr/lib/system is only for the base-only libdns_sd. Runtime
    # dispatch resolution is unchanged (governed by RUNPATH, verified via ldd).
    ./configure \
      $BUILD_FLAG \
      --with-dispatch-include=/usr/include \
      --with-dispatch-library=/System/Library/Libraries \
      --with-zeroconf-api=mdns \
      LDFLAGS="-L/System/Library/Libraries -L/usr/lib/system"
  else
    ./configure \
      --with-dispatch-include=/System/Library/Headers \
      --with-dispatch-library=/System/Library/Libraries
  fi
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_libsbase() {
  ensure_gnustep_env
  cd "$REPOS_DIR/libs-base"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_libsgui() {
  ensure_gnustep_env

  # Patch libs-gui
  echo "Patching libs-gui..."
  patch.sh libs-gui

  cd "$REPOS_DIR/libs-gui"
  ./configure $BUILD_FLAG
  if [ "$WINDOWS" -eq 1 ]; then
    $MAKE_CMD -j"$CPUS" OBJCFLAGS="$WIN_OBJCFLAGS" || exit 1
    return
  fi
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_libsgui() {
  ensure_gnustep_env
  cd "$REPOS_DIR/libs-gui"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_libsback() {
  ensure_gnustep_env

  # Patch libs-back
  echo "Patching libs-back..."
  patch.sh libs-back # https://github.com/gnustep/libs-back/issues/74

  cd "$REPOS_DIR/libs-back"
  export fonts=no
  if [ "$WINDOWS" -eq 1 ]; then
    # The win32 window server (libs-back's default on mingw) drawing through
    # cairo, the same combination MSYS2 packages.
    ./configure --enable-graphics=cairo
    $MAKE_CMD -j"$CPUS" OBJCFLAGS="$WIN_OBJCFLAGS" || exit 1
    return
  fi
  ./configure $BUILD_FLAG
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_libsback() {
  ensure_gnustep_env
  cd "$REPOS_DIR/libs-back"
  export fonts=no
  if [ "$WINDOWS" -eq 1 ]; then
    $MAKE_CMD install OBJCFLAGS="$WIN_OBJCFLAGS"
    $MAKE_CMD clean
    # The plistupdate hook is skipped on Windows: the rule it injects is
    # guarded with "command -v plistupdate || true", so nothing later misses it.
    return
  fi
  $MAKE_CMD install
  $MAKE_CMD clean

  # Hook into tools-make to inject build time and git hash into
  # Info-gnustep.plist files. This is an internal build-time helper living
  # inside the gershwin-components tree (not a repository of its own), needed
  # from here on by every later build, so it is tied to libs-back's install
  # rather than exposed as a separate build-repo/install-repo target.
  cd "$REPOS_DIR/gershwin-components/plistupdate"
  $MAKE_CMD CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
  $MAKE_CMD install
  sh -e ./setup-integration.sh
  $MAKE_CMD clean
}

build_libsav() {
  ensure_gnustep_env

  # Patch libs-av
  echo "Patching libs-av..."
  patch.sh libs-av # https://github.com/gnustep/libs-av/pull/1

  cd "$REPOS_DIR/libs-av"
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_libsav() {
  ensure_gnustep_env
  cd "$REPOS_DIR/libs-av"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_corelibs() {
  if [ "$WINDOWS" -eq 1 ]; then
    # No gershwin-system (X session scripts and Unix defaults), no libdispatch,
    # no libs-av (ffmpeg): the Windows domain is the GNUstep stack plus the
    # fonts and pictures. libobjc2 before tools-make, see build_libobjc2_windows.
    build_gershwin_assets;   install_gershwin_assets
    build_libobjc2;          install_libobjc2
    build_toolsmake;         install_toolsmake
    build_libsbase;          install_libsbase
    build_libsgui;           install_libsgui
    build_libsback;          install_libsback
    return
  fi
  build_gershwin_system;   install_gershwin_system
  build_gershwin_assets;   install_gershwin_assets
  build_libdispatch;       install_libdispatch
  build_toolsmake;         install_toolsmake
  build_libobjc2;          install_libobjc2
  build_libsbase;          install_libsbase
  build_libsgui;           install_libsgui
  build_libsback;          install_libsback
  build_libsav;            install_libsav
}

build_workspace() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-workspace"
  # OpenBSD ships autoconf and automake with version-suffixed binaries;
  # autoreconf needs these env vars to pick the right versions.
  if [ "$(uname -s)" = "OpenBSD" ]; then
    export AUTOCONF_VERSION
    export AUTOMAKE_VERSION
    AUTOCONF_VERSION=$(ls /usr/local/bin/autoconf-* 2>/dev/null | sed 's|.*/autoconf-||' | sort -V | tail -1)
    AUTOMAKE_VERSION=$(ls /usr/local/bin/automake-* 2>/dev/null | sed 's|.*/automake-||' | sort -V | tail -1)
    echo "Using AUTOCONF_VERSION=$AUTOCONF_VERSION AUTOMAKE_VERSION=$AUTOMAKE_VERSION"
  fi
  autoreconf -fi
  if [ "$WINDOWS" -eq 1 ]; then
    # No D-Bus, AppImage/squashfs, libdispatch or the sqlite-backed metadata
    # indexer on Windows; the workspace's own GNUmakefiles leave out the X11
    # and Unix-only parts when GNUSTEP_TARGET_OS is mingw.
    ./configure --disable-dbus --disable-squashfs --disable-libdispatch --disable-gwmetadata
    $MAKE_CMD -j"$CPUS" || exit 1
    return
  fi
  ./configure $BUILD_FLAG
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_workspace() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-workspace"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_systempreferences() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-systempreferences"
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_systempreferences() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-systempreferences"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_eau_theme() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-eau-theme"
  $MAKE_CMD -j"$CPUS" || exit 1
}

install_eau_theme() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-eau-theme"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_terminal() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-terminal"
  # On glibc based Linux systems, -liconv should not be used as iconv is part of glibc
  # TODO: Port this fix to GNUmakefile.preamble properly
  if [ "$(uname)" = "Linux" ] ; then
    sed -i -e 's|-liconv ||g' GNUmakefile.preamble
    $MAKE_CMD CPPFLAGS="-D__GNU__ -DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1 # Do not include termio.h which is outdated
  else
    $MAKE_CMD CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
  fi
}

install_terminal() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-terminal"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_textedit() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-textedit"
  $MAKE_CMD CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
}

install_textedit() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-textedit"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_windowmanager() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-windowmanager/"
  $MAKE_CMD CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
}

install_windowmanager() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-windowmanager/"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_components() {
  ensure_gnustep_env
  # Components with a .DISABLED file in their directory will not be built
  cd "$REPOS_DIR/gershwin-components/"
  $MAKE_CMD CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
}

install_components() {
  ensure_gnustep_env
  cd "$REPOS_DIR/gershwin-components/"
  $MAKE_CMD install
  $MAKE_CMD clean
}

build_driveui() {
  # DriveUI tooling (the runtime DriveUI.bundle, the drive_ui CLI and the
  # run_uitest / uitest_tests harness) lives in this repository rather than
  # under Library/Sources, so build it from here.  Each piece is installed
  # separately; the bundle and the tools must end up in /System before the
  # desktop is started for "make test".
  cd "$WORKDIR/DriveUI"
  $MAKE_CMD -j"$CPUS" || exit 1
  $MAKE_CMD install
  $MAKE_CMD clean
  ( cd drive_ui && $MAKE_CMD -j"$CPUS" && $MAKE_CMD install && $MAKE_CMD clean ) || exit 1
  ( cd uitest && $MAKE_CMD -j"$CPUS" && $MAKE_CMD install && $MAKE_CMD clean ) || exit 1
  ( cd uitest/Tests && $MAKE_CMD -j"$CPUS" && $MAKE_CMD install && $MAKE_CMD clean ) || exit 1
}

# UI-test scripts can launch helper apps by name ("launch application X"),
# but run_uitest only starts apps found in the standard .app locations, and
# the isolated session runs as a dedicated test user whose HOME differs from
# this install's.  Fixture apps are therefore installed into
# /System/Library/CoreServices/Applications, next to other system helpers
# that users do not launch manually (Menu, ...), where every user's
# run_uitest finds them.  The <app>_INSTALL_DIR override on the command line
# beats any value the fixture's own GNUmakefile sets.
build_ui_test_fixtures() {
  ensure_gnustep_env
  if [ -d "$REPOS_DIR/gershwin-eau-theme/Test" ]; then
    ( cd "$REPOS_DIR/gershwin-eau-theme/Test" && \
      $MAKE_CMD alerttest_INSTALL_DIR="/System/Library/CoreServices/Applications" install && \
      $MAKE_CMD clean ) || exit 1
  fi
}

# Map a Repositories.plist repository Name to its build_/install_ function.
# Shared by the granular "build-repo"/"install-repo" entry points (used by
# Software Update, which runs build then install per repository with a
# rollback point in between) and by the coarse per-target/"all" cases below,
# so both paths run the exact same code. gershwin-developer, docs and the
# wiki are metadata/content repositories with no build step; libs-steptalk is
# pinned and cloned but has no build stage yet either.
build_one_repo() {
  case "$1" in
    gershwin-system)            build_gershwin_system ;;
    gershwin-assets)            build_gershwin_assets ;;
    swift-corelibs-libdispatch) build_libdispatch ;;
    tools-make)                 build_toolsmake ;;
    libobjc2)                   build_libobjc2 ;;
    libs-base)                  build_libsbase ;;
    libs-gui)                   build_libsgui ;;
    libs-back)                  build_libsback ;;
    libs-av)                    build_libsav ;;
    gershwin-systempreferences) build_systempreferences ;;
    gershwin-workspace)         build_workspace ;;
    gershwin-eau-theme)         build_eau_theme ;;
    gershwin-terminal)          build_terminal ;;
    gershwin-textedit)          build_textedit ;;
    gershwin-windowmanager)     build_windowmanager ;;
    gershwin-components)        build_components ;;
    # Metadata/content repositories and not-yet-buildable pins genuinely
    # have no build step - this is success, not the unknown-repository case
    # below, which is why each is named explicitly rather than folded into
    # the fallback (a real typo or newly-added repo missing its case here
    # must still fail loudly, not silently look like "nothing to build").
    gershwin-developer|docs|gershwin-desktop.wiki|libs-steptalk)
      echo "No build step for repository: $1 (metadata/content or not-yet-buildable pin)"
      ;;
    *)
      echo "No build step for repository: $1" >&2
      exit 1
      ;;
  esac
}

install_one_repo() {
  case "$1" in
    gershwin-system)            install_gershwin_system ;;
    gershwin-assets)            install_gershwin_assets ;;
    swift-corelibs-libdispatch) install_libdispatch ;;
    tools-make)                 install_toolsmake ;;
    libobjc2)                   install_libobjc2 ;;
    libs-base)                  install_libsbase ;;
    libs-gui)                   install_libsgui ;;
    libs-back)                  install_libsback ;;
    libs-av)                    install_libsav ;;
    gershwin-systempreferences) install_systempreferences ;;
    gershwin-workspace)         install_workspace ;;
    gershwin-eau-theme)         install_eau_theme ;;
    gershwin-terminal)          install_terminal ;;
    gershwin-textedit)          install_textedit ;;
    gershwin-windowmanager)     install_windowmanager ;;
    gershwin-components)        install_components ;;
    gershwin-developer|docs|gershwin-desktop.wiki|libs-steptalk)
      echo "No install step for repository: $1 (metadata/content or not-yet-buildable pin)"
      ;;
    *)
      echo "No install step for repository: $1" >&2
      exit 1
      ;;
  esac
}

# Dispatch on the requested target.  Default "all" reproduces the original
# end-to-end System Domain install in the exact same order.  "build-repo"/
# "install-repo" additionally let a caller drive one repository at a time.
TARGET="${1:-all}"
case "$TARGET" in
  build-repo)
    build_one_repo "$2"
    ;;
  install-repo)
    install_one_repo "$2"
    ;;
  corelibs)
    build_corelibs
    ;;
  workspace)
    # gershwin-workspace's MDIndexing prefPane links the PreferencePanes
    # framework (installed by gershwin-systempreferences); build that first
    # so <PreferencePanes/PreferencePanes.h> resolves. Not on Windows, where
    # the metadata indexer (and with it MDIndexing) is not built.
    if [ "$WINDOWS" -eq 0 ]; then
      build_systempreferences; install_systempreferences
    fi
    build_workspace;         install_workspace
    ;;
  systempreferences)
    build_systempreferences; install_systempreferences
    ;;
  eau-theme)
    build_eau_theme; install_eau_theme
    ;;
  terminal)
    build_terminal; install_terminal
    ;;
  textedit)
    build_textedit; install_textedit
    ;;
  windowmanager)
    build_windowmanager; install_windowmanager
    ;;
  components)
    build_components; install_components
    ;;
  tooling)
    ensure_gnustep_env
    build_driveui
    ;;
  test)
    ensure_gnustep_env
    build_driveui
    build_ui_test_fixtures
    # CI containers have no X session, so run the suite on a fresh virtual
    # display as a dedicated test user rather than the default "session" mode.
    UITEST_SESSION=isolated sh "$WORKDIR/Library/Scripts/run-uitests.sh"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "UI tests failed (exit $rc)" >&2
      exit "$rc"
    fi
    ;;
  all)
    build_corelibs
    # workspace's MDIndexing prefPane depends on the PreferencePanes
    # framework, so systempreferences must be built first.
    build_systempreferences; install_systempreferences
    build_workspace;         install_workspace
    build_eau_theme;         install_eau_theme
    build_terminal;          install_terminal
    build_textedit;          install_textedit
    build_windowmanager;     install_windowmanager
    build_components;        install_components
    build_driveui
    ;;
  *)
    echo "Unknown target: $TARGET"
    echo "Valid targets: corelibs workspace systempreferences eau-theme terminal textedit windowmanager components tooling test all"
    echo "Or: build-repo <name> / install-repo <name> for one repository from Library/Repositories.plist"
    exit 1
    ;;
esac

echo ""
echo "Done."
