"""Lexer and Parser

    Constructs a list of IR nodes from a list of input strings."""

import Ophis.Errors as Err
import Ophis.Opcodes as Ops
import Ophis.IR as IR
import Ophis.CmdLine as Cmd
import sys
import os
import os.path

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.


loadedfiles = {}


class Lexeme(object):
    "Class for lexer tokens.  Used by lexer and parser."
    def __init__(self, type="UNKNOWN", value=None):
        self.type = type.upper()
        self.value = value

    def __str__(self):
        if self.value is None:
            return self.type
        else:
            return self.type + ":" + str(self.value)

    def __repr__(self):
        return "Lexeme(" + repr(self.type) + ", " + repr(self.value) + ")"

    def matches(self, other):
        "1 if Lexemes a and b have the same type."
        return self.type == other.type


bases = {"$": ("hexadecimal", 16),
         "%": ("binary", 2),
         "0": ("octal", 8)}


punctuation = "#,`<>():.+-*/&|^[]"


def lex(point, line):
    """Turns a line of source into a sequence of lexemes."""
    Err.currentpoint = point
    result = []

    def is_opcode(op):
        "Tests whether a string is an opcode or an identifier"
        return op in Ops.opcodes

    def add_token(token):
        "Converts a substring into a single lexeme"
        if token == "":
            return
        if token == "0":
            result.append(Lexeme("NUM", 0))
            return
        firstchar = token[0]
        rest = token[1:]
        if firstchar == '"':
            result.append(Lexeme("STRING", rest))
            return
        elif firstchar in bases:
            try:
                result.append(Lexeme("NUM", long(rest, bases[firstchar][1])))
                return
            except ValueError:
                Err.log('Invalid ' + bases[firstchar][0] + ' constant: ' +
                        rest)
                result.append(Lexeme("NUM", 0))
                return
        elif firstchar.isdigit():
            try:
                result.append(Lexeme("NUM", long(token)))
            except ValueError:
                Err.log('Identifiers may not begin with a number')
                result.append(Lexeme("LABEL", "ERROR"))
            return
        elif firstchar == "'":
            if len(rest) == 1:
                result.append(Lexeme("NUM", ord(rest)))
            else:
                Err.log("Invalid character constant '" + rest + "'")
                result.append(Lexeme("NUM", 0))
            return
        elif firstchar in punctuation:
            if rest != "":
                Err.log("Internal lexer error!  '" + token + "' can't happen!")
            result.append(Lexeme(firstchar))
            return
        else:   # Label, opcode, or index register
            id = token.lower()
            if is_opcode(id):
                result.append(Lexeme("OPCODE", id))
            elif id == "x":
                result.append(Lexeme("X"))
            elif id == "y":
                result.append(Lexeme("Y"))
            else:
                result.append(Lexeme("LABEL", id))
            return
        # should never reach here
        Err.log("Internal lexer error: add_token fall-through")

    def add_EOL():
        "Adds an end-of-line lexeme"
        result.append(Lexeme("EOL"))

    # Actual routine begins here
    value = ""
    quotemode = False
    backslashmode = False
    for c in line.strip():
        if backslashmode:
            backslashmode = False
            value = value + c
        elif c == "\\":
            backslashmode = True
        elif quotemode:
            if c == '"':
                quotemode = False
            else:
                value = value + c
        elif c == ';':
            add_token(value)
            value = ""
            break
        elif c == '.' and value != "":
            value = value + c
        elif c.isspace():
            add_token(value)
            value = ""
        elif c in punctuation:
            add_token(value)
            add_token(c)
            value = ""
        elif c == '"':
            add_token(value)
            value = '"'
            quotemode = True
        else:
            value = value + c
    if backslashmode:
        Err.log("Backslashed newline")
    if quotemode:
        Err.log("Unterminated string constant")
    add_token(value)
    add_EOL()
    return result


