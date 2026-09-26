# gershwin-developer

This is intended for Gershwin developers only.  For more stable packaging with applied defaults use GhostBSD.

## Supported Operating Systems

* FreeBSD
* GhostBSD (requires `pkg install -g 'GhostBSD*-dev'` for building)
* OpenBSD
* Arch Linux
* Artix (Arch Linux without systemd)
* Debian
* Devuan (Debian without systemd)
* Void Linux (runit)
* Windows (MSYS2 MINGW64, see below)

## Requirements for building

* root access
* git (e.g., `pkg install git-lite`) (NOTE: Need to use `/usr/local/bin/git` on FreeBSD freshly installed system when chrooted at the end of the installation)

## Building from source, installation and uninstallation

After installing, configuring the above requirements run the following commands as root:

```
git clone https://github.com/gershwin-desktop/gershwin-developer.git /Developer
# Build and install Gershwin from sources
cd /Developer && make install
```

`make install` runs `bootstrap.sh` (installs the host packages the build needs)
and `checkout.sh` (clones/updates the sources under `Library/Sources`) itself,
every time, so re-running it picks up upstream changes and reinstalls over an
existing `/System`. The two scripts can still be run on their own — as
`make bootstrap` / `make checkout`, or directly — when only that step is wanted.

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

## Build targets

`make install` refreshes the sources and then builds and installs the entire
system domain; it runs every time, with no "already installed" short-circuit.
The build is also split into granular targets so a single component can be
(re)built on its own — useful for CI and incremental development. Every
per-component target requires the core libraries to be installed first
(`make corelibs`). All targets run as root, like `make install`.

| Target | Builds |
| --- | --- |
| `corelibs` | core libraries (libdispatch, libobjc2, tools-make, libs-base, libs-gui, libs-back) plus gershwin-system, gershwin-assets and the plistupdate hook |
| `workspace` | gershwin-workspace |
| `systempreferences` | gershwin-systempreferences |
| `eau-theme` | gershwin-eau-theme |
| `terminal` | gershwin-terminal |
| `textedit` | gershwin-textedit |
| `windowmanager` | gershwin-windowmanager |
| `components` | gershwin-components (Menu, DirectoryServices, LoginWindow, …) |

For example, build the core libraries once and then just (re)build the workspace:

```
cd /Developer
make corelibs
make workspace
```

## Building on Windows

The Windows build is the same scripts inside an MSYS2 MINGW64 shell with the
mingw-w64 clang toolchain (the gnustep-2.x ABI needs clang and lld there as
everywhere else). `/System` is a directory inside the MSYS2 root, so no root
is needed:

```
pacman -S git make
git clone https://github.com/gershwin-desktop/gershwin-developer.git
cd gershwin-developer
./Library/Scripts/bootstrap.sh      # pacman installs Library/OSSupport/windows.txt
./Library/Scripts/checkout.sh
make corelibs
make workspace
```

What the Windows domain contains: libobjc2, tools-make, libs-base, libs-gui
and libs-back (win32 window server drawing through cairo), all with the
patches from `Library/Patches/`, GNUstep's WinUXTheme (the native Windows
look, set as the default theme), plus the fonts and pictures from
gershwin-assets. Not on Windows: gershwin-system (X session scripts),
libdispatch, libs-av, the plistupdate hook, D-Bus, and the desktop
components other than the Workspace.

`.github/workflows/build-windows.yml` runs this on GitHub Actions. After
`make corelibs` it publishes the self-contained core system (with the MinGW
runtime DLLs bundled by `Library/Scripts/windows-bundle-runtime.sh`) as
`Gershwin-System-Windows-x86_64-<id>.zip` on the rolling `windows-system`
release, where `<id>` is `Library/Scripts/windows-system-id.sh`, a hash of
the pins, patches, scripts and package list. The CI of gershwin-workspace
(and of other components in the future) downloads the zip with the id of the
gershwin-developer it builds with, and only builds the stack itself when no
such zip exists yet. It then builds the Workspace on top and uploads the
whole `/System` as the workflow artifact.

## Pinned upstream libraries

The upstream libraries (`libobjc2`, `tools-make`, `libs-base`, `libs-gui`,
`libs-back`, `libs-av`, `libs-steptalk`, `swift-corelibs-libdispatch`) are
checked out at pinned commits by default, so that the sources we build are the
sources the patches in `Library/Patches/` were written against. Without the pins
an upstream commit can silently break a patch and fail the build.

Gershwin's own repositories are **never** pinned — they always track their
branch, so the build picks up our work as it lands.

To check whether a pin can be advanced, build against the upstream HEADs
instead:

```
PINNED=0 /Developer/Library/Scripts/checkout.sh
```

The pins live in the `PINS` list at the top of `checkout.sh`.

## Skipping repositories during checkout

`checkout.sh` clones every repository the build needs. Set `SKIP_REPOS` to a
space- or comma-separated list of repository names to skip cloning/updating some
of them — handy when you provide a repository's sources yourself (for example a
CI checkout of the component under test, symlinked into `Library/Sources/`):

```
SKIP_REPOS="gershwin-workspace gershwin-terminal" /Developer/Library/Scripts/checkout.sh
```

## Building against a development or feature branch

By default `checkout.sh` clones each repository's default branch. Set `BRANCH`
to build against another branch instead — most commonly a `dev` branch holding
work in progress *before it lands in the default branch*:

```
BRANCH=dev /Developer/Library/Scripts/checkout.sh
```

`BRANCH` is generic — any branch name works — so it doubles as a tool for
testing a feature branch across repositories:

```
BRANCH=my-feature /Developer/Library/Scripts/checkout.sh
```

For each repository that **has** the named branch, it is cloned/checked out on
that branch; repositories **without** it fall back to their default branch, so a
partial rollout (where only some repos have the branch yet) just works. The run
logs which repository used the branch and prints a summary at the end. Leaving
`BRANCH` unset keeps the previous behaviour, and `BRANCH` can be combined with
`PINNED` and `SKIP_REPOS`.
