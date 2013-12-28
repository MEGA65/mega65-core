"""Symbol tables and environments for Ophis.

   Implements the symbol lookup, through nested environments -
   any non-temporary variable is stored at the top level."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import Ophis.Errors as Err


class Environment(object):
    """Environment class.
    Controls the various scopes and global abstract execution variables."""
    def __init__(self):
        self.dicts = [{}]
        self.stack = [0]
        self.pc = 0
        self.segmentdict = {}
        self.segment = "*text-default*"
        self.scopecount = 0

    def __contains__(self, item):
        if item[0] == '_':
            for dict in [self.dicts[i] for i in self.stack]:
                if item in dict:
                    return True
            return False
        return item in self.dicts[0]

    def __getitem__(self, item):
        if item[0] == '_':
            for dict in [self.dicts[i] for i in self.stack]:
                if item in dict:
                    return dict[item]
        else:
            if item in self.dicts[0]:
                return self.dicts[0][item]
        Err.log("Unknown label '%s'" % item)
        return 0

    def __setitem__(self, item, value):
        if item[0] == '_':
            self.dicts[self.stack[0]][item] = value
        else:
            self.dicts[0][item] = value

    def __str__(self):
        return str(self.dicts)

    def getPC(self):
        return self.pc

    def setPC(self, value):
        self.pc = value

    def incPC(self, amount):
        self.pc += amount

    def getsegment(self):
        return self.segment

    def setsegment(self, segment):
        self.segmentdict[self.segment] = self.pc
        self.segment = segment
        self.pc = self.segmentdict.get(segment, 0)

    def reset(self):
        "Clears out program counter, segment, and scoping information"
        self.pc = 0
        self.segmentdict = {}
        self.segment = "*text-default*"
        self.scopecount = 0
        if len(self.stack) > 1:
            Err.log("Unmatched .scope")
        self.stack = [0]

    def newscope(self):
        "Enters a new scope for temporary labels."
        self.scopecount += 1
        self.stack.insert(0, self.scopecount)
        if len(self.dicts) <= self.scopecount:
            self.dicts.append({})

    def endscope(self):
        "Leaves a scope."
        if len(self.stack) == 1:
            Err.log("Unmatched .scend")
        self.stack.pop(0)
