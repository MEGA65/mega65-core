"""The Ophis Assembler passes

    Ophis's design philosophy is to build the IR once, then run a great
    many assembler passes over the result.  Thus, each pass does a
    single, specialized job.  When strung together, the full
    translation occurs.  This structure also makes the assembler
    very extensible; additional analyses or optimizations may be
    added as new subclasses of Pass."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import sys
import Ophis.Errors as Err
import Ophis.IR as IR
import Ophis.Opcodes as Ops
import Ophis.CmdLine as Cmd
import Ophis.Macro as Macro

# The passes themselves


class Pass(object):
    """Superclass for all assembler passes.  Automatically handles IR
    types that modify the environent's structure, and by default
    raises an error on anything else.  Override visitUnknown in your
    extension pass to produce a pass that accepts everything."""
    name = "Default Pass"

    def __init__(self):
        self.writeOK = True

    def visitNone(self, node, env):
        pass

    def visitSEQUENCE(self, node, env):
        Err.currentpoint = node.ppt
        for n in node.data:
            n.accept(self, env)

    def visitDataSegment(self, node, env):
        self.writeOK = False
        env.setsegment(node.data[0])

    def visitTextSegment(self, node, env):
        self.writeOK = True
        env.setsegment(node.data[0])

    def visitScopeBegin(self, node, env):
        env.newscope()

    def visitScopeEnd(self, node, env):
        env.endscope()

    def visitUnknown(self, node, env):
        Err.log("Internal error!  " + self.name +
                " cannot understand node type " + node.nodetype)

    def prePass(self):
        pass

    def postPass(self):
        pass

    def go(self, node, env):
        """Prepares the environment and runs this pass, possibly
        printing debugging information."""
        if Err.count == 0:
            if Cmd.print_pass:
                print>>sys.stderr, "Running: " + self.name
            env.reset()
            self.prePass()
            node.accept(self, env)
            self.postPass()
            env.reset()
            if Cmd.print_labels:
                print>>sys.stderr, "Current labels:"
                print>>sys.stderr, env
            if Cmd.print_ir:
                print>>sys.stderr, "Current IR:"
                print>>sys.stderr, node


class FixPoint(object):
    """A specialized class that is not a pass but can be run like one.
    This class takes a list of passes and a "fixpoint" function."""
    def __init__(self, name, passes, fixpoint):
        self.name = name
        self.passes = passes
        self.fixpoint = fixpoint

    def go(self, node, env):
        """Runs this FixPoint's passes, in order, until the fixpoint
        is true.  Always runs the passes at least once."""
        for i in xrange(100):
            if Err.count != 0:
                break
            for p in self.passes:
                p.go(node, env)
            if Err.count != 0:
                break
            if self.fixpoint():
                break
            if Cmd.print_pass:
                print>>sys.stderr, "Fixpoint failed, looping back"
        else:
            Err.log("Can't make %s converge!  Maybe there's a recursive "
                    "dependency somewhere?" % self.name)


class DefineMacros(Pass):
    "Extract macro definitions and remove them from the IR"
    name = "Macro definition pass"

    def prePass(self):
        self.inDef = False
        self.nestedError = False

    def postPass(self):
        if self.inDef:
            Err.log("Unmatched .macro")
        elif Cmd.print_ir:
            print>>sys.stderr, "Macro definitions:"
            Macro.dump()

    def visitMacroBegin(self, node, env):
        if self.inDef:
            Err.log("Nested macro definition")
            self.nestedError = True
        else:
            Macro.newMacro(node.data[0])
            node.nodetype = "None"
            node.data = []
            self.inDef = True

    def visitMacroEnd(self, node, env):
        if self.inDef:
            Macro.endMacro()
            node.nodetype = "None"
            node.data = []
            self.inDef = False
        elif not self.nestedError:
            Err.log("Unmatched .macend")

    def visitUnknown(self, node, env):
        if self.inDef:
            Macro.registerNode(node)
            node.nodetype = "None"
            node.data = []


class ExpandMacros(Pass):
    "Replace macro invocations with the appropriate text"
    name = "Macro expansion pass"

    def prePass(self):
        self.changed = False

    def visitMacroInvoke(self, node, env):
        replacement = Macro.expandMacro(node.ppt, node.data[0], node.data[1:])
        node.nodetype = replacement.nodetype
        node.data = replacement.data
        self.changed = True

    def visitUnknown(self, node, env):
        pass


class InitLabels(Pass):
    "Finds all reachable labels"
    name = "Label initialization pass"

    def __init__(self):
        Pass.__init__(self)
        self.labelmap = {}
        self.runcount = 0

    def prePass(self):
        self.changed = False
        self.PCvalid = True
        self.runcount += 1

    def visitAdvance(self, node, env):
        self.PCvalid = node.data[0].valid(env, self.PCvalid)

    def visitSetPC(self, node, env):
        self.PCvalid = node.data[0].valid(env, self.PCvalid)

    def visitLabel(self, node, env):
        (label, val) = node.data
        fulllabel = "%d:%s" % (env.stack[0], label)
        if fulllabel in self.labelmap and self.labelmap[fulllabel] is not node:
            Err.log("Duplicate label definition '%s'" % label)
        if fulllabel not in self.labelmap:
            self.labelmap[fulllabel] = node
        if val.valid(env, self.PCvalid) and label not in env:
            env[label] = 0
            self.changed = True
        if label in ['a', 'x', 'y'] and self.runcount == 1:
            print>>sys.stderr, str(node.ppt) + ": WARNING: " \
                "using register name as label"
        if label in Ops.opcodes and self.runcount == 1:
            print>>sys.stderr, str(node.ppt) + ": WARNING: " \
                "using opcode name as label"

    def visitUnknown(self, node, env):
        pass


class CircularityCheck(Pass):
    "Checks for circular label dependencies"
    name = "Circularity check pass"

    def prePass(self):
        self.changed = False
        self.PCvalid = True

    def visitAdvance(self, node, env):
        PCvalid = self.PCvalid
        self.PCvalid = node.data[0].valid(env, self.PCvalid)
        if not node.data[0].valid(env, PCvalid):
            Err.log("Undefined or circular reference on .advance")

    def visitSetPC(self, node, env):
        PCvalid = self.PCvalid
        self.PCvalid = node.data[0].valid(env, self.PCvalid)
        if not node.data[0].valid(env, PCvalid):
            Err.log("Undefined or circular reference on program counter set")

    def visitCheckPC(self, node, env):
        if not node.data[0].valid(env, self.PCvalid):
            Err.log("Undefined or circular reference on program counter check")

    def visitLabel(self, node, env):
        (label, val) = node.data
        if not val.valid(env, self.PCvalid):
            Err.log("Undefined or circular dependency for label '%s'" % label)

    def visitUnknown(self, node, env):
        pass


class CheckExprs(Pass):
    "Ensures all expressions can resolve"
    name = "Expression checking pass"

    def visitUnknown(self, node, env):
        # Throw away result, just confirm validity of all expressions
        for i in [x for x in node.data if isinstance(x, IR.Expr)]:
            i.value(env)


class EasyModes(Pass):
    "Assigns address modes to hardcoded and branch instructions"
    name = "Easy addressing modes pass"

    def visitMemory(self, node, env):
        if Ops.opcodes[node.data[0]][14] is not None:
            node.nodetype = "Relative"
            return
        if node.data[1].hardcoded:
            if not collapse_no_index(node, env):
                node.nodetype = "Absolute"

    def visitMemoryX(self, node, env):
        if node.data[1].hardcoded:
            if not collapse_x(node, env):
                node.nodetype = "AbsoluteX"

    def visitMemoryY(self, node, env):
        if node.data[1].hardcoded:
            if not collapse_y(node, env):
                node.nodetype = "AbsoluteY"

    def visitPointer(self, node, env):
        if node.data[1].hardcoded:
            if not collapse_no_index_ind(node, env):
                node.nodetype = "Indirect"

    def visitPointerX(self, node, env):
        if node.data[1].hardcoded:
            if not collapse_x_ind(node, env):
                node.nodetype = "AbsIndX"

    def visitPointerY(self, node, env):
        if node.data[1].hardcoded:
            if not collapse_y_ind(node, env):
                node.nodetype = "AbsIndY"

    def visitUnknown(self, node, env):
        pass


class PCTracker(Pass):
    "Superclass for passes that need an accurate program counter."
    name = "**BUG** PC Tracker Superpass used directly"

    def visitSetPC(self, node, env):
        env.setPC(node.data[0].value(env))

    def visitAdvance(self, node, env):
        env.setPC(node.data[0].value(env))

    def visitImplied(self, node, env):
        env.incPC(1)

    def visitImmediate(self, node, env):
        env.incPC(2)

    def visitIndirectX(self, node, env):
        env.incPC(2)

    def visitIndirectY(self, node, env):
        env.incPC(2)

    def visitZPIndirect(self, node, env):
        env.incPC(2)

    def visitZeroPage(self, node, env):
        env.incPC(2)

    def visitZeroPageX(self, node, env):
        env.incPC(2)

    def visitZeroPageY(self, node, env):
        env.incPC(2)

    def visitRelative(self, node, env):
        env.incPC(2)

    def visitIndirect(self, node, env):
        env.incPC(3)

    def visitAbsolute(self, node, env):
        env.incPC(3)

    def visitAbsoluteX(self, node, env):
        env.incPC(3)

    def visitAbsoluteY(self, node, env):
        env.incPC(3)

    def visitAbsIndX(self, node, env):
        env.incPC(3)

    def visitAbsIndY(self, node, env):
        env.incPC(3)

    def visitMemory(self, node, env):
        env.incPC(3)

    def visitMemoryX(self, node, env):
        env.incPC(3)

    def visitMemoryY(self, node, env):
        env.incPC(3)

    def visitPointer(self, node, env):
        env.incPC(3)

    def visitPointerX(self, node, env):
        env.incPC(3)

    def visitPointerY(self, node, env):
        env.incPC(3)

    def visitCheckPC(self, node, env):
        pass

    def visitLabel(self, node, env):
        pass

    def visitByte(self, node, env):
        env.incPC(len(node.data))

    def visitByteRange(self, node, env):
        if node.data[1].valid(env):
            env.incPC(node.data[1].value(env))

    def visitWord(self, node, env):
        env.incPC(len(node.data) * 2)

    def visitDword(self, node, env):
        env.incPC(len(node.data) * 4)

    def visitWordBE(self, node, env):
        env.incPC(len(node.data) * 2)

    def visitDwordBE(self, node, env):
        env.incPC(len(node.data) * 4)


class UpdateLabels(PCTracker):
    "Computes the new values for all entries in the symbol table"
    name = "Label Update Pass"

    def prePass(self):
        self.changed = False

    def visitLabel(self, node, env):
        (label, val) = node.data
        old = env[label]
        env[label] = val.value(env)
        if old != env[label]:
            self.changed = True


class Collapse(PCTracker):
    "Selects as many zero-page instructions to convert as possible."
    name = "Instruction Collapse Pass"

    def prePass(self):
        self.changed = False

    def visitMemory(self, node, env):
        self.changed |= collapse_no_index(node, env)
        PCTracker.visitMemory(self, node, env)

    def visitMemoryX(self, node, env):
        self.changed |= collapse_x(node, env)
        PCTracker.visitMemoryX(self, node, env)

    def visitMemoryY(self, node, env):
        self.changed |= collapse_y(node, env)
        PCTracker.visitMemoryY(self, node, env)

    def visitPointer(self, node, env):
        self.changed |= collapse_no_index_ind(node, env)
        PCTracker.visitPointer(self, node, env)

    def visitPointerX(self, node, env):
        self.changed |= collapse_x_ind(node, env)
        PCTracker.visitPointerX(self, node, env)

    def visitPointerY(self, node, env):
        self.changed |= collapse_y_ind(node, env)
        PCTracker.visitPointerY(self, node, env)

    # Previously zero-paged elements may end up un-zero-paged by
    # the branch extension pass. Force them to Absolute equivalents
    # if this happens.

    def visitZeroPage(self, node, env):
        if node.data[1].value(env) >= 0x100:
            if Ops.opcodes[node.data[0]][5] is not None:
                node.nodetype = "Absolute"
                PCTracker.visitAbsolute(self, node, env)
                self.changed = True
                return
        PCTracker.visitZeroPage(self, node, env)

    def visitZeroPageX(self, node, env):
        if node.data[1].value(env) >= 0x100:
            if Ops.opcodes[node.data[0]][6] is not None:
                node.nodetype = "AbsoluteX"
                PCTracker.visitAbsoluteX(self, node, env)
                self.changed = True
                return
        PCTracker.visitZeroPageX(self, node, env)

    def visitZeroPageY(self, node, env):
        if node.data[1].value(env) >= 0x100:
            if Ops.opcodes[node.data[0]][7] is not None:
                node.nodetype = "AbsoluteY"
                PCTracker.visitAbsoluteY(self, node, env)
                self.changed = True
                return
        PCTracker.visitZeroPageY(self, node, env)


def collapse_no_index(node, env):
    """Transforms a Memory node into a ZeroPage one if possible.
    Returns boolean indicating whether or not it made the collapse."""
    if node.data[1].value(env) < 0x100:
        if Ops.opcodes[node.data[0]][2] is not None:
            node.nodetype = "ZeroPage"
            return True
    return False


def collapse_x(node, env):
    """Transforms a MemoryX node into a ZeroPageX one if possible.
    Returns boolean indicating whether or not it made the collapse."""
    if node.data[1].value(env) < 0x100:
        if Ops.opcodes[node.data[0]][3] is not None:
            node.nodetype = "ZeroPageX"
            return True
    return False


def collapse_y(node, env):
    """Transforms a MemoryY node into a ZeroPageY one if possible.
    Returns boolean indicating whether or not it made the collapse."""
    if node.data[1].value(env) < 0x100:
        if Ops.opcodes[node.data[0]][4] is not None:
            node.nodetype = "ZeroPageY"
            return True
    return False


def collapse_no_index_ind(node, env):
    """Transforms a Pointer node into a ZPIndirect one if possible.
    Returns boolean indicating whether or not it made the collapse."""
    if node.data[1].value(env) < 0x100:
        if Ops.opcodes[node.data[0]][11] is not None:
            node.nodetype = "ZPIndirect"
            return True
    return False


def collapse_x_ind(node, env):
    """Transforms a PointerX node into an IndirectX one if possible.
    Returns boolean indicating whether or not it made the collapse."""
    if node.data[1].value(env) < 0x100:
        if Ops.opcodes[node.data[0]][12] is not None:
            node.nodetype = "IndirectX"
            return True
    return False


def collapse_y_ind(node, env):
    """Transforms a PointerY node into an IndirectY one if possible.
    Returns boolean indicating whether or not it made the collapse."""
    if node.data[1].value(env) < 0x100:
        if Ops.opcodes[node.data[0]][13] is not None:
            node.nodetype = "IndirectY"
            return True
    return False


class ExtendBranches(PCTracker):
    """Eliminates any branch instructions that would end up going past
    the 128-byte range, and replaces them with a branch-jump pair."""
    name = "Branch Expansion Pass"
    reversed = {'bcc': 'bcs',
                'bcs': 'bcc',
                'beq': 'bne',
                'bmi': 'bpl',
                'bne': 'beq',
                'bpl': 'bmi',
                'bvc': 'bvs',
                'bvs': 'bvc',
                # 65c02 ones. 'bra' is special, though, having no inverse
                'bbr0': 'bbs0',
                'bbs0': 'bbr0',
                'bbr1': 'bbs1',
                'bbs1': 'bbr1',
                'bbr2': 'bbs2',
                'bbs2': 'bbr2',
                'bbr3': 'bbs3',
                'bbs3': 'bbr3',
                'bbr4': 'bbs4',
                'bbs4': 'bbr4',
                'bbr5': 'bbs5',
                'bbs5': 'bbr5',
                'bbr6': 'bbs6',
                'bbs6': 'bbr6',
                'bbr7': 'bbs7',
                'bbs7': 'bbr7'
                }

    def prePass(self):
        self.changed = False

    def visitRelative(self, node, env):
        (opcode, expr) = node.data
        arg = expr.value(env)
        arg = arg - (env.getPC() + 2)
        if arg < -128 or arg > 127:
            if opcode == 'bra':
                # If BRA - BRanch Always - is out of range, it's a JMP.
                node.data = ('jmp', expr)
                node.nodetype = "Absolute"
                if Cmd.warn_on_branch_extend:
                    print>>sys.stderr, str(node.ppt) + ": WARNING: " \
                                       "bra out of range, replacing with jmp"
            else:
                # Otherwise, we replace it with a 'macro' of sorts by hand:
                # $branch LOC -> $reversed_branch ^+5; JMP LOC
                # We don't use temp labels here because labels need to have
                # been fixed in place by this point, and JMP is always 3
                # bytes long.
                expansion = [IR.Node(node.ppt, "Relative",
                                     ExtendBranches.reversed[opcode],
                                     IR.SequenceExpr([IR.PCExpr(), "+",
                                                      IR.ConstantExpr(5)])),
                             IR.Node(node.ppt, "Absolute", 'jmp', expr)]
                node.nodetype = 'SEQUENCE'
                node.data = expansion
                if Cmd.warn_on_branch_extend:
                    print>>sys.stderr, str(node.ppt) + ": WARNING: " + \
                                       opcode + " out of range, " \
                                       "replacing with " + \
                                       ExtendBranches.reversed[opcode] + \
                                       "/jmp combo"
            self.changed = True
            node.accept(self, env)
        else:
            env.incPC(2)


class NormalizeModes(Pass):
    """Eliminates the intermediate "Memory" and "Pointer" nodes,
    converting them to "Absolute"."""
    name = "Mode Normalization pass"

    def visitMemory(self, node, env):
        node.nodetype = "Absolute"

    def visitMemoryX(self, node, env):
        node.nodetype = "AbsoluteX"

    def visitMemoryY(self, node, env):
        node.nodetype = "AbsoluteY"

    def visitPointer(self, node, env):
        node.nodetype = "Indirect"

    def visitPointerX(self, node, env):
        node.nodetype = "AbsIndX"

    # If we ever hit a PointerY by this point, we have a bug.

    def visitPointerY(self, node, env):
        node.nodetype = "AbsIndY"

    def visitUnknown(self, node, env):
        pass


class Assembler(Pass):
    """Converts the IR into a list of bytes, suitable for writing to
    a file."""
    name = "Assembler"

    def prePass(self):
        self.output = []
        self.code = 0
        self.data = 0
        self.filler = 0

    def postPass(self):
        if Cmd.print_summary and Err.count == 0:
            print>>sys.stderr, "Assembly complete: %s bytes output " \
                               "(%s code, %s data, %s filler)" \
                               % (len(self.output),
                                  self.code, self.data, self.filler)

    def outputbyte(self, expr, env):
        'Outputs a byte, with range checking'
        if self.writeOK:
            val = expr.value(env)
            if val < 0x00 or val > 0xff:
                Err.log("Byte constant " + str(expr) + " out of range")
                val = 0
            self.output.append(int(val))
        else:
            Err.log("Attempt to write to data segment")

    def outputword(self, expr, env):
        'Outputs a little-endian word, with range checking'
        if self.writeOK:
            val = expr.value(env)
            if val < 0x0000 or val > 0xFFFF:
                Err.log("Word constant " + str(expr) + " out of range")
                val = 0
            self.output.append(int(val & 0xFF))
            self.output.append(int((val >> 8) & 0xFF))
        else:
            Err.log("Attempt to write to data segment")

    def outputdword(self, expr, env):
        'Outputs a little-endian dword, with range checking'
        if self.writeOK:
            val = expr.value(env)
            if val < 0x00000000 or val > 0xFFFFFFFFL:
                Err.log("DWord constant " + str(expr) + " out of range")
                val = 0
            self.output.append(int(val & 0xFF))
            self.output.append(int((val >> 8) & 0xFF))
            self.output.append(int((val >> 16) & 0xFF))
            self.output.append(int((val >> 24) & 0xFF))
        else:
            Err.log("Attempt to write to data segment")

    def outputword_be(self, expr, env):
        'Outputs a big-endian word, with range checking'
        if self.writeOK:
            val = expr.value(env)
            if val < 0x0000 or val > 0xFFFF:
                Err.log("Word constant " + str(expr) + " out of range")
                val = 0
            self.output.append(int((val >> 8) & 0xFF))
            self.output.append(int(val & 0xFF))
        else:
            Err.log("Attempt to write to data segment")

    def outputdword_be(self, expr, env):
        'Outputs a big-endian dword, with range checking'
        if self.writeOK:
            val = expr.value(env)
            if val < 0x00000000 or val > 0xFFFFFFFFL:
                Err.log("DWord constant " + str(expr) + " out of range")
                val = 0
            self.output.append(int((val >> 24) & 0xFF))
            self.output.append(int((val >> 16) & 0xFF))
            self.output.append(int((val >> 8) & 0xFF))
            self.output.append(int(val & 0xFF))
        else:
            Err.log("Attempt to write to data segment")

    def assemble(self, node, mode, env):
        "A generic instruction called by the visitor methods themselves"
        (opcode, expr) = node.data
        bin_op = Ops.opcodes[opcode][mode]
        if bin_op is None:
            Err.log('%s does not have mode "%s"' % (opcode.upper(),
                                                    Ops.modes[mode]))
            return
        self.outputbyte(IR.ConstantExpr(bin_op), env)
        arglen = Ops.lengths[mode]
        if mode == 14:  # Special handling for relative mode
            arg = expr.value(env)
            arg = arg - (env.getPC() + 2)
            if arg < -128 or arg > 127:
                Err.log("Branch target out of bounds")
                arg = 0
            if arg < 0:
                arg += 256
            expr = IR.ConstantExpr(arg)
        if arglen == 1:
            self.outputbyte(expr, env)
        if arglen == 2:
            self.outputword(expr, env)
        env.incPC(1 + arglen)
        self.code += 1 + arglen

    def visitImplied(self, node, env):
        self.assemble(node,  0, env)

    def visitImmediate(self, node, env):
        self.assemble(node,  1, env)

    def visitZeroPage(self, node, env):
        self.assemble(node,  2, env)

    def visitZeroPageX(self, node, env):
        self.assemble(node,  3, env)

    def visitZeroPageY(self, node, env):
        self.assemble(node,  4, env)

    def visitAbsolute(self, node, env):
        self.assemble(node,  5, env)

    def visitAbsoluteX(self, node, env):
        self.assemble(node,  6, env)

    def visitAbsoluteY(self, node, env):
        self.assemble(node,  7, env)

    def visitIndirect(self, node, env):
        self.assemble(node,  8, env)

    def visitAbsIndX(self, node, env):
        self.assemble(node,  9, env)

    def visitAbsIndY(self, node, env):
        self.assemble(node, 10, env)

    def visitZPIndirect(self, node, env):
        self.assemble(node, 11, env)

    def visitIndirectX(self, node, env):
        self.assemble(node, 12, env)

    def visitIndirectY(self, node, env):
        self.assemble(node, 13, env)

    def visitRelative(self, node, env):
        self.assemble(node, 14, env)

    def visitLabel(self, node, env):
        pass

    def visitByte(self, node, env):
        for expr in node.data:
            self.outputbyte(expr, env)
        env.incPC(len(node.data))
        self.data += len(node.data)

    def visitByteRange(self, node, env):
        offset = node.data[0].value(env) + 2
        length = node.data[1].value(env)
        if offset < 2:
            Err.log("Negative offset in .incbin")
        elif offset > len(node.data):
            Err.log("Offset extends past end of file")
        elif length < 0:
            Err.log("Negative length")
        elif offset + length > len(node.data):
            Err.log("File too small for .incbin subrange")
        else:
            for expr in node.data[offset:(offset + length)]:
                self.outputbyte(expr, env)
            env.incPC(length)
            self.data += length

    def visitWord(self, node, env):
        for expr in node.data:
            self.outputword(expr, env)
        env.incPC(len(node.data) * 2)
        self.data += len(node.data) * 2

    def visitDword(self, node, env):
        for expr in node.data:
            self.outputdword(expr, env)
        env.incPC(len(node.data) * 4)
        self.data += len(node.data) * 4

    def visitWordBE(self, node, env):
        for expr in node.data:
            self.outputword_be(expr, env)
        env.incPC(len(node.data) * 2)
        self.data += len(node.data) * 2

    def visitDwordBE(self, node, env):
        for expr in node.data:
            self.outputdword_be(expr, env)
        env.incPC(len(node.data) * 4)
        self.data += len(node.data) * 4

    def visitSetPC(self, node, env):
        env.setPC(node.data[0].value(env))

    def visitCheckPC(self, node, env):
        pc = env.getPC()
        target = node.data[0].value(env)
        if (pc > target):
            Err.log(".checkpc assertion failed: $%x > $%x" % (pc, target))

    def visitAdvance(self, node, env):
        pc = env.getPC()
        target = node.data[0].value(env)
        if (pc > target):
            Err.log("Attempted to .advance backwards: $%x to $%x" %
                    (pc, target))
        else:
            for i in xrange(target - pc):
                self.outputbyte(node.data[1], env)
            self.filler += target - pc
        env.setPC(target)
