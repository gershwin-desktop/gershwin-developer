/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Where the output of an application that `launch application` starts goes,
 * and how such an application ended.
 */

#import <Foundation/Foundation.h>

/* The handle the launched application writes its stdout and stderr to: the
 * null device when dir is nil or empty, otherwise <dir>/<name>.log opened for
 * appending, after a line that marks this launch.  nil (and *err set) when
 * that file cannot be opened. */
NSFileHandle *UITestAppOutputHandle(NSString *dir, NSString *name,
                                    NSString **err);

/* "<App> (pid N) exited with status S" or "... was killed by signal S" for a
 * launched task that has ended, nil while it runs or when task is nil. */
NSString *UITestTaskExitDescription(NSTask *task);
