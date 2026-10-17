# SHITE: Spreadsheet Hardware Integrated Technology Engine

A spreadsheet recalculation and rendering engine for the MEGA65, beside
SSNAIL on the attic RAM (HyperRAM / SDRAM) through LUMP.  The 45GS02 owns
the user interface, formula parsing and editing; SHITE evaluates formulas,
detects what changed, maintains the per-row cell index and renders cells as
screen text.

Status: specification, draft 1.  Nothing here is implemented yet.

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

Every command names a sheet descriptor; it holds the sheet's geometry and
where results go.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `"SHT1"` |
| 4 | 4 | row table address |
| 8 | 2 | number of rows (1-32768) |
| 10 | 2 | number of columns (1-32768) |
| 12 | 4 | change list address (16-byte aligned) |
| 16 | 2 | change list capacity (entries) |
| 18 | 2 | reserved, 0 |
| 20 | 4 | previous change list address (0: none) |
| 24 | 4 | round counter (SHITE increments it each RECALC) |
| 28 | 4 | changed cells in the last round |
| 32 | 4 | formulas evaluated in the last round |
| 36 | 4 | errors produced in the last round |
| 40 | 1 | result flags: bit 0 change list overflowed, bit 1 changed set equal to the previous round's |
| 41 | 1 | reserved, 0 |
| 42 | 2 | the row of a malformed row block (with ERR_FORMAT) |
| 44 | 20 | reserved, 0 |

### 3.2 Row table

`rows` 32-bit entries at the row table address.  An entry is the address of
that row's row block, or `$FFFFFFFF` for an empty row.  Row blocks are
16-byte aligned, so the CPU can move a row block anywhere by copying it and
updating its entry: everything inside a row block is relative to its start.

### 3.3 Row block

A header granule, then cells, each a whole number of granules.

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | row number (checked against the table index) |
| 2 | 2 | block length, granules (header included) |
| 4 | 2 | number of cells |
| 6 | 2 | tree root: granule offset of the root cell (0: no cells) |
| 8 | 2 | first free granule (where the CPU appends a new cell) |
| 10 | 2 | changed cells in the last RECALC |
| 12 | 2 | row flags: bit 0 index stale (set by the CPU, cleared by REBALANCE) |
| 14 | 2 | reserved, 0 |

Granule offsets are from the start of the row block, in 16-byte units, so a
row block holds up to 1 MB.

### 3.4 Cell

Every cell starts with an 8-byte header:

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | column number |
| 2 | 1 | kind (bits 3-0) and flags (bits 7-4) |
| 3 | 1 | length, granules (1-255: up to 4 KB) |
| 4 | 2 | left child: granule offset (0: none) |
| 6 | 2 | right child: granule offset (0: none) |

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
translator's, section 12).  SHITE never changes or interprets one: RECALC
skips it, FORMAT_CELLS shows its text, and a formula referring to it gets
#COMPILE!.

Flags:

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

Value types are I32, I64 (each optionally fixed point, from the cell's
format), F64 and text; errors propagate as values.

- Integer with integer: I64, exactly.  Overflow is #NUM! (no silent switch
  to F64).  Fixed-point operands are aligned to the larger k first (add,
  subtract, compare); multiply adds the k's; the result keeps the cell's
  own format's k if the formula's cell has one (rounded half away from
  zero), else the arithmetic's k.
- Anything with F64: F64.  Fixed-point integers convert exactly where they
  can (to 2^53).
- Divide: F64, unless both operands are fixed point with the same decimal
  k, then I64 at that k, rounded half away from zero.
- Comparisons give I64 0 or 1.  Text compares with text, bytewise; text
  with a number is #VALUE!.
- F64 follows IEEE 754 double, round to nearest even, except that
  subnormals are flushed to zero (inputs and results, keeping the sign);
  NaN and infinities become #NUM! when stored.

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
| 8 | #NAME? (an unknown function) |
| 9 | #COMPILE! (a reference to an UNCOMPILED cell) |

An operation with an error operand gives that error (the first one, in
evaluation order).  A reference to an EMPTY cell, or a missing one, is I64
0; to a TEXT cell, its text.

## 5. Formula bytecode

The CPU compiles formulas to postfix bytecode, evaluated on a 32-entry
stack (each entry a 64-bit value and a kind).  One byte of opcode, then
immediates, little-endian.

| Opcode | Mnemonic | Immediates | Effect |
|---|---|---|---|
| $00 | END | | the top of the stack is the result |
| $01 | I32 | 4 | push a constant |
| $02 | I64 | 8 | push a constant |
| $03 | F64 | 8 | push a constant |
| $04 | STR | 1 length, bytes | push a text constant |
| $05 | FIX | 1 k | the top (an integer) is fixed point k (the k byte as in a format) |
| $08 | REF | 2 row, 2 col | push a cell's value |
| $0A | RANGE | 2 r1, 2 c1, 2 r2, 2 c2, 1 function | aggregate over a rectangle |
| $10-$17 | ADD SUB MUL DIV POW MOD NEG PCT | | arithmetic (PCT: divide by 100) |
| $18-$1D | EQ NE LT LE GT GE | | comparisons |
| $1E-$20 | AND OR NOT | | logic (non-zero is true) |
| $21 | JZ | 2 | pop; jump (relative) if zero: lazy IF |
| $22 | JMP | 2 | jump (relative) |
| $28-$2F | ABS INT TRUNC ROUND SQRT SIGN MIN2 MAX2 | | (ROUND: value, decimals) |
| $30-$3B | EXP LN LOG10 SIN COS TAN ASIN ACOS ATAN ATAN2 PI POW10 | | transcendentals, F64 |
| $40-$48 | CONCAT LEN LEFT RIGHT MID UPPER LOWER TRIM VALUE | | text |
| $49 | TEXT | 8 format | number to text, as the formatter |

