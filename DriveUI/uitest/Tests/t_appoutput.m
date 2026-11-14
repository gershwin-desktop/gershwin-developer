/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * t_appoutput - ObjectTesting coverage for where run_uitest puts the output
 * of the applications it launches and how it reports their end
 * (UITestAppOutput.m).
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../UITestAppOutput.h"
/* Compiled in rather than listed in the GNUmakefile, like t_treeformat. */
#include "../UITestAppOutput.m"

static NSTask *
finishedTask(NSString *path, NSArray *args, NSFileHandle *output)
{
  NSTask *task = [[[NSTask alloc] init] autorelease];
  [task setLaunchPath: path];
  [task setArguments: args];
  if (output != nil)
    {
      [task setStandardOutput: output];
      [task setStandardError: output];
    }
  [task launch];
  [task waitUntilExit];
  return task;
}

int
main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_appoutput.%d", getpid()]];
  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  NSString *log = [dir stringByAppendingPathComponent: @"Probe.log"];
  NSString *err = nil;

  START_SET("output handle")
    NSFileHandle *h = UITestAppOutputHandle(nil, @"Probe", &err);
    PASS(h != nil && ![fm fileExistsAtPath: log],
      "without a log directory the output is discarded");

    h = UITestAppOutputHandle(dir, @"Probe", &err);
    PASS(h != nil, "a log directory gives a handle");
    finishedTask(@"/bin/sh",
      [NSArray arrayWithObjects: @"-c", @"echo out; echo err >&2", nil], h);
    NSString *text = [NSString stringWithContentsOfFile: log
      encoding: NSUTF8StringEncoding error: NULL];
    PASS(text != nil && [text rangeOfString: @"launch application \"Probe\""].location
      != NSNotFound, "the log marks the launch");
    PASS(text != nil && [text rangeOfString: @"out\n"].location != NSNotFound
      && [text rangeOfString: @"err\n"].location != NSNotFound,
      "stdout and stderr of the application land in <dir>/<App>.log");

    h = UITestAppOutputHandle(dir, @"Probe", &err);
    finishedTask(@"/bin/sh", [NSArray arrayWithObjects: @"-c", @"echo second", nil], h);
    text = [NSString stringWithContentsOfFile: log
      encoding: NSUTF8StringEncoding error: NULL];
    PASS(text != nil && [text rangeOfString: @"out\n"].location != NSNotFound
      && [text rangeOfString: @"second\n"].location != NSNotFound,
      "a second launch appends instead of replacing the first");

    err = nil;
    h = UITestAppOutputHandle([dir stringByAppendingPathComponent: @"missing"],
      @"Probe", &err);
    PASS(h == nil && [err length] > 0,
      "a log directory that cannot be written fails the launch with a reason");
  END_SET("output handle")

  START_SET("exit description")
    PASS(UITestTaskExitDescription(nil) == nil, "no task, no description");
    NSTask *t = finishedTask(@"/bin/sh",
      [NSArray arrayWithObjects: @"-c", @"exit 3", nil], nil);
    NSString *d = UITestTaskExitDescription(t);
    PASS(d != nil && [d hasPrefix: @"sh (pid "]
      && [d hasSuffix: @"exited with status 3"], "an exit status is reported");
    t = finishedTask(@"/bin/sh",
      [NSArray arrayWithObjects: @"-c", @"kill -9 $$", nil], nil);
    d = UITestTaskExitDescription(t);
    PASS(d != nil && [d hasSuffix: @"was killed by signal 9"],
      "a signal is reported as such");
  END_SET("exit description")

  [fm removeItemAtPath: dir error: NULL];
  [pool drain];
  return 0;
}
