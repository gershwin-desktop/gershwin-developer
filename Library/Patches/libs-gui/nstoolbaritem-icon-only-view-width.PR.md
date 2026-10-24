NSToolbarItem: size an icon-only item with a view by its view

In NSToolbarDisplayModeIconOnly a toolbar item with a view shows neither its label nor an image, but `-[GSToolbarBackView layout]` still makes it at least `ItemBackViewRegularWidth` (60 points) wide and as wide as its label. Two 24 point buttons side by side therefore end up in items of different widths, depending on how long their hidden labels are (in the user's language), and the flexible space that GSToolbarView shares out by the items' `minSize` no longer matches the widths the items really get, so the last items can be pushed out of the window.

The test added here puts two items with a 24x24 button each into an icon-only toolbar, one labelled "A" and one with a long label, and measures the item widths (`cd Tests && gnustep-tests gui/NSToolbarItem/iconOnlyViewWidth.m`, under Xvfb). Master cacd5cb08:

```
icon only: view 24 pt, item with label "A" 61 pt, item with a long label 209 pt
Failed test:     iconOnlyViewWidth.m:102 ... items with views of the same width are equally wide
Failed test:     iconOnlyViewWidth.m:104 ... an item with a view is not padded to the image item width
```

With this change:

```
icon only: view 24 pt, item with label "A" 44 pt, item with a long label 44 pt
Passed test:     iconOnlyViewWidth.m:102 ... items with views of the same width are equally wide
Passed test:     iconOnlyViewWidth.m:104 ... an item with a view is not padded to the image item width
```

In icon-only mode an item with a view is now exactly its view plus the usual `InsetItemViewX` on each side; the other display modes and items with an image are unchanged, and the NSToolbarItem and NSToolbar test groups pass. This is the width counterpart of part of #972 (sizing toolbar items from their content), limited to the case where the label is not shown at all.

cc @pkgdemon
