Upstream PR: https://github.com/gnustep/libs-back/pull/249

On X11, the monitor frames in `-screenList` are built from
`XRRGetScreenResources` CRTC data. `RRSetScreenSize` — what `xrandr --fb`
and streaming/remote-desktop servers issue on every viewport change — does
not bump the resources config timestamp that `XRRGetScreenResources`
caches on, so `crtc_info` keeps serving the geometry from before the
resize. Xvfb additionally exposes several outputs with only one connected,
so the connected-output check inside the loop does not fire, and the one
connected monitor keeps its stale CRTC frame.

Applications then lay out against a screen that no longer exists. With
GNUstep Workspace as a streamed desktop (Selkies + Xvfb with RANDR),
after 1280x800 -> 1680x1050 -> 1280x800 at GSScaleFactor 2.0 the desktop
window clamps itself against the stale 1280-wide screen and lands at
origin.x = -400, painting a quarter of the display.

When exactly one output is connected, its frame always spans the whole X
screen, so this takes the frame from the root geometry
(`DisplayWidth`/`DisplayHeight`, refreshed through
`XRRUpdateConfiguration` when `RRScreenChangeNotify` arrives) after the
RANDR loop instead of the potentially stale CRTC.

Validated with a pixel-assertion harness (Xvfb + RANDR, multi-hop
1280x800 <-> 1680x1050 at GSScaleFactor 2.0, Workspace desktop, 13
points per screenshot): 13/13 on baseline, after the grow hop and after
the back hop, three consecutive runs, on top of master @ 41c46c5; the
same harness fails deterministically after the first hop without the
change (the original stale-frame clamping).

Found while running Gershwin as a remote desktop; tracking in
gershwin-desktop/issues#95. Per the landing agreement, Gershwin images
carry this diff as a patch until the upstream PR merges.
