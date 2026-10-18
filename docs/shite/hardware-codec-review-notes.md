# Review notes on SHITE draft 2

Date: 2026-10-18.

Status: feedback for the author of the [canonical README](README.md), following
its incorporation of the hardware codec proposal. These are review findings
and suggested resolutions, not approved specification changes. The user
arbitrates; the other author can incorporate the agreed resolutions into the
README. No existing specification or RTL is changed by these notes.

## Overall assessment

The consolidation is sound. In particular:

- The short-reference marker resolves top-level framing unambiguously. Trading
  one column payload bit for the marker, with a long-reference fallback, keeps
  common references at four bytes and operators short.
- The reference-specific big-endian layout looks straightforward to implement.
- The canonical JZ/JMP IF lowering is sufficient for reconstruction, including
  nested IFs in conditions and either branch. No structural marker tokens are
  needed while the stated compiler restrictions hold.
- Jump execution needs no additional IF continuation stack. Codec traversal
  still needs a bounded nesting stack.

Four correctness/contract issues and one capacity decision remain below.

## R1. Give HOSTCALL result references fixed-width patch slots

Relevant sections: README 5.3, 5.6 and 10.

COMPILE emits a placeholder result reference at absolute row 32767, column
16383. It fits the four-byte short form. The CPU subsequently rewrites it to
the actual result cell, which might require a five-byte long reference, for
example absolute column 20000.

Growing that slot shifts subsequent instructions, changes bytecode length and
can invalidate enclosing or subsequent jump offsets. A simple reference rewrite
is therefore not sufficient under the present variable-width definition.

Suggested resolution: inside HOSTCALL, store the fixed four-byte full reference
payload used by REF, without REF's opcode. HOSTCALL already supplies the context
needed to interpret all 32 bits, so no short-reference marker is necessary.
Alternatively, always reserve the five-byte long form and forbid resizing it
during binding. Specify which rule walkers and the codec must use.

Check: compile a host call inside IF, then bind it to a high-column result cell.
Binding must preserve all following byte positions and jump targets. The CPU
must complete binding before the formula becomes executable.

## R2. Preserve blank identity until the consumer handles it

Relevant sections: README 4 and the stack-entry kinds in 5.

A reference currently pushes I64 zero for an EMPTY or missing cell, together
with a "from a reference" bit. That has the same representation as a reference
to a numeric-zero cell. Aggregates, however, must skip empty cells while
counting numeric zero.

The provenance bit alone cannot distinguish those cases. COUNT, AVERAGE and
some MIN/MAX cases would consequently give incorrect results.

Suggested resolution: retain an internal blank/empty kind, or equivalent
metadata, until the consuming operation applies its coercion rules. Arithmetic
can still treat a blank reference as zero; aggregates can skip it.

Checks:

- A1 empty: `COUNT(A1)` is 0.
- A1 contains numeric zero: `COUNT(A1)` is 1.
- A1 empty: `AVERAGE(A1)` has no numeric contributors and gives #DIV/0!.
- Blank-reference arithmetic retains the agreed zero-coercion behaviour.

## R3. Refine the round-trip guarantee

Relevant sections: README 5.2, literal rules in 5.4, and canonical text / host
functions in 10.

The requirement that recompiling reconstructed text gives "the same bytecode"
is stronger than the current representation and binding protocol support:

- A bound HOSTCALL reconstructs its call text, which does not contain its helper
  result-cell identity. Recompilation emits the placeholder, not the bound ID.
- Both short and long encodings of small counts are accepted. Text alone does
  not preserve which encoding was used.
- Numeric values need type-aware spellings. For example, printing an F64 literal
  as `1.25` would currently recompile it as fixed point. Those kinds can behave
  differently in subsequent arithmetic. Fixed-point scale and signed zero also
  need preservation where observable under SHITE's rules.

Suggested resolution: distinguish preservation of typed expression semantics
and structure from byte-for-byte identity. Define canonical numeric syntax that
can retain required kinds/scales, canonical bytecode where applicable, and an
explicit CPU rebinding step for host calls. A stronger identity guarantee can
apply to a precisely defined canonical subset rather than every accepted stream.

Checks: round-trip native F64 and fixed-point expressions, accepted nonminimal
count encodings, and a host call after its result reference has been bound.
Use the same formula origin and codec settings when assessing the guarantee.

## R4. Define convergence accounting for CPU-produced result cells

Relevant sections: README 5.6, RECALC in 6, and 7.

The draft says that CPU-written host results participate in convergence by
setting CHANGED. RECALC's returned count and change list, however, record formula
results changed by RECALC itself. Setting a flag on a numeric host-result cell
does not automatically add it to either count or list.

The driver must not declare convergence solely from a zero hardware change
count while CPU updates or required host computations remain outstanding.

Suggested resolution: either give the CPU driver a separate external-change /
pending-work completion criterion, or define how CPU updates are registered in
the round counts and lists. Specify ordering relative to BEGIN, END and the
convergence check. Retain the repeated-round model; a new scheduler is not
required merely to close this accounting gap.

Check: native formulas feed a CPU-supported function whose result feeds another
native formula. Ensure the driver cannot stop before the external producer and
its consumers have settled, including around an otherwise zero-change round.

## R5. Agree the explicit-argument capacity

Relevant sections: README 5's 32-entry evaluation stack and CALL in 5.7.

CALL requires all its arguments to be present on the value stack. Thus one RECT
argument can cover a huge range, but 33 separate cell arguments cannot execute
on a 32-entry stack. The larger encoded count range does not remove that limit;
nested argument expressions may reach the stack bound even sooner.

This can be a deliberate initial limit, rather than a correctness bug, provided
the compiler checks maximum live stack depth and reports a positioned resource
error. Otherwise, provide a streamed/counted collection operand or another
bounded accumulation representation for larger disjoint argument lists.
Any alternative must preserve evaluation order, error behaviour and canonical
reconstruction.

Checks: contrast a large rectangular SUM with a SUM over more than 32 separately
listed cells. State whether the latter is supported or deliberately rejected.

## Suggested review order

Resolve R1 and R2 first: both have small, direct representation fixes that avoid
later rework. Then settle the R3 contract, R4 driver protocol and R5 capacity
policy. Record agreements in README.md after user arbitration; keep this file
as feedback history rather than a competing canonical specification.
