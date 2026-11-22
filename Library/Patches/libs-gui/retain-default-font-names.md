# retain-default-font-names.patch

Backport of upstream libs-gui commit 8a092cfa7 ("Fix: retain the default
font names for the font roles"), which landed one day after our pin
8f804fd52. No upstream PR is needed; drop this patch when the pin moves
past 8a092cfa7.

Why: `init_font_roles()` in `Source/NSFont.m` stored the default font names
from the font enumerator without retaining them. Our libs-back patch
`monospace-default-fixed-pitch.patch` makes `-defaultBoldSystemFontName` and
`-defaultFixedPitchFontName` return names resolved through fontconfig
(autoreleased), so those entries dangled after the first autorelease pool
drained. The next `+boldSystemFontOfSize:` (the WindowManager's Alt-Tab title
label) then messaged a freed string: the WindowManager crashed in libobjc on
Alt-Tab (NSZombieEnabled: `-[GSCInlineString copy]: message sent to
deallocated instance`, from `keyForFont` <- `getNSFont` <- `+[NSFont
boldSystemFontOfSize:]`).
