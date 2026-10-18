# SHITE: Spreadsheet Hardware Integrated Technology Engine

A spreadsheet recalculation and rendering engine for the MEGA65, beside
SSNAIL on the attic RAM (HyperRAM / SDRAM) through LUMP.  The 45GS02 owns
the user interface, formula parsing and editing; SHITE evaluates formulas,
detects what changed, maintains the per-row cell index and renders cells as
screen text.

Status: specification, draft 2: the canonical description.  It merges
[the hardware codec proposal](hardware-codec-proposal.md) and
[its review notes](hardware-codec-review-notes.md) (with the
[discussion record](formula-codec-discussion.md), kept as history).
Implemented so far: the build structure (section 1), REBALANCE_ROW and
FIND_CELL, and the reference model `SSNAIL/shite.py` (being brought to
this draft's 24-bit columns, 12-bit links and 32-bit rows).

Design goals, in order: correct and deterministic results; small area
(iterative units, shared datapaths: several million simple cell updates per
second is plenty); a memory format the CPU can edit cheaply through the
ordinary attic RAM interface.

## 1. Build options and dispatch

SHITE's commands are SSNAIL instructions.  SSNAIL's shell (its registers at
`$FFD7500`, job control, instruction fetch and decode, the scalar and
control instructions, COPY and SYNC) dispatches them to the SHITE unit and
waits for it, so SHITE has no registers of its own, and a SSNAIL program can
run a whole recalculation loop on its own (RECALC leaves the changed count
in a register: BNE back while it is not zero).

While SHITE runs an instruction the rest of SSNAIL is idle, so SHITE's
memory accesses go through SSNAIL's LUMP ports by a plain multiplexer:
there is no arbitration.

Two generics on `ssnail` (set from `iomapper.vhdl`) choose the units:

| `has_llm` | `has_shite` | Built |
|---|---|---|
| true | true | everything |
| true | false | SSNAIL as today |
| false | true | SSNAIL's shell and SHITE: the LLM / vector opcodes report ERR_OPCODE |
| false | false | nothing (no `ssnail` instance; its LUMP outputs idle, as `no_ssnail_gen` today) |

SSNAIL's capability register says which are present, so software can check
before it starts a job.

## 2. Memory model

The sheet lives in attic RAM.  The CPU reads and writes it through the
usual attic RAM interface; SHITE through LUMP.  No new shared memory is
needed.

- SHITE keeps no sheet state between commands.  Its caches are invalidated
  when a command starts, so CPU edits made between commands are always
  seen.
- The CPU must not write the sheet while SHITE is busy (status bit 0).
  Reads are always safe, but may see a round half done.
- All structures are little-endian.  Addresses are 28-bit SSNAIL-style
  physical addresses (`$8000000` up), held in 32-bit fields.
- Everything SHITE reads or writes in bulk is 16-byte aligned (a granule),
  so LUMP transfers are whole 8-byte groups.

## 3. Data structures

### 3.1 Sheet descriptor (64 bytes, 16-byte aligned)

Every instruction names a sheet descriptor; it holds the sheet's geometry,
where results go, and the codec's settings.  A sheet has up to 2^20 rows
and 2^24 columns: enough to keep several of the user's sheets as regions
of one.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `"SHT1"` |
| 4 | 4 | row table address |
| 8 | 4 | number of rows (1 to 2^20) |
| 12 | 4 | number of columns (1 to 2^24) |
| 16 | 4 | change list address (16-byte aligned) |
| 20 | 4 | change list capacity (entries) |
| 24 | 4 | previous change list address (0: no comparison) |
| 28 | 4 | round counter (incremented by RECALC with END) |
| 32 | 4 | changed cells this round |
| 36 | 4 | formulas evaluated this round |
| 40 | 4 | formulas whose result is an error, this round |
| 44 | 1 | flags: bit 0 the change list overflowed this round, bit 1 this round's changes equal the previous round's |
| 45 | 3 | reserved, 0 |
| 48 | 4 | the row of a malformed row block (with ERR_FORMAT; $FFFFFFFF: the descriptor) |
| 52 | 4 | changed cells in the previous round |
| 56 | 4 | codec: function name table address (section 10) |
| 60 | 1 | codec: decimal separator (ASCII, e.g. `.`) |
| 61 | 1 | codec: argument separator (e.g. `,`, or `;` with a `,` decimal separator) |
| 62 | 2 | reserved, 0 |

### 3.2 Row table

`rows` 32-bit entries at the row table address.  An entry is the address of
that row's row block, or `$FFFFFFFF` for an empty row.  Row blocks are
16-byte aligned, so the CPU can move a row block anywhere by copying it and
updating its entry: everything inside a row block is relative to its start.

### 3.3 Row block

A header granule, then cells, each a whole number of granules.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | row number (checked against the table index) |
| 4 | 2 | block length, granules (header included; at most 4096) |
| 6 | 2 | number of cells |
| 8 | 2 | tree root: granule offset of the root cell (0: no cells) |
| 10 | 2 | first free granule (where the CPU appends a new cell) |
| 12 | 2 | changed cells in the last RECALC that visited the row |
| 14 | 2 | row flags: bit 0 index stale (set by the CPU, cleared by REBALANCE) |

Granule offsets are from the start of the row block, in 16-byte units; a
row block holds up to 4096 granules (64 KB).

### 3.4 Cell

Every cell starts with an 8-byte header:

| Offset | Size | Field |
|---|---|---|
| 0 | 3 | column number (24 bits) |
| 3 | 1 | kind (bits 3-0) and flags (bits 7-4) |
| 4 | 1 | length, granules (1-255: up to 4 KB) |
| 5 | 3 | tree links, 24 bits: bits 11-0 the left child, bits 23-12 the right child (granule offsets, 0: none) |

Kinds:

| Kind | Name | Body after the header |
|---|---|---|
| 0 | EMPTY | format (8): a blank cell that only carries formatting |
| 1 | TEXT | format (8); length (2); the text, ASCII |
| 2 | FORMULA | format (8); result (8); result kind (1), result text capacity (1), bytecode length (2), reserved (4); bytecode; result text |
| 3 | F64 | value (8); format (8) if flag bit 6 |
| 4 | I64 | value (8); format (8) if flag bit 6 |
| 5 | I32 | value (4, sign-extended into 8); format (8) if flag bit 6 |
| 6 | ERROR | error code (8) |
| 7 | UNCOMPILED | format (8); compile error code (1), reserved (1), error position (2), text length (2), reserved (2); the formula's text, ASCII |
| 15 | FREE | nothing: a hole (the CPU left it moving a cell that grew); every walk skips it, and it is never in the tree |

So a plain number with the default format is a single granule, and with its
own format two.

An UNCOMPILED cell holds a formula as typed that has not been compiled (or
failed to compile: the code and the character position are the
codec's, section 10).  SHITE never changes or interprets one: RECALC
skips it, FORMAT_CELLS shows its text, and a formula referring to it gets
#COMPILE!.

Flags (byte 3):

| Bit | Name | Meaning |
|---|---|---|
| 4 | CHANGED | the value changed since this flag was last cleared.  Set by the CPU when it edits a cell, by RECALC when a result changes; cleared by FORMAT_CELLS (if asked) or the CPU |
| 5 | ERROR | the result is an error (a formula's result kind is 6, its result is the code) |
| 6 | HAS_FORMAT | number kinds only: a format follows the value |
| 7 | reserved | 0 |

A formula's result kind is 1 (text: the text is in its result text area,
its length in the first two bytes of the result field), 3, 4, 5 (a number in
the result field) or 6 (an error, the code in the result field).  A result
text longer than the capacity is an error (#VALUE!).

Within a row, cells form a binary search tree by column number through the
child links.  REBALANCE_ROW rebuilds it balanced, as exactly this tree: the
cells sorted by column c[0..n-1], the root c[(0 + n - 1) div 2], and below
each c[m] of a range lo..hi the trees of lo..m-1 (left) and m+1..hi (right),
each by the same rule.  The CPU may also maintain the tree itself.

### 3.5 Format (8 bytes)

| Byte | Field |
|---|---|
| 0 | style (bits 3-0): 0 general, 1 fixed, 2 scientific, 3 percent, 4 integer, 5 text; alignment (bits 5-4): 0 default (numbers right, text left), 1 left, 2 centre, 3 right |
| 1 | decimals shown (0-15) |
| 2 | fixed point: bits 6-0 the point position k, bit 7 binary.  An integer kind's value means v x 10^-k (decimal) or v x 2^-k (binary).  0: an ordinary integer |
| 3 | flags: bit 0 thousands separators, bits 2-1 negatives (0 minus sign, 1 parentheses, 2 minus and colour), bit 3 leading zeros, bit 4 prefix, bit 5 suffix |
| 4 | prefix character (screen code), e.g. a currency sign |
| 5 | suffix character |
| 6 | colour: bits 3-0 normal, bits 7-4 negative (with negatives = 2) |
| 7 | reserved, 0 |

The default format (no format present) is general, default alignment, no
fixed point.

## 4. Values and arithmetic

Value types are I64 (I32 cells widen to it), optionally fixed point; F64;
text; and errors, which propagate as values.  Fixed point is a cell's
format byte 2 (or a FIX in a formula): v x 10^-k (decimal, k <= 18) or
v x 2^-k (binary, k <= 62).  An integer with a fixed point past those
limits (bad data) is #NUM! wherever it is used, as is a result stored into
a cell whose format's fixed point is.

- **Integers**: I64 with I64 gives I64, exactly.  Overflow is #NUM! (no
  silent switch to F64).  Add, subtract and compare first align both to
  the larger k (multiplying by 10^d or 2^d; overflow is #NUM!); multiply
  adds the k's.  Mixed decimal and binary fixed point converts both to F64.
- **F64**: anything with an F64 gives F64.  An integer converts as
  F64(v) / F64(10^k) (decimal: two roundings; F64(10^k) is exact to
  k = 22) or exactly scaled by 2^-k (binary).  IEEE 754 double, round to
  nearest even, except that subnormals are flushed to zero (inputs and
  results, keeping the sign).
- **Divide**: F64, unless both are fixed point with the same decimal k:
  then I64 at that k, (a x 10^k) / b rounded half away from zero.  A zero
  divisor is #DIV/0! (integer or F64).
- **Comparisons** give I64 0 or 1.  Text compares with text, bytewise;
  text with a number is #VALUE!.
- **Storing a formula's result**: an integer result is rescaled to the
  formula cell's own fixed-point format (rounding half away from zero
  when that drops digits; #NUM! on overflow); if the cell has no
  fixed-point format, a result with k > 0 becomes F64.  An F64 NaN or
  infinity is stored as #NUM!.

References and ranges:

- A **reference** pushes its cell's value, marked as coming from a
  reference: an EMPTY cell or no cell is *blank* (kept as its own kind
  until something uses it: arithmetic and comparisons take it as I64 0,
  aggregates skip it), numbers with their format's fixed point, TEXT its
  text, FORMULA its stored result, ERROR its code, UNCOMPILED #COMPILE!.
  A reference outside the sheet is #REF!.  So with A1 empty, `COUNT(A1)`
  is 0 and `AVERAGE(A1)` #DIV/0!, while with A1 = 0 they are 1 and 0.
- A **range** (RECT, section 5) is a rectangle of cells, and a **cell
  list** (CELLS) a list of single cells, used by the aggregate functions.  Within a range, rows are walked in ascending order
  and the cells of a row in ascending column order (an in-order walk of
  the row's tree: trees at most 32 deep, else ERR_FORMAT).
- **Aggregates** (SUM, AVERAGE, MIN, MAX, COUNT; later PRODUCT, COUNTA)
  take their arguments in order.  A range, a cell list, or a value from a
  reference, contributes its numbers and skips text and blank cells; any other value
  must be a number (text is #VALUE!).  An error anywhere is the result (the
  first, in order).  SUM is a left-to-right fold of ADD from I64 0; MIN
  and MAX fold the comparison (no numbers: I64 0); COUNT counts the
  numbers; AVERAGE is SUM / COUNT (no numbers: #DIV/0!).

Errors (codes):

| Code | Error |
|---|---|
| 1 | #DIV/0! |
| 2 | #VALUE! |
| 3 | #REF! (a reference outside the sheet) |
| 4 | #NUM! (overflow, NaN, out of a function's domain) |
| 5 | #CIRC! (set by the CPU, see 7) |
| 6 | #N/A |
| 7 | #STACK! (bad bytecode, stack over- or underflow) |
| 8 | #NAME? (a function this hardware does not have) |
| 9 | #COMPILE! (a reference to an UNCOMPILED cell) |

An operation with an error operand gives that error (the first one, in
evaluation order).

## 5. Formula bytecode

Formulas are compiled to postfix (RPN) bytecode, run on a 32-entry stack:
operands are pushed, and operators and functions take theirs from the top
(a function's argument count is in its CALL).
Each entry is a kind (I64, F64, text, error, blank, range, cell list), a
64-bit payload, a fixed-point byte and a "from a reference" bit.  The stack
depth is a deliberate limit: COMPILE computes a formula's deepest point and
rejects one past 32 with a positioned resource error (long argument lists of
single cells do not count against it: they become one CELLS entry).
Execution starts at the
first byte and ends at END; one value must then be on the stack.

### 5.1 Framing

Every item starts with one byte that says what it is:

| First byte | Item |
|---|---|
| $00-$7F | an opcode, with its operands (5.4) |
| $80-$FF | a short cell reference, 4 bytes (5.3) |

### 5.2 Counts and identifiers

Function identifiers, argument counts and lengths use one or two bytes:

```text
short: [0vvvvvvv]              0..127
long:  [1vvvvvvv][wwwwwwww]    0..32767, value = (first & $7F) | (second << 7)
```

A small value may also be written long (a compiler can reserve two bytes
and fill them in later); decoders accept both.

### 5.3 Cell references

A reference has a row and a column, each either absolute (`$`: a row or
column number) or relative (a signed offset from the formula's own cell,
modulo 2^20 for rows and 2^24 for columns).  References are stored
big-endian, so that the first byte carries the marker.

- **Short form, 4 bytes** (the usual one), first byte $80-$FF:

  ```text
  bit 31      1 (marker)
  bit 30      row absolute
  bits 29-15  row: absolute 0-32767, or relative -16384..16383
  bit 14      column absolute
  bits 13-0   column: absolute 0-16383, or relative -8192..8191
  ```

- **Long form, 7 bytes**: opcode REF, then 48 bits big-endian: bit 47 row
  absolute, bit 46 column absolute, bits 45-44 zero, bits 43-24 row (or
  offset, 20 bits), bits 23-0 column (or offset, 24 bits).  For anything
  the short form cannot hold.

A compiler uses the short form whenever it fits.  `A1`, `$A1`, `A$1` and
`$A$1` are one reference each; a formula copied elsewhere keeps its meaning;
and its text can be rebuilt exactly.

### 5.4 Opcodes

| Opcode | Mnemonic | Operands | Effect |
|---|---|---|---|
| $00 | END | | the formula's result is the stack's one value |
| $01 | I8 | 1 (signed) | push an integer constant |
| $02 | I32 | 4 | push an integer constant |
| $03 | I64 | 8 | push an integer constant |
| $04 | F64 | 8 | push an F64 constant |
| $05 | STR | count, bytes | push a text constant (ASCII) |
| $06 | FIX | 1 | the top (an integer) is fixed point, the byte as a format's byte 2 |
| $07 | REF | 6 | push a cell's value (the long form of 5.3) |
| $08 | RECT | two references | push a range: the rectangle between two cells |
| $09 | HOSTCALL | count, text, 6 | push the result cell's value; the text is the call as written; the 6 bytes are the result cell, always in the long form's payload (5.3, 5.6) |
| $0A | JZ | 2 | pop; if zero, jump forward (5.5) |
| $0B | JMP | 2 | jump forward (5.5) |
| $0C | CALL | function, count | call a function on the top `count` values (5.7) |
| $0D | CELLS | count, references | push a cell list: `count` references (each short or long), one stack entry |
| $10 | ADD | | |
| $11 | SUB | | |
| $12 | MUL | | |
| $13 | DIV | | |
| $14 | POW | | `^` |
| $15 | NEG | | unary minus |
| $16 | PCT | | `%`: divide by 100 |
| $17 | CONCAT | | `&` |
| $18-$1D | EQ NE LT LE GT GE | | comparisons |
| $1E-$7F | | | reserved |

Multi-byte operands are little-endian, except references (5.3).  An
unknown opcode is #STACK!; a known one the hardware does not have yet is
#NAME?.  Constants use the narrowest kind that holds them exactly; a
decimal constant such as `1.25` is I64 125, FIX 2.

### 5.5 IF

`IF(c, t, e)` compiles to jumps, so only the chosen branch runs:

```text
<c>  JZ else  <t>  JMP end  else: <e>  end:
```

JZ's and JMP's operand is a forward offset in bytes from the end of the
instruction.  JZ pops a number (zero, I64 or F64 of either sign, is
false); an error ends the formula with that error, text is #VALUE!.  Each
branch leaves exactly one value.  `IF(c, t)` has `<e>` = I8 0.

Compilers emit only this pattern, so the codec can rebuild `IF` exactly:
the JMP is the last instruction before JZ's target, and its own target
ends the else branch; both jumps are forward and properly nested (IFs may
nest in any of the three parts).  The evaluator itself just follows the
jumps; no other control flow is promised a formula text.

### 5.6 Host calls

A function SHITE does not do in hardware (or a sheet-level helper) is a
HOSTCALL: the call's text as the user wrote it (so it can be shown and
edited again, without keeping the formula's source elsewhere) and a result
cell, an ordinary cell the CPU keeps up to date.  Execution skips the text
and pushes the result cell's value, as a reference would.

The result cell is always the 6-byte long-form payload (no REF opcode), so
it can be rebound to any cell in place: nothing after it moves, and no
jump changes.  A formula must not run (RECALC) until its host calls are
bound.

The CPU owns everything about host calls: which cells they depend on, when
to recompute them, and where result cells live (for example hidden rows).
It updates result cells only between rounds (after END, before the next
BEGIN), setting CHANGED on those it changes; RECALC's counts and lists do
not include them (section 7).

### 5.7 Functions

CALL takes a function identifier and an argument count (both 5.2): the
arguments are the top `count` stack entries, the first deepest.  The
identifiers:

| Id | Function | Id | Function | Id | Function |
|---|---|---|---|---|---|
| 0 | SUM | 10 | ROUND | 20 | LOG10 |
| 1 | AVERAGE | 11 | SIGN | 21 | SIN |
| 2 | MIN | 12 | SQRT | 22 | COS |
| 3 | MAX | 13 | MOD | 23 | TAN |
| 4 | COUNT | 14 | AND | 24 | ASIN |
| 5 | COUNTA | 15 | OR | 25 | ACOS |
| 6 | PRODUCT | 16 | NOT | 26 | ATAN |
| 7 | ABS | 17 | IF (name only: compiled to jumps) | 27 | ATAN2 |
| 8 | INT | 18 | EXP | 28 | PI |
| 9 | TRUNC | 19 | LN | 29 | POWER |

30-39 text: LEN, LEFT, RIGHT, MID, UPPER, LOWER, TRIM, VALUE, TEXT,
CONCATENATE.  40-49 lookup and conditional aggregates: SUMIF, COUNTIF,
VLOOKUP, HLOOKUP, MATCH, INDEX.  The rest of 0-32767 is free: new hardware
functions, and names the codec maps to host calls.

## 6. Instructions

SSNAIL opcodes $40-$45: the usual 16-byte instruction (opcode, a, b, c,
X, Y, Z).  X is the sheet descriptor (or a parameter block); results go to
memory, and to SSNAIL registers where shown.  A malformed descriptor or row
block ends the job with SSNAIL error ERR_FORMAT, the row in the descriptor.

| Opcode | Instruction | Operands | Register results |
|---|---|---|---|
| $40 | RECALC | X descriptor, R[a] first row, R[b] last row, R[c bits 3-0] first column, R[c bits 7-4] last column, Z flags (bit 0 BEGIN, bit 1 END) | R[a] = cells changed by this call |
| $41 | REBALANCE_ROW | X descriptor, R[a] first row, R[b] last row | |
| $42 | FIND_CELL | X descriptor, R[a] row, R[b] column | R[a] = cell address, or 0 |
| $43 | FORMAT_CELLS | X parameter block | |
| $44 | COMPILE | X parameter block (section 10) | R[a] = bytecode length, or 0 |
| $45 | DECOMPILE | X parameter block (section 10) | R[a] = text length, or 0 |

### RECALC

Evaluates every FORMULA cell in the rows and columns given: rows ascending,
and within a row in the order the cells lie in its row block, each with the
values as they are at that moment (results computed earlier in the call
are seen by later cells).  If a result differs from the stored one (kind,
then bits: an F64 bit for bit, text bytewise), SHITE stores it, sets the
cell's CHANGED flag (and ERROR as the result is an error or not), counts
it, and appends `(row, col)` (4 + 4 bytes) to the change list.  Past the
list's capacity the count stays exact and the overflow flag is set.  Each
row visited gets its row header's changed count from this call.

A round can be one call or several (a whole sheet, or a region at a time):

- **BEGIN** zeroes this round's counts and flags.
- **END** compares this round's change list with the previous round's (the
  same count, neither overflowed, the same entries) and sets flag bit 1,
  increments the round counter, keeps this round's count as the previous
  one, and swaps the two list addresses, so the next round writes over the
  older list.

Rows and columns beyond the sheet's are ignored, so a whole-sheet round is
one RECALC with both flags and every register $FFFFFFFF but the firsts.

### REBALANCE_ROW

Parameters: the sheet descriptor, first and last row.

For each row with a block: walks the block's cells in memory order (by
their lengths, from granule 1 to the first free granule), checks each
length, rejects duplicate columns (status: error, with the row), then
rewrites the child links as a balanced binary search tree by column, and
the root, and clears the row's "index stale" flag.

### FIND_CELL

The cell's address, or 0.  (For convenience: the tree walk is cheap for the
CPU too.)

### FORMAT_CELLS

Parameters (a block of 32 bytes): the sheet descriptor, first and last row,
first and last column, the column width list (one byte per column, 0 hides
a column), the destination address and stride (bytes per screen line), the
character size (1: screen codes; 2: 16-bit characters with attributes), an
optional colour destination and stride, and flags: bit 0 only cells with
CHANGED (others are left untouched in the destination), bit 1 clear
CHANGED on the cells rendered, bit 2 upper case character set.

Each cell is rendered into its column's width: numbers by their format (the
fixed-point k, decimals with rounding half away from zero, separators,
sign style, prefix and suffix; general: as many significant digits as fit,
switching to scientific; `###` if it still does not fit), text clipped or
by alignment, errors as their names, empty and missing cells as spaces.
Text is stored as ASCII and written as screen codes.

The destination is in attic RAM: the VIC-IV shows screens from chip RAM,
so the CPU copies the rendered area there with DMA (cheap: an attic to
chip RAM block copy).

## 7. Recalculation and cycles

The CPU (or a SSNAIL program: RECALC leaves the count in R[a], so BNE
loops) runs rounds until one changes nothing.  With row-major order a
sheet whose formulas only refer upwards and leftwards settles in one round;
others in a few more.

- If cells are still changing after as many rounds as the longest
  dependency chain could need (at most the number of formulas), the cells
  in the change list are on, or depend on, a cycle.  The CPU marks them
  #CIRC! (or, by the user's choice, keeps iterating: spreadsheet
  "iterative calculation", stopping when changes fall below a threshold).
- "Same as the previous round" with a non-empty list is a strong early
  sign of a cycle (an oscillation).
- A cycle that is stable (`A1 = B1`, `B1 = A1`) never changes, so rounds
  cannot see it.  If that matters, a later instruction can do an exact
  check by evaluating on demand with in-progress marks.
- Host calls (5.6): the CPU recomputes their result cells between rounds
  when their inputs changed, setting CHANGED, so the next round sees them.
  Convergence is then a round with no changes **and** no result cell
  updated by the CPU since that round's BEGIN (and none waiting to be
  computed): the driver counts its own updates, as RECALC's count and lists
  hold only the formulas it recomputed.

## 8. Registers

SSNAIL's (`$FFD7500-$FFD751F`).  Its capability register ($02): bit 0
HyperRAM, bit 1 SDRAM, bit 2 the LLM / vector units, bit 3 SHITE.  Jobs, status, errors, stop requests and the
interrupt are SSNAIL's.

## 9. Hardware outline (area first)

- **Sequencer**: one state machine, like SSNAIL's units, issuing LUMP
  reads and writes and driving the datapaths below.
- **Arithmetic**: an iterative F64 unit (add, multiply, divide, square
  root, conversions), a 64-bit integer unit (add, compare, multiply through
  DSPs over several cycles, divide by the same iterative divider), and a
  CORDIC unit (shift and add: SIN, COS, TAN, ATAN, ASIN, ACOS; EXP and LN in
  hyperbolic mode), which is small and precise enough for F64.  SSNAIL's
  FPU is F32 and pipelined for streaming; SHITE has its own small F64 unit
  rather than sharing SSNAIL's (simpler, and the same in a SHITE-only build).
- **Formatter**: the integer divider (by 10) or double-dabble for digits,
  then a small character emitter.
- **Memory**: a segment cache of 8 lines of 256 bytes (2 KB of block RAM,
  address-tagged: cells are variable length, so it caches row block
  segments), a 64-entry (row, column) -> address cache in LUT RAM for
  references, the 32-entry evaluation stack, and a 256-byte text scratch.

## 10. Formula codec (COMPILE, DECOMPILE)

A hardware unit (a serial scanner and shunting-yard parser, RAM-backed
stacks, a serial table reader and text writer) converting between formula
text and bytecode, so the CPU never keeps the source of a compiled formula.
It uses SHITE's arithmetic for numbers.  Parameter blocks (16-byte
aligned):

