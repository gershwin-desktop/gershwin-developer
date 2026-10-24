# table-stripes-below-last-row.patch (prepared, not committed, no PR)

GSTheme -drawTableViewBackgroundInClipRect:inView:withBackgroundColor: finds
its first stripe with -rowAtPoint:, which is -1 below the last row. It then
starts at row 0, paints the top of the table and leaves an exposed area below
the items in the plain background colour, so a table with alternating row
colours loses its stripes there after a partial redraw (window expose,
scrolling). The patch counts the rows from the clip rect's position.

Workspace's list view (gershwin-workspace FSNode/FSNListView.m,
-drawBackgroundInClipRect:) carries the same arithmetic locally; it can be
dropped once this is upstream. Reproducer: gershwin-workspace
Tests/FSNodeListView MI-LST-116 fails with the local override removed.

Upstream (2026-10-24, not pushed): branch fix-table-stripes-below-last-row in
/Developer/Library/Sources/libs-gui (worktree
/Developer/Library/Sources/libs-gui-fix-table-stripes-below-last-row), one
commit on master cacd5cb08 with ChangeLog and Tests/gui/NSTableView/
stripesBelowLastRow.m (a table in a scroll view, only the area below the
last row redrawn); text in .upstream.diff and .PR.md. The test fails on
master and on the pin 8f804fd plus the other patches, and passes with the
branch and with pin plus all patches.
