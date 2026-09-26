#!/bin/sh
set -e

# The upstream (non-Gershwin) libraries are pinned by default, so the tree we
# build is the tree Library/Patches/ was written against. Track their moving
# HEADs instead — e.g. to check whether a pin can be advanced — with:
#   PINNED=0 ./Library/Scripts/checkout.sh
# Gershwin's own repositories are never pinned; they always track their branch.
#
# Build against a feature branch where it exists (e.g. a "dev" channel) with:
#   BRANCH=dev ./Library/Scripts/checkout.sh
# For each repo that HAS the branch on its remote it is cloned/checked out;
# repos without it fall back to their default branch. Unset (the default)
# leaves behaviour identical to before.

PINNED="${PINNED:-1}"

# Repositories to skip cloning/updating, given as a space- or comma-separated
# list of repo names (e.g. SKIP_REPOS="gershwin-workspace"). Useful when the
# source tree for a repo is provided by other means, such as a CI checkout of
# the repo under test.
SKIP_REPOS="${SKIP_REPOS:-}"
SKIP_REPOS=$(printf '%s' "$SKIP_REPOS" | tr ',' ' ')

# Optional branch to prefer for every repo that has it (e.g. BRANCH=dev). A repo
# without the branch silently falls back to its default branch, so a partial
# rollout works. Independent of PINNED: the pinned upstream libs don't carry
# such a branch, so their pins are unaffected.
BRANCH="${BRANCH:-}"

# On GitHub Actions, prefer the dev branch automatically when the run is for
# dev: the workflow's PR head branch, PR base branch, or the branch the run
# was dispatched from is 'dev'.  This is what makes a "Dev" run test the dev
# snapshots of the gershwin repos (which carry the uitests) without touching
# the workflow.  An explicit BRANCH= still wins.
if [ -z "$BRANCH" ]; then
  for _ref in "${GITHUB_HEAD_REF:-}" "${GITHUB_BASE_REF:-}" "${GITHUB_REF#refs/heads/}"
  do
    if [ "$_ref" = "dev" ]; then
      BRANCH=dev
      echo "Detected a dev run; preferring the dev branch for Gershwin repos."
      break
    fi
  done
fi

ON_BRANCH=""     # repos actually placed on $BRANCH (for the end-of-run summary)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/../Sources"

# The repository list, clone order, upstream pins and per-repo restart flag
# all live in Library/Repositories.csv - the same file Software Update reads
# - so there is exactly one place to change them. CSV rather than a plist so
# plain awk/cut can read it before GNUstep exists on a fresh machine; no
# field here (name, URL, sha) ever contains a comma, so no quoting is needed.
REPOS_CSV="$SCRIPT_DIR/../Repositories.csv"

# Names of every repository, in the order Repositories.csv lists them.
list_repo_names() {
    awk -F, '/^#/ { next } $1 == "" || $1 == "Name" { next } { print $1 }' "$REPOS_CSV"
}

# The clone URL for repo $1.
url_for() {
    awk -F, -v name="$1" '/^#/ { next } $1 == name { print $2; exit }' "$REPOS_CSV"
}

# The pinned commit for repo $1, or nothing if it is not pinned.
pin_for() {
    awk -F, -v name="$1" '/^#/ { next } $1 == name { print $3; exit }' "$REPOS_CSV"
}

mkdir -p "$REPOS_DIR"
cd "$REPOS_DIR"

