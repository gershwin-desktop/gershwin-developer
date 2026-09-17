/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* LD_PRELOAD diagnostic for the UI test CI (see run-uitests.sh).
 *
 * Workspace dies when one of its X server connections has its descriptor
 * closed underneath it by some other code in the process; Xlib then only
 * reports "X connection broken" and exits, which names the victim but not the
 * culprit.  Xlib closes its own connections through libxcb, so any other
 * caller of close() or dup2() that is about to close a socket connected to
 * the X server is the culprit: print its backtrace to stderr. */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <execinfo.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

static int (*real_close)(int);
static int (*real_dup2)(int, int);

static int
is_x_server_socket(int fd)
{
  struct sockaddr_un addr;
  socklen_t len = sizeof(addr);
  const char *path;

  memset(&addr, 0, sizeof(addr));
  if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0
      || addr.sun_family != AF_UNIX)
    {
      return 0;
    }
  /* Linux X servers also listen on an abstract socket, whose name starts
   * with a NUL byte. */
  path = (addr.sun_path[0] != '\0') ? addr.sun_path : addr.sun_path + 1;
  return strstr(path, ".X11-unix/X") != NULL;
}

static int
called_from_libxcb(void *returnAddress)
{
  Dl_info info;

  return dladdr(returnAddress, &info) != 0 && info.dli_fname != NULL
    && strstr(info.dli_fname, "libxcb") != NULL;
}

static void
report(const char *call, int fd, void *returnAddress)
{
  char line[512];
  void *frames[40];
  Dl_info info;
  const char *caller = "?";
  ssize_t written;
  int n;

  if (dladdr(returnAddress, &info) != 0 && info.dli_fname != NULL)
    {
      caller = info.dli_fname;
    }
  n = snprintf(line, sizeof(line),
    "XFDWATCH: %s(%d) closes an X server connection, called from %s,"
    " pid %d thread %p\n", call, fd, caller, (int)getpid(),
    (void *)pthread_self());
  written = write(STDERR_FILENO, line, (size_t)n);
  (void)written;
  n = backtrace(frames, 40);
  backtrace_symbols_fd(frames, n, STDERR_FILENO);
}

/* The checks must not change errno as seen by the caller. */
static int
must_report(int fd, void *returnAddress)
{
  int savedErrno = errno;
  int culprit = fd >= 0 && is_x_server_socket(fd)
    && !called_from_libxcb(returnAddress);

  errno = savedErrno;
  return culprit;
}

int
close(int fd)
{
  void *returnAddress = __builtin_return_address(0);

  if (real_close == NULL)
    {
      real_close = (int (*)(int))dlsym(RTLD_NEXT, "close");
    }
  if (must_report(fd, returnAddress))
    {
      report("close", fd, returnAddress);
    }
  return real_close(fd);
}

int
dup2(int oldfd, int newfd)
{
  void *returnAddress = __builtin_return_address(0);

  if (real_dup2 == NULL)
    {
      real_dup2 = (int (*)(int, int))dlsym(RTLD_NEXT, "dup2");
    }
  if (oldfd != newfd && must_report(newfd, returnAddress))
    {
      report("dup2 onto", newfd, returnAddress);
    }
  return real_dup2(oldfd, newfd);
}
