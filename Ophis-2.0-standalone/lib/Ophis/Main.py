"""Main controller routines for the Ophis assembler.

    When invoked as main, interprets its command line and goes from there.
    Otherwise, use run_ophis(cmdline-list) to use it inside a script."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import sys
import os
import Ophis.Frontend
import Ophis.IR
import Ophis.CorePragmas
import Ophis.Passes
import Ophis.Errors as Err
import Ophis.Environment
import Ophis.CmdLine
import Ophis.Opcodes


def run_all():
    """Transforms the source infiles to a binary outfile.

    Returns a shell-style exit code: 1 if there were errors, 0 if there
    were no errors.

    """
    Err.count = 0
    z = Ophis.Frontend.parse(Ophis.CmdLine.infiles)
    env = Ophis.Environment.Environment()

    m = Ophis.Passes.ExpandMacros()
    i = Ophis.Passes.InitLabels()
    l_basic = Ophis.Passes.UpdateLabels()
    l = Ophis.Passes.FixPoint("label update", [l_basic],
                              lambda: not l_basic.changed)

    # The instruction selector is a bunch of fixpoints, and which
    # passes run depends on the command line options a bit.
    c_basic = Ophis.Passes.Collapse()
    c = Ophis.Passes.FixPoint("instruction selection 1", [l, c_basic],
                              lambda: not c_basic.changed)

    if Ophis.CmdLine.enable_branch_extend:
        b = Ophis.Passes.ExtendBranches()
        instruction_select = Ophis.Passes.FixPoint("instruction selection 2",
                                                   [c, b],
                                                   lambda: not b.changed)
    else:
        instruction_select = c
    a = Ophis.Passes.Assembler()

    passes = []
    passes.append(Ophis.Passes.DefineMacros())
    passes.append(Ophis.Passes.FixPoint("macro expansion", [m],
                                        lambda: not m.changed))
    passes.append(Ophis.Passes.FixPoint("label initialization", [i],
                                        lambda: not i.changed))
    passes.extend([Ophis.Passes.CircularityCheck(),
                   Ophis.Passes.CheckExprs(),
                   Ophis.Passes.EasyModes()])
    passes.append(instruction_select)
    passes.extend([Ophis.Passes.NormalizeModes(),
                   Ophis.Passes.UpdateLabels(),
                   a])

    for p in passes:
        p.go(z, env)

    if Err.count == 0:
        try:
            outfile = Ophis.CmdLine.outfile
            if outfile == '-':
                output = sys.stdout
                if sys.platform == "win32":
                    # We can't dump our binary in text mode; that would be
                    # disastrous. So, we'll do some platform-specific
                    # things here to force our stdout to binary mode.
                    import msvcrt
                    msvcrt.setmode(sys.stdout.fileno(), os.O_BINARY)
            elif outfile is None:
                output = file('ophis.bin', 'wb')
            else:
                output = file(outfile, 'wb')
            output.write("".join(map(chr, a.output)))
            output.flush()
            if outfile != '-':
                output.close()
            return 0
        except IOError:
            print>>sys.stderr, "Could not write to " + outfile
            return 1
    else:
        Err.report()
        return 1


def run_ophis(args):
    Ophis.CmdLine.parse_args(args)
    Ophis.Frontend.pragma_modules.append(Ophis.CorePragmas)

    if Ophis.CmdLine.enable_undoc_ops:
        Ophis.Opcodes.opcodes.update(Ophis.Opcodes.undocops)
    elif Ophis.CmdLine.enable_65c02_exts:
        Ophis.Opcodes.opcodes.update(Ophis.Opcodes.c02extensions)
    elif Ophis.CmdLine.enable_4502_exts:
        Ophis.Opcodes.opcodes.update(Ophis.Opcodes.csg4502extensions)

    Ophis.CorePragmas.reset()
    return run_all()


if __name__ == '__main__':
    sys.exit(run_ophis(sys.argv[1:]))
