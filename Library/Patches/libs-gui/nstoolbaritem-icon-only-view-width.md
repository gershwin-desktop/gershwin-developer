NSToolbarItem: in icon-only mode, size an item with a view by its view

Status: prepared, not committed, not installed. Built on the pin (8f804fd)
plus every patch in /Developer/Library/Patches/libs-gui and tested on
2026-10-24 in an isolated session (LD_LIBRARY_PATH to the build): with the
Workspace toolbar's sizing workaround switched off, the installed library
made the Look Inside item 65 points next to a 44 point Action item and
pushed the search field 11 points past the window edge; with the patched
library both items were 44 points and the search field ended inside the
window.

GSToolbarBackView -layout makes every item at least ItemBackViewRegularWidth
(60 points) and as wide as its label, even in NSToolbarDisplayModeIconOnly,
where neither label nor image is shown. Two views of the same width (a button
and a pull-down button side by side) therefore end up in items of different
widths depending on how long their hidden labels are in the user's language,
and GSToolbarView's flexible-space share-out (which uses the items' minSize)
no longer matches the widths the items really get, pushing the last items out
of the window.

With the patch an icon-only item with a view is exactly its view plus the
usual insets. Found while adding the folder window toolbar to Gershwin
Workspace (branch feature/viewer-toolbar), which works around it by giving its
views the width GSToolbarView would force on them (GWViewerToolbar
-viewWidthForLabel:minimum:); that workaround has to stay until this patch is installed; with the patch
installed it is harmless in icon-only mode (the views are simply as wide as
the workaround makes them), see below for removing it.
GSToolbarButton -layout (items with an image instead of a view) has the same
code and is left alone: the 60 point minimum is reasonable for image items.

Upstream (2026-10-24, not pushed): branch fix-nstoolbaritem-icon-only-view-width
in /Developer/Library/Sources/libs-gui (worktree
/Developer/Library/Sources/libs-gui-fix-nstoolbaritem-icon-only-view-width), one
commit on master cacd5cb08 with ChangeLog and Tests/gui/NSToolbarItem/
iconOnlyViewWidth.m; text in .upstream.diff and .PR.md. Related: issue #972
(toolbar heights from content). The patch now sets the width in the
NSToolbarDisplayModeIconOnly case of the display mode switch, as the PR does.
Test: master 61 and 209 pt items for two 24 pt views, fixed 44 and 44 pt;
pin 8f804fd plus all patches gives 44 and 44 pt.
Workspace: the workaround only matters while the toolbar shows labels; the
user can pick Icon & Text in the palette, where this patch changes nothing.
