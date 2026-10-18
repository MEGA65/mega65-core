# SHITE formula text / RPN codec: discussion record

Date: 2026-10-18.

Status: design discussion for review by the SHITE implementer and the user.
This records the formula-converter conversation, not a final bytecode ABI or
an implementation instruction. The user arbitrates disagreements. An assistant
proposal below is not an agreement merely because it appears in this document.

Current review proposal: [hardware codec changes and extensions](hardware-codec-proposal.md).
Subsequent user clarification favours retaining canonically reversible JZ/JMP
for IF, with execution-neutral markers if disambiguation needs them. The earlier
length-delimited IF discussion below is history, not the current recommendation.
Agreed changes are to be integrated by the other author into README.md, which
remains the canonical specification.

Related draft: [SHITE specification](README.md), especially sections 5, 7, 9,
12 and 13. Background work exists in `src/vhdl/ssnail*.vhdl` and related files.
The RTL has not been reviewed for this discussion, and no implementation or
existing specification is changed by this record.

## 1. Objective and area budget

Give a spreadsheet application two operations:

1. Compile formula text into the binary representation consumed by SHITE, or
   return an error code and a position in the input string.
2. Reconstruct editable formula text from that representation.

Successfully compiled native formulas should not need a separately retained
source string. Invalid/incomplete editing text is a separate concern; saved
text for CPU-supported calls is an intentional exception described below.

The user's priority is the smallest reasonably practical FPGA area. No latency,
formula-length, stack-depth, or LUT/BRAM budget has been fixed. The working
proposal is to trade cycles and AtticRAM accesses for less logic, rather than
build a parallel parser or fast formatter.

The RPN format was explicitly open to redesign in this conversation. Existing
draft encodings are therefore inputs to reconciliation, not silently superseded.

## 2. User requirements and accepted directions

| ID | Direction | Status |
|---|---|---|
| A1 | Compile text to SHITE binary, with error and input position on failure; convert binary back to text. | User requirement |
| A2 | Fully parenthesised canonical output is acceptable. Original whitespace, capitals and redundant parentheses need not survive. | Explicitly accepted |
| A3 | Function spellings live in AtticRAM as token plus NUL-terminated string entries. Support EN and DE tables and arbitrary renaming. | User requirement |
| A4 | Numeric conversion uses SHITE's ALU/FPU facilities being developed. | User requirement |
| A5 | The converter can be supplied with the formula cell's coordinates. | User provision |
| A6 | A reference has 16-bit row and column fields; bit 15 in each is its `$` lock flag. | User requirement |
| A7 | Common function tokens use one byte, with bit 7 indicating a two-byte token. | User requirement |
| A8 | Variable cell/argument lists have a prefixed count: seven bits in the short form, bit 7 indicating an extended form. | User requirement; exact extended packing needs confirmation |
| A9 | Numeric and string literals are required. | User requirement |
| A10 | Support `IF`, nested `IF`, and lookup functions. Retain JZ/JMP if canonically reversible; add structural markers if needed. | Latest user direction; supersedes the earlier length-delimited preference |
| A11 | Use an all-ones cell ID as an escape for ranges, sets, lists, etc., aiming to keep normal cell references at four bytes. | User-proposed direction; framing remains open |
| A12 | General external calls retain call text with a length and a result-cell ID. The CPU maintains the result; some calls can instead become mini-spreadsheets. | User direction |
| A13 | Initially, arbitrary fancy function implementations are out of scope, but the format must leave room for them. | User scope constraint |

`SUMRANGE` and `SUMCELLS`, both presented as `SUM(...)`, were suggested by the
user as possible internal specialisations. Their exact encoding is not decided.

## 3. Round-trip contract

Proposed contract: formatting and reparsing preserve expression structure,
function identity, reference lock flags and numeric values/types to the extent
required by SHITE's value model. Decide separately whether byte-for-byte
bytecode identity is required; it does not follow automatically from semantic
round trips.

For example:

```text
= a1 * ( b2 + 3 )
        -> A1 B2 3 ADD MUL
        -> =(A1*(B2+3))
```

