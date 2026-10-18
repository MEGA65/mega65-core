# SHITE hardware formula codec: proposed changes and extensions

Date: 2026-10-18.

Status: companion proposal for review by the author of the
[SHITE draft](README.md). The user arbitrates disagreements; agreed changes
should then be integrated into that draft, which remains the canonical
specification. This file does not assign new opcode numbers or authorise an
implementation. No changes to the existing draft or RTL accompany it.

The longer [discussion record](formula-codec-discussion.md) preserves the
exploration and review IDs. This proposal incorporates the user's subsequent
clarification: retain JZ/JMP as a good decomposition of IF, provided canonical
reconstruction is reliable; add execution-neutral structural markers only if
needed for disambiguation. A new length-delimited IF instruction is not the
preferred proposal.

## 1. Advance the hardware codec, retaining the existing execution model

The existing draft puts text conversion in CPU-side C/Python first, with
hardware conversion possible later. We are specifically exploring that later
hardware codec now, with minimum practical FPGA area as the priority.

Required operations:

- Formula text to executable SHITE representation, or error code and input
  position on failure.
- Executable representation to editable canonical formula text, without
  separately storing source for successfully compiled native formulas.

Proposed architecture: a serial scanner and shunting-yard parser, RAM-backed
stacks, a serial character/table reader and writer, and shared copy/address
machinery. Use SHITE's ALU/FPU for numeric conversion. Scratch storage can live
in AtticRAM; caches and extra local RAM should need a demonstrated benefit.
No area or throughput estimate has yet been measured.

This proposal does not replace the draft's recalculation rounds, value model,
error propagation or memory-access ownership rules. CPU-supported functions
need integration with those rules, as discussed in section 7.

## 2. Relax canonical text formatting

The user accepts fully parenthesised canonical output. The formatter need not
minimise parentheses or reproduce whitespace, original capitalisation or
redundant grouping. It must preserve evaluation structure, reference locks,
function identity and the numeric distinctions required by SHITE's value
model. Numeric output must reparse exactly enough to retain those distinctions;
cell display rounding is not sufficient for formula reconstruction.

For example, `=A1*(B2+3)` may be reconstructed as `=(A1*(B2+3))`.

A packed text-fragment stack and serial byte-moving loop is one small formatter
implementation. A scratch expression tree is an alternative; neither is a
requirement on the bytecode format. Error positions, stack limits and output
bounds must be explicit. Failed/incomplete formula text remains a separate
case, consistent with the existing UNCOMPILED cell kind.

## 3. Put configurable function spellings in AtticRAM

User-required table entries:

```text
[function token][NUL-terminated name]
[function token][NUL-terminated name]
...
```

Support EN and DE tables and arbitrary function renaming. Stable numeric tokens
retain semantic identity; names are presentation and parsing data. Read the
table serially from AtticRAM rather than requiring an FPGA-resident copy.

Internal specialisations such as SUMRANGE and SUMCELLS may both print as the
public SUM function. Proposed mapping: resolve the public family during name
lookup, select the internal form after parsing its arguments, and map internal
forms back to the public token during reconstruction. This avoids ambiguous
first-match lookup of several unrelated tokens spelling SUM.

Still to agree: table bounds/termination, byte encoding, case matching, valid
name syntax, collision handling and aliases. First-entry canonical spelling
with later aliases is a proposal, not a user decision. Decimal and argument
separators also need a policy independent of function-name translation.

## 4. Compact function IDs and counted lists

User direction: common functions have one-byte tokens, with bit 7 indicating
a two-byte token. Variable lists are prefixed by a count using the same
short/extended idea.

Proposed bit packing, to confirm:

```text
short: [0vvvvvvv]             0..127
long:  [1vvvvvvv][wwwwwwww]   0..32767

long value = (first & 0x7f) | (second << 7)
```

This occupies 16 bits but carries 15 value bits. If the user intended a full
16-bit value range, use a different agreed encoding rather than silently
discarding a bit. Allowing extended encodings of small values would permit
reserved fields to be backpatched without moving output.

Reuse this decoder for lengths where suitable, but agree their maxima first.
Counted cell collections and function argument lists are distinct: expression
arguments require a defined postfix calling grammar, not just a count of raw
cell references. Leave room for general argument-counted function calls beyond
the initial hardware-supported set.

## 5. Four-byte cell references and compact collections

User proposal: where a cell reference is expected, keep its ordinary four-byte
representation and use the all-ones value to introduce other operand forms:

```text
[row16][column16]           ordinary reference
[FFFFFFFF][kind][payload]  extended form
```

Row-first order above follows the existing draft. No change to its little-endian
fields or unlocked modulo-relative-coordinate scheme is proposed here. The
codec receives its formula cell's coordinates, so it can reconstruct relative
references. The earlier actual-coordinate-ID alternative is not an agreed
change to that scheme.

Each field retains bit 15 as the absolute-reference flag. All ones therefore
collides with an otherwise valid reference; provide an escaped literal-reference
form, or explicitly agree a reservation. Preserving all coordinate IDs through
an escape is the current assistant recommendation.

Collection forms under discussion:

| Form | Payload |
|---|---|
| Rectangle | Two complete endpoint references; shape implied |
| Cell list | Count, then four-byte cell references |
| Mixed areas | Count, then tagged cells or rectangles |

Proposed counts describe encoded entries, not expanded cells. Thus
`SUM(A1:A100,C3,E1:E20)` has three areas. Walk rectangles directly without
expanding them. SUMRANGE/SUMCELLS specialisations can imply common layouts;
keep a general mixed form rather than adding every possible combination.

