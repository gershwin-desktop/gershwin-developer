A view is clipped to its own bounds, so a theme can only mark the default button inside the button's frame. Themes that want a ring or a glow around it have no way to do so: a ring drawn from `-drawButton:in:view:style:state:` is cut off at the frame.

This adds two GSTheme methods. `-defaultButtonRingOutset` says how far outside the frame the theme draws (default 0), and `-drawDefaultButtonRingForCell:inView:` draws (default nothing). After a view has drawn its subviews and one of them is the window's default button, the view is focused again and the theme paints over them, clipped to what is being redrawn. A sibling redrawn on its own gets the ring back where it overlapped it. The superview redraws the ring area when the default cell changes (old and new), when the button moves, resizes, hides, is disabled or leaves its superview, and when the window's key state changes. With an outset of 0 no extra invalidation or focus happens, so nothing changes for existing themes. The same mechanism would serve a focus ring outside a control's frame.

Two small changes were needed on the way: NSControl clears its cell's control view in `-dealloc`, because a window keeps its default button cell after the button is gone and drawing now asks that cell for its control view; and alert panels now make their default button the panel's default button cell, which they never did.

Cost: `-displayRectIgnoringOpacity:inContext:` gains one nesting counter and one `-defaultButtonCell` call, 58 to 65 ns per display of a view in a window without a default button. In a window with one, the check costs 70 to 110 ns per displayed view, with an outset of 0 returning before any focus change; a real display of a small view costs about 45 us on the same machine.

`Tests/gui/GSTheme/defaultButtonRing.m` uses a theme subclass and reads the pixels back from a window, covering the call, the invalidation rects, partial redraws, opaque neighbors, boxes, tab views, a superview that clips the ring, an NSMatrix cell and a released button. Run under Xvfb with `-GSTheme GNUstep`:

```
master:   16 Passed, 37 Failed
          Failed test: defaultButtonRing.m:205 ... one call per display of the superview
          Failed test: defaultButtonRing.m:209 ... the ring is painted outside the button
          Failed test: defaultButtonRing.m:243 ... the old default button's ring area
          Failed test: defaultButtonRing.m:465 ... a cell does not outlive its control view
          Failed test: defaultButtonRing.m:476 ... the first button of an alert panel is its default button
with fix: 53 Passed, 0 Failed
```

`gnustep-tests` in `Tests/gui` for GSTheme, NSView, NSWindow, NSButton, NSButtonCell, NSAlert, NSBox, NSControl and NSTabView gives the same results with and without the change, apart from the new test (NSView, NSWindow and NSButton have failures here on master too). A bundle theme without a ring was compared pixel by pixel in a test window with and without the change, through every state below at scale factors 1 and 2: identical. Sheets, alert panels and the save panel were also checked in a running application.

Before and after with a Platinum-style test theme:

![window](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/window-before-after.png)

Moving the default button, disabled, inactive window, inside a box, on a tab page, in an alert sheet:

![states](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/states.png)

Enlarged at scale factor 1, 1.25 and 2 (before, after; disabled, inactive window; another color scheme before, after):

![scale 1](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/ring-scale-1.png)
![scale 1.25](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/ring-scale-125.png)
![scale 2](https://raw.githubusercontent.com/probonopd/libs-gui/pr-screenshots-default-ring/ring-scale-2.png)

cc @pkgdemon
