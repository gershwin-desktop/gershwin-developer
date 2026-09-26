.NOTPARALLEL:

# None of these targets produce a file of their own name, so they must never be
# considered up to date: "make install" rebuilds and reinstalls every time.
.PHONY: check_root install bootstrap selfupdate checkout system corelibs workspace \
	systempreferences eau-theme terminal textedit windowmanager components \
	tooling test uninstall

# On Windows (MSYS2) there is no root: /System lives inside the MSYS2 root and
# the build runs as the logged-in user, so the check is skipped there.
check_root:
	@case "`uname -s`" in \
	  MINGW*|MSYS*) ;; \
	  *) if [ `id -u` -ne 0 ]; then \
	       echo "This Makefile must be run as root or with sudo."; \
	       exit 1; \
	     fi ;; \
	esac

install: system

# Every build starts from a refreshed tree: bootstrap.sh installs the host
# packages the build needs and checkout.sh clones/updates Library/Sources.
# Both are re-run on every "make install" so an existing tree is brought up to
# date rather than built as it was left, and the install itself always runs —
# reinstalling over an existing /System is how a rebuild is deployed.
bootstrap: check_root
	@sh ./Library/Scripts/bootstrap.sh

# This checkout is refreshed before checkout.sh runs, so a build never uses a
# stale checkout.sh, patch set or install script. Non-fatal, and skipped with
# SELF_UPDATE=0 -- see the script.
selfupdate: check_root
	@sh ./Library/Scripts/self-update.sh

checkout: check_root selfupdate
	@sh ./Library/Scripts/checkout.sh

system: check_root bootstrap selfupdate checkout
	@echo "Installing GNUstep System Domain..."
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh all

# Granular build targets. Each builds a single component from
# Library/Sources, assuming the core libraries are already installed
# (run "make corelibs" first). Useful for per-repo CI.
corelibs: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh corelibs

workspace: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh workspace

systempreferences: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh systempreferences

eau-theme: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh eau-theme

terminal: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh terminal

textedit: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh textedit

windowmanager: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh windowmanager

components: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh components

# DriveUI tooling (bundle, drive_ui, run_uitest, uitest_tests harness).
tooling: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh tooling

# Build the DriveUI tooling and run the UI test suite against a built desktop
# (Menu/Workspace/WindowManager must be installed; run "make all" first).
test: check_root
	@FROM_MAKEFILE=1 sh ./Library/Scripts/install-system-domain.sh test

uninstall: check_root
	@if [ -d "/usr/lib/system" ]; then \
	  echo "NextBSD system detected. Performing selective uninstall..."; \
	  if [ -d "/System/Applications" ]; then \
	    rm -rf /System/Applications; \
	    echo "Removed /System/Applications"; \
	  fi; \
	  for dir in /System/Library/*/; do \
	    name=$$(basename "$$dir"); \
	    case "$$name" in \
	      Caches|Extensions|LaunchDaemons) \
	        echo "Keeping /System/Library/$$name";; \
	      *) \
	        rm -rf "$$dir"; \
	        echo "Removed /System/Library/$$name";; \
	    esac; \
	  done; \
	  echo "Selective uninstall complete."; \
	elif [ -d "/System/Library" ]; then \
	  rm -rf /System >/dev/null 2>&1 || true; \
	  echo "Removed GNUstep System Domain /System"; \
	  echo "Uninstallation complete: /System"; \
	else \
	  echo "GNUstep appears to be already uninstalled. Nothing was removed."; \
	fi

