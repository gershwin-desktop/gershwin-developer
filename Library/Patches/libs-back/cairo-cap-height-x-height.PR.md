On the cairo backend `-[NSFont capHeight]` is 0 for every font, and `-xHeight` is a fixed 60 percent of the ascender rather than the font's own value. Anything that centres a line of text on one of these metrics, a table cell or a custom control drawing its own label, then sits several points too high. Seen with a hand-drawn source list cell whose labels were visibly above the row centre.

Reproducer, a small tool printing the metrics of three fonts:

```objc
#import <AppKit/AppKit.h>
int main(void)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
      for (NSFont *f in @[[NSFont systemFontOfSize: 13],
                          [NSFont boldSystemFontOfSize: 11],
                          [NSFont userFontOfSize: 12]])
        printf("%s %g: ascender %.2f descender %.2f capHeight %.2f xHeight %.2f\n",
               [[f fontName] UTF8String], [f pointSize], [f ascender],
               [f descender], [f capHeight], [f xHeight]);
    }
  return 0;
}
```

Before (master, Inter as the system font):

```
Inter-Medium 13: ascender 12.59 descender -3.14 capHeight 0.00 xHeight 7.56
Inter-Bold 11: ascender 10.66 descender -2.65 capHeight 0.00 xHeight 6.39
Inter-Medium 12: ascender 11.62 descender -2.89 capHeight 0.00 xHeight 6.97
```

After:

```
Inter-Medium 13: ascender 12.59 descender -3.14 capHeight 9.46 xHeight 7.10
Inter-Bold 11: ascender 10.66 descender -2.65 capHeight 8.00 xHeight 6.00
Inter-Medium 12: ascender 11.62 descender -2.89 capHeight 8.73 xHeight 6.55
```

Inter's cap height is 0.727 em, so 9.46 at 13 points is the real value, and its x-height is 0.546 em, so the old estimate was 6 percent high. The change takes both from `cairo_scaled_font_text_extents` of "H" and "x" on the scaled font, which works for every face cairo renders, and keeps the old estimate for the x-height only when the face has no "x" glyph.

cc @pkgdemon
