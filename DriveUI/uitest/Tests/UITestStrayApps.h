/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * The applications a failed UI test leaves behind.  A test that times out
 * does not reach its own "quit", and an application still open with its
 * windows covers the next test's drag source or answers its title lookups,
 * so one failure would fail the tests after it as well.
 */

#import <Foundation/Foundation.h>

/* Pids of the live applications that serve DriveUI (a driveui.<pid>.sock in
 * socketDir, owned by a process that still exists). */
NSSet *UITestDriveUIPids(NSString *socketDir);

/* Terminate every application of the calling user that serves DriveUI now
 * and did not before, except those whose process name is in keepNames (the
 * desktop components the session itself starts).  SIGTERM first so an app
 * can save, SIGKILL after grace seconds for one that is wedged.  Returns the
 * pids that were terminated.  inspect (may be nil) is called
 * for each one first, while it is still alive, to record why it was left open. */
NSArray *UITestTerminateStrayApps(NSSet *before, NSString *socketDir,
                                  NSSet *keepNames, NSTimeInterval grace,
                                  void (^inspect)(pid_t pid, NSString *name));
