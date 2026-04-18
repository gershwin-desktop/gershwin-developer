#!/bin/sh

# Script to apply the libs-back _NET_WM_PID patch
# This patch stamps _NET_WM_PID on every individual GNUstep window (window->ident)
# inside window:frame:backingStore:style: so the window manager can always
# identify the owning process via the EWMH standard property.

set -e  # Exit on any error

PATCH_FILE="libs-back-net-wm-pid.patch"
REPO_DIR="libs-back"

echo "Applying patch: $PATCH_FILE to repository: $REPO_DIR"
echo "Working directory: $(pwd)"

if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: Patch file '$PATCH_FILE' not found in current directory."
    exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Repository directory '$REPO_DIR' not found."
    exit 1
fi

cd "$REPO_DIR"

echo "Entering directory: $REPO_DIR"
echo "Applying patch with verbose output..."

if patch -p1 < "../$PATCH_FILE"; then
    echo "Patch applied successfully."
else
    echo "Error: Failed to apply patch."
    exit 1
fi

echo "Patch application complete."
