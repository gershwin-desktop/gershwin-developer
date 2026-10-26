GSToolTips: size the tooltip window for the user space scale factor

With a user space scale factor other than 1, tooltips are cut off: the window is made the size of the text as measured in points, but the window frame is in screen units, so it comes out too small by the scale factor.

To reproduce, run any application that sets a tool tip with `-GSScaleFactor 1.3` (or set `GSScaleFactor` in `NSGlobalDomain`) and hover the view. A tip reading "Break point: C4" is drawn as

```
Break
```

with the rest of the text clipped by the window's edge. With this change it reads "Break point: C4" in full; at scale factor 1 nothing changes.

`-[GSToolTips _timedOut:]` now multiplies the measured text size by the window's `userSpaceScaleFactor` before creating the tooltip window; the window's content view is in points again, so the text fits it.

cc @pkgdemon
