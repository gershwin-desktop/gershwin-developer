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
# Only the scripts that take part in producing /System: the test and CI
# helper scripts next to them do not change what is built.
{
  cat Library/Repositories.csv Library/OSSupport/windows.txt
  { find Library/Patches -type f
    printf '%s\n' Library/Scripts/bootstrap.sh Library/Scripts/checkout.sh \
      Library/Scripts/functions.sh Library/Scripts/patch.sh \
      Library/Scripts/install-system-domain.sh Library/Scripts/windows-bundle-runtime.sh
  } | LC_ALL=C sort | while read -r f; do
    printf '%s\n' "$f"; cat "$f"
  done
} | sha256sum | cut -c1-16
