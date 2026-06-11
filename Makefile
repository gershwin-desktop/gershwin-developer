check_root:
	@if [ `id -u` -ne 0 ]; then \
		echo "This Makefile must be run as root or with sudo."; \
		exit 1; \
	fi

install: system

system: check_root
	@if [ -d "/System/Applications" ]; then \
		echo "Gershwin System Domain appears to be already installed."; \
	else \
		echo "Installing GNUstep System Domain..."; \
		FROM_MAKEFILE=1 sh ./Library/Scripts/Install-System-Domain.sh; \
	fi

uninstall: check_root
	@if [ -d "/usr/lib/system" ]; then \
	  echo "NextBSD system detected (/usr/lib/system exists)."; \
	  echo "Cannot uninstall /System on NextBSD as it may contain system libraries."; \
	elif [ -d "/System/Library" ]; then \
	  rm -rf /System >/dev/null 2>&1 || true; \
	  echo "Removed GNUstep System Domain /System"; \
	  echo "Uninstallation complete: /System"; \
	else \
	  echo "GNUstep appears to be already uninstalled. Nothing was removed."; \
	fi