The RPN above is symbolic, not a decided physical encoding.

Full parentheses avoid precedence logic in the formatter and preserve the
evaluation tree. Reassociating floating-point operations can change results.
Destructive constant folding or lowering to arbitrary control flow can lose
the formula structure, so either retain that structure or explicitly weaken
the reconstruction contract before adopting such transformations.

Number printing must recover the stored literal when reparsed. Ordinary cell
display rounding is insufficient. Numeric kind, fixed-point metadata, negative
zero and other supported distinctions need reconciliation with SHITE's actual
numeric rules; no new numeric representation is selected here.

## 4. Proposed small converter architecture

### Text to binary

Use a serial scanner and a shunting-yard parser, with:

- Current input offset and token-start offset.
- An expected-operand / expected-operator state.
- An operator/function stack, including argument counts and source positions.
- A sequential output writer, with backpatching for structured blocks.
- Fixed semantic metadata for precedence, associativity, arity and dispatch.
- A serial AtticRAM reader for configurable textual function names.

The name table changes spelling, not function semantics. Arithmetic conversion
is a serial client of SHITE's own ALU/FPU, rather than a duplicate datapath.

Errors should cover malformed syntax, unknown names, bad literals, unmatched
delimiters and resource exhaustion. Saved opening-delimiter positions allow an
unmatched opening parenthesis to be reported at its source position. Exact
error codes, zero/one-based offsets, byte/character offsets and limits remain
open. Publish output as valid only after successful compilation.

### Binary to text

The preferred discussion proposal is a stack of text fragments in one packed
scratch buffer. Operand records create fragments; operators combine their
argument fragments with parentheses or function punctuation:

```text
A1   -> A1
B2   -> A1 | B2
3    -> A1 | B2 | 3
ADD  -> A1 | (B2+3)
MUL  -> (A1*(B2+3))
```

A descriptor stack records fragment boundaries/lengths. A serial byte-moving
loop inserts punctuation and moves text. Awkward expressions may require
roughly quadratic text movement; that is a latency trade, not measured
performance. A scratch-RAM expression tree followed by traversal is an
alternative if it simplifies implementation or improves latency.

Conditional reconstruction needs a formatting traversal stack as well as
ordinary fragment handling. Both branches must be visited for reconstruction.

The two conversion directions can share byte reads/writes, address arithmetic,
table lookup, copy machinery, arithmetic facilities and scratch storage when
they run at different times. Stacks and scratch buffers may live in AtticRAM;
local RAM/caches are optional later optimisations. No area estimate has been
measured or promised.

## 5. Function spelling tables and locale

User-specified entry shape:

```text
[function token][name bytes][NUL]
[function token][name bytes][NUL]
...
```

Use the agreed extended-token convention for token fields. Table termination,
address/length parameters and malformed-table handling are still undecided.
An end marker was suggested but no token value is reserved by this document.

Proposed implementation: scan the AtticRAM table serially, comparing a name
while compiling and finding a token while formatting. No local copy or parallel
string-comparison bank is required. Linear-search latency is acceptable as a
starting hypothesis, not a measured result.

Assistant proposals requiring review:

- Duplicate entries for one token can provide input aliases; the first spelling
  is used for canonical output.
- Public function-family tokens name `SUM`, etc. Internal `SUMRANGE` and
  `SUMCELLS` forms map to that public token when printing. Parsing first resolves
  the public name and selects an internal form after seeing the arguments.
  Two unrelated tokens with the same spelling cannot simply use first-match
  name lookup without an ambiguity rule.
- Decimal and argument separators can be configured separately from names,
  e.g. decimal point/comma and comma/semicolon argument separators.

Specify byte encoding, case matching, allowed name characters and token
boundaries. Arbitrary renaming must have a defined response to names colliding
with syntax or each other; a quoted-name syntax is one possible solution, not
an accepted requirement. Literal strings also need escaping rules. No ASCII,
PETSCII or UTF-8 choice is made here.

## 6. Compact tokens, counts and lengths

