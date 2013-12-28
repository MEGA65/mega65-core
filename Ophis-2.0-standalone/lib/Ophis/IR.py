"""Ophis Intermediate Representation

    Classes for representing the Intermediate nodes upon which the
    assembler passes operate."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import Ophis.Errors as Err


class Node(object):
    """The default IR Node
    Instances of Node always have the three fields ppt(Program Point),
    nodetype(a string), and data (a list)."""
    def __init__(self, ppt, nodetype, *data):
        self.ppt = ppt
        self.nodetype = nodetype
        self.data = list(data)

    def accept(self, asmpass, env=None):
        """Implements the Visitor pattern for an assembler pass.
        Calls the routine 'asmpass.visitTYPE(self, env)' where
        TYPE is the value of self.nodetype."""
        Err.currentpoint = self.ppt
        routine = getattr(asmpass, "visit" + self.nodetype,
                          asmpass.visitUnknown)
        routine(self, env)

    def __str__(self):
        if self.nodetype != "SEQUENCE":
            return str(self.ppt) + ": " + self.nodetype + " - " + \
                   " ".join(map(str, self.data))
        else:
            return "\n".join(map(str, self.data))

    def __repr__(self):
        args = [self.ppt, self.nodetype] + self.data
        return "Node(" + ", ".join(map(repr, args)) + ")"


NullNode = Node("<none>", "None")


def SequenceNode(ppt, nodelist):
    return Node(ppt, "SEQUENCE", *nodelist)


class Expr(object):
    """Base class for Ophis expressions
    All expressions have a field called "data" and a boolean field
    called "hardcoded".  An expression is hardcoded if it has no
    symbolic values in it."""
    def __init__(self, data):
        self.data = data
        self.hardcoded = False

    def __str__(self):
        return "<UNKNOWN: " + repr(self.data) + ">"

    def valid(self, env=None, PCvalid=False):
        """Returns true if the the expression can be successfully
        evaluated in the specified environment."""
        return False

    def value(self, env=None):
        "Evaluates this expression in the given environment."
        return None


class ConstantExpr(Expr):
    "Represents a numeric constant"
    def __init__(self, data):
        self.data = data
        self.hardcoded = True

    def __str__(self):
        return str(self.data)

    def valid(self, env=None, PCvalid=False):
        return True

    def value(self, env=None):
        return self.data


class LabelExpr(Expr):
    "Represents a symbolic constant"
    def __init__(self, data):
        self.data = data
        self.hardcoded = False

    def __str__(self):
        return self.data

    def valid(self, env=None, PCvalid=False):
        return (env is not None) and self.data in env

    def value(self, env=None):
        return env[self.data]


class PCExpr(Expr):
    "Represents the current program counter: ^"
    def __init__(self):
        self.hardcoded = False

    def __str__(self):
        return "^"

    def valid(self, env=None, PCvalid=False):
        return env is not None and PCvalid

    def value(self, env=None):
        return env.getPC()


class HighByteExpr(Expr):
    "Represents the expression >{data}"
    def __init__(self, data):
        self.data = data
        self.hardcoded = data.hardcoded

    def __str__(self):
        return ">" + str(self.data)

    def valid(self, env=None, PCvalid=False):
        return self.data.valid(env, PCvalid)

    def value(self, env=None):
        val = self.data.value(env)
        return (val >> 8) & 0xff


class LowByteExpr(Expr):
    "Represents the expression <{data}"
    def __init__(self, data):
        self.data = data
        self.hardcoded = data.hardcoded

    def __str__(self):
        return "<" + str(self.data)

    def valid(self, env=None, PCvalid=False):
        return self.data.valid(env, PCvalid)

    def value(self, env=None):
        val = self.data.value(env)
        return val & 0xff


class SequenceExpr(Expr):
    """Represents an interleaving of operands (of type Expr) and
    operators (of type String).  Subclasses must provide a routine
    operate(self, firstarg, op, secondarg) that evaluates the
    operator."""
    def __init__(self, data):
        """Constructor for Sequence Expressions.  Results will be
        screwy if the data inpot isn't a list with types
        [Expr, str, Expr, str, Expr, str, ... Expr, str, Expr]."""
        self.data = data
        self.operands = [x for x in data if isinstance(x, Expr)]
        self.operators = [x for x in data if type(x) == str]
        for i in self.operands:
            if not i.hardcoded:
                self.hardcoded = False
                break
        else:
            self.hardcoded = True

    def __str__(self):
        return "[" + " ".join(map(str, self.data)) + "]"

    def valid(self, env=None, PCvalid=False):
        for i in self.operands:
            if not i.valid(env, PCvalid):
                return False
        return True

    def value(self, env=None):
        subs = map((lambda x: x.value(env)), self.operands)
        result = subs[0]
        index = 1
        for op in self.operators:
            result = self.operate(result, op, subs[index])
            index += 1
        return result

    def operate(self, start, op, other):
        if op == "*":
            return start * other
        if op == "/":
            return start // other
        if op == "+":
            return start + other
        if op == "-":
            return start - other
        if op == "&":
            return start & other
        if op == "|":
            return start | other
        if op == "^":
            return start ^ other
