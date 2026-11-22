GSToolbarCustomizationPalette: offer the default set to drag back into the toolbar

Once a toolbar has been customized there is no way back to its default items in GNUstep: the customization palette's nib has a place for the default set, but `-awakeFromNib` removes it ("for now, _defaultTemplateView isn't implemented"). This is stacked on #1014, whose one-line fix the palette items of the default set need too; the diff collapses to this commit once that one is merged.

The place is now a row showing the toolbar's default items, under the caption "... or drag the default set into the toolbar.", which is dragged as a whole with the new `GSDefaultToolbarSetPboardType`. GSToolbarView accepts that type while the palette runs; on drop it replaces all items with the default ones, broadcast to the other toolbars with the same identifier as for single items, and saves the configuration. Spaces are drawn narrowed in the row, and the palette window grows to fit it.

The test added here opens the palette for a toolbar with four default items, replaces the items with another one and drops the default set on the toolbar view (`cd Tests && gnustep-tests gui/NSToolbar/paletteDefaultSet.m`, under Xvfb). Master cacd5cb08:

```
Failed test:     paletteDefaultSet.m:172 ... the palette shows the four default items as one row
Failed test:     paletteDefaultSet.m:192 ... the toolbar accepts the default set
Failed test:     paletteDefaultSet.m:195 ... dropping the default set restores the default items
default set row in the palette: missing, 0 items
toolbar after dropping the default set: Three
```

With this change:

```
Passed test:     paletteDefaultSet.m:172 ... the palette shows the four default items as one row
Passed test:     paletteDefaultSet.m:192 ... the toolbar accepts the default set
Passed test:     paletteDefaultSet.m:195 ... dropping the default set restores the default items
default set row in the palette: shown, 4 items
toolbar after dropping the default set: One, Two, NSToolbarFlexibleSpaceItem, NSToolbarCustomizeToolbarItem
```

The drag itself was also done with the pointer (`xdotool mousedown 1`, ten `mousemove` steps from the row to the toolbar, `mouseup 1`) in a small program with the same toolbar under Xvfb: the toolbar went from `Three` to `One, Two, NSToolbarFlexibleSpaceItem, NSToolbarCustomizeToolbarItem`. The NSToolbar and NSToolbarItem test groups pass. The new caption has no translations in the .strings files yet.

cc @pkgdemon