class ParseLine(object):
    "Maintains the parse state of a line of code. Enables arbitrary lookahead."

    def __init__(self, lexemes):
        self.lexemes = lexemes
        self.location = 0

    def lookahead(self, i):
        """Returns the token i units ahead in the parse.
    lookahead(0) returns the next token; trying to read off the end of
    the sequence returns the last token in the sequence (usually EOL)."""
        target = self.location + i
        if target >= len(self.lexemes):
            target = -1
        return self.lexemes[target]

    def pop(self):
        "Returns and removes the next element in the line."
        old = self.location
        if self.location < len(self.lexemes) - 1:
            self.location += 1
        return self.lexemes[old]

    def expect(self, *tokens):
        """Reads a token from the ParseLine line and returns it if it's of a
    type in the sequence tokens.  Otherwise, it logs an error."""
        token = self.pop()
        if token.type in tokens:
            return token
        if 'LABEL' in tokens:
            if token.type in ['X', 'Y']:
                token.value = token.type.lower()
                token.type = 'LABEL'
                return token
            elif token.type == 'OPCODE':
                token.type = 'LABEL'
                return token
        Err.log('Expected: "' + '", "'.join(tokens) + '"')
        return token


pragma_modules = []


def parse_expr(line):
    "Parses an Ophis arithmetic expression."

    def atom():
        "Parses lowest-priority expression components."
        next = line.lookahead(0).type
        if next == "NUM":
            return IR.ConstantExpr(line.expect("NUM").value)
        elif next in ["LABEL", "X", "Y", "OPCODE"]:
            return IR.LabelExpr(line.expect("LABEL").value)
        elif next == "^":
            line.expect("^")
            return IR.PCExpr()
        elif next == "[":
            line.expect("[")
            result = parse_expr(line)
            line.expect("]")
            return result
        elif next == "+":
            offset = 0
            while next == "+":
                offset += 1
                line.expect("+")
                next = line.lookahead(0).type
            return IR.LabelExpr("*" + str(templabelcount + offset))
        elif next == "-":
            offset = 1
            while next == "-":
                offset -= 1
                line.expect("-")
                next = line.lookahead(0).type
            return IR.LabelExpr("*" + str(templabelcount + offset))
        elif next == ">":
            line.expect(">")
            return IR.HighByteExpr(atom())
        elif next == "<":
            line.expect("<")
            return IR.LowByteExpr(atom())
        else:
            Err.log('Expected: expression')

    def precedence_read(constructor, reader, separators):
        """Handles precedence.  The reader argument is a function that returns
    expressions that bind more tightly than these; separators is a list
    of strings naming the operators at this precedence level.  The
    constructor argument is a class, indicating what node type holds
    objects of this precedence level.

    Returns a list of Expr objects with separator strings between them."""
        result = [reader()]  # first object
        nextop = line.lookahead(0).type
        while (nextop in separators):
            line.expect(nextop)
            result.append(nextop)
            result.append(reader())
            nextop = line.lookahead(0).type
        if len(result) == 1:
            return result[0]
        return constructor(result)

    def term():
        "Parses * and /"
        return precedence_read(IR.SequenceExpr, atom, ["*", "/"])

    def arith():
        "Parses + and -"
        return precedence_read(IR.SequenceExpr, term, ["+", "-"])

    def bits():
        "Parses &, |, and ^"
        return precedence_read(IR.SequenceExpr, arith, ["&", "|", "^"])

    return bits()


