A view that returns NO from `-wantsDefaultClipping` was not clipped, but what it drew outside its frame did not last: its display and invalidation rectangles were cut at its bounds, and a superview redrawing next to it painted over that area without displaying it again.

With this change such a view can draw anywhere in the visible part of its superview. `-lockFocus`, the `-display...` methods and `-setNeedsDisplay...` no longer cut its rectangles at its bounds, the superview redisplays it wherever it redraws, and the area is redrawn when the view moves, resizes or leaves its superview. Views that keep the default clipping take the same paths as before.

The default button ring is the first user. `-[GSTheme defaultButtonRingOutset]` (default 0) says how far outside the frame a theme marks the default button. When it is not 0, the window's default button returns NO from `-wantsDefaultClipping`, limits its drawing area to the ring, and clips itself to the area being redrawn, so the theme simply draws the ring with the button, for example in `-drawButton:in:view:style:state:`. The window redraws the old and the new default button, and redraws it when its key state changes. With an outset of 0 nothing changes for existing themes. Two small changes are still needed: NSControl clears its cell's control view in `-dealloc`, because a window keeps its default button cell after the button is gone, and alert panels make their default button the panel's default button cell.

Both tests read the pixels back from a window. Run under Xvfb with `-GSTheme GNUstep`:

```
Tests/gui/NSView/wantsDefaultClipping.m
master:   8 Passed, 6 Failed
          Failed test: wantsDefaultClipping.m:148 ... and outside of it
          Failed test: wantsDefaultClipping.m:154 ... the superview redrawing next to its frame draws it again
          Failed test: wantsDefaultClipping.m:160 ... -setNeedsDisplay: covers what it draws outside its frame
          Failed test: wantsDefaultClipping.m:165 ... -setNeedsDisplayInRect: is not cut at its bounds
          Failed test: wantsDefaultClipping.m:170 ... and it draws at the new place
          Failed test: wantsDefaultClipping.m:177 ... showing it draws it again
with fix: 14 Passed, 0 Failed

Tests/gui/GSTheme/defaultButtonRing.m
master:   10 Passed, 15 Failed
          Failed test: defaultButtonRing.m:187 ... the ring is drawn outside the button
          Failed test: defaultButtonRing.m:191 ... a redraw of the superview keeps the ring
          Failed test: defaultButtonRing.m:203 ... the ring follows the button
          Failed test: defaultButtonRing.m:216 ... the window losing key redraws the ring
          ...
          Failed test: defaultButtonRing.m:293 ... a cell does not outlive its control view
          Failed test: defaultButtonRing.m:305 ... the first button of an alert panel is its default button
with fix: 25 Passed, 0 Failed
```

The tests in `Tests/gui` for GSTheme, NSView, NSWindow, NSButton, NSButtonCell, NSAlert, NSBox, NSControl, NSTabView, NSMatrix, NSClipView and NSScrollView give the same results with and without the change, apart from the new ones. The display loop now asks each subview for the area it draws in, about 50 ns per subview: a small redraw of a view with 60 buttons went from 23 to 26 us.

The screenshots are unchanged: the same theme, now drawing its ring with the button, gives the same pixels as with the earlier version of this PR at scale factors 1, 1.25 and 2.

Before and after with a Platinum-style test theme:

![window](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/window-before-after.png)

Moving the default button, disabled, inactive window, inside a box, on a tab page, in an alert sheet:

![states](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/states.png)

Enlarged at scale factor 1, 1.25 and 2 (before, after; disabled, inactive window; another color scheme before, after):

![scale 1](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/ring-scale-1.png)
![scale 1.25](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/ring-scale-125.png)
![scale 2](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/ring-scale-2.png)

cc @pkgdemon
