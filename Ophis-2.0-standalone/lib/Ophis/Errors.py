"""Error logging

    Keeps track of the number of errors inflicted so far, and
    where in the assembly the errors are occurring."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import sys

count = 0
currentpoint = "<Top Level>"


def log(err):
    """Reports an error at the current program point, and increases
the global error count."""
    global count
    count = count + 1
    print>>sys.stderr, currentpoint + ": " + err


def report():
    "Print out the number of errors."
    if count == 0:
        print>>sys.stderr, "No errors"
    elif count == 1:
        print>>sys.stderr, "1 error"
    else:
        print>>sys.stderr, str(count) + " errors"
