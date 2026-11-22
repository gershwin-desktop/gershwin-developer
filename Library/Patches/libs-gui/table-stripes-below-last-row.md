# table-stripes-below-last-row.patch (gnustep/libs-gui#1017)

GSTheme -drawTableViewBackgroundInClipRect:inView:withBackgroundColor: finds
its first stripe with -rowAtPoint:, which is -1 below the last row. It then
starts at row 0, paints the top of the table and leaves an exposed area below
the items in the plain background color, so a table with alternating row
colors loses its stripes there after a partial redraw (window expose,
scrolling). The patch paints each row's stripe in its own -rectOfRow:, so
rows of different heights (-outlineView:heightOfRowByItem:) keep theirs, and the
stripes below the last row continue at the standard row height from the end of the
last row, colors continuing from it, counted from the clip rect. The first
version counted stripes as floor(NSMinY / rowHeight), which Fred Kiefer
rejected in review because it only works when all rows have the same height.

Workspace's list view (gershwin-workspace FSNode/FSNListView.m,
-drawBackgroundInClipRect:) carries the same arithmetic locally; it can be
dropped once this is upstream. Reproducer: gershwin-workspace
Tests/FSNodeListView MI-LST-116 fails with the local override removed.

Upstream: gnustep/libs-gui#1017, branch probonopd:fix-table-stripes-below-last-row,
one commit on master b85f2e26e with ChangeLog and two tests in
Tests/gui/NSTableView: stripesBelowLastRow.m (only the area below the last of
three rows redrawn) and stripesVariableRowHeights.m (an outline view with rows
16, 40 and 28 high; a full redraw, a redraw of only the area below the last
row and one of only the middle compared with the expected stripes). Both fail
on master and on the previous version of this patch, and pass with the branch
and with pin 8f804fd plus all patches (2026-10-26). Text in .upstream.diff and
.PR.md.
