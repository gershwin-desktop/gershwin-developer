/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <errno.h>
#import <string.h>
#import <unistd.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import "DriveUISocket.h"

static NSString *
failure(NSString *step, NSString *path)
{
  return [NSString stringWithFormat: @"%@ %@: %s", step, path, strerror(errno)];
}

int
DriveUIOpenListener(NSString *path, NSString **why)
{
  struct sockaddr_un addr;

  if ([path length] >= sizeof(addr.sun_path))
    {
      if (why != NULL)
        *why = [NSString stringWithFormat: @"socket path too long: %@", path];
      return -1;
    }

  /* A leftover of an earlier process with this pid; a missing file is the
   * normal case. */
  if (unlink([path UTF8String]) != 0 && errno != ENOENT)
    {
      if (why != NULL)
        *why = failure(@"cannot remove the old socket", path);
      return -1;
    }

  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0)
    {
      if (why != NULL)
        *why = failure(@"socket() for", path);
      return -1;
    }

  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, [path UTF8String], sizeof(addr.sun_path) - 1);
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
    {
      if (why != NULL)
        *why = failure(@"bind()", path);
      close(fd);
      return -1;
    }
  if (listen(fd, 8) < 0)
    {
      if (why != NULL)
        *why = failure(@"listen() on", path);
      close(fd);
      return -1;
    }
  chmod([path UTF8String], 0666);
  return fd;
}
