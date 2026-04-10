#!/bin/sh

# Script to apply libs-gui menu tracking patches:
# 1. Remove spurious "shouldFinish = YES;" in inner event loop (breaks all menus)
# 2. Make transient/context menus use click-to-dismiss regardless of interface style
#
# Portable across Linux and FreeBSD.

set -e

REPO_DIR="${REPO_DIR:-libs-gui}"
TARGET="$REPO_DIR/Source/NSMenuView.m"

echo "Applying libs-gui menu tracking patches"

if [ ! -f "$TARGET" ]; then
    echo "Error: $TARGET not found."
    exit 1
fi

APPLIED=0

# Patch 1: Remove the "shouldFinish = YES;" line that appears right after
# the mouse-up type check + opening brace in the inner event loop.
# We identify it by context: it's the ONLY "shouldFinish = YES;" that
# is indented with exactly 10 spaces (inside the inner loop's if block).
if grep -A2 'NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp' "$TARGET" | grep -q 'shouldFinish = YES'; then
    echo "Applying patch 1: Remove shouldFinish = YES from inner loop..."
    # Use awk for portable multi-line context matching
    awk '
    /NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp/ { found=1 }
    found && /shouldFinish = YES;/ { found=0; next }
    { print }
    ' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
    APPLIED=$((APPLIED + 1))
else
    echo "Patch 1 already applied, skipping."
fi

# Patch 2: Make transient menus always use click-to-dismiss.
# Remove the "style == NSWindows95InterfaceStyle" condition so
# transient menus absorb the first mouse-up regardless of style.
if grep -q 'isTransient\] && style == NSWindows95InterfaceStyle' "$TARGET"; then
    echo "Applying patch 2: Transient menu click-to-dismiss for all styles..."
    awk '
    /isTransient\] && style == NSWindows95InterfaceStyle/ {
        print "      // Or if menu is transient (context/popup menu) -- keep open after"
        print "      // the initial right-click release for click-to-dismiss behavior."
        print "      [[self menu] isTransient] ||"
        next
    }
    { print }
    ' "$TARGET" > "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
    APPLIED=$((APPLIED + 1))
else
    echo "Patch 2 already applied, skipping."
fi

if [ "$APPLIED" -gt 0 ]; then
    echo "$APPLIED patch(es) applied successfully."
else
    echo "All patches already applied."
fi