def parse_line(ppt, lexemelist):
    "Turn a line of source into an IR Node."
    Err.currentpoint = ppt
    result = []
    line = ParseLine(lexemelist)

    def aux():
        "Accumulates all IR nodes defined by this line."
        if line.lookahead(0).type == "EOL":
            pass
        elif line.lookahead(1).type == ":":
            newlabel = line.expect("LABEL").value
            line.expect(":")
            result.append(IR.Node(ppt, "Label", newlabel, IR.PCExpr()))
            aux()
        elif line.lookahead(0).type == "*":
            global templabelcount
            templabelcount = templabelcount + 1
            result.append(IR.Node(ppt, "Label", "*" + str(templabelcount),
                                  IR.PCExpr()))
            line.expect("*")
            aux()
        elif line.lookahead(0).type == "." or line.lookahead(0).type == "`":
            which = line.expect(".", "`").type
            if (which == "."):
                pragma = line.expect("LABEL").value
            else:
                pragma = "invoke"
            pragmaFunction = "pragma" + pragma.title()
            for mod in pragma_modules:
                if hasattr(mod, pragmaFunction):
                    getattr(mod, pragmaFunction)(ppt, line, result)
                    break
            else:
                Err.log("Unknown pragma " + pragma)
        else:   # Instruction
            opcode = line.expect("OPCODE").value
            if line.lookahead(0).type == "#":
                mode = "Immediate"
                line.expect("#")
                arg = parse_expr(line)
                line.expect("EOL")
            elif line.lookahead(0).type == "(":
                line.expect("(")
                arg = parse_expr(line)
                if line.lookahead(0).type == ",":
                    mode = "PointerX"
                    line.expect(",")
                    line.expect("X")
                    line.expect(")")
                    line.expect("EOL")
                else:
                    line.expect(")")
                    tok = line.expect(",", "EOL").type
                    if tok == "EOL":
                        mode = "Pointer"
                    else:
                        mode = "PointerY"
                        line.expect("Y")
                        line.expect("EOL")
            elif line.lookahead(0).type == "EOL":
                mode = "Implied"
                arg = None
            else:
                arg = parse_expr(line)
                tok = line.expect("EOL", ",").type
                if tok == ",":
                    tok = line.expect("X", "Y").type
                    if tok == "X":
                        mode = "MemoryX"
                    else:
                        mode = "MemoryY"
                    line.expect("EOL")
                else:
                    mode = "Memory"
            result.append(IR.Node(ppt, mode, opcode, arg))

    aux()
    result = [node for node in result if node is not IR.NullNode]
    if len(result) == 0:
        return IR.NullNode
    if len(result) == 1:
        return result[0]
    return IR.SequenceNode(ppt, result)


context_directory = None


def parse_file(ppt, filename, load_once=False):
    "Loads an Ophis source file, and returns an IR list."
    global context_directory, loadedfiles
    Err.currentpoint = ppt
    old_context = context_directory
    if filename != '-':
        if context_directory is not None:
            filename = os.path.abspath(os.path.join(context_directory,
                                                    filename))
        if load_once and filename in loadedfiles:
            if Cmd.print_loaded_files:
                print>>sys.stderr, "Skipping " + filename
            return IR.NullNode
        loadedfiles[filename] = True
    if Cmd.print_loaded_files:
        if filename != '-':
            print>>sys.stderr, "Loading " + filename
        else:
            print>>sys.stderr, "Loading from standard input"
    try:
        if filename != '-':
            if context_directory is not None:
                filename = os.path.join(context_directory, filename)
            f = file(filename)
            linelist = f.readlines()
            f.close()
            context_directory = os.path.abspath(os.path.dirname(filename))
        else:
            context_directory = os.getcwd()
            linelist = sys.stdin.readlines()
        pptlist = ["%s:%d" % (filename, i + 1) for i in range(len(linelist))]
        lexlist = map(lex, pptlist, linelist)
        IRlist = map(parse_line, pptlist, lexlist)
        IRlist = [node for node in IRlist if node is not IR.NullNode]
        context_directory = old_context
        return IR.SequenceNode(ppt, IRlist)
    except IOError:
        Err.log("Could not read " + filename)
        context_directory = old_context
        return IR.NullNode


def parse(filenames):
    """Top level parsing routine, taking a source file name
    list and returning an IR list."""
    global templabelcount
    templabelcount = 0
    nodes = [parse_file("<Top Level>", f) for f in filenames]
    if len(nodes) == 1:
        return nodes[0]
    return IR.SequenceNode("<Top level>", nodes)
