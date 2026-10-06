/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * t_driveuisocket - ObjectTesting coverage for the listening socket of a
 * DriveUI server (DriveUI/DriveUISocket.m).  An app whose server cannot
 * listen must say why, not run on silently without one.
 */

#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>
#import "Testing.h"
#import "../../DriveUISocket.h"
/* Compiled in rather than listed in the GNUmakefile, like t_treeformat. */
#include "../../DriveUISocket.m"

static BOOL
canConnect(NSString *path)
{
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, [path UTF8String], sizeof(addr.sun_path) - 1);
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  BOOL ok = connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0;
  close(fd);
  return ok;
}

int
main(void)
{
  NSAutoreleasePool *arp = [[NSAutoreleasePool alloc] init];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSString stringWithFormat: @"/tmp/t_driveuisocket.%d",
    (int)getpid()];
  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES
    attributes: nil error: NULL];
  NSString *path = [dir stringByAppendingPathComponent: @"driveui.1.sock"];
  NSString *why = nil;

  int fd = DriveUIOpenListener(path, &why);
  PASS(fd >= 0 && why == nil, "a free path gets a listening socket");
  PASS(canConnect(path), "a client can connect to it");
  close(fd);

  fd = DriveUIOpenListener(path, &why);
  PASS(fd >= 0, "the socket of an earlier process with this pid is replaced");
  close(fd);

  /* Another user's stale file cannot be removed.  The directory standing in
   * for the sticky /tmp is read-only; root ignores that, so skip as root. */
  if (getuid() != 0)
    {
      chmod([dir UTF8String], 0555);
      why = nil;
      fd = DriveUIOpenListener(path, &why);
      PASS(fd < 0, "a stale socket that cannot be removed is refused");
      PASS([why length] > 0 && [why rangeOfString: path].location != NSNotFound,
           "the refusal names the path and the reason");
      chmod([dir UTF8String], 0755);
    }

  why = nil;
  fd = DriveUIOpenListener([dir stringByAppendingPathComponent: @"nodir/x.sock"],
    &why);
  PASS(fd < 0 && [why length] > 0, "a path that cannot be bound says why");

  [fm removeItemAtPath: dir error: NULL];
  [arp release];
  return 0;
}
