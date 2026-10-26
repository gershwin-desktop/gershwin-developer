GSTheme: keep the alternating row colors below the last row

A table view with `usesAlternatingRowBackgroundColors` in a scroll view covers the clip view below its last row and paints stripes there. But when only that area is redrawn (an expose of the lower part of the window, or scrolling), it is left in the plain background color: `-drawTableViewBackgroundInClipRect:inView:withBackgroundColor:` takes its first stripe from `-rowAtPoint:` at the top of the clip rect, which is -1 below the last row, so it starts at row 0 and paints the top of the table instead of the area being redrawn. It also steps from stripe to stripe by `-rowHeight`, so the stripes do not follow rows of different heights (`-outlineView:heightOfRowByItem:`).

The tests added here redraw parts of a table and read the colors back (`cd Tests && gnustep-tests gui/NSTableView`, under Xvfb): `stripesBelowLastRow.m` redraws only the area below the last of three rows, `stripesVariableRowHeights.m` uses rows 16, 40 and 28 high and compares a full redraw, a redraw of only the area below the last row and one of only the middle against the expected stripes. Master b85f2e26e:

```
rows end at 48, table is 138 high, redrawn 48 to 96
Passed test:     stripesBelowLastRow.m:106 ... the table covers its clip view below the last row
Passed test:     stripesBelowLastRow.m:109 ... there are two distinct alternating row colours
Failed test:     stripesBelowLastRow.m:111 ... the rows drawn below the last row alternate
Failed test:     stripesBelowLastRow.m:114 ... the stripes below the last row continue those of the rows above
rows end at 84, standard row height 16, table is 138 high
Passed test:     stripesVariableRowHeights.m:198 ... the rows have the heights given by the delegate
Passed test:     stripesVariableRowHeights.m:200 ... the table covers its clip view well below the last row
Passed test:     stripesVariableRowHeights.m:203 ... there are two distinct alternating row colors
Failed test:     stripesVariableRowHeights.m:205 ... a full redraw paints a stripe per row and standard height stripes below
Failed test:     stripesVariableRowHeights.m:207 ... redrawing only the area below the last row paints the same stripes
Failed test:     stripesVariableRowHeights.m:209 ... redrawing only the middle of the table paints the same stripes
```

With this change all of them pass. The rows in the clip rect now get their stripe in their own `-rectOfRow:`, and below the last row the stripes continue at the standard row height from the end of the last row, with the colors continuing from it; the first of them is counted from the clip rect, and `-rowAtPoint:` is no longer asked for a point below the last row. The NSTableView, NSOutlineView and GSTheme test groups give the same results as on master otherwise (`rendering.m` and `state.m` fail here on master too, because of the machine's own scale factor and theme).

cc @pkgdemon
