GSTheme: keep the alternating row colours below the last row

A table view with `usesAlternatingRowBackgroundColors` in a scroll view covers the clip view below its last row and paints stripes there. But when only that area is redrawn (an expose of the lower part of the window, or scrolling), it is left in the plain background colour: `-drawTableViewBackgroundInClipRect:inView:withBackgroundColor:` takes its first stripe from `-rowAtPoint:` at the top of the clip rect, which is -1 below the last row, so it starts at row 0 and paints the top of the table instead of the area being redrawn.

The test added here redraws only the area below the last of three rows, as an expose does, and reads the colours back (`cd Tests && gnustep-tests gui/NSTableView/stripesBelowLastRow.m`, under Xvfb). Master cacd5cb08:

```
rows end at 48, table is 138 high, redrawn 48 to 96
Passed test:     stripesBelowLastRow.m:106 ... the table covers its clip view below the last row
Passed test:     stripesBelowLastRow.m:109 ... there are two distinct alternating row colours
Failed test:     stripesBelowLastRow.m:111 ... the rows drawn below the last row alternate
Failed test:     stripesBelowLastRow.m:114 ... the stripes below the last row continue those of the rows above
```

With this change all four pass. The rows are now counted from the position of the clip rect (`floor(NSMinY / rowHeight)` to `ceil(NSMaxY / rowHeight)`), the same arithmetic the loop already used to step from one stripe to the next. The NSTableView and GSTheme test groups give the same results as on master (`rendering.m` and `state.m` fail here on master too, because of the machine's own scale factor and theme).

cc @pkgdemon
