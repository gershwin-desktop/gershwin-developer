
#!/bin/sh
set -e

if [ "$FROM_MAKEFILE" != "1" ]; then
    echo "This script must be run from the Makefile."
    exit 1
fi

. ./Library/Scripts/Functions.sh
detect_platform
export_vars

# On OpenBSD, X11 headers/libs live under /usr/X11R6 which clang does not
# search by default.  Export CPPFLAGS/LDFLAGS for autoconf configure scripts,
# and collect the GNUstep make variables separately so they can be passed as
# discrete arguments (never fold extra args into MAKE_CMD itself, since quoted
# run_make would then be treated as a single command name by the shell).
MAKE_EXTRA_ARGS=
if [ "$(uname -s)" = "OpenBSD" ]; then
    export CPPFLAGS="${CPPFLAGS:+$CPPFLAGS }-I/usr/X11R6/include"
    export LDFLAGS="${LDFLAGS:+$LDFLAGS }-L/usr/X11R6/lib"
    MAKE_EXTRA_ARGS='ADDITIONAL_INCLUDE_DIRS=-I/usr/X11R6/include ADDITIONAL_LIB_DIRS=-L/usr/X11R6/lib'
fi

# run_make: wrapper that prepends MAKE_EXTRA_ARGS (if any) as discrete make
# variable assignments, then forwards all remaining arguments to MAKE_CMD.
run_make() {
    if [ -n "$MAKE_EXTRA_ARGS" ]; then
        # Use set -- to split MAKE_EXTRA_ARGS into separate words safely.
        set -- $MAKE_EXTRA_ARGS "$@"
    fi
    "$MAKE_CMD" "$@"
}

export REPOS_DIR="$WORKDIR/Library/Sources"

cd "$REPOS_DIR/gershwin-system"
run_make install
export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"

cd "$REPOS_DIR/gershwin-assets"
cp -R Library/* /System/Library/

# Patch libdispatch
echo "Patching libdispatch..."
( cd "$WORKDIR/Library/Patches" && REPO_DIR="$REPOS_DIR/swift-corelibs-libdispatch" sh ./apply_swift-corelibs-libdispatch_patch.sh )

# Build libdispatch first - provides BlocksRuntime needed by tools-make configure
echo "Building/installing libdispatch..."
if [ -d "$REPOS_DIR/swift-corelibs-libdispatch/Build" ] ; then
  rm -rf "$REPOS_DIR/swift-corelibs-libdispatch/Build"
fi
mkdir -p "$REPOS_DIR/swift-corelibs-libdispatch/Build"

cd "$REPOS_DIR/swift-corelibs-libdispatch/Build"

cmake .. \
  -DCMAKE_INSTALL_PREFIX=/System/Library \
  -DCMAKE_INSTALL_LIBDIR=Libraries \
  -DINSTALL_DISPATCH_HEADERS_DIR=/System/Library/Headers/dispatch \
  -DINSTALL_BLOCK_HEADERS_DIR=/System/Library/Headers \
  -DINSTALL_OS_HEADERS_DIR=/System/Library/Headers/os \
  -DINSTALL_PRIVATE_HEADERS=ON \
  -DCMAKE_INSTALL_MANDIR=Documentation/man \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++

run_make -j"$CPUS" || exit 1
run_make install || exit 1

# Build tools-make - can now find _Block_copy in libdispatch's BlocksRuntime
# Use libobjc_LIBS=" " to prevent configure from adding -lobjc to link tests
echo "Building/installing tools-make..."
cd "$REPOS_DIR/tools-make"
run_make distclean 2>/dev/null || true
./configure \
  --with-config-file=/System/Library/Preferences/GNUstep.conf \
  --with-layout=gershwin \
  --with-library-combo=ng-gnu-gnu \
  --with-objc-lib-flag=" " \
  LDFLAGS="-L/System/Library/Libraries" \
  CPPFLAGS="-I/System/Library/Headers" \
  libobjc_LIBS=" "
run_make || exit 1
run_make install

. /System/Library/Makefiles/GNUstep.sh

# Build libobjc2 - gnustep-config now available for paths
echo "Building/installing libobjc2..."
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

run_make -j"$CPUS" || exit 1
run_make install || exit 1

export GNUSTEP_INSTALLATION_DOMAIN="SYSTEM"

cd "$REPOS_DIR/libs-base"
./configure \
  --with-dispatch-include=/System/Library/Headers \
  --with-dispatch-library=/System/Library/Libraries
run_make -j"$CPUS" || exit 1
run_make install
run_make clean

# Patch libs-gui
echo "Patching libs-gui..."
( cd "$WORKDIR/Library/Patches" && REPO_DIR="$REPOS_DIR/libs-gui" sh ./apply_libs-gui-menu-mouseup_patch.sh )
( cd "$WORKDIR/Library/Patches" && REPO_DIR="$REPOS_DIR/libs-gui" sh ./apply_libs-gui-menu-dropdown-tracking_patch.sh ) # https://github.com/gnustep/libs-back/issues/76

cd "$REPOS_DIR/libs-gui"
./configure
run_make -j"$CPUS" || exit 1
run_make install
run_make clean

# Patch libs-back
echo "Patching libs-back..."
( cd "$WORKDIR/Library/Patches" && REPO_DIR="$REPOS_DIR/libs-back" sh ./apply_libs_back_net_wm_pid_patch.sh ) # https://github.com/gnustep/libs-back/issues/74

cd "$REPOS_DIR/libs-back"
export fonts=no
./configure
run_make -j"$CPUS" || exit 1
run_make install
run_make clean

# Hook into tools-make to inject build time and git hash into Info-gnustep.plist files
cd "$REPOS_DIR/gershwin-components/plistupdate"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
sh -e ./setup-integration.sh
run_make clean

# Patch gershwin-workspace: fix swap16/32/64 macro clash on OpenBSD
echo "Patching gershwin-workspace..."
( cd "$WORKDIR/Library/Patches" && REPO_DIR="$REPOS_DIR/gershwin-workspace" sh ./apply_gershwin-workspace-dsbbuddy-swap_patch.sh )

cd "$REPOS_DIR/gershwin-workspace"
# OpenBSD ships autoconf and automake with version-suffixed binaries;
# autoreconf needs these env vars to find the right versions.
if [ "$(uname -s)" = "OpenBSD" ]; then
    export AUTOCONF_VERSION
    export AUTOMAKE_VERSION
    AUTOCONF_VERSION=$(ls /usr/local/bin/autoconf-* 2>/dev/null | sed 's|.*/autoconf-||' | sort -V | tail -1)
    AUTOMAKE_VERSION=$(ls /usr/local/bin/automake-* 2>/dev/null | sed 's|.*/automake-||' | sort -V | tail -1)
    echo "Using AUTOCONF_VERSION=$AUTOCONF_VERSION AUTOMAKE_VERSION=$AUTOMAKE_VERSION"
