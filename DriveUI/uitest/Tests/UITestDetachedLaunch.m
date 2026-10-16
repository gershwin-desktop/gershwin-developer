/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "UITestDetachedLaunch.h"
#include <errno.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

pid_t
UITestLaunchDetached(NSString *path, NSString *logPath)
{
  /* Everything the children use is prepared before fork(): the child of a
   * threaded process may only call async-signal-safe functions. */
  const char *exe = [path fileSystemRepresentation];
  const char *log = [logPath fileSystemRepresentation];
  char *const argv[] = { (char *)exe, NULL };
  long maxfd = sysconf(_SC_OPEN_MAX);
  int report[2];
  pid_t mid;
  pid_t started = 0;

  if (maxfd < 0 || pipe(report) != 0)
    {
      return 0;
    }
  mid = fork();
  if (mid < 0)
    {
      close(report[0]);
      close(report[1]);
      return 0;
    }
  if (mid == 0)
    {
      int in = open("/dev/null", O_RDONLY);
      int out = open(log, O_WRONLY | O_CREAT | O_APPEND, 0644);
      pid_t pid;

      if (in < 0 || out < 0 || setsid() < 0)
        {
          _exit(1);
        }
      /* The intermediate child exits at once, so the started process is
       * reparented and never becomes a zombie of the harness that a
       * by-name process check would still count as running. */
      pid = fork();
      if (pid != 0)
        {
          if (pid > 0)
            {
              write(report[1], &pid, sizeof(pid));
            }
          _exit(pid > 0 ? 0 : 1);
        }
      dup2(in, STDIN_FILENO);
      dup2(out, STDOUT_FILENO);
      dup2(out, STDERR_FILENO);
      /* An inherited socket of the harness would keep the peer's end of a
       * desktop connection open after the harness is gone. */
      for (long fd = STDERR_FILENO + 1; fd < maxfd; fd++)
        {
          close((int)fd);
        }
      execv(exe, argv);
      _exit(127);
    }

  close(report[1]);
  while (waitpid(mid, NULL, 0) < 0 && errno == EINTR)
    ;
  if (read(report[0], &started, sizeof(started)) != sizeof(started))
    {
      started = 0;
    }
  close(report[0]);
  return started;
}
