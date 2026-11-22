#!/bin/sh
set -e

# Refresh this repository itself before checkout.sh runs, so a build never uses
# a stale checkout.sh, patch set or install script.  Deliberately non-fatal:
# local commits, a detached HEAD, a dirty tree or no network all leave the
# working copy exactly as it is and the build carries on.
#
# Skip it entirely -- e.g. in CI, which supplies its own checkout -- with:
#   SELF_UPDATE=0 make install
#
# Note that make has already read the Makefile by the time this runs, so a
# pulled change to the Makefile itself only takes effect on the next run.

SELF_UPDATE="${SELF_UPDATE:-1}"

if [ "$SELF_UPDATE" = "0" ]; then
    echo "SELF_UPDATE=0; skipping the update of this checkout."
    exit 0
fi

# Work from the repository root whatever directory we were invoked from, so no
# make variable is needed for the path ($(CURDIR) is GNU make only; bmake, which
# is make on NextBSD and FreeBSD, has no such variable).
REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_DIR"

if [ ! -d .git ]; then
    echo "Not a git checkout; skipping the update of this tree."
    exit 0
fi

# "make install" runs as root, so the checkout is normally owned by another
# user and git would refuse to touch it.  Marked safe for this command only,
# rather than writing to root's global config.
GIT="git -c safe.directory=$REPO_DIR"

echo "Updating the gershwin-developer checkout..."
$GIT pull --ff-only \
    || echo "Warning: could not fast-forward this checkout; building it as it is."
