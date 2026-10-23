# SHITE's microcode engine

SHITE's instructions are moving from one large state machine (`shite.vhdl`,
about 300 states) to microcode run by a small engine (`shite_useq.vhdl`).
The state machine's cost was its control, not its arithmetic: each 64-bit
register was written from dozens of states, and each such register became a
wide multiplexer.  Yosys, with each group of states emptied in turn, put the
core at 22,400 LUTs:

| States emptied | LUTs saved | Flip-flops saved |
|---|---|---|
| formula evaluation: byte reader, operands, stack, binary operators | 8,910 | 1,300 |
| scalar functions (MOD, ROUND, POWER, SQRT, INT and others) | 5,644 | 763 |
| the multiplier and divider | 4,354 | 803 |
| MOVE_CELLS, CELLS_MOVED | 3,661 | 1,122 |
| F64 add, multiply, divide, normalise, convert | 3,492 | 916 |
| RECALC's row walk and counters | 1,993 | 621 |
| the codec units' jobs and memory | 1,928 | 787 |
| FORMAT_CELLS | 991 | 514 |
| the aggregates | 875 | 402 |
| REBALANCE_ROW | 869 | 356 |
| the cell lookup | 454 | 49 |

The rows overlap, so they don't add up to the total.

The engine has one register file and one ALU, and the microcode lives in
block RAM.  Every instruction ($40-$49) is microcode now.  `shite.vhdl` keeps
the engine, the codec units, and a small state machine that serves the
engine's memory requests and its jobs on the units.

## The engine

The engine runs on sclock (40.5 MHz).  Each cycle it reads its registers,
uses the ALU, picks its branch and addresses the ROM for the next micro-op.

- **ROM**: 4096 × 72 bits of block RAM, read on the clock edge.  Its next
  address is chosen combinationally from the op in hand.
- **Registers**: 128 × 64 bits of LUT RAM, with two asynchronous read ports
  and one write port.
  - `r0` reads as 0, and writes to it are lost.
  - Registers declared with `.const` start with their value (the RAM's
    initial contents), so 64-bit constants cost no micro-ops.
- **ALU**: add, subtract, logic, shifts, field extract and insert.
- **Branches**: a branch tests the result of the same op, so a compare and
  its branch are one micro-op.  The conditions:
  - zero and nonzero;
  - unsigned ≥ and <, signed < and ≥ (these take the adder's carry and
    overflow, so they need a SUB);
  - sign;
  - SSNAIL's abort.

  Ops can also call and return (16 deep), jump through a table
  (`target + result`), and jump to an address in a register.  RECALC's
  evaluator leaves an aborted formula the same way.  `SETSP`
  backs out of calls: the byte reader, past a formula's end, goes straight
  to the formula's end, wherever it was called from.
- **Memory**: one 8-byte group per request.
  - The engine raises a request (`req_t` toggles); the state machine serves
    it in states `U_RUN`, `M_DEC`, `M_ISSUE`, `M_WAIT` and `U_MACK`, then
    acknowledges (`ack_t` toggles).
  - The engine keeps the last group it read.  A load from that group takes
    one cycle, and a store into it updates it.
  - Stores write through to memory and don't wait: the engine goes on, and
    the next memory request, job or END waits for the store's acknowledge.
  - A load's address can be indexed: `ra + rb × 1, 4, 8 or 16 + offset`.
  - A memory fault (an address outside the map, or a read error) ends the
    instruction in the state machine, as before.
- **The codec units** (`shite_formula_codec`, `shite_cell_text`,
  `shite_number_text`) are reached through ports.  `OUT #port, ra` sets one
  of a job's inputs, `IN rd, #port` reads one of a unit's results, and
  `JOB #unit` runs a job: the state machine starts the unit and serves its
  memory requests, then acknowledges.  The engine forgets its kept group
  after a job, since the unit may have written it.  The port numbers are
  the `P_` and `I_` names in `shite_ucode.asm`, decoded in `shite.vhdl`.
