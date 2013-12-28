"""Macro support for Ophis.

    Ophis Macros are cached SequenceNodes with arguments
    set via .alias commands and prevented from escaping
    with .scope and .scend commands."""

# Copyright 2002-2012 Michael C. Martin and additional contributors.
# You may use, modify, and distribute this file under the MIT
# license: See README for details.

import sys

import Ophis.IR as IR
import Ophis.CmdLine as Cmd
import Ophis.Errors as Err

macros = {}
currentname = None
currentbody = None


def newMacro(name):
    "Start creating a new macro with the specified name."
    global currentname
    global currentbody
    global macros
    if currentname is not None:
        Err.log("Internal error!  Nested macro attempt!")
    else:
        if name in macros:
            Err.log("Duplicate macro definition '%s'" % name)
        currentname = name
        currentbody = []


def registerNode(node):
    global currentbody
    currentbody.append(IR.Node(node.ppt, node.nodetype, *node.data))


def endMacro():
    global currentname
    global currentbody
    global macros
    if currentname is None:
        Err.log("Internal error!  Ended a non-existent macro!")
    else:
        macros[currentname] = currentbody
        currentname = None
        currentbody = None


def expandMacro(ppt, name, arglist):
    global macros
    if name not in macros:
        Err.log("Undefined macro '%s'" % name)
        return IR.NullNode
    argexprs = [IR.Node(ppt, "Label", "_*%d" % i, arg)
                for (i, arg) in zip(xrange(1, sys.maxint), arglist)]
    bindexprs = [IR.Node(ppt, "Label", "_%d" % i, IR.LabelExpr("_*%d" % i))
                 for i in range(1, len(arglist) + 1)]
    body = [IR.Node("%s->%s" % (ppt, node.ppt), node.nodetype, *node.data)
            for node in macros[name]]
    invocation = [IR.Node(ppt, "ScopeBegin")] + argexprs + \
                 [IR.Node(ppt, "ScopeBegin")] + bindexprs + body + \
                 [IR.Node(ppt, "ScopeEnd"), IR.Node(ppt, "ScopeEnd")]
    return IR.SequenceNode(ppt, invocation)


def dump():
    global macros
    for mac in macros:
        body = macros[mac]
        print>>sys.stderr, "Macro: " + mac
        for node in body:
            print>>sys.stderr, node
        print>>sys.stderr, ""
