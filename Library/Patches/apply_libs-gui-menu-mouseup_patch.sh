#!/bin/sh

# Script to apply libs-gui menu tracking patches:
# 1. Remove spurious "shouldFinish = YES;" in inner event loop (breaks all menus)
# 2. Make transient/context menus use click-to-dismiss regardless of interface style

set -e

REPO_DIR="${REPO_DIR:-libs-gui}"
TARGET="$REPO_DIR/Source/NSMenuView.m"

echo "Applying libs-gui menu tracking patches"

if [ ! -f "$TARGET" ]; then
    echo "Error: $TARGET not found."
    exit 1
fi

APPLIED=0

# Patch 1: Remove shouldFinish = YES from inner event loop
if grep -A2 'NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp' "$TARGET" | grep -q 'shouldFinish = YES'; then
    echo "Applying patch 1: Remove shouldFinish = YES from inner loop..."
    sed -i '/NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp/{
n
/^      {$/!b
n
/shouldFinish = YES;/d
}' "$TARGET"
    APPLIED=$((APPLIED + 1))
else
    echo "Patch 1 already applied, skipping."
fi

# Patch 2: Make transient menus always use click-to-dismiss
# Change: ([[self menu] isTransient] && style == NSWindows95InterfaceStyle)
# To:     [[self menu] isTransient]
if grep -q 'isTransient\] && style == NSWindows95InterfaceStyle' "$TARGET"; then
    echo "Applying patch 2: Transient menu click-to-dismiss for all styles..."
    sed -i 's/.*isTransient\] && style == NSWindows95InterfaceStyle.*/      \/\/ Or if menu is transient (context\/popup menu) — keep open after\n      \/\/ the initial right-click release for click-to-dismiss behavior.\n      [[self menu] isTransient] ||/' "$TARGET"
    APPLIED=$((APPLIED + 1))
else
    echo "Patch 2 already applied, skipping."
fi

if [ "$APPLIED" -gt 0 ]; then
    echo "$APPLIED patch(es) applied successfully."
else
    echo "All patches already applied."
fi
