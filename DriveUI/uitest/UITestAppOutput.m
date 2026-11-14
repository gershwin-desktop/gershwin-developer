/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "UITestAppOutput.h"
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>

NSFileHandle *
UITestAppOutputHandle(NSString *dir, NSString *name, NSString **err)
{
  if ([dir length] == 0)
    return [NSFileHandle fileHandleWithNullDevice];
  NSString *path = [dir stringByAppendingPathComponent:
    [name stringByAppendingPathExtension: @"log"]];
  int fd = open([path fileSystemRepresentation],
    O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd < 0)
    {
      if (err != NULL)
        *err = [NSString stringWithFormat: @"cannot open %@: %s",
          path, strerror(errno)];
      return nil;
    }
  /* Many scripts launch the same application into one file; the marker says
   * which launch the lines below it belong to. */
  NSString *marker = [NSString stringWithFormat:
    @"=== %@ launch application \"%@\" ===\n", [NSDate date], name];
  const char *m = [marker UTF8String];
  if (write(fd, m, strlen(m)) < 0)
    {
      if (err != NULL)
        *err = [NSString stringWithFormat: @"cannot write %@: %s",
          path, strerror(errno)];
      close(fd);
      return nil;
    }
  return [[[NSFileHandle alloc] initWithFileDescriptor: fd
                                        closeOnDealloc: YES] autorelease];
}

NSString *
UITestTaskExitDescription(NSTask *task)
{
  if (task == nil || [task isRunning])
    return nil;
  NSString *app = [[task launchPath] lastPathComponent];
  int status = [task terminationStatus];
  if ([task terminationReason] == NSTaskTerminationReasonUncaughtSignal)
    return [NSString stringWithFormat: @"%@ (pid %d) was killed by signal %d",
      app, [task processIdentifier], status];
  return [NSString stringWithFormat: @"%@ (pid %d) exited with status %d",
    app, [task processIdentifier], status];
}
