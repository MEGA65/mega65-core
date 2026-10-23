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
Implemented so far (section 12): the build structure (section 1),
REBALANCE_ROW, FIND_CELL, RECALC (all but the transcendental, text and
lookup functions), MOVE_CELLS and CELLS_MOVED, and through the codec units
FORMAT_CELLS, COMPILE, DECOMPILE, RENDER and PARSE (the number literal); in
hardware, and $40-$42, $48 and $49 in the reference model
`SSNAIL/shite.py`.  Planned: the sheet table's references (3.6, 10).

Design goals, in order: correct and deterministic results; small area
(iterative units, shared datapaths: several million simple cell updates per
second is plenty); a memory format the CPU can edit cheaply through the
ordinary attic RAM interface.

## 1. Build options and dispatch

SHITE is one of the LUMP clients of the command dispatcher (historically
SSNAIL's shell, `ssnail.vhdl`): its registers at `$FFD7500`, job control,
instruction fetch and decode, the scalar and control instructions, COPY and
SYNC.  The dispatcher hands each instruction to the unit that owns its
opcode: SHITE ($40-$4F), the vector units, SSNAIL's language model units.
So SHITE has no registers of its own, and a job can run a whole
recalculation loop on its own (RECALC leaves the changed count in a
register: BNE back while it is not zero).

While SHITE runs an instruction the dispatcher and its other units are
idle, so SHITE's memory accesses go through the dispatcher's LUMP ports by
a plain multiplexer: there is no arbitration.

Generics on `ssnail_top` (set from `iomapper.vhdl`) choose the units:
`has_llm` (SSNAIL's LLM units), `has_vec` (only the vector element ops,
for 3D: VADD VMUL VSUB CVT16 VRECIP VCVTI16 VMAX VMIN VPROJ16; `has_llm`
includes them) and `has_shite`.  With none of them SSNAIL is its shell;
an opcode whose unit is not built reports ERR_OPCODE, and the unit's logic
is not synthesised at all.

SHITE runs on the CPU's 40.5 MHz clock, a quarter of clock162 from the same
MMCM (`shite_bridge` is its clock162 side: SSNAIL's
coprocessor port and the LUMP commands, crossing by toggles).

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
| 48 | 4 | the row of a malformed row block (with ERR_FORMAT; with a wrong magic nothing is written: the memory may not be a descriptor) |
| 52 | 4 | changed cells in the previous round |
| 56 | 4 | codec: function name table address (section 10) |
| 60 | 1 | codec: decimal separator (ASCII, e.g. `.`) |
| 61 | 1 | codec: argument separator (e.g. `,`, or `;` with a `,` decimal separator) |
| 62 | 2 | reserved, 0 |
| 64 | 4 | sheet table address (3.6; 0: none, the whole physical sheet is one sheet) |
| 68 | 2 | number of sheets in the table |
| 70 | 58 | reserved, 0 |

The descriptor is 128 bytes, 16-byte aligned.  (The execution unit reads
only bytes 0-63; bytes 64 on are the codec's and MOVE_CELLS'.)

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

### 3.6 Sheet table (multiple sheets on one physical sheet)

SHITE has one physical sheet (2^20 rows by 2^24 columns).  A program can
give the user several sheets in two ways:

- **Separate physical sheets**: a descriptor (and row table) per sheet in
  attic RAM.  Each is complete and independent, but a formula can only
  refer to cells of its own.
- **Regions of one physical sheet**: each of the user's sheets is a
  rectangle of the physical sheet, named in the sheet table.  Formulas can
  then refer across sheets (`Costs!B3`), and one RECALC round covers them
  all.

The table: `sheets` entries of 32 bytes, 16-byte aligned:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | first row (physical) |
| 4 | 4 | first column (physical) |
| 8 | 4 | last row (inclusive) |
| 12 | 4 | last column (inclusive) |
| 16 | 4 | the name's address (ASCII) |
| 20 | 1 | the name's length (1-31) |
| 21 | 1 | flags: bit 0 hidden (for the program; SHITE ignores it) |
| 22 | 10 | reserved, 0 |

Rectangles must not overlap; names differ regardless of case.  Bytecode
always holds physical references (5.3): the table only changes how
formula text is read and written (section 10, sheet references).  A
sheet's own cell `A1` is its first row and column.

RECALC, FORMAT_CELLS and the rest know nothing of sheets: they work on
physical rows and columns.  So nothing stops a relative reference that
is copied far enough from reaching into another sheet's rectangle; COMPILE
checks references against the sheets when it compiles; MOVE_CELLS and
CELLS_MOVED move physical cells, the sheets unknown to them (6).

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

A **deleted reference** (to a cell that no longer exists, such as one
overwritten by MOVE_CELLS) is relative with both fields at their minimum:
row -16384, column -8192 in the short form, or row -2^19, column -2^23 in
the long one.  It is #REF! when evaluated, and `#REF!` in formula text.
COMPILE never produces it for a real cell (such an offset uses the other
form).  It keeps the reference's size, so it can be written in place.

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

What they do (a range or cell-list argument to a function that is not an
aggregate is #VALUE!; a wrong argument count for a fixed one, too):

| Function | Arguments | Result |
|---|---|---|
| SUM, AVERAGE, MIN, MAX, COUNT | any | section 4 |
| PRODUCT | any | a left-to-right fold of MUL from I64 1; no numbers: I64 0 |
| COUNTA | any | how many values are not blank (text and errors count) |
| AND, OR | any | as the aggregates (text and blanks from cells skipped), each number true when not zero; I64 1 or 0; no numbers: #VALUE! |
| NOT | 1 | I64 1 if the value is zero (blank: zero), else 0 |
| ABS | 1 | the magnitude, keeping the fixed point (I64 -2^63: #NUM!) |
| SIGN | 1 | I64 -1, 0 or 1 (F64 NaN: #NUM!) |
| INT | 1 | rounded down: an integer to I64 (fixed point dropped); F64 to F64 (a zero result keeps its sign, as IEEE floor) |
| TRUNC | 1 | rounded toward zero, likewise |
| MOD | 2 | a - b x floor(a / b) (the divisor's sign): integers aligned as for ADD, exactly; else F64, as q = floor(F64(a / b)), then F64(a - F64(b x q)); b zero: #DIV/0! |
| `%` (PCT) | 1 | / 100: an integer gets two more decimals of fixed point (decimal, up to k = 18); else F64(x / 100) |
| `^` (POW), POWER | 2 | b must be an integer (I64, no fixed point; else #NAME? until the transcendentals); 0^0 #NUM!, 0^(b < 0) #DIV/0!.  An integer a with b >= 0: exactly, the fixed point times b (past its limit: F64), overflow #NUM!.  Else F64, square and multiply from b's lowest bit (r = 1; for each bit: r = r x x if set; x = x x x if bits remain), then 1 / r for b < 0 (1 / +-0: +-infinity) |
| ROUND | 2 | x to n decimals, half away from zero, from x's exact value; n an integer -18..18 (else #NUM!).  An integer or decimal fixed point: exactly (n >= k: unchanged; n >= 0: k = n; n < 0: k = 0).  F64: n >= 0: N = \|x\| x 10^n rounded to an integer, then F64(N) / F64(10^n) (correctly rounded), with x's sign; x itself if it is integral or \|x\| x 10^n >= 2^53 (then within an ulp anyway).  n < 0: \|x\|'s integer part rounded at 10^-n (the fraction cannot change that), times 10^-n, to F64, with x's sign; x itself if \|x\| >= 2^63 |
| SQRT | 1 | F64, correctly rounded; negative #NUM! (-0: -0) |

JZ's test (5.5) is NOT's: zero (I64, F64 of either sign, blank) is false.
F64 NaN is true.  The transcendentals follow.

30-39 text: LEN, LEFT, RIGHT, MID, UPPER, LOWER, TRIM, VALUE, TEXT,
CONCATENATE.  40-49 lookup and conditional aggregates: SUMIF, COUNTIF,
VLOOKUP, HLOOKUP, MATCH, INDEX.  The rest of 0-32767 is free: new hardware
functions, and names the codec maps to host calls.

## 6. Instructions

SSNAIL opcodes $40-$47: the usual 16-byte instruction (opcode, a, b, c,
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
| $46 | RENDER | X parameter block (section 10) | R[a] bits 3-0: the colour chosen (normal or negative), bits 15-8: the renderer's error (0: none) |
| $47 | PARSE | X parameter block (section 10) | R[a] = the kind found (0: not a number) |
| $48 | MOVE_CELLS | X parameter block | R[a] = cells moved |
| $49 | CELLS_MOVED | X parameter block | R[a] = formulas changed |

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

Renders a rectangle of cells as screen text.  Parameter block (48 bytes,
16-byte aligned):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | the sheet descriptor |
| 4 | 4 | first row |
| 8 | 4 | last row |
| 12 | 4 | first column |
| 16 | 4 | last column |
| 20 | 4 | column widths: one byte per column, from the first (0: the column is hidden) |
| 24 | 4 | destination |
| 28 | 2 | destination stride (bytes per screen line) |
| 30 | 1 | character size: 1 (screen codes) or 2 (16-bit characters: the screen code, then 0) |
| 31 | 1 | flags: bit 0 only cells with CHANGED; bit 1 clear CHANGED on the cells rendered; bit 2 the upper-case character set |
| 32 | 4 | colour destination (0: none): one byte per character, the colour |
| 36 | 2 | colour stride |
| 38 | 1 | default colour (cells without a format, and blank fields) |
| 39 | 1 | reserved, 0 |
| 40 | 4 | scratch: 1 KB of attic RAM (RENDER's 512 bytes, then a field for 16-bit characters) |
| 44 | 4 | reserved, 0 |

Row r is screen line r - first row; within a line the columns follow one
another, each its width.  Every field is exactly its width: the rendered
text aligned and padded with spaces.  With flag bit 0, the fields of cells
without CHANGED (and of missing cells) are left as they are.

The destination is in attic RAM: the VIC-IV shows screens from chip RAM,
so the CPU copies the rendered area there with DMA (an attic to chip RAM
block copy).

**What a cell shows** (then aligned, and clipped to the width):

| Cell | Shows | Default alignment | Too wide |
|---|---|---|---|
| none, EMPTY | spaces | | |
| TEXT, UNCOMPILED | its text | left | its first `width` characters |
| ERROR, or a formula's error | the error's name (`#DIV/0!` ... `#COMPILE!`, section 4) | centre | its first `width` characters |
| a number, or a formula's number | by its format (below) | right | `width` `#`s |

The format's alignment (byte 0 bits 5-4) overrides the default; centring
puts an odd space on the right.

**Numbers.**  The style (format byte 0 bits 3-0), d = format byte 1 (0-15):

| Style | Shows |
|---|---|
| 0 general | an integer: its digits; decimal fixed point k: k decimals; F64 and binary fixed point: the general rule below |
| 1 fixed | d decimals |
| 2 scientific | a mantissa with d decimals, `E`, a sign, the exponent in at least 2 digits (`1.50E+03`) |
| 3 percent | the value x 100 with d decimals, then `%` |
| 4 integer | no decimals |
| 5 text | as general, aligned left by default |

Format byte 3 adds: bit 0 thousands separators every three integer digits;
bits 2-1 negatives: 0 a minus sign, 1 parentheses, 2 a minus sign and the
negative colour (byte 6 bits 7-4); bit 3 leading zeros (the integer part
padded with zeros to the width); bit 4 the prefix character (byte 4)
after the sign; bit 5 the suffix character (byte 5) at the end.  The
decimal point is the descriptor's decimal separator (`.` if 0); the
thousands separator is `,`, or `.` when the decimal separator is `,`.

**Digits, exactly.**  Every number is rounded from its exact value (an
F64 is exactly m x 2^E), half away from zero; never through a rounded F64
step.  A value rounded to d decimals is an integer N, and the text is N's
digits with the point d from the right (`0.05`, not `.05`).  Percent
multiplies by 100 first, exactly.  Scientific: E with 10^E <= |x| < 10^(E+1),
the mantissa rounded to d decimals (a carry to 10 makes it 1 and E + 1).
So a stored F64 2.675 (really 2.67499999...) shows `2.67` with two
decimals, as ROUND gives; a typed 2.675 is fixed point and shows `2.68`.

**General.**  Zero is `0`.  Integers and decimal fixed point show all
their digits (fixed point: its k decimals) if they fit.  Otherwise, and
for F64 and binary fixed point: the most significant digits that fit the
width (at most 15 for F64), each try rounded from the exact value: an
ordinary decimal if one fits, else scientific (`E`, sign, at least two
exponent digits), redundant fractional zeros dropped; `#`s if nothing
fits.  Style 5 (text) is general, aligned left by default.

Format byte 3 bit 3 (leading zeros) is reserved in this version: no
effect.  The prefix and suffix characters (bytes 4, 5) are screen codes.

**Characters.**  Text is ASCII and written as screen codes: `@` 0, `A`-`Z`
65-90 and `a`-`z` 1-26 (with flag bit 2, the upper-case set: both 1-26),
`[` 27, `]` 29, `^` 30, space to `?` (32-63) unchanged, `_` 100, `|` 93,
`` ` `` 39, `{` 27, `}` 29, `~` 30, `\` 77, anything else `?` (63).

**Colour** (with a colour destination): each character of a number's
field takes the format's colour (byte 6 bits 3-0; bits 7-4 for a negative
with negatives = 2), everything else the default colour.

**Implementation (recommended split).**  Number-to-text belongs with the
codec (section 10): DECOMPILE prints numbers too, with the same digit
generator and text writer, and both use SHITE's shared F64 unit.  So the
codec unit provides RENDER (a value into a field); and the execution unit
implements FORMAT_CELLS itself, walking the rectangle (as RECALC's ranges do), taking
each cell's value and format, calling that operation, and handling CHANGED
and the colours.  20 000 to 200 000 cells a second is plenty.

### MOVE_CELLS and CELLS_MOVED

Moving a rectangle of cells, as a spreadsheet's cut and paste, or inserting
or deleting rows or columns: the cells go to the new place, and the
references to them follow them.

- **MOVE_CELLS** moves the cells of the source rectangle S so that its top
  left corner is at the destination, to D (S's image there).  Cells already
  in D and not themselves in S are deleted; the result is as if every cell
  moved at once, so S and D may overlap.  A cell whose new place is off the
  sheet is dropped.  It then fixes the references (below) of the moved
  formulas, of the other formulas in the rows it rebuilt, and of the
  formulas in the rows to fix (offsets 28-32).
- **CELLS_MOVED** is the second half alone, for a move the program made
  itself (the cells copied, their bytecode as it was): it fixes the
  references of the formulas in the rows to fix, taking a formula now in D
  to have come from the same place in S.

A reference is fixed by its target, worked out from where the formula was:

- in S: it follows its cell (a relative one gets the offset from the
  formula's new place, an absolute one the cell's new row and column);
  a cell dropped off the sheet makes it a deleted reference (5.3, `#REF!`).
- in D but not S (a cell overwritten): a deleted reference.
- anywhere else: the same target, written relative to the formula's new
  place.

Each reference keeps its form and size (short or long; a deleted one stays
deleted), so bytecode never moves and no jump changes.  A range is its two
corners, each fixed on its own: inserting a row inside SUM(A1:A10) gives
SUM(A1:A11); deleting row 1 of A1:A10 makes the range #REF!.  A reference
that no longer fits its form (a short one more than 16383 rows or 8191
columns from its formula, or absolute past row 32767 or column 16383)
refuses the whole instruction: why 3 below, and the formula's row and
column.  Within a sheet of up to 16384 rows by 8192 columns this cannot
happen; COMPILE uses the long form for anything further.

Both instructions check everything before changing anything, so a refused
or malformed one (ERR_FORMAT) leaves the sheet as it was:

- **MOVE_CELLS**: checks the formulas of the rows to fix; builds every row
  of S and D afresh in the heap (its own cells but those in S or D, in
  memory order, then those moving in from S, each with CHANGED set, and its
  tree as REBALANCE_ROW builds it; no spare granules; an empty row a
  header alone); then points the row table at the new blocks (an empty row:
  $FFFFFFFF), and rewrites the rows to fix.  The old blocks, and the heap
  below its new start, are the program's to reuse.
- **CELLS_MOVED**: checks the formulas of the rows to fix, then rewrites
  them in place.

A formula whose bytecode changes gets CHANGED.  The walk over a formula
stops at END, at the end of its bytecode, or at a byte that is not an
opcode (the rest, malformed, is left as it is).  Neither instruction knows
of the sheet table (3.6): they work on physical cells, so a move between
the user's sheets is a move like any other.

Parameter block (64 bytes, 16-byte aligned; CELLS_MOVED uses the same,
without the heap):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | the sheet descriptor |
| 4 | 4 | source: first row |
| 8 | 4 | source: first column |
| 12 | 4 | source: last row ($FFFFFFFF: to the sheet's last; clipped to it) |
| 16 | 4 | source: last column (likewise) |
| 20 | 4 | destination: first row (bits 19-0) |
| 24 | 4 | destination: first column (bits 23-0) |
| 28 | 4 | first row of the formulas to fix |
| 32 | 4 | last row of the formulas to fix ($FFFFFFFF: all) |
| 36 | 4 | MOVE_CELLS: the heap's start (16-byte aligned); result: its new start |
| 40 | 4 | MOVE_CELLS: the heap's end; result (bytes 44-47): references made deleted |
| 48 | 4 | result: why it was refused (ERR_FORMAT): 0 a malformed row block (the row in the descriptor, as ever), 1 the heap too small, 2 a row's cells past 4096 granules, 3 a reference that does not fit its form |
| 52 | 4 | result: the row (why 1-3) |
| 56 | 4 | result: the column (why 3: with the row, the formula) |
| 60 | 4 | reserved, 0 |

Bytes 48-55 are zeroed first.  A source with its first row past its last
(after clipping), or its first column past its last, moves nothing.

Typical uses (rows 0-based, the sheet's last row L, last column C):

| To | Source | Destination |
|---|---|---|
| insert a row at r | r, 0, L, C | r + 1, 0 |
| delete row r | r + 1, 0, L, C (row r: overwritten) | r, 0 |
| insert a column at c | 0, c, L, C | 0, c + 1 |
| cut and paste | the block | the new top left |

The last row (or column) moves off the sheet when inserting, so keep it
empty.  Each is one instruction; fix every row (28-32: 0, $FFFFFFFF) unless
the program knows which rows can refer to the moved cells.

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
HyperRAM, bit 1 SDRAM, bit 2 the LLM units, bit 3 SHITE, bit 4 the vector
element ops.  Jobs, status, errors, stop requests and the
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
- **Formatter / codec**: `shite_number_text` (one shared number
  converter, exact, with a byte-serial big-integer engine),
  `shite_cell_text` (RENDER), `shite_formula_codec` (COMPILE, DECOMPILE).
  Planned speed-up: displayed values with |x| x 10^d < 2^128 (all ordinary
  values) need only m x 10^d and a shift, exactly, in 128 bits: a fast path
  on the shared multiplier, leaving the serial engine for extreme magnitudes
  and shortest round-trip printing.
- **Memory**: a segment cache of 8 lines of 256 bytes (2 KB of block RAM,
  address-tagged: cells are variable length, so it caches row block
  segments), a 64-entry (row, column) -> address cache in LUT RAM for
  references, the 32-entry evaluation stack, and a 256-byte text scratch.

## 10. The codec: COMPILE, DECOMPILE, RENDER, PARSE

A hardware unit (a serial scanner and shunting-yard parser, RAM-backed
stacks, a serial table reader and text writer) for everything between text
and SHITE's values: formula text to bytecode and back (so the CPU never
keeps the source of a compiled formula), and numbers to and from text (a
cell's display, a value typed in).  It uses SHITE's shared arithmetic (the
F64 unit, the multiplier and divider) for numbers.  Parameter blocks (16-byte
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
- **Sheet references** (planned; with a sheet table, 3.6): `Name!A1`,
  `Name!A1:B3` and `'Name with spaces'!A1` (a `'` inside the quotes
  doubled).  A reference without a sheet name is to the formula's own
  sheet (the one whose rectangle holds the formula cell).  COMPILE turns
  each into a physical reference, relative or absolute as written, and
  rejects (with its position) a reference outside its sheet's rectangle,
  an unknown sheet, and a range whose corners are in different sheets.
  DECOMPILE prints a reference with the sheet that holds its target, the
  name left out when that is the formula's own sheet; a target in no sheet
  is printed as a physical reference after `!` alone (`!A1`), which
  COMPILE reads back the same way.  Without a sheet table everything is
  one sheet, as before.
- **Deleted references** (5.3): DECOMPILE prints `#REF!`; COMPILE reads
  `#REF!` as one.
- **Limits**: nesting and stack depths, and the output bounds, are the
  codec's to state; exceeding them is a compile error with its position.

### RENDER

One value into a field of exactly `width` characters, as FORMAT_CELLS
shows a cell (section 6: what a cell shows, the number formats, the exact
digits, the characters).  FORMAT_CELLS uses it for each cell; the CPU can
too (a status line, an edit line).  Parameter block (32 bytes, 16-byte
aligned):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | the sheet descriptor (the separators) |
| 4 | 1 | the value's kind: 0 blank, 1 text, 3 F64, 4 I64, 6 error (3.4's codes) |
| 5 | 1 | its fixed point (I64; as a format's byte 2) |
| 6 | 1 | width |
| 7 | 1 | character size (1 or 2, as FORMAT_CELLS); bit 7: the upper-case set |
| 8 | 8 | the value (I64, F64, or the error code); for text: its address (4) and length (2) |
| 16 | 8 | the format (3.5; all zero: the default) |
| 24 | 4 | destination |
| 28 | 4 | scratch: 512 bytes of attic RAM |

R[a] bits 3-0: the colour the format gives the value (the negative
colour for a negative number with negatives = 2); bits 15-8: the
renderer's error code (0: none; a number it cannot show is `#NUM!` in the
field, not an error).

### PARSE

A value typed in, to the value a cell would hold.  Parameter block (32
bytes, 16-byte aligned):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | the sheet descriptor (the separators) |
| 4 | 4 | the text (ASCII) |
| 8 | 2 | its length |
| 10 | 6 | reserved, 0 |
| 16 | 8 | result: the value |
| 24 | 1 | result: its kind (0: not a number, 3 F64, 4 I64) |
| 25 | 1 | result: its fixed point (a format's byte 2) |
| 26 | 1 | result: a style for the cell, if the text implies one (0 none, 3 percent, 1 fixed with the prefix below) |
| 27 | 1 | result: a prefix character it carried (a currency sign), else 0 |
| 28 | 4 | reserved, 0 |

The text: spaces around it, then an optional sign (or the whole number in
parentheses, negative), an optional prefix character (a currency sign:
not a digit, sign, separator or letter), digits with optional thousands
separators (the descriptor's), an optional decimal separator and
decimals, an optional exponent (`E` and a signed integer), and an optional
`%`.  As COMPILE's numbers (above): without an exponent an integer is I64,
with decimals fixed point (k decimals, k <= 18; more: F64); with an
exponent F64, correctly rounded; `%` divides by 100 as the `%` operator
does.  Anything else (a word, a date, two numbers) is not a number: kind
0, and the CPU stores the text as text.  (So far the hardware parses the
number literal alone; the front end for spaces, parentheses, a prefix,
separators and `%` is to come.)

## 11. Testing

As SSNAIL: a Python reference model (`SSNAIL/shite.py`, run by the
emulator for SSNAIL's opcodes $40-$45) that defines the results exactly,
and GHDL benches that run the same sheets on the hardware and compare
memory: `tb_shite_step1` REBALANCE_ROW and FIND_CELL; `step2` RECALC with
integers, rounds, regions and change lists; `step3` fixed point; `step4`
F64 (about 480 formulas: specials, rounding, the subnormal boundary,
conversions); `step5` ranges, cell lists, aggregates and host calls;
`step9` MOVE_CELLS and CELLS_MOVED (and moves refused, the sheet
unchanged).  `SSNAIL/tests/test_shite_move.py` checks what a move means in
the model: after inserting a row every formula has its value, and so on.

## 12. Phases

1. **Done**: the build structure, REBALANCE_ROW, FIND_CELL.
2. **Done**: RECALC's core: I64 (with fixed point) and F64, constants,
   references (both forms), RECT, CELLS, ADD SUB MUL DIV NEG, the
   comparisons, HOSTCALL, CALL with SUM, AVERAGE, MIN, MAX and COUNT, the
   errors, rounds and change lists (benches `tb_shite_step1` to `step5`).
3. **Done**: FORMAT_CELLS (the rendering in the codec unit, the walk in
   the execution unit, section 6; `tb_shite_step8`).
4. **Done**: PCT, IF (JZ / JMP), MOD, AND / OR / NOT, ABS, INT, TRUNC,
   SIGN, PRODUCT, COUNTA (`tb_shite_step6`); POW / POWER (integer
   exponents), ROUND, SQRT (`tb_shite_step7`).
5. **Transcendentals** (the CORDIC unit) and **text** (STR, CONCAT, the
   text functions).
6. **Done, mostly**: the codec (section 10: COMPILE, DECOMPILE, RENDER,
   PARSE's literal; `tb_shite_step8`).  To come: PARSE's front end, the
   15-digit general cap, the fast number path, sheet references.
7. **Done**: moving cells: MOVE_CELLS, CELLS_MOVED (section 6), and deleted
   references (5.3) (`tb_shite_step9`).

A function the hardware does not have yet is #NAME? (a sheet still
recalculates, with that cell an error).

## 13. Open questions

- Text: ASCII in cells (as above), or PETSCII?
- Named ranges: not in this version.
- MOVE_CELLS / CELLS_MOVED: several moves at once (a list, applied as one),
  which sorting rows would want; one rectangle covers inserting and
  deleting rows and columns.  And whether a range should shrink when a row
  at its end is deleted (as other spreadsheets do), rather than become
  #REF!.
- An exact stable-cycle check (section 7).