The following is the assistant's proposed interpretation of the extension bit:

```text
short: [0vvvvvvv]
long:  [1vvvvvvv][wwwwwwww]

value = (first & 0x7f) | (second << 7)
```

This gives 0..127 in one byte and 0..32767 in two. The user's phrase "16 bit
value" needs confirmation: a two-byte representation with one flag bit has
15 payload bits. Supporting all 65536 values would need a different scheme.
The bit order above is proposed, not agreed.

Suggested reuse: function IDs and list counts, potentially also string lengths
and block lengths if their bounds fit. Do not assume every length field must
use this format before its maximum is defined.

Allowing a long encoding for a small value would let the compiler reserve two
bytes and backpatch a count/length without shifting subsequent bytes. This is
an assistant proposal; shortest-form enforcement and bytecode canonicalisation
remain open.

## 7. Cell references, escape and stream framing

A normal reference contains two 16-bit fields. Bit 15 of each is its `$` flag;
bits 14..0 carry a coordinate ID or a relative-coordinate representation.
Row/column order and relative-coordinate semantics are not settled by the
conversation.

The user's escape proposal, shown in a reference context:

```text
[coordinate16][coordinate16]        ordinary four-byte reference
[FFFFFFFF][kind][payload...]        extended reference/collection
```

`FFFFFFFF` collides with the maximum row/column payload and both lock flags
set. Proposed resolution: provide an escaped literal-reference subtype, so
that this otherwise valid reference remains representable. Reserving a cell
or coordinate instead is another option, but has not been approved.

There is a separate top-level framing problem: arbitrary naked four-byte cell
references cannot be distinguished from arbitrary one-byte RPN operators by
their first byte. The all-ones escape alone does not solve that.

Alternatives discussed, neither selected:

1. Every top-level item begins with a four-byte reference-or-escape word.
   Ordinary references cost four bytes; operators/literals/functions begin
   with the four-byte escape and then their token/payload.
2. Counted reference runs or other operand contexts identify where four-byte
   references occur; operators outside those contexts keep short tokens.

A conventional explicit `REF` token is another comparison baseline, but adds
a byte per ordinary reference and does not meet the desired standalone
four-byte cost. Any final grammar must show unambiguous examples mixing cell
references, numeric/string literals, arithmetic operators and nested functions.

Relative-reference arbitration is especially important. The assistant suggested
actual IDs with copy/fill adjusting unlocked references. The existing draft
instead stores relative offsets modulo 32768 when the lock bit is clear.
Modulo representation can address all 15-bit coordinate IDs; the earlier
discussion's concern about ordinary signed-offset reach is not by itself an
objection to that draft. Define relocation, bounds and wrap/error behaviour
before choosing. The supplied formula-cell coordinates support either design.

## 8. Rectangles, disjoint areas and aggregates

Suggested operand forms, with the actual tags and enclosing framing undecided:

| Form | Payload | Implied information |
|---|---|---|
| Rectangle | Two complete endpoint references | Endpoints delimit a rectangle |
| Cell list | Count, then four-byte references | Every entry is a single cell |
| Mixed areas | Count, then tagged cells/rectangles | Each entry carries its shape |

Proposed count semantics: number of encoded entries, not the number of cells
covered. For `SUM(A1:A100,C3,E1:E20)`, a mixed-area list has three entries.
A large rectangle does not consume one count unit per covered cell.

Walk rectangles with row/column counters instead of expanding them. Preserve
endpoint lock flags for reconstruction and relocation. User-suggested internal
specialisations such as `SUMRANGE` / `SUMCELLS` can imply homogeneous layouts
and avoid repeated tags. Keep a general mixed form rather than creating an
opcode for every possible shape combination.

The distinction between a cell-collection operand and a general function's
argument list still needs a precise grammar: arguments can themselves be
expressions. A prefix count is easy in a literal list; ordinary postfix calls
need an explicit rule locating their argument count and operands.

## 9. Structured IF and traversal

Historical proposal, initially accepted as a direction but superseded by the
user's subsequent preference for retaining reversible JZ/JMP:

