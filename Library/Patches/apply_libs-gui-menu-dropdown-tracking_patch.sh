#!/bin/sh

# Script to apply the libs-gui menu dropdown tracking fix.
# This patch ensures the top-level horizontal menu view remains available
# while tracking attached submenus, allowing the user to switch dropdowns
# by moving back over the menu bar.

set -e  # Exit on any error

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="libs-gui-menu-dropdown-tracking.patch"
REPO_DIR="${REPO_DIR:-libs-gui}"

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

echo "Entering directory: $REPO_DIR"

# Check if patch already appears to be applied.
if grep -q "\[self isHorizontal\] == YES" Source/NSMenuView.m 2>/dev/null && \
   grep -q "[self sizeToFit];" Source/NSMenu.m 2>/dev/null; then
    echo "Patch already applied, skipping."
    exit 0
fi

echo "Applying patch..."
if patch -p1 -N < "$PATCH_DIR/$PATCH_FILE"; then
    echo "Patch applied successfully."
else
    # patch -N may fail if already applied or partially applied.
    if grep -q "\[self isHorizontal\] == YES" Source/NSMenuView.m 2>/dev/null && \
       grep -q "[self sizeToFit];" Source/NSMenu.m 2>/dev/null; then
        echo "Patch appears to already be applied."
        exit 0
    fi
    echo "Error: Failed to apply patch."
    exit 1
fi

echo "Patch application complete."