for NAME in $(list_repo_names); do
    REPO=$(url_for "$NAME")

    case " $SKIP_REPOS " in
        *" $NAME "*)
            echo "Skipping $NAME (in SKIP_REPOS)..."
            continue
            ;;
    esac

    # Resolve which branch to use for this repo. $BRANCH is generic — any branch
    # name works (e.g. BRANCH=dev, or a feature branch you want to test). Probed
    # in the parent shell (not a subshell) so we can print a summary at the end.
    # A repo that doesn't have the branch falls back to its default branch.
    USE_BRANCH=""
    if [ -n "$BRANCH" ]; then
        if git ls-remote --exit-code --heads "$REPO" "$BRANCH" >/dev/null 2>&1; then
            USE_BRANCH="$BRANCH"
            ON_BRANCH="$ON_BRANCH $NAME"
        else
            echo "  $NAME: no '$BRANCH' branch — using default branch"
        fi
    fi

    # Only a repo that is about to be moved onto a pin skips the pull; everything
    # else (all of Gershwin's own repos) still fast-forwards as it always did.
    PIN=""
    if [ "$PINNED" -eq 1 ]; then
        PIN=$(pin_for "$NAME")
    fi

    if [ -d "$NAME/.git" ]; then
        echo "Updating $NAME..."
        (
            cd "$NAME"
            git fetch --all --tags
            if [ -n "$USE_BRANCH" ]; then
                echo "  $NAME: checking out branch '$USE_BRANCH'"
                git checkout "$USE_BRANCH"
            fi
            if [ -z "$PIN" ]; then
                # An earlier pinned run leaves the repo on a detached HEAD, and
                # --ff-only then has no branch to advance. Put it back on its
                # default branch first, so PINNED=0 un-pins an existing tree
                # rather than silently leaving it at the old pin.
                if [ -z "$USE_BRANCH" ] && ! git symbolic-ref -q HEAD >/dev/null; then
                    DEFAULT_BRANCH=$(git symbolic-ref -q --short refs/remotes/origin/HEAD || true)
                    if [ -z "$DEFAULT_BRANCH" ]; then
                        git remote set-head origin -a >/dev/null 2>&1 || true
                        DEFAULT_BRANCH=$(git symbolic-ref -q --short refs/remotes/origin/HEAD || true)
                    fi
                    DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
                    if [ -n "$DEFAULT_BRANCH" ]; then
                        echo "  $NAME: detached — returning to '$DEFAULT_BRANCH'"
                        git checkout "$DEFAULT_BRANCH"
                    fi
                fi
                git pull --ff-only
            fi
        )
    else
        echo "Cloning $NAME..."
        if [ -n "$USE_BRANCH" ]; then
            echo "  $NAME: cloning branch '$USE_BRANCH'"
        fi
        git clone ${USE_BRANCH:+--branch "$USE_BRANCH"} "$REPO"
    fi
done

# Summary of which repos were placed on $BRANCH (only when BRANCH is in play).
if [ -n "$BRANCH" ]; then
    if [ -n "$ON_BRANCH" ]; then
        echo "Branch '$BRANCH' used for:$ON_BRANCH"
    else
        echo "No repository has a '$BRANCH' branch — all on their default branch."
    fi
fi

# Apply the pinned commits (the default; PINNED=0 opts out). A repo listed in
# SKIP_REPOS was never cloned here, so it has nothing to pin.
if [ "$PINNED" -eq 1 ]; then
    echo "Checking out pinned commits..."

    for NAME in $(list_repo_names); do
        [ -d "$NAME/.git" ] || continue
        COMMIT=$(pin_for "$NAME")
        [ -n "$COMMIT" ] || continue
        echo "  $NAME -> $COMMIT"
        (
            cd "$NAME"
            git checkout "$COMMIT"
        )
    done
fi

# Gershwin's own repositories are intentionally not pinned in Repositories.plist:
# pinning them would mean the build no longer picks up our own work. These
# commits are kept only as a record of a known-good set. Do not add a Pin key
# for them.
# gershwin-windowmanager       1f3cc1c
# gershwin-components          3395d99
# gershwin-eau-theme           4babcb0
# gershwin-assets              4deb482
# gershwin-workspace           1bc3b98
# gershwin-system              cdeafb6
# gershwin-systempreferences   8d49f50
# gershwin-terminal            71124e3
# gershwin-textedit            3df6db8

# Lower CMake version requirements
# Use a temp-file approach for in-place sed to avoid -i portability issues
# across GNU/Linux, FreeBSD and OpenBSD.  All three support -E for ERE.
sed_inplace_ere() {
    _pat="$1"; _file="$2"
    _tmp="$(mktemp)"
    sed -E "$_pat" "$_file" > "$_tmp" && mv "$_tmp" "$_file"
}
# libdispatch is not cloned at all when it is in SKIP_REPOS (Windows builds
# without it), so only touch the file when it is there.
if [ -f swift-corelibs-libdispatch/CMakeLists.txt ]; then
    sed_inplace_ere \
        's/cmake_minimum_required\(VERSION 3\.[0-9]+(\.\.\.3\.[0-9]+)?\)/cmake_minimum_required(VERSION 3.20...3.99)/g' \
        swift-corelibs-libdispatch/CMakeLists.txt
fi

echo "Done."
