/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Starting a desktop component again from the harness.  It has to outlive
 * the harness and must not hold on to the harness's own descriptors, and the
 * setsid(1) command the harness used for that exists on Linux only.
 */

#import <Foundation/Foundation.h>

/* Start the executable at path without arguments in a session of its own,
 * stdin from /dev/null, stdout and stderr appended to logPath, no other
 * descriptor of the caller inherited and no zombie left behind.  Returns the
 * pid of the started process, or 0 when it could not be started. */
pid_t UITestLaunchDetached(NSString *path, NSString *logPath);
