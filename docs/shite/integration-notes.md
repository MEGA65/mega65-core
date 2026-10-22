# SHITE integration notes

Date: 2026-10-18.  For the authors of the execution unit (`shite.vhdl`) and
of the codec units (`shite_formula_codec`, `shite_number_text`,
`shite_cell_text`).  The canonical description stays the
[README](README.md); this note lists who does what next.

## Settled (by the user, recorded in the README)

1. **Rounding is exact everywhere.**  The cell renderer's display rounding
   from the exact value (as built) is the rule.  `ROUND()` in the evaluator
   now rounds the exact value too (README 5.7), so a stored F64 2.675 shows
   `2.67` and `ROUND(2.675, 2)` gives 2.67; a typed 2.675 is fixed point and
   gives 2.68 in both.
2. **General format: at most 15 significant digits for F64** (README 6,
   "General").  `shite_number_text` currently tries 17: please change that
   to 15 (integers and decimal fixed point keep all their digits).
3. **Defaults for the open details** (README 6):
   - format byte 3 bit 3 (leading zeros): reserved, no effect, as built;
   - style 5 (text): general, aligned left by default (please check the
     renderer aligns it left);
   - prefix / suffix characters are screen codes, as built.
4. **RENDER takes a 512-byte scratch area, FORMAT_CELLS 1 KB** (RENDER's
   parameter block offset 28, FORMAT_CELLS' offset 40), for the renderer's
   raw number text.

## Done (execution unit side), 2026-10-18

The units are wired into `shite.vhdl` and run as SSNAIL instructions:
COMPILE, DECOMPILE, RENDER, PARSE (the literal) and FORMAT_CELLS, sharing
one converter, through an adapter from their RAM handshake to the
execution unit's eight-byte LUMP transaction (a memory fault reaches the
unit as `ram_error`; SSNAIL's stop request is their abort).
`tb_shite_step8` runs 32 of `tests/test_shite_codec.py`'s compile and
decompile jobs, RENDER, PARSE and FORMAT_CELLS (character sizes 1 and 2,
colours, only-CHANGED and clearing) and checks the bytes each writes.

Conformance points found on the way (README 6), for the renderer:

- Scientific display text should have the exponent's sign and at least
  two digits (`1.2E+06`); the renderer writes `1.2E6`.  (Canonical
  formula numbers keep their own `1.2E6` style.)
- Errors are centred by default (README 6, "What a cell shows"); the
  renderer's notes say other kinds default to left.

## The execution unit's side (as planned)

- Dispatch of SSNAIL opcodes $43-$47 in `shite.vhdl`: reading each
  parameter block, driving the codec / renderer / converter job ports,
  writing the results back (lengths, error codes and positions, PARSE's
  value) and R[a].  Codec errors are data in the block (the job succeeds);
  memory faults and aborts end the job as SSNAIL errors.
- A RAM adapter: the units' eight-byte held-valid RAM handshake onto the
  execution unit's eight-byte LUMP transaction, one client at a time (the
  codec or renderer, and the shared converter while it holds the port).
- FORMAT_CELLS ($43): the rectangle walk (rows, each row's cells in column
  order, as RECALC's ranges), resolving formula results to their value
  kinds, the CHANGED test and clearing, character size 2, the colour
  plane, and one RENDER per field.
- One `shite_number_text` instance, shared, as both units intend.

## Needed from the codec side

1. **PARSE's front end** (README 10, PARSE): spaces around the text,
   parentheses for a negative, a currency prefix character, thousands
   separators, a trailing `%`, then the converter's literal parse; kind 0
   for anything that is not a number.  Text handling, so it belongs with
   the codec; a job interface like RENDER's would let the execution unit
   dispatch it the same way.
2. **Python reference implementations** of COMPILE, DECOMPILE, RENDER and
   PARSE, as a module of the SSNAIL tools (beside `shite.py`, say
   `shite_codec.py`), which the emulator (`ssnail_sim.py`, `Machine.shite`)
   can call for opcodes $44-$47.  The MEGA65 client is developed against
   the emulator, and the execution unit's GHDL benches take their expected
   memory from it, so without these neither can use the codec.  The test
   generators' builders are a good start but construct cases rather than
   compile arbitrary text.
3. **The 15-digit cap** (above).
4. **A fast path for number rendering** (planned, README 9): an F64 is
   m x 2^E with m < 2^53, so for d <= 18 decimals |x| x 10^d = m x 10^d x 2^E
   is exact in 128 bits (m x 10^d < 2^113) and rounding it is a shift with
   the bit below kept; general and scientific likewise for ordinary
   exponents.  Only extreme magnitudes and DECOMPILE's shortest round-trip
   printing need the serial big-integer engine.  The execution unit's
   iterative 64 x 64 multiplier (128-bit product) and 128 / 64 divider can be
   shared for it, as the F64 unit is; how to share them (a request port
   like the converter's) is to agree.

## Added 2026-10-21 (README 3.1, 3.6, 5.3, 10)

For the codec side, when the items above are done:

6. **Sheet references.**  The descriptor grows to 128 bytes; bytes 64-69
   point at a sheet table of named rectangles of the physical sheet
   (README 3.6).  COMPILE reads `Name!A1`, `Name!A1:B3`, `'Quoted name'!A1`
   and `!A1` (physical), relative to the named sheet's origin, and checks
   the reference lies in that sheet; an unqualified reference is to the
   formula cell's own sheet.  DECOMPILE prints the sheet holding each
   target, leaving out the formula's own.  Bytecode is unchanged: always
   physical references.
7. **Deleted references** (README 5.3): relative with both fields at their
   minimum, in either form.  DECOMPILE prints `#REF!`, COMPILE reads
   `#REF!` back as one; COMPILE must not produce that encoding for a real
   cell (use the long form for such an offset).

The execution unit evaluates a deleted reference as #REF!, and produces
them in MOVE_CELLS / CELLS_MOVED (README 6) for references to cells
overwritten or moved off the sheet.
