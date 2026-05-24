#!/bin/sh

# Apply the gershwin-workspace DSBuddyAllocator swap-function patch.
# OpenBSD's <sys/endian.h> defines swap16/swap32/swap64 as macros which
# clash with the static helper functions of the same name in DSBuddyAllocator.m.
# The patch adds #undef guards before those definitions.

set -e

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="gershwin-workspace-dsbbuddy-swap.patch"
REPO_DIR="${REPO_DIR:-gershwin-workspace}"

echo "Applying patch: $PATCH_FILE to repository: $REPO_DIR"

if [ ! -f "$PATCH_DIR/$PATCH_FILE" ]; then
    echo "Error: Patch file '$PATCH_FILE' not found in $PATCH_DIR."
    exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Repository directory '$REPO_DIR' not found."
    exit 1
fi

cd "$REPO_DIR"

# Check if already applied
if grep -q '#undef swap16' DSStore/DSBuddyAllocator.m 2>/dev/null; then
    echo "Patch already applied, skipping."
    exit 0
fi

echo "Applying patch..."
if patch -p1 -N < "$PATCH_DIR/$PATCH_FILE"; then
    echo "Patch applied successfully."
else
    if grep -q '#undef swap16' DSStore/DSBuddyAllocator.m 2>/dev/null; then
        echo "Patch was already partially applied."
        exit 0
    fi
    echo "Error: Failed to apply patch."
    exit 1
fi

echo "Patch application complete."
