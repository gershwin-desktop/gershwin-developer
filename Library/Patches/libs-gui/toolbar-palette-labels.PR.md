GSToolbarCustomizationPalette: keep the label of an item without a palette label

In the toolbar customization palette every item that has no palette label of its own is shown without a label, the standard Customize, Print, Colors and Fonts items among them. `-[GSToolbarCustomizationView paletteItemsWithToolbarItems:]` replaces an item's label with its palette label whenever `-paletteLabel` is not nil, but since `-paletteLabel` returns an empty string when none was set (as AppKit does, see `Tests/gui/NSToolbarItem/paletteLabel.m`), that replaces every such label with "".

The test added here passes an item with a label only and one with a palette label through the palette (`cd Tests && gnustep-tests gui/NSToolbarItem/paletteItemLabel.m`). Master cacd5cb08:

```
palette labels: "", "Palette Label"
Failed test:     paletteItemLabel.m:50 ... an item without a palette label keeps its label in the palette
Passed test:     paletteItemLabel.m:52 ... an item with a palette label shows it in the palette
```

With this change:

```
palette labels: "Label", "Palette Label"
Passed test:     paletteItemLabel.m:50 ... an item without a palette label keeps its label in the palette
Passed test:     paletteItemLabel.m:52 ... an item with a palette label shows it in the palette
```

Only a non-empty palette label replaces the label now.

cc @pkgdemon