| COMPILE | |
|---|---|
| 0 | the sheet descriptor (name table, separators) |
| 4 | the source text (ASCII, without the `=`) |
| 8 | its length (2), the output's capacity (2) |
| 12 | the formula cell's row (4) |
| 16 | the formula cell's column (4) |
| 20 | the output buffer (bytecode) |
| 24 | result: bytecode length (2), error code (1), host calls made (1) |
| 28 | result: error position in the text (2), reserved (2) |

DECOMPILE's block is the same with the roles swapped: input bytecode and
its length, output text and its capacity, the text's length as the result.
Errors (code, position) are the codec's to define, with 0 for none; a
failed compile leaves the CPU to store the text as an UNCOMPILED cell
(3.4).

- **Canonical text**: DECOMPILE may fully parenthesise
  (`=A1*(B2+3)` gives `=(A1*(B2+3))`) and need not keep spacing, case or
  redundant grouping.
- **The round trip**: compiling DECOMPILE's text again (with the same
  formula cell and codec settings) gives bytecode with the same meaning:
  the same structure, evaluation order, value kinds and fixed points, `$`
  locks, function identities, IFs (5.5) and host-call texts.  For
  COMPILE's own (canonical) output it gives the same bytes, except that
  host calls come back unbound (the placeholder result cell, for the CPU
  to bind again).  Canonical bytecode: references in the short form when
  they fit, counts and identifiers in their short form when they fit,
  integer constants as the narrowest of I8, I32, I64, and runs of plain
  cell arguments to an aggregate as one CELLS.  Other accepted streams (a
  long count where a short one fits, say) round-trip by meaning only.
