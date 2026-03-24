# gershwin-developer

This is intended for Gershwin developers only.  For more stable packaging with applied defaults use GhostBSD.

## Supported Operating Systems

* FreeBSD
* GhostBSD (requires `pkg install -g 'GhostBSD*-dev'` for building)
* Arch Linux
* Artix (Arch Linux without systemd)
* Debian
* Devuan (Debian without systemd)

## Requirements for building

* root access
* git (e.g., `pkg install git-lite`) (NOTE: Need to use `/usr/local/bin/git` on FreeBSD freshly installed system when chrooted at the end of the installation)

## Building from source, installation and uninstallation

After installing, configuring the above requirements run the following commands as root:

```
#  Get the rest of the requirements for building
git clone https://github.com/gershwin-desktop/gershwin-developer.git /Developer
/Developer/Library/Scripts/Bootstrap.sh
/Developer/Library/Scripts/Checkout.sh
# Build and install Gershwin from sources
cd /Developer && make install
```

To remove Gershwin installed from sources run the following as root:

```
cd /Developer && make uninstall
```

## Requirements for usage

* xorg or xlibre
* At runtime, the packages mentioned in the respective `.dependencies` file

## Usage

After making sure usage requirements are met the following should be run as regular user to start Gershwin after logging in:

```
startx /System/Library/Scripts/Gershwin.sh
```

or:

```
/System/Library/Scripts/LoginWindow.sh # Starts the X server automatically
```

or, on FreeBSD/GhostBSD: 

```
service loginwindow enable && service loginwindow start
```

## Optional libraries
* libdbus for waiting for the Global Menu to appear and for implementing the FileManager1 service that lets, e.g., web browsers, open the file manager to show the downloaded files
* libsquashfs for AppImage icons

## Binaries

* https://api.cirrus-ci.com/v1/artifact/github/gershwin-desktop/gershwin-build/data/system/artifacts/FreeBSD/14/amd64/
* https://api.cirrus-ci.com/v1/artifact/github/gershwin-desktop/gershwin-build/data/system/artifacts/ArchLinux/x86_64/
* https://api.cirrus-ci.com/v1/artifact/github/gershwin-desktop/gershwin-build/data/system/artifacts/Debian/x86_64/
