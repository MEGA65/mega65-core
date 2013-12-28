"""Command line options data."""

import optparse

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

enable_branch_extend = True
enable_undoc_ops = False
enable_65c02_exts = False

warn_on_branch_extend = True

print_summary = True
print_loaded_files = False
print_pass = False
print_ir = False
print_labels = False

infiles = None
outfile = None


def parse_args(raw_args):
    "Populate the module's globals based on the command-line options given."
    global enable_collapse, enable_branch_extend
    global enable_undoc_ops, enable_65c02_exts
    global warn_on_branch_extend
    global print_summary, print_loaded_files
    global print_pass, print_ir, print_labels
    global infiles, outfile

    parser = optparse.OptionParser(
        usage="Usage: %prog [options] srcfile [srcfile ...]",
        version="Ophis 6502 cross-assembler, version 2.0")

    parser.add_option("-o", default=None, dest="outfile",
                      help="Output filename (default 'ophis.bin')")

    ingrp = optparse.OptionGroup(parser, "Input options")
    ingrp.add_option("-u", "--undoc", action="store_true", default=False,
                     help="Enable 6502 undocumented opcodes")
    ingrp.add_option("-c", "--65c02", action="store_true", default=False,
                     dest="c02", help="Enable 65c02 extended instruction set")

    outgrp = optparse.OptionGroup(parser, "Console output options")
    outgrp.add_option("-v", "--verbose", action="store_const", const=2,
                      help="Verbose mode", default=1)
    outgrp.add_option("-q", "--quiet", action="store_const", help="Quiet mode",
                      dest="verbose", const=0)
    outgrp.add_option("-d", "--debug", action="count", dest="verbose",
                      help=optparse.SUPPRESS_HELP)
    outgrp.add_option("--no-warn", action="store_false", dest="warn",
                      default=True, help="Do not print warnings")

    bingrp = optparse.OptionGroup(parser, "Compilation options")
    bingrp.add_option("--no-branch-extend", action="store_false",
                      dest="enable_branch_extend", default="True",
                      help="Disable branch-extension pass")

    parser.add_option_group(ingrp)
    parser.add_option_group(outgrp)
    parser.add_option_group(bingrp)

    (options, args) = parser.parse_args(raw_args)

    if len(args) == 0:
        parser.error("No input files specified")
    if options.c02 and options.undoc:
        parser.error("--undoc and --65c02 are mutually exclusive")

    infiles = args
    outfile = options.outfile
    enable_branch_extend = options.enable_branch_extend
    enable_undoc_ops = options.undoc
    enable_65c02_exts = options.c02
    warn_on_branch_extend = options.warn
    print_summary = options.verbose > 0  # no options set
    print_loaded_files = options.verbose > 1  # v
    print_pass = options.verbose > 2  # dd
    print_ir = options.verbose > 3  # ddd
    print_labels = options.verbose > 4  # dddd
