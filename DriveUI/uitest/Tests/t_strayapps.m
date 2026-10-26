/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * t_strayapps - ObjectTesting coverage for the cleanup of the applications
 * a failed UI test leaves behind (UITestStrayApps.m).
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "UITestStrayApps.h"
/* Compiled in rather than listed in the GNUmakefile, like t_treeformat. */
#include "UITestStrayApps.m"

/* Started through a shell that exits at once, so the sleeper is reparented
 * like an app launched by run_uitest and leaves no zombie behind. */
static pid_t
startSleeper(NSString *dir, NSString *tool)
{
  NSString *link = [dir stringByAppendingPathComponent: tool];
  [[NSFileManager defaultManager] createSymbolicLinkAtPath: link
    withDestinationPath: @"/bin/sleep" error: NULL];
  NSString *cmd = [NSString stringWithFormat:
    @"sh -c '%@ 60 </dev/null >/dev/null 2>&1 & echo $!'", link];
  FILE *fp = popen([cmd UTF8String], "r");
  char line[32] = "0";
  if (fp != NULL)
    {
      if (fgets(line, sizeof(line), fp) == NULL)
        {
          line[0] = '0';
        }
      pclose(fp);
    }
  pid_t pid = (pid_t)atoi(line);
  [NSThread sleepForTimeInterval: 0.2];
  [[NSFileManager defaultManager] createFileAtPath: [dir
    stringByAppendingPathComponent: [NSString stringWithFormat:
    @"driveui.%d.sock", (int)pid]] contents: nil attributes: nil];
  return pid;
}

int
main(void)
{
  NSAutoreleasePool *arp = [[NSAutoreleasePool alloc] init];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_strayapps.%d", (int)getpid()]];
  [[NSFileManager defaultManager] createDirectoryAtPath: dir
    withIntermediateDirectories: YES attributes: nil error: NULL];

  pid_t desktop = startSleeper(dir, @"Menu");
  NSSet *before = UITestDriveUIPids(dir);
  PASS([before containsObject: [NSNumber numberWithInt: desktop]],
       "a live app with a DriveUI socket is listed");

  pid_t stray = startSleeper(dir, @"AppGardenFake");
  pid_t old = desktop;
  NSSet *keep = [NSSet setWithObject: @"Menu"];
  NSArray *killed = UITestTerminateStrayApps(before, dir, keep, 2.0, nil);

  NSArray *expected = [NSArray arrayWithObject: [NSNumber numberWithInt: stray]];
  PASS([killed isEqual: expected],
       "only the app that appeared during the test is a stray");
  PASS(kill(stray, 0) != 0,
       "the stray app is terminated");
  PASS(kill(old, 0) == 0, "an app that was there before is left alone");
  NSString *strayPath = [dir stringByAppendingPathComponent:
    [NSString stringWithFormat: @"driveui.%d.sock", (int)stray]];
  BOOL socketLeft = [[NSFileManager defaultManager]
    fileExistsAtPath: strayPath];
  PASS(!socketLeft, "the stray's socket is removed");

  /* A desktop component that restarted during the test is not a stray. */
  pid_t restarted = startSleeper(dir, @"Menu2");
  keep = [NSSet setWithObject: @"Menu2"];
  killed = UITestTerminateStrayApps(before, dir, keep, 2.0, nil);
  PASS([killed count] == 0 && kill(restarted, 0) == 0,
       "a kept desktop component survives even when it is new");

  kill(old, SIGKILL);
  kill(restarted, SIGKILL);
  [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
  [arp release];
  return 0;
}
