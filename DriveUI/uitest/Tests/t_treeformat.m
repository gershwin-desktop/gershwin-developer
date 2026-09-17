/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * t_treeformat - ObjectTesting coverage for the DriveUI widget tree wire
 * format (DriveUI/DriveUITreeFormat.m).  Multi-line widget text must survive
 * the line-based transport intact, or text checks only see its first line.
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../DriveUITreeFormat.h"
/* Compiled in rather than listed in the GNUmakefile: a test tool's object for
 * a source two directories up would land in this source directory. */
#include "../../DriveUITreeFormat.m"

int
main(void)
{
  NSAutoreleasePool *arp = [[NSAutoreleasePool alloc] init];
  NSString *text = @"line 001\nline 002\tcol\r\nC:\\dir\\n";

  NSString *escaped = DriveUIEscapeTreeField(text);
  PASS([escaped rangeOfString: @"\n"].location == NSNotFound
       && [escaped rangeOfString: @"\t"].location == NSNotFound
       && [escaped rangeOfString: @"\r"].location == NSNotFound,
       "escaped field carries no row or field separator");
  PASS_EQUAL(DriveUIUnescapeTreeField(escaped), text,
             "unescape restores the original text, backslashes included");
  PASS_EQUAL(DriveUIEscapeTreeField(@"plain"), @"plain",
             "plain text is unchanged");
  PASS_EQUAL(DriveUIEscapeTreeField(nil), @"", "nil escapes to empty");

  NSString *tree = [NSString stringWithFormat:
    @"1\tNSTextField\t%@\t0\n2\tNSButton\tOK\t0\n",
    DriveUIEscapeTreeField(text)];
  NSArray *rows = DriveUIParseTree(tree);
  PASS([rows count] == 2, "a multi-line widget stays one row");
  if ([rows count] == 2)
    {
      PASS_EQUAL([[rows objectAtIndex: 0] objectAtIndex: 2], text,
                 "the row carries the complete multi-line text");
      PASS_EQUAL([[rows objectAtIndex: 1] objectAtIndex: 2], @"OK",
                 "the following row is intact");
    }

  [arp release];
  return 0;
}