- **Numbers**: a decimal with no exponent is an integer, or fixed point
  when it has a fraction (`1.25` is I64 125, FIX 2: at most 18 decimals);
  with an exponent it is F64 (`1.25E0`, `1E-3`).  DECOMPILE prints integers
  and fixed point that way (keeping trailing zeros: `1.50` is k = 2), and F64
  constants always with an exponent, as the shortest digits that read back
  to the same bits (`-0E0` for negative zero).
- **Function names**: a table in attic RAM, `[identifier (5.2)][name, NUL]`
  repeated, ending with an empty name; the first entry for an identifier is
  its canonical spelling, later ones aliases.  So English and German (or any
  renaming) are just tables: one at a time, the descriptor's, so changing
  the language is pointing it at another table.  Names match regardless
  of case; an unknown
  name is a compile error.
- **Host functions**: identifiers 16384-32767 in the table are the CPU's.
  A call to one compiles to a HOSTCALL (5.6) holding the call's text and,
  as its result cell, the placeholder absolute row 2^20 - 1, column
  2^24 - 1; COMPILE returns how many it made (block byte 27).  The CPU
  then binds each to its result cell, rewriting the 6-byte slot in place
  (it finds them by walking the bytecode by 5.1-5.4).
- **Separators**: the descriptor's decimal and argument separators.
- **Limits**: nesting and stack depths, and the output bounds, are the
  codec's to state; exceeding them is a compile error with its position.

