#!/bin/sh
# windows-bundle-runtime.sh - make the Windows /System self-contained.
#
# The binaries built on Windows load DLLs from the MSYS2 toolchain (the C++
# runtime for libobjc2's exception handling, libffi, libxml2, gnutls, icu,
# cairo, freetype, fontconfig, the image libraries, ...), which a stock
# Windows machine does not have. Run after "make workspace", inside the same
# UCRT64 shell, this copies every such DLL that any .exe or .dll under
# /System needs into /System/Library/Tools, next to GNUstep's own DLLs (on
# Windows tools-make puts the DLLs where the tools are, so one directory on
# PATH resolves everything), bundles a fontconfig configuration that finds
# the Windows fonts and the Gershwin fonts without any MSYS2 paths, and
# writes a Workspace.cmd launcher at the top of /System that puts the
# Tools directory on PATH, the one thing the tree needs from its environment.
set -e

case "$(uname -s)" in
  MINGW*|MSYS*) ;;
  *) echo "This script is for the MSYS2 UCRT64 build on Windows."; exit 1 ;;
esac

. /System/Library/Makefiles/GNUstep.sh
TOOLS=/System/Library/Tools
MINGW_BIN="$(cygpath -u "$MINGW_PREFIX")/bin"

echo "Bundling the MinGW runtime DLLs into $TOOLS..."
# ntldd -R lists the transitive closure of a binary's DLLs, resolved through
# PATH (which GNUstep.sh has pointed at $TOOLS, and the shell at the MSYS2
# environment's bin). Everything resolved there is toolchain runtime to
# bundle; everything else is Windows itself or already in /System. Compared
# in lower case because Windows paths are case-insensitive and ntldd reports
# them in whatever case the search found them.
MINGW_BIN_LC="$(printf '%s' "$MINGW_BIN" | tr '[:upper:]' '[:lower:]')"
find /System -type f \( -name '*.exe' -o -name '*.dll' \) | while read -r bin; do
  ntldd -R "$bin" 2>/dev/null | awk '/=>/ { print $3 }'
done | sort -u | while read -r dll; do
  dll="$(cygpath -u "$dll")"
  case "$(printf '%s' "$dll" | tr '[:upper:]' '[:lower:]')" in
    "$MINGW_BIN_LC"/*) ;;
    *) continue ;;
  esac
  name="$(basename "$dll")"
  if [ ! -f "$TOOLS/$name" ]; then
    cp "$dll" "$TOOLS/$name"
    echo "  $name"
  fi
done

# Anything a DLL loads only at run time (LoadLibrary) is invisible to ntldd.
# The ones we know of: gnutls loads its crypto and unistring helpers, cairo
# and fontconfig are direct links, libobjc2 nothing. Copy the usual suspects
# when present so a runtime probe does not fail on a stock machine.
for name in libgcc_s_seh-1.dll libwinpthread-1.dll libstdc++-6.dll; do
  if [ -f "$MINGW_BIN/$name" ] && [ ! -f "$TOOLS/$name" ]; then
    cp "$MINGW_BIN/$name" "$TOOLS/$name"
    echo "  $name"
  fi
done

echo "Bundling the fontconfig configuration..."
# fontconfig's Windows build looks for its configuration in etc/fonts next
# to (the parent of) its own DLL, so this location needs no environment
# variable at run time.
FC=/System/Library/Tools/etc/fonts
mkdir -p "$FC/conf.d"
if [ -d "$MINGW_PREFIX/etc/fonts/conf.d" ]; then
  cp "$MINGW_PREFIX"/etc/fonts/conf.d/*.conf "$FC/conf.d/" 2>/dev/null || true
fi
# A configuration of our own rather than MSYS2's: no MSYS2 paths, the
# Windows font directory, the Gershwin fonts relative to this file, and the
# per-user cache directory fontconfig knows on Windows.
cat > "$FC/fonts.conf" <<'CONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- Gershwin on Windows: bundled fontconfig configuration. -->
<fontconfig>
  <dir>WINDOWSFONTDIR</dir>
  <dir prefix="relative">../../../Fonts</dir>
  <cachedir>LOCAL_APPDATA_FONTCONFIG_CACHE</cachedir>
  <include ignore_missing="yes">conf.d</include>
</fontconfig>
CONF

if [ -x /System/Applications/Workspace.app/Workspace.exe ]; then
echo "Writing the launcher..."
# CRLF for cmd.exe. %~dp0 is the directory this launcher lives in, with a
# trailing backslash.
printf '%s\r\n' \
  '@echo off' \
  'rem Starts the Gershwin Workspace from this self-contained tree.' \
  'set "PATH=%~dp0Library\Tools;%PATH%"' \
  'start "" "%~dp0Applications\Workspace.app\Workspace.exe" %*' \
  > /System/Workspace.cmd
fi

echo "Done."
