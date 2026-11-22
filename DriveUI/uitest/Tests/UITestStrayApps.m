/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <signal.h>
#import <stdio.h>
#import <unistd.h>
#import "UITestStrayApps.h"

NSSet *
UITestDriveUIPids(NSString *socketDir)
{
  NSMutableSet *pids = [NSMutableSet set];
  NSArray *entries = [[NSFileManager defaultManager]
    contentsOfDirectoryAtPath: socketDir error: NULL];
  for (NSString *entry in entries)
    {
      if (![entry hasPrefix: @"driveui."] || ![entry hasSuffix: @".sock"])
        {
          continue;
        }
      NSRange range = NSMakeRange(8, [entry length] - 8 - 5);
      int pid = [[entry substringWithRange: range] intValue];
      /* A crashed app leaves its socket behind; only a live process counts. */
      if (pid > 0 && kill((pid_t)pid, 0) == 0)
        {
          [pids addObject: [NSNumber numberWithInt: pid]];
        }
    }
  return pids;
}

/* The process name when the process belongs to the calling user, else nil.
 * ps rather than /proc, which the BSDs do not mount. */
static NSString *
ownProcessName(pid_t pid)
{
  char cmd[96];
  snprintf(cmd, sizeof(cmd), "ps -o uid= -o comm= -p %d 2>/dev/null", (int)pid);
  FILE *fp = popen(cmd, "r");
  if (fp == NULL)
    {
      return nil;
    }
  char line[512];
  NSString *name = nil;
  if (fgets(line, sizeof(line), fp) != NULL)
    {
      int uid = -1;
      char comm[480];
      if (sscanf(line, "%d %479[^\n]", &uid, comm) == 2
        && uid == (int)getuid())
        {
          name = [[NSString stringWithUTF8String: comm] lastPathComponent];
        }
    }
  pclose(fp);
  return name;
}

NSArray *
UITestTerminateStrayApps(NSSet *before, NSString *socketDir,
                         NSSet *keepNames, NSTimeInterval grace,
                         void (^inspect)(pid_t pid, NSString *name))
{
  NSMutableArray *strays = [NSMutableArray array];
  for (NSNumber *number in UITestDriveUIPids(socketDir))
    {
      if ([before containsObject: number])
        {
          continue;
        }
      NSString *name = ownProcessName((pid_t)[number intValue]);
      if (name == nil || [keepNames containsObject: name])
        {
          continue;
        }
      [strays addObject: number];
      if (inspect != nil)
        {
          inspect((pid_t)[number intValue], name);
        }
    }

  for (NSNumber *number in strays)
    {
      kill((pid_t)[number intValue], SIGTERM);
    }
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: grace];
  BOOL alive = YES;
  while (alive && [limit timeIntervalSinceNow] > 0)
    {
      alive = NO;
      for (NSNumber *number in strays)
        {
          if (kill((pid_t)[number intValue], 0) == 0)
            {
              alive = YES;
            }
        }
      if (alive)
        {
          usleep(100000);
        }
    }
  for (NSNumber *number in strays)
    {
      if (kill((pid_t)[number intValue], 0) == 0)
        {
          kill((pid_t)[number intValue], SIGKILL);
        }
      /* The socket of a killed app is never removed by the app itself. */
      unlink([[socketDir stringByAppendingPathComponent: [NSString
        stringWithFormat: @"driveui.%d.sock", [number intValue]]] UTF8String]);
    }
  return strays;
}
