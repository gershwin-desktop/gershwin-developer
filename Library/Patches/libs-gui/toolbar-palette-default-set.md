Toolbar customization palette: default set row and labels of image items

Status: prepared, not committed, not installed. Built on the pin (8f804fd)
plus every patch in /Developer/Library/Patches/libs-gui plus
nstoolbaritem-icon-only-view-width.patch, and tested on 2026-10-24 in an
isolated session with the Workspace folder window toolbar (LD_LIBRARY_PATH
to the build): the Customize item showed its label, the palette showed the
default set, and after Look Inside and Action had been dragged out of the
toolbar, dragging the default set onto it restored all five items, saved
to the defaults and passed to the other windows sharing the toolbar.

Two changes:

1. The palette replaced every item's label with its palette label, but
   -paletteLabel returns @"" (not nil) when none was set, so items without
   one lost their label, e.g. the standard Customize item. Only a non-empty
   palette label replaces the label now.

2. The default set row the palette's nib has a place for
   (_defaultTemplateView) was removed at load ("not implemented"). It is
   now a GSToolbarDefaultSetView under the caption "... or drag the default
   set into the toolbar.", showing the toolbar's default items in a row
   (spaces narrowed and unlabelled) that is dragged as a whole with the
   pasteboard type GSDefaultToolbarSetPboardType. GSToolbarView accepts that
   type while the palette runs and on drop replaces all items with the
   default ones, broadcasting to the toolbars with the same identifier, and
   saves the configuration. The palette window grows to fit the row.

The new caption string has no translations in libs-gui's .strings yet.

Upstream (2026-10-24, not pushed): split in two stacked branches in
/Developer/Library/Sources/libs-gui, each with ChangeLog and a test:
fix-toolbar-palette-labels (change 1; toolbar-palette-labels.upstream.diff and
.PR.md; worktree /Developer/Library/Sources/libs-gui-fix-toolbar-palette-labels)
and on top of it fix-toolbar-palette-default-set (change 2;
toolbar-palette-default-set.upstream.diff and .PR.md; worktree
/Developer/Library/Sources/libs-gui-fix-toolbar-palette-default-set). The
default-set PR body has a #<labels PR> placeholder to fill in once the
labels PR exists. This patch carries both and declares the pasteboard type
with APPKIT_EXPORT like GSMovableToolbarItemPboardType.
Tests: Tests/gui/NSToolbarItem/paletteItemLabel.m and
Tests/gui/NSToolbar/paletteDefaultSet.m fail on master cacd5cb08 and pass
with the branches and with pin 8f804fd plus all patches; a real xdotool
drag of the row restored the default items. On the pin (with or without
this patch) paletteDefaultSet.m crashes at exit over-releasing an NSWindow;
master does not, so that is older pin code, not this patch.
