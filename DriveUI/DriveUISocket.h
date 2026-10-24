/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/* Open the listening Unix-domain socket of a DriveUI server at path, world
 * accessible so drive_ui can connect from any user.  Returns the descriptor,
 * or -1 with the failed step and its reason in *why.  A stale file that
 * cannot be removed (it belongs to another user, whose dead app once had the
 * same pid) is such a failure: without the reason the app runs on with no
 * DriveUI server, and the tests that drive it wait out their timeouts. */
int DriveUIOpenListener(NSString *path, NSString **why);
