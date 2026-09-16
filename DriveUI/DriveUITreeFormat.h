/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/* The widget tree travels as one line per widget with tab-separated fields.
 * Widget text can itself contain newlines and tabs (a multi-line alert
 * message, a text view holding a whole log), which would split one widget
 * into several broken rows and cut its text off after the first line.  Both
 * ends therefore escape each field: backslash, newline, carriage return and
 * tab become \\, \n, \r and \t. */
NSString *DriveUIEscapeTreeField(NSString *field);
NSString *DriveUIUnescapeTreeField(NSString *field);

/* Split a tree reply into rows of unescaped fields. */
NSArray *DriveUIParseTree(NSString *tree);