## 11. Testing

As SSNAIL: a Python reference model (`SSNAIL/shite.py`, run by the
emulator for SSNAIL's opcodes $40-$45) that defines the results exactly,
and GHDL benches that run the same sheets on the hardware and compare
memory (`tb_shite_step1`: REBALANCE_ROW and FIND_CELL).

## 12. Phases

1. **Done**: the build structure, REBALANCE_ROW, FIND_CELL.
2. **RECALC core**: I64 (with fixed point) and F64, constants, references
   (both forms), RECT, ADD SUB MUL DIV NEG, the comparisons, HOSTCALL,
   CALL with SUM, AVERAGE, MIN, MAX and COUNT, the errors.
3. **FORMAT_CELLS** (the number formats).
4. **More**: POW, PCT, IF (JZ / JMP), MOD, AND / OR / NOT, ABS, INT,
   TRUNC, ROUND, SIGN, SQRT, PRODUCT, COUNTA.
5. **Transcendentals** (the CORDIC unit) and **text** (STR, CONCAT, the
   text functions).
6. **The codec** (section 10), in parallel.

A function the hardware does not have yet is #NAME? (a sheet still
recalculates, with that cell an error).

## 13. Open questions

- Text: ASCII in cells (as above), or PETSCII?
- Named ranges, cross-sheet references: not in this version.
- An exact stable-cycle check (section 7).