fi
autoreconf -fi
# CPPFLAGS/LDFLAGS already exported above with X11 paths for OpenBSD.
# Pass them to configure as well so it finds X11.
./configure ${CPPFLAGS:+CPPFLAGS="$CPPFLAGS"} ${LDFLAGS:+LDFLAGS="$LDFLAGS"}
run_make -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-systempreferences"
run_make -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-eau-theme"
run_make -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-terminal"
# On glibc based Linux systems, -liconv should not be used as iconv is part of glibc
# On OpenBSD, iconv is also part of libc (no separate libiconv needed)
# TODO: Port this fix to GNUmakefile.preamble properly
if [ "$(uname)" = "Linux" ] ; then
  sed -i -e 's|-liconv ||g' GNUmakefile.preamble
  run_make CPPFLAGS="-D__GNU__ -DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1 # Do not include termio.h which is outdated
elif [ "$(uname)" = "OpenBSD" ] ; then
  sed -i '' -e 's|-liconv ||g' GNUmakefile.preamble
  run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
else
  run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
fi
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-textedit"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-windowmanager/"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Menu"
./configure || exit 1
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/DirectoryServices"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/LoginWindow"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/appwrap"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/pkgwrap"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Display"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Keyboard"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/GlobalShortcuts"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Screenshot"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Printers"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Network"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Sound"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Sharing"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Console"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/SudoAskPass"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Processes"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean

cd "$REPOS_DIR/gershwin-components/Assistants/AssistantFramework"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1

cd "$REPOS_DIR/gershwin-components/Assistants/CreateLiveMediaAssistant"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean
cd "$REPOS_DIR/gershwin-components/Assistants/InstallationAssistant"
run_make CPPFLAGS="-DGNUSTEP_INSTALL_TYPE=SYSTEM" -j"$CPUS" || exit 1
run_make install
run_make clean
cd "$REPOS_DIR/gershwin-components/Assistants/AssistantFramework"
run_make clean

echo ""
echo "Done."
