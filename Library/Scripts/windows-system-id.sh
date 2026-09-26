#!/bin/sh
# windows-system-id.sh - print the identity of the Windows core system.
#
# A hash over everything in gershwin-developer that determines what
# "make corelibs" produces on Windows: the repository pins, the patches,
# the build scripts and the package list. gershwin-developer's Windows CI
# publishes the built /System as Gershwin-System-Windows-x86_64-<id>.zip
# on its "windows-system" release, and the CI of the other repositories
# downloads the zip with the same id instead of building the stack, falling
# back to building it when no such zip exists yet. Run from anywhere; the
# result depends only on the file contents.
set -e
cd "$(dirname "$0")/../.."
{
  cat Library/Repositories.csv Library/OSSupport/windows.txt
  find Library/Patches Library/Scripts -type f | LC_ALL=C sort | while read -r f; do
    printf '%s\n' "$f"; cat "$f"
  done
} | sha256sum | cut -c1-16
