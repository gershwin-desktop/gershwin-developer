Copying a directory that contains a symbolic link changes the mode, owner and dates of the file the link points to. After recreating the link, the copy code applies the source link's attributes with `-changeFileAttributes:atPath:`, which follows links (`chmod()`, `chown()`, `utimensat()` with flag 0). A link's mode is 0777 on Linux, so the target becomes writable by everyone, and with an absolute link that target can be any file outside the copied tree. `-copyItemAtPath:toPath:error:`, `-linkPath:toPath:handler:` and a move across file systems do the same.

```objc
#import <Foundation/Foundation.h>
#include <sys/stat.h>

static void show(const char *p)
{
  struct stat sb;

  stat(p, &sb);
  printf("%-20s mode %04o mtime %ld\n", p, sb.st_mode & 07777, (long)sb.st_mtime);
}

int main()
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *secret = [[fm currentDirectoryPath]
    stringByAppendingPathComponent: @"secret"];

  [fm createDirectoryAtPath: @"tree" attributes: nil];
  [fm createFileAtPath: secret contents: [NSData data] attributes:
    [NSDictionary dictionaryWithObject: [NSNumber numberWithInt: 0600]
				forKey: NSFilePosixPermissions]];
  [fm createSymbolicLinkAtPath: @"tree/link" pathContent: secret];
  show("secret");
  [fm copyPath: @"tree" toPath: @"tree-copy" handler: nil];
  show("secret");
  [pool release];
  return 0;
}
```

`clang $(gnustep-config --objc-flags) repro.m -o repro $(gnustep-config --base-libs) && ./repro`

Before (master):
```
secret               mode 0600 mtime 1794636786
secret               mode 0777 mtime 1794636786
```
After:
```
secret               mode 0600 mtime 1794637120
secret               mode 0600 mtime 1794637120
```

The new test `Tests/base/NSFileManager/copySymlinkAttributes.m` covers the four entry points with a relative and an absolute link. `cd Tests && gnustep-tests base/NSFileManager` gives 119 passed and 6 failed on master, and 125 passed with this change (the new test also passes when run as root, where the owner checks matter).

The copy, link and move code now applies the attributes without following a final symbolic link: the owner with `lchown()`, the dates with `utimensat()` and `AT_SYMLINK_NOFOLLOW` (skipped where `utimensat()` is not available), and the mode not at all, since link permissions are not used for access checks (Linux has no `lchmod()`, and FreeBSD ignores the permissions of a link). `-changeFileAttributes:atPath:` itself still follows links as before.

cc @pkgdemon
