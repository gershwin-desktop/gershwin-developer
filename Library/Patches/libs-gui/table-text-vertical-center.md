# table-text-vertical-center.patch (prepared, not committed, no PR)

NSTextFieldCell draws its text at the top of its title rect. In a table or
outline view the title rect is the whole cell, so any row taller than one
line of text shows the text at the top of the row: in Eau every table made
in code gets 22 pt rows (NSTableView+Eau.m) for a ~15 pt line, and the text
sits 2 px (scale 1) / 4-5 px (scale 2) above the row center, e.g. in System
Preferences' Keyboard pane lists. NSCell's own -_drawAttributedText:inFrame:
already centers vertically; NSTextFieldCell never did.

The patch overrides -[NSTextFieldCell titleRectForBounds:]: when the cell
does not wrap and its control view is an NSTableView (outline views
included), the title rect is shrunk to one line of text and centered,
rounded to device pixels with -centerScanRect:. Drawing and the field
editor both use this rect, so editing in place lines up with the drawn
text. -editColumn:row:withEvent:select: sets the table as the edited cell's
control view, so a cell a delegate hands out fresh is centered as well.
Untouched: wrapping cells, cells outside tables (labels, text fields),
header cells (control view is the header view), rows lower than the text
(default theme: 16 pt rows, no change), NSBrowserCell (already centered).

Measured in an isolated session (cap-height center vs row center, + = too
high): Keyboard pane 22 pt rows +1.75 px -> -0.25 px at scale 1, +4.4 px ->
+0.5 px at scale 2; outline view +4.5 -> +0.5 px (scale 2); field editor
on the same pixel row as the drawn text at scale 2, 1 px above at scale 1
(as before the patch). Evidence: ~/SUPERAGENT/runs/tablecentre/.

Makes these app-side workarounds redundant once installed: Menu
ForceQuitPanel.m ForceQuitNameCell, Workspace FSNListCell (branch
feature/list-view-rows), libs-gui GSCharacterPanel.m
GSVerticallyCenteredTextFieldCell (upstream may drop it with the PR).

Upstream (2026-10-24, not pushed): branch fix-table-text-vertical-center
(worktree /Developer/Library/Sources/libs-gui-fix-table-text-vertical-center),
one commit on master cacd5cb08 with ChangeLog and
Tests/gui/NSTextFieldCell/tableTitleRect.m; comment-free diff in
.upstream.diff, PR text in .PR.md. Related open PR #944 (ours, NSTextFieldCell
truncation) touches -drawInteriorWithFrame:inView: next to the new method;
the two apply in either order.
