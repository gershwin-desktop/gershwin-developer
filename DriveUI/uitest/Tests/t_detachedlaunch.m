/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * t_detachedlaunch - ObjectTesting coverage for starting a desktop component
 * again from the harness (UITestDetachedLaunch.m).
 */

#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#import "Testing.h"
#import "UITestDetachedLaunch.h"
/* Compiled in rather than listed in the GNUmakefile, like t_strayapps. */
#include "UITestDetachedLaunch.m"

static NSString *
waitForFile(NSString *file, NSString *needle)
{
  for (int i = 0; i < 50; i++)
    {
      NSString *s = [NSString stringWithContentsOfFile: file];
      if (s != nil && [s rangeOfString: needle].location != NSNotFound)
        {
          return s;
        }
      usleep(100000);
    }
  return [NSString stringWithContentsOfFile: file];
}

int
main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_detachedlaunch.%d", getpid()]];
  NSString *empty = [dir stringByAppendingPathComponent: @"emptybin"];
  NSString *script = [dir stringByAppendingPathComponent: @"probe"];
  NSString *log = [dir stringByAppendingPathComponent: @"probe.log"];

  [fm createDirectoryAtPath: empty withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  /* The probe reports what it got from the launcher and then stays up, so
   * its session and parent can be read while it runs. */
  [@"#!/bin/sh\nPATH=/bin:/usr/bin\n"
    @"ls /dev/fd/ | tr '\\n' ' ' | sed 's/^/fds=/'; echo\n"
    @"if read x; then echo stdin=data; else echo stdin=eof; fi\n"
    @"exec sleep 30\n"
    writeToFile: script atomically: YES];
  [fm setAttributes: @{NSFilePosixPermissions: @0755}
       ofItemAtPath: script error: NULL];

  /* A marker the started process must not inherit: an inherited desktop
   * socket kept the peer's connection to a dead component open. */
  int marker = open("/dev/null", O_RDONLY);
  while (marker >= 0 && marker < 9)
    {
      marker = dup(marker);
    }

  /* FreeBSD and OpenBSD have no setsid(1); an empty PATH makes any
   * dependence on a command look the same here. */
  setenv("PATH", [empty fileSystemRepresentation], 1);

  pid_t pid = UITestLaunchDetached(script, log);
  PASS(pid > 0, "the started process's pid is returned");

  NSString *out = waitForFile(log, @"stdin=");
  PASS(out != nil && [out rangeOfString: @"stdin=eof"].location != NSNotFound,
       "the started process runs and reads /dev/null as stdin");
  PASS(pid > 0 && getsid(pid) > 0 && getsid(pid) != getsid(0),
       "the started process runs in a session of its own");
  NSString *fdTag = [NSString stringWithFormat: @" %d ", marker];
  PASS(out != nil && [out rangeOfString: fdTag].location == NSNotFound
       && [out rangeOfString: @"fds="].location != NSNotFound,
       "no descriptor of the caller is inherited");
  PASS(pid > 0 && waitpid(pid, NULL, WNOHANG) == -1 && errno == ECHILD,
       "the started process is not a child of the caller (no zombie)");

  if (pid > 0)
    {
      kill(pid, SIGTERM);
    }
  close(marker);
  [fm removeItemAtPath: dir error: NULL];
  [pool release];
  return 0;
}
