NSTextFieldCell: center single-line text vertically in table view rows

A table or outline view whose rows are taller than one line of text (a theme that raises the row height, or an application that sets a taller row to fit icons) shows the text of its NSTextFieldCell data cells at the top of each row: `-drawInteriorWithFrame:inView:` draws into `-titleRectForBounds:`, which is the whole cell. NSCell's own `-_drawAttributedText:inFrame:` already centers text vertically; NSTextFieldCell does not. Applications work around it with a cell subclass, as GSCharacterPanel.m does with GSVerticallyCenteredTextFieldCell.

The test added here (`cd Tests && gnustep-tests gui/NSTextFieldCell/tableTitleRect.m`, under Xvfb) asks a cell whose control view is a table view for its title rect in a 40 pt high frame, and starts editing a cell in a table with 40 pt rows. Master cacd5cb08:

```
Passed test:       tableTitleRect.m:66 ... outside a table view the title rect is the whole cell
Failed test:       tableTitleRect.m:71 ... in a table view the title rect is one line high
Passed test:       tableTitleRect.m:73 ... in a table view the title rect is vertically centered
Passed test:       tableTitleRect.m:75 ... centering does not change the horizontal extent
Passed test:       tableTitleRect.m:79 ... a cell lower than its text keeps the whole rect
Passed test:       tableTitleRect.m:84 ... an empty cell keeps a centered line for the field editor
Passed test:       tableTitleRect.m:90 ... a wrapping cell keeps the whole rect
Passed test:       tableTitleRect.m:125 ... the cell is being edited
Failed test:       tableTitleRect.m:128 ... the field editor is vertically centered in the cell
```

With this change all nine pass. In a table with 22 pt rows the cap height of the text moves from 2 px above the row center to within half a pixel of it (4.4 px to 0.5 px at a scale factor of 2), and the field editor sits on the same line as the drawn text. `-titleRectForBounds:` now returns a one-line rect centered in the cell, rounded with `-centerScanRect:`, when the cell does not wrap and its control view is a table view; drawing and the field editor both use it. `-editColumn:row:withEvent:select:` sets the table view as the edited cell's control view, since a delegate may hand out a cell that was never drawn. Wrapping cells, cells outside table views (labels, text fields), header cells and rows no taller than the text (the default 16 pt row) are unchanged, and the NSTextFieldCell, NSTableView and NSOutlineView test groups give the same results as on master.

cc @pkgdemon