- **Multiplier and divider**: `MUL` gives a 64 × 64 product's low half
  (`MOVX MULHI` the high), unsigned, a bit a cycle; `DIV` divides `DIVHI:ra`
  (`OUT #32` sets DIVHI) by rb, restoring, a bit a cycle (`MOVX DIVQH`, the
  quotient's high half; `MOVX DIVR`, the remainder).  The state machine's
  were the same speed.
- **Data RAM**: 2048 × 64 bits of block RAM, addressed by `ra + imm`, its
  first contents from `.data`.  A load takes two cycles and a store one.
  REBALANCE_ROW (and MOVE_CELLS' tree for each row it builds) keeps its
  list of cells in words 0-1023 and its tree's queue after it; RECALC its
  evaluation stack from 1024, the range walk's stack from 1088, and the
  powers of ten from 1152.

## Micro-op format (72 bits)

| Bits | Field |
|---|---|
| 71-66 | op |
| 65-59 | rd (0: not written) |
| 58-52 | ra |
| 51-45 | rb |
| 44 | B is the immediate (else rb) |
| 43-40 | condition |
| 39-28 | branch target |
| 27-0 | immediate (sign-extended): an offset, a field's position (bits 5-0) and width (bits 13-8, 0 meaning 64), or a MOVX source |

Constants wider than the immediate live in `.const` registers.

| Op | Result | Notes |
|---|---|---|
| 0 ADD, 1 SUB | ra ± B | sets the carry and overflow for the conditions |
| 2 AND, 3 OR, 4 XOR, 5 ANDN | ra op B | ANDN is ra AND NOT B |
| 6 SHL, 7 SHR, 8 SAR | ra shifted by B (bits 5-0) | |
| 9 EXT, 10 EXTS | the field of ra at lo, w bits wide | EXTS sign-extends |
| 11 INS | rb with ra's low w bits put at lo | |
| 12 HI | B's low 32 bits, then ra's low 32 bits | |
| 13 SETSP | none | the call stack's depth set to ra (from MOVX SP) |
| 14 MOVX | the instruction's OP, RA, RB, RC, RD, RZ or X; the call stack's depth (SP); MULHI, DIVQH, DIVR | |
| 15 CLZ | ra's leading zeros (64 if ra is 0) | |
| 16-19 LDB, LDH, LDL, LDQ | 1, 2, 4 or 8 bytes at `ra + rb × s + imm`, zero-extended | must not cross an 8-byte group; s is 1, 4, 8 or 16 (imm bits 27-26), the offset 26 bits |
| 20-23 STB, STH, STL, STQ | rb's low 1, 2, 4 or 8 bytes stored at `ra + imm` | must not cross an 8-byte group |
| 24 LDD, 25 STD | the data RAM at `ra + imm` (LDD: indexed, as a load) | STD stores rb |
| 26 RES | none | the instruction's result is ra's low 32 bits |
| 27 END | none | ends the instruction with error code imm |
| 28 OUT | none | a codec job's input (port imm) set to ra |
| 29 IN | a codec unit's result (port imm) | |
| 30 JOB | none | runs a job on unit imm (0 the formula codec, 1 the renderer, 2 PARSE's converter) |
| 31 MUL, 32 DIV | the product's low half, the quotient's | 64 and 128 cycles |

| Condition | Taken when |
|---|---|
| 0 | never: the next op |
| 1 JMP, 2 CALL | always (CALL pushes the next op's address) |
| 3 RET | always, to the address popped |
| 4 JTAB | always, to target + result (`jr reg`: target 0) |
| 5 Z, 6 NZ | the result is zero, nonzero |
| 7 UGE, 8 ULT | unsigned ra ≥ B, ra < B (after a SUB) |
| 9 LT, 10 GE | signed ra < B, ra ≥ B (after a SUB) |
| 11 MI, 12 PL | the result's bit 63 is set, clear |
| 13 ABT, 14 NABT | SSNAIL's abort is set, clear |

A load can branch on the value it loaded (`ldl t0, [a] | z empty`).

## Assembler

`src/vhdl/tools/shite_uasm.py` turns `src/vhdl/shite_ucode.asm` into
`src/vhdl/shite_ucode_pkg.vhdl` (the ROM, the registers' first values and the
encoding's constants).  Vivado reads the committed package; after editing the
source, run `tools/shite_uasm.py` in `src/vhdl`.  The test runner rebuilds
the package and fails if the committed one differs.

```
.equ  NAME = expr            ; a constant for expressions
.reg  a, b, c                ; registers by name (from r1 up)
.const M32 = 0xFFFFFFFF      ; a register holding this from the start (from r127 down)
.scope / .endscope           ; registers named between are freed at the end
.alias b = a                 ; another name for a register
.data 1152 = 1               ; the data RAM's word 1152 starts as 1
label:
      op operands [| cond [target]]
```

A scope's registers are reused by the next scope, so two scopes must never
be live at once: a routine called from inside another scope keeps its
registers outside any scope (`rb_block` does: MOVE_CELLS calls it).
Labels can be used in expressions (`li bx_end, #fx_end`).

Pseudo-ops:

| Pseudo-op | Meaning |
|---|---|
| `nop`, `mov`, `li` | the usual |
| `ldq rd, [ra + rb*16 + 8]` | an indexed load |
| `jmp`, `call`, `ret` | branch, call, return |
| `jtab reg, table` | jump to table + reg |
| `jr reg` | jump to the address in reg |
| `beq`, `bne`, `bltu`, `bgeu`, `bgtu`, `bleu`, `blt`, `bge`, `bgt`, `ble` | compare and branch, against a register or `#imm` |
| `bz`, `bnz`, `babt` | branch on zero, nonzero, abort |

Any op can carry a condition: `add row, row, #1 | jmp b_row`.

## Checking it without a simulator

`tools/shite_usim.py` models the engine op by op in Python (the micro-ops'
results, not their cycles; the codec units not at all).
`tools/shite_ucheck.py gen_shiteN.py` runs a bench's program with every
SHITE instruction also run on that model from the same memory, and stops
at the first one whose memory, result or error differs from the reference
model's.  `--trace N` prints instruction N's micro-ops.  It takes seconds
where the VHDL bench takes minutes.

## Moving the rest

Instructions move a family at a time, each step passing the whole bench
suite:

1. REBALANCE_ROW and FIND_CELL (done; `tb_shite_step10` covers their
   refusals).
2. MOVE_CELLS and CELLS_MOVED, sharing REBALANCE's tree builder (done; the
   state machine's REBALANCE, MOVE and list RAM are gone).
3. FORMAT_CELLS and the codec jobs (COMPILE, DECOMPILE, RENDER, PARSE)
   (done; the codec units stay hardware).
4. RECALC: the walk, the evaluator, the functions and the aggregates
   (done; the engine gained the multiplier, the divider and CLZ, and
   normalises and rounds F64 in microcode).

`shite.vhdl` now keeps only the memory crossing, the codec units and the
engine.

## Size and speed

Yosys `synth_xilinx`, LUTs (the engine's register file is another 88 RAM64M;
the codec units, separate, not counted):

| | SHITE | engine |
|---|---|---|
| all state machine | 22,442 | |
| REBALANCE, FIND_CELL, MOVE in microcode | 17,790 | 2,950 |
| and FORMAT_CELLS, the codec jobs | 16,359 | 3,047 |
| everything (the state machine only memory and the units' jobs) | 690 | 3,701 |

The engine uses 12 RAMB36: 8 for the ROM, 4 for the data RAM.

Microcode runs an op per cycle where the state machine did several things
in a state, so the instructions are slower, about twice.  On the benches
(simulated, each including about 0.2 ms of set-up):

| | state machine | microcode |
|---|---|---|
| `tb_shite_step1` (REBALANCE_ROW, 64 FIND_CELLs) | 340 µs | 476 µs |
| `tb_shite_step2` (RECALC, integers) | 0.71 ms | 1.49 ms |
| `tb_shite_step4` (RECALC, F64 and functions) | 2.71 ms | 4.90 ms |
| `tb_shite_step7` (RECALC, SQRT, POWER) | 6.86 ms | 8.61 ms |
| `tb_shite_step8` (the codec jobs, FORMAT_CELLS) | 1.86 ms | 1.90 ms |
| `tb_shite_step9` (six moves, a CELLS_MOVED) | 4.01 ms | 8.23 ms |

The time is mostly micro-ops, not memory: RECALC's is spread evenly over
the evaluator (dispatch, operands, the stack, the binary operators, F64);
MOVE's is its byte-by-byte walk of each formula.  The benches' timeouts are
ten times what they were.

## Tests

The VHDL benches (`tools/run_ssnail_tests.py`) run every instruction
against the reference model.  Besides them:

- `tools/shite_ucheck.py gen_shiteN.py`: a bench's program on the
  microcode model (seconds, not minutes), instruction by instruction.
- `tools/shite_ufuzz.py --sheets N`: RECALC on random sheets and formulas
  (every operator, function and aggregate, fixed points at and past their
  limits, F64 at its edges, references off the sheet, IF, rounds with BEGIN
  and END), the model against the microcode.  It found one difference the
  benches had not: a blank result stored into a cell whose fixed point is
  past its limits, #NUM! in the model, (I64, 0) in the state machine; the
  microcode follows the model.
- Mutants of the microcode (a check removed, a constant changed): those of
  REBALANCE_ROW, FIND_CELL, MOVE and the codec jobs caught by the benches
  but two (a RENDER error's code in R[a], the renderer's upper-case flag:
  both passed straight through); RECALC's 16 caught by the benches or the
  fuzzer but two: SQRT's sticky bit, and F64 addition's for exponents more
  than 64 apart (rounding ties, not met by random values).