```text
<condition RPN>
IF <then-byte-length> <else-byte-length>
    <then RPN>
    <else RPN>
<continuation>
```

These are byte lengths of complete branch bodies. Exact length encoding,
token placement and frame layout remain to be specified.

Execution consumes the condition, chooses a block, executes only that block,
and resumes after both blocks. Each successful branch produces one result.
For example, `IF(A1=0,0,1/A1)` must not evaluate the division when the condition
is true. Condition errors and branch errors need defined propagation rules.

A small nested-control stack can record:

- The selected branch's end address.
- The continuation after the complete `IF`.

An inner `IF` pushes another frame. At a selected branch boundary, pop the
frame and resume at its continuation. Validate block bounds and stack effects;
report resource exhaustion rather than overrun the stack or output buffer.

Compilation reserves length fields and backpatches them at argument completion.
Formatting traverses both branches, reconstructing
`IF(condition,then,else)`. A static dependency walker can visit both branches
without evaluating either; an execution walker visits only the selected one.
Traversal must skip literal payloads and opaque text by their lengths.

The same mechanism could later support `IFERROR`, `CHOOSE`, etc.; those are
examples, not newly agreed implementation scope.

Current proposal: retain the draft's JZ/JMP with a canonical IF lowering:

```text
<condition RPN>
JZ else_start
<then RPN>
JMP after_if
else_start:
<else RPN>
after_if:
```

The JMP ends the then block immediately before the JZ target and identifies
the end of the else block. Require proper nesting and validate boundaries and
stack effects. A bounded traversal stack can reconstruct both branches and
combine them with the condition fragment; nested IFs follow the same rule.
Arbitrary jump graphs are not promised reversible source representations.

If that grammar cannot remain unambiguous, add no-op structural markers such as
IF_BEGIN/IF_END for codec traversal. They are skipped during execution. With
JZ/JMP, execution itself does not need the additional continuation stack of
the earlier block proposal; the value stack and program counter suffice for
nested conditionals. See the companion proposal for the complete rationale.

## 10. Lookups and future function implementations

Lookup representation can use ordinary expression arguments, cell/range
descriptors and mode values. Scanning, searching or indexing those ranges is
execution behaviour rather than a new source-expression representation.
Exact supported lookup functions and semantics remain undecided.

Retain an extensible function-ID namespace and a general argument-counted call
path alongside specialised compact forms. An unimplemented function can report
an unsupported-function error, or be represented through the CPU-supported
mechanism below when the compiler/application provides it. Hardware need not
implement arbitrary user functions in the initial version.

## 11. CPU-supported calls and mini-spreadsheets

User direction: retain the function-call text and its length, followed by a
cell ID where its result can be found. Symbolic payload:

```text
HOSTCALL
    text-length
    saved-call-text
    result-cell
```

Its outer escape/token and field widths depend on the unresolved stream
grammar. Evaluation skips the text and reads the result cell like a normal
value source. Reconstruction emits the saved call text. The FPGA does not
need to understand or execute the opaque call itself.

The result may be produced by:

1. A hidden mini-spreadsheet of ordinary cells implementing the operation.
2. CPU code that recalculates and writes the result when requisite inputs have
   changed since the previous update.

This is an intentional source-text exception for operations that cannot yet
be fully represented/reconstructed as native SHITE expressions.

Assistant proposals / integration issues, not agreed scheduling architecture:

- Record call dependencies when creating the call, rather than repeatedly
  parsing its text. The CPU may keep that information outside the RPN; adding
  a counted dependency list is an alternative if a self-contained record is
  needed.
- Define result freshness and publication. Dependency-before-use scheduling
  or a yield-on-dirty-result mechanism could prevent stale reads. The existing
  draft instead uses repeated recalculation rounds, so decide how CPU-produced
  cells participate in those rounds and convergence before adding either
  mechanism.
- Copying a formula may require relocating its saved call text and creating or
  rebinding helper cells. An opaque text blob cannot be relocated by merely
  rewriting native reference fields. Treat helper result IDs deliberately,
  rather than assuming they have the source formula's ordinary `$` behaviour.