Each reference row and column is 16 bits: bit 15 set means absolute (the
`$`), and bits 14-0 are then the row or column number; clear means
relative, and bits 14-0 are a signed offset from the formula's own cell,
modulo 32768.  So `A1`, `$A1`, `A$1` and `$A$1` are all one opcode, a
formula copied elsewhere keeps its meaning, and its text can be rebuilt
exactly (section 12).  Rows and columns are 0 to 32767.

RANGE functions: 0 SUM, 1 AVERAGE, 2 MIN, 3 MAX, 4 COUNT (numbers), 5 COUNTA
(non-empty), 6 PRODUCT.  SUMIF and COUNTIF may follow (a criterion from the
stack).  Ranges are walked row by row, and in column order within a row
(an in-order walk of each row's tree from the range's first column).

## 6. Instructions

SSNAIL opcodes $40-$43 (the usual 16-byte instruction: a, b, X, Y, Z).  X
is the sheet descriptor (or FORMAT_CELLS's parameter block); results go to
memory, and to SSNAIL registers where shown.  A malformed descriptor or row
block ends the job with SSNAIL error ERR_FORMAT, the faulting row in the
descriptor.

| Opcode | Instruction | Operands | Register results |
|---|---|---|---|
| $40 | RECALC | X descriptor | R[a] = cells changed |
| $41 | REBALANCE_ROW | X descriptor, R[a] first row, R[b] last row | |
| $42 | FIND_CELL | X descriptor, R[a] row, R[b] column | R[a] = cell address, or 0 |
| $43 | FORMAT_CELLS | X parameter block | |

### RECALC (one round)

Parameters: the sheet descriptor.

Visits every FORMULA cell, row by row (rows ascending) and within a row in
the order the cells lie in its row block, and evaluates it with the values as they are at that moment
(newly computed results are seen by later cells in the same round).  If the
result differs from the stored one (kind, then bits: an F64 bit-for-bit,
text bytewise), SHITE stores it, sets the cell's CHANGED flag, counts it in
its row block and the descriptor, and appends `(row, col)` (2 + 2 bytes) to
the change list.  If more cells change than the list holds, the count is
still exact and the overflow flag is set.

At the end, if a previous change list is given, SHITE compares the two
lists and sets the "same as the previous round" flag.

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

The CPU calls RECALC until a round changes nothing.  With row-major order a
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
  cannot see it.  If that matters, a later command can do an exact check
  by evaluating on demand with in-progress marks (it is not in draft 1).

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

## 10. Testing

As SSNAIL: a Python reference model (`shite_sim.py`) that defines the
results exactly, a small formula compiler for tests, and GHDL benches that
run the same sheets on the hardware model and compare memory.

## 11. Phases

Draft 1's hardware does the simple, common part first; the bytecode and
formats leave room for the rest.

1. **Core**: I64 / I32 (with fixed point) and F64 numbers, text cells,
   constants, REF, ADD SUB MUL DIV NEG, the comparisons, RANGE with SUM,
   MIN, MAX, COUNT and AVERAGE, the errors; RECALC, REBALANCE_ROW,
   FORMAT_CELLS (all the number formats); FIND_CELL.
2. **More functions**: POW, MOD, PCT, AND / OR / NOT, JZ / JMP (IF), ABS,
   INT, TRUNC, ROUND, SIGN, SQRT, MIN2 / MAX2, PRODUCT and COUNTA.
3. **Transcendentals**: the CORDIC unit and EXP to POW10.
4. **Text functions**: CONCAT to TEXT.

An opcode the hardware does not have yet gives #NAME? (so a sheet still
recalculates, with that cell an error).

## 12. Formula translator (planned, not in draft 1)

The CPU needs to turn what the user types into bytecode, and bytecode back
into text for the edit line.  Both directions share one table of functions
(names, opcodes, argument counts) and one of operators (precedence,
associativity):

- **Compile**: ASCII formula (`=SUM(A1:A9)*$B$2+-3.5%`) to bytecode, by
  shunting-yard (operator precedence) with function calls and ranges;
  references relative to the formula's own cell, absolute where `$` says;
  IF to JZ / JMP; constants as the narrowest exact kind (I32, I64, F64);
  errors with a position for the edit line.
- **Decompile**: bytecode back to ASCII, adding parentheses only where
  precedence needs them, references rebuilt from the flags (so `$A1` stays
  `$A1`), numbers in their shortest exact form.  Compile then decompile
  gives the formula back with canonical spacing and capitals.
- **Where**: a C version for the MEGA65 client and a Python version for
  the tools and tests (it also writes the test sheets).  A later SHITE
  command could do either direction in hardware, since the bytecode
  machine and the formatter are already there.
- **Tests**: round trips over a corpus of formulas, and compile, run on the
  reference model, compare with a host spreadsheet's results.

## 13. Open questions

- I64 overflow: #NUM! (as above), or promote to F64?
- Text: ASCII in cells (as above), or PETSCII?
- Lazy IF via JZ / JMP (as above), or a strict IF opcode?
- Do formulas need names (named ranges) or cross-sheet references in this
  version?
- SUMIF / COUNTIF / VLOOKUP: draft 2?