### Stream framing remains the largest format question

The reference escape works within reference contexts. It does not by itself
distinguish arbitrary naked references from short operators at the top level.

Choose and demonstrate an unambiguous grammar before assigning opcode values:

1. Reference-or-escape words for all top-level items: four-byte references,
   but an escape-word overhead on operators/functions/literals.
2. Counted/contextual reference runs: four-byte references where expected,
   with short operators outside those runs.

The draft's explicit REF opcode remains a useful baseline but costs five bytes
per ordinary reference. No choice between these alternatives has been made.

## 6. Keep JZ/JMP, with a canonically reversible IF lowering

The user considers JZ/JMP a good decomposition of IF. They can remain reversible
without extra tokens if compiler-produced formulas obey one structural rule:

```text
<condition RPN>
JZ else_start
<then-expression RPN>
JMP after_if
else_start:
<else-expression RPN>
after_if:
<continuation>
```

Labels above are symbolic; retain relative jump operands in the actual stream.
The two branches each add exactly one value without consuming surrounding
expression operands. JZ consumes the condition. Only the selected branch
executes. Nested IF uses the same pattern inside conditions or either branch.

Canonical compiler rules proposed for review:

- The owning JMP ends the then block immediately before the JZ target.
- That JMP targets the first instruction after the else block.
- Both jumps are forward, and nested regions are properly contained.
- There are no jumps into payload bytes or across unrelated IF regions.
- Do not optimise away, invert, share or rearrange this pattern without also
  preserving explicit reconstruction metadata.

This restricts the canonical formula grammar, not necessarily every bytecode
program the execution engine could run. Arbitrary control-flow graphs are not
promised a source-formula reconstruction.

### How the codec can reconstruct it

At a JZ, the fragment stack already contains the reconstructed condition. Its
target identifies the else start. Under the canonical rule, the fixed-width JMP
immediately before that target identifies the end of the then block, and its
target identifies the end of the else block. The width is the agreed encoded
JMP width, not an assumed byte count before stream framing is settled.

Save a small traversal frame, reconstruct the two bounded branches, then push
the fragment `IF(condition,then,else)` and resume after the region. Nested JZs
push nested frames, including when they occur inside a condition. Validate all
instruction boundaries and branch stack effects by decoding records; do not
search raw literal/string bytes for opcode values.

The evaluator needs no additional IF continuation stack for this jump-based
lowering: its program counter and existing value stack handle nesting. Parsing
and reconstruction still need bounded nesting stacks. This differs from the
earlier length-delimited-IF execution proposal, which needed continuation
frames at runtime.

### Optional structural markers if the canonical rule is insufficient

If other compiler/control-flow needs make the rule above ambiguous, add
execution-neutral markers, for example:

```text
IF_BEGIN
    <condition RPN>
    JZ else_start
    <then RPN>
    JMP if_end
else_start:
    <else RPN>
if_end:
IF_END
```

The evaluator decodes and skips the markers without changing the value stack;
the codec uses them to identify nested source constructs. No marker opcode
numbers or mandatory marker policy are assigned here. The minimum-overhead
proposal is the strict canonical JZ/JMP pattern without markers, unless review
identifies a concrete disambiguation need. Generic jumps alone are not a
guarantee of reversibility if that pattern is relaxed.

## 7. CPU-supported calls and mini-spreadsheets

User-required direction, shown as a payload before final stream framing:

```text
HOSTCALL
    text-length
    saved-call-text
    result-cell
```

Execution skips the text and reads the result cell normally. Reconstruction
emits the saved call. This is an intentional source-text exception for
non-native operations. Some calls can compile into hidden helper cells forming
a mini-spreadsheet; others are computed by the CPU, which updates their result
cells when requisite inputs have changed since the previous update.

No arbitrary hardware function-call ABI is required initially. Keep the format
extensible without requiring every fancy function in the hardware evaluator.
Native lookup functions can use ordinary expression arguments, cell/range
descriptors and mode values; exact function coverage still needs agreement.

Integration questions for the draft author:

- How are external-call dependencies recorded? CPU-side metadata avoids
  repeatedly parsing saved text; an in-stream dependency list is an alternative.
- How do CPU-produced values, errors and change flags participate in the
  existing RECALC rounds and convergence rules? Do not silently substitute a
  different scheduler. Yield-on-dirty and dependency-first execution were
  discussion options, not agreed requirements.
- How does copy/fill relocate saved text and create or rebind helper result
  cells? Opaque text cannot be relocated by rewriting native reference fields.
- What happens to saved external-call text when names or locale tables change?
- What work, if any, is scheduled for external calls in unselected IF branches?
  Native short-circuit execution does not itself settle external scheduling.

## 8. Requested review and incorporation

Please compare this proposal with the existing draft and return agreements,
objections and concrete alternatives for the user to arbitrate. In particular:

1. Settle stream framing with encoded examples of `=A1`, `=A1+B1`, literals,
   aggregate collections and a host call.
2. Confirm extended token/count packing and size limits.
3. Confirm canonical JZ/JMP IF reconstruction, including IF inside a condition
   and both branches; identify whether markers are actually necessary.
4. Reconcile name-table details, public/internal function mapping and locale.
5. Integrate result-cell producers with the existing recalculation model.
6. Define bounded hardware codec interfaces and resources without freezing
   unrelated numerical or implementation choices.

After arbitration, update README.md with the agreed design; that integrated
document becomes the canonical description. Retain this companion and the
discussion record as review history rather than treating unmerged proposals
as an additional conflicting specification.