- A host call in an unselected `IF` branch need not be refreshed solely for
  that evaluation. Demand scheduling can exploit this; eager CPU updates are
  also possible. Do not confuse bytecode short-circuiting with a guarantee
  about external scheduling.
- Saved text needs a defined locale/encoding policy when the function table
  changes. Native tokens can be renamed automatically; opaque call text may
  require CPU reconstruction.

## 12. Reconciliation with the existing SHITE draft

Only the documentation was consulted to place this record. No conclusion
about current RTL implementation status is implied.

| Topic | Existing `README.md` draft | This discussion / action needed |
|---|---|---|
| Translator location | CPU C/Python first; hardware later | Explore a minimum-area hardware codec; implementation timing not decided |
| Bytecode framing | One-byte opcode with immediates | Short/extended function IDs and desired naked four-byte references; settle grammar |
| Reference field order | Row, then column | Column-first appeared in an assistant sketch; no user decision; reconcile explicitly |
| Relative references | Signed offset modulo 32768 when unlocked | Actual-ID alternative was proposed, not adopted; current companion proposes retaining the draft scheme |
| Function naming | Shared name/metadata tables | User requires AtticRAM token-plus-NUL-string spelling tables, including EN/DE |
| Canonical text | Remove unnecessary parentheses | Fully parenthesised output explicitly acceptable |
| Conditional code | JZ/JMP | Retained in the latest direction; require canonical reconstruction, with no-op markers if needed |
| Literals | I32/I64/F64 and short strings | Numeric and string literals required; reconcile widths, kinds and exact round trips |
| Recalculation | Repeated rounds and change lists | CPU-supported result cells must integrate with this, or an explicit replacement |
| Cell/formula limits | Granule-based cell sizes, bounded stacks and scratch | Converter and nested-control limits still need agreement |

Do not silently transplant the proposed format into the evaluator or rewrite
the existing draft while these points are under arbitration.

## 13. Review and arbitration checklist

Feedback can cite these IDs. Record reviewer proposals separately from the
user's final decision so that an LLM recommendation is not mistaken for assent.

| ID | Decision required | Current disposition |
|---|---|---|
| Q1 | Top-level framing preserving cheap references and short tokens | Open; reference-or-escape words vs counted/contextual reference runs |
| Q2 | Coordinate order, actual IDs vs modulo-relative values, relocation and bounds | Open; existing draft is row-first and modulo-relative |
| Q3 | Meaning/packing of extended counts and IDs; maximum values; nonminimal forms | Proposed two-byte, 15-payload-bit form; confirm |
| Q4 | All-ones reference collision and escape subtype namespace | Escaped literal reference proposed |
| Q5 | List vs function-argument grammar, rectangle/mixed-area forms, count semantics | Compact specialisations proposed; encoded-entry counts proposed |
| Q6 | Canonical IF lowering, nested traversal, validation and possible markers | Latest direction retains reversible JZ/JMP; markers only if needed |
| Q7 | Numeric kinds, exact parse/print rules, string encoding/length/escaping | Required, not frozen |
| Q8 | Name-table bounds/termination, aliases, family mapping, case/locale/name syntax | AtticRAM table required; detailed policies proposed/open |
| Q9 | External-call dependencies, result freshness, scheduling and relocation | Text plus result-cell direction accepted; integration open |
| Q10 | Hardware/CPU split, command interface, memory ownership and resource budgets | Area-first hardware exploration; no implementation authorisation from this record |
| Q11 | Round-trip guarantee: semantic/typed expression stability vs identical bytes | Canonical text accepted; stronger guarantee to specify |

Suggested next review artifact: a small set of fully encoded examples covering
`=A1`, `=A1+B1`, literals, a rectangle sum, disjoint areas, mixed absolute and
relative references, nested `IF`, and a CPU-supported call. The examples should
settle Q1 before numeric opcode assignments or RTL work begin. This is a review
suggestion, not work already performed.
