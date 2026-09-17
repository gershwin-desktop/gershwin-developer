/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DriveUITreeFormat.h"

NSString *DriveUIEscapeTreeField(NSString *field)
{
  if (field == nil)
    return @"";
  NSUInteger len = [field length];
  NSMutableString *out = [NSMutableString stringWithCapacity: len];
  for (NSUInteger i = 0; i < len; i++)
    {
      unichar c = [field characterAtIndex: i];
      switch (c)
        {
          case '\\': [out appendString: @"\\\\"]; break;
          case '\n': [out appendString: @"\\n"]; break;
          case '\r': [out appendString: @"\\r"]; break;
          case '\t': [out appendString: @"\\t"]; break;
          default: [out appendFormat: @"%C", c]; break;
        }
    }
  return out;
}

NSString *DriveUIUnescapeTreeField(NSString *field)
{
  if ([field rangeOfString: @"\\"].location == NSNotFound)
    return field;
  NSUInteger len = [field length];
  NSMutableString *out = [NSMutableString stringWithCapacity: len];
  for (NSUInteger i = 0; i < len; i++)
    {
      unichar c = [field characterAtIndex: i];
      if (c == '\\' && i + 1 < len)
        {
          unichar n = [field characterAtIndex: ++i];
          switch (n)
            {
              case 'n': c = '\n'; break;
              case 'r': c = '\r'; break;
              case 't': c = '\t'; break;
              default: c = n; break;
            }
        }
      [out appendFormat: @"%C", c];
    }
  return out;
}

NSArray *DriveUIParseTree(NSString *tree)
{
  NSMutableArray *rows = [NSMutableArray array];
  for (NSString *line in [tree componentsSeparatedByString: @"\n"])
    {
      if ([line length] == 0)
        continue;
      NSMutableArray *fields = [NSMutableArray array];
      for (NSString *f in [line componentsSeparatedByString: @"\t"])
        [fields addObject: DriveUIUnescapeTreeField(f)];
      [rows addObject: fields];
    }
  return rows;
}
