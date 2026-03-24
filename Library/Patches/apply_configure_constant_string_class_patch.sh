#!/bin/sh

# Script to apply the libs-base configure constant-string-class patch
# Changes the -fconstant-string-class check from AC_RUN_IFELSE to AC_COMPILE_IFELSE
# semantics so it works with Clang 22+ which rejects the run-based test.

set -e  # Exit on any error

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="configure-constant-string-class.patch"
REPO_DIR="${REPO_DIR:-libs-base}"

echo "Applying patch: $PATCH_FILE to repository: $REPO_DIR"
echo "Working directory: $(pwd)"

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
echo "Applying patch..."

if patch -p1 < "$PATCH_DIR/$PATCH_FILE"; then
    echo "Patch applied successfully."
else
    echo "Error: Failed to apply patch."
    exit 1
fi

echo "Patch application complete."
