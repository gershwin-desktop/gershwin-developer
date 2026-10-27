Upstream PR: https://github.com/gnustep/libs-back/pull/249

On X11, the monitor frames in `-screenList` are built from
`XRRGetScreenResources` CRTC data. An fb-only resize — `xrandr --fb`,
and what streaming servers issue on every viewport change — does not
touch the CRTC: as established upstream with Xvfb measurements, the CRTC
keeps accurately reporting the mode it still drives inside the grown
framebuffer, and the streaming server simply never sets a matching mode.
When no window manager publishes `_NET_WORKAREA`, the root geometry
(`DisplayWidth`/`DisplayHeight`, refreshed through
`XRRUpdateConfiguration` when `RRScreenChangeNotify` arrives) is the
only authority left for the screen.

Applications then lay out against a screen that no longer exists. With
GNUstep Workspace as a streamed desktop (Selkies + Xvfb with RANDR),
after 1280x800 -> 1680x1050 -> 1280x800 at GSScaleFactor 2.0 the desktop
window clamps itself against the stale 1280-wide screen and lands at
origin.x = -400, painting a quarter of the display.

When exactly one output is connected and no work area is published, this
takes the frame from the root geometry after the RANDR loop, guarded by
`workAreas == nil` so a window manager's `_NET_WORKAREA` still wins. It
composes with the existing `workAreas != nil` branch in the same
function and with the work-area API patch.

Validated upstream with a self-contained test (`Tests/x11/screenframe.m`
in the PR: runs its own Xvfb, re-executes itself per reading) with GNUstep
CI green on all five backends; originally caught here with a
pixel-assertion harness (Xvfb + RANDR, multi-hop 1280x800 <-> 1680x1050
at GSScaleFactor 2.0, Workspace desktop, 13 points per screenshot):
13/13 on baseline and after each hop on top of master @ 41c46c5, failing
deterministically without the change.

Found while running Gershwin as a remote desktop; tracking in
gershwin-desktop/issues#95. Per the landing agreement, Gershwin images
carry this diff as a patch until the upstream PR merges; the patch is
regenerated one-to-one from the reworked upstream branch and verified to
apply on the current libs-back pin (bbcc3de) on top of
`screen-work-area-api`. The test lives in the upstream PR; the patch
carries the source change only.
