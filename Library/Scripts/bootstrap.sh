#!/bin/sh

# Check if the script is run as root. On Windows (MSYS2) the build is a
# per-user affair - pacman and the /System tree live inside the MSYS2 root, so
# there is no root user to require.
case "$(uname -s)" in
  MINGW*|MSYS*) ;;
  *)
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
    ;;
esac

# Detect OS. MSYS2 has no /etc/os-release, so the Windows check comes first.
case "$(uname -s)" in
  MINGW*|MSYS*) OS_ID="windows" ;;
  *) OS_ID="" ;;
esac
if [ -n "$OS_ID" ]; then
    :
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_LIKE="$ID_LIKE"
elif [ "$(uname -s)" = "NextBSD" ]; then
    OS_ID="nextbsd"
elif [ "$(uname -s)" = "FreeBSD" ]; then
    OS_ID="freebsd"
elif [ "$(uname -s)" = "OpenBSD" ]; then
    OS_ID="openbsd"
else
    echo "Unsupported or unknown OS."
    exit 1
fi

echo "Detected OS: $OS_ID"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REQUIREMENTS_FILE="$BASE_DIR/Library/OSSupport/${OS_ID}.txt"

if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "No requirements file found for OS: $OS_ID"
    echo "Expected: $REQUIREMENTS_FILE"
    exit 1
fi

echo "Checking packages in: $REQUIREMENTS_FILE"

missing=""

case "$OS_ID" in
  arch|artix|manjaro)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [ -z "$pkg" ] && continue
      if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      pacman -S --noconfirm $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  debian|devuan|ubuntu|zorin)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      pkg="${pkg%%#*}"           # strip comments after #
      pkg="$(echo "$pkg" | xargs)" # trim whitespace
      [ -z "$pkg" ] && continue
      if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Missing packages:$missing"
      echo "Updating apt cache..."
      apt-get update -y
      echo "Installing:$missing"
      DEBIAN_FRONTEND=noninteractive apt-get install -y $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  freebsd)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [ -z "$pkg" ] && continue
      if ! pkg info "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      pkg install -y $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  ghostbsd)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [ -z "$pkg" ] && continue
      if ! pkg info "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      pkg install -y $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  openbsd)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [ -z "$pkg" ] && continue
      # Strip any port-revision suffix (e.g. autoconf-2.72p0 -> autoconf-2.72)
      # and check if a package with that stem is already installed.
      stem="${pkg%p[0-9]*}"
      if ! pkg_info | grep -q "^${stem}[- ]"; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      # Install packages one by one so a single missing package doesn't abort
      # installation of the rest.
      for pkg in $missing; do
        pkg_add -I "$pkg" || echo "Warning: could not install $pkg, continuing..."
      done
    else
      echo "All required packages are already installed."
    fi
    ;;

  nextbsd)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [ -z "$pkg" ] && continue
      if ! pkg info "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      pkg install -y $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  windows)
    # MSYS2: one pacman for both the MSYS-side tools and the mingw-w64 native
    # packages. --needed skips what is already installed, so this is cheap to
    # re-run. Comment lines and blank lines in the requirements file are skipped.
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      pkg="${pkg%%#*}"
      pkg="$(echo "$pkg" | xargs)"
      [ -z "$pkg" ] && continue
      if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      pacman -S --needed --noconfirm $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  void)
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [ -z "$pkg" ] && continue
      # A local query is the only reliable installed-check here: "xbps-query -Rs"
      # searches the repositories and exits 0 even for a name that does not exist.
      if ! xbps-query "$pkg" >/dev/null 2>&1; then
        missing="$missing $pkg"
      fi
    done < "$REQUIREMENTS_FILE"

    if [ -n "$missing" ]; then
      echo "Installing:$missing"
      xbps-install -Sy $missing
    else
      echo "All required packages are already installed."
    fi
    ;;

  *)
    echo "Unsupported OS for package checking: $OS_ID"
    exit 1
    ;;
esac
