#!/bin/sh

# Script to apply the libs-gui menu mouse-up patch
# Removes the spurious "shouldFinish = YES;" in NSMenuView's mouse-up
# handler (inside the do/while event loop near the break statement).
# This line caused premature menu tracking termination.

set -e

REPO_DIR="${REPO_DIR:-libs-gui}"
TARGET="$REPO_DIR/Source/NSMenuView.m"

echo "Applying libs-gui menu mouse-up patch"

if [ ! -f "$TARGET" ]; then
    echo "Error: $TARGET not found."
    exit 1
fi

# Check if patch is already applied: the shouldFinish = YES line
# should appear 2 lines after the MouseUp type check
if grep -A2 'NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp' "$TARGET" | grep -q 'shouldFinish = YES'; then
    echo "Patch not yet applied, proceeding..."
else
    echo "Patch already applied, skipping."
    exit 0
fi

# Remove the specific "shouldFinish = YES;" line that follows the
# MouseUp check + opening brace.  Match the exact indented line.
sed -i '/NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp/{
n
/^      {$/!b
n
/shouldFinish = YES;/d
}' "$TARGET"

# Verify
if grep -A2 'NSLeftMouseUp.*NSRightMouseUp.*NSOtherMouseUp' "$TARGET" | grep -q 'shouldFinish = YES'; then
    echo "Error: Patch did not apply correctly."
    exit 1
fi

echo "Patch applied successfully."
