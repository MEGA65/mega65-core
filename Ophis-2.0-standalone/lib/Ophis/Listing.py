"""The Ophis program lister

    When displaying an assembled binary for human inspection, it is
    traditional to mix binary with reconstructed instructions that
    have all arguments precomputed. This class manages that."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import sys


class Listing(object):
    """Encapsulates the program listing. Accepts fully formatted
    instruction strings, or batches of data bytes. Batches of data
    bytes are assumed to be contiguous unless a divider is explicitly
    requested."""

    def __init__(self, fname):
        self.listing = [(0, [])]
        self.filename = fname

    def listInstruction(self, inst):
        "Add a preformatted instruction list to the listing."
        self.listing.append(inst)

    def listDivider(self, newpc):
        "Indicate that the next data block will begin at the given PC."
        self.listing.append((newpc, []))

    def listData(self, vals, pc):
        """Add a batch of data to the listing. If this starts a new
        batch of data, begin that batch at the listed PC."""
        if type(self.listing[-1]) is not tuple:
            self.listing.append((pc, []))
        self.listing[-1][1].extend(vals)

    def dump(self):
        if self.filename == "-":
            out = sys.stdout
        else:
            out = file(self.filename, "w")
        for x in self.listing:
            if type(x) is str:
                print>>out, x
            elif type(x) is tuple:
                i = 0
                pc = x[0]
                while True:
                    row = x[1][i:i + 16]
                    if row == []:
                        break
                    dataline = " %04X " % (pc + i)
                    dataline += (" %02X" * len(row)) % tuple(row)
                    charline = ""
                    for c in row:
                        if c < 31 or c > 127:
                            charline += "."
                        else:
                            charline += chr(c)
                    print>>out, "%-54s  |%-16s|" % (dataline, charline)
                    i += 16
        if self.filename != "-":
            out.close()


class NullLister(object):
    "A dummy Lister that actually does nothing."
    def listInstruction(self, inst):
        pass

    def listDivider(self, newpc):
        pass

    def listData(self, vals, pc):
        pass

    def dump(self):
        pass
