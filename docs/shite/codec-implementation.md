# Standalone hardware formula codec

`src/vhdl/shite_formula_codec.vhdl` implements text compilation and canonical
reconstruction against sections 5 and 10 of the [canonical draft](README.md).
`shite_codec_pkg.vhdl` defines its error codes and small semantic tables.
The evaluator, SSNAIL dispatch, LUMP transport and their existing test runner
are not modified. The core has direct job parameters and an eight-byte RAM
interface, ready for their command/transport adapters.

## Implemented transformations

- Serial shunting-yard compilation of arithmetic, comparisons, concatenation,
  prefix signs, postfix percent, grouping and function calls.
- Canonical short/long references with 20-bit rows, 24-bit columns, independent
  absolute flags and modulo-relative coordinates.
- RECT operands and canonical CELLS runs inside aggregates, including extended
  counts and mixed reference/expression/range arguments.
- Nested IF lowered to the specified JZ/JMP pattern. Reconstruction traverses
  both branches using their structural boundaries, without running either.
- Counted string literals, with doubled quotation marks in source text.
- AtticRAM function-name lookup, ASCII case folding, aliases and first-entry
  canonical spelling. No function names are hard-coded into the RTL.
- Extended function IDs and CPU-owned IDs 16384..32767. HOSTCALL preserves the
  original call text and emits the fixed six-byte unbound result reference.
- Positioned syntax/resource errors, bounded output writes, memory-error
  reporting, and abort that drains an outstanding RAM/numeric transaction.

The numeric representation is handled through the shared conversion service
below. The codec itself implements neither an FPU nor a duplicate decimal
literal conversion datapath.

## Job interface

Pulse `start` for one clock when `busy` is low. The core latches:

| Port | Meaning |
|---|---|
| `decompile` | 0: text to bytecode; 1: bytecode to text |
| `source`, `source_length` | 28-bit byte address and 16-bit input length |
| `destination`, `output_capacity` | Output byte address and capacity |
| `names` | Function spelling table address |
| `formula_row`, `formula_column` | Formula origin, 20 and 24 bits |
| `decimal_separator`, `argument_separator` | Current locale punctuation |

Source text and reconstructed text omit the leading `=`. Input and output are
length-delimited, not NUL-terminated. Source NUL bytes are rejected. String
quotation uses `"a""b"` for a literal containing a quotation mark.

Function identifiers start with an ASCII letter or underscore and continue
with ASCII letters, digits, underscores or dots. A following `(` distinguishes
a function call from a cell reference. `$` is supported in references. Name
tables end with an identifier followed by an empty NUL-terminated name.

The implemented operator precedence, highest first, is prefix minus, power,
multiply/divide, add/subtract, concatenation, comparison; power associates
rightwards. Percent is postfix. Prefix minus directly on a numeric token is
folded into that literal through the numeric service's sign flag. Other NEG
nodes reconstruct with explicit operand grouping so recompilation preserves
their bytecode structure. These grammar details are codec choices for
integration review, not changes to arithmetic execution.

On completion `done` pulses, `busy` falls, and `error` is zero on success.
`result_length` is valid only on success; it is zero on failure. `host_calls`
counts placeholders newly emitted during compilation, capped at 255; a job
that would emit another fails rather than wrapping. DECOMPILE emits no new
host bindings and returns zero in that field.

Buffers and the name table must be disjoint and remain owned by the job until
completion. Partial output may exist after failure and must not be published.
Reset cancels the interface and must be coordinated with the RAM/numeric
adapter. Abort, in contrast, waits for already-issued service requests to finish.

## Eight-byte RAM interface

There is one outstanding transaction at most:

- `ram_valid` is held until the adapter asserts `ram_ready` for completion.
- `ram_address` is always eight-byte aligned.
- Reads return `ram_rdata`, with the lowest-addressed byte in bits 7..0.
- Writes use `ram_wdata` and eight per-byte `ram_byte_enable` bits.
- `ram_error` is sampled with `ram_ready` and ends the job with CODEC_MEMORY.

Command fields stay stable while a transaction is outstanding. Completion
must be acknowledged once, not repeatedly for a held request. A transport
without byte enables can perform the equivalent masked write in its adapter.

The core caches one eight-byte read group, updates it on its own writes, and
invalidates it after a numeric-service formatting request. A single address
setup state shares address addition and byte-lane selection across all users.
No assumption is made about RAM latency or consecutive read response timing.

Text fragments reside in the destination buffer. Inserting parentheses,
function names, separators and CELLS headers uses a backwards byte-copy loop.
This can be slow for large/deep formulas; it avoids an on-chip formula text
buffer or expression tree.

## Shared numeric conversion service

`number_start` pulses to request a conversion. The codec does not issue RAM
transactions until `number_done`; the integration layer can give the numeric
converter the same RAM port during that interval. All request fields remain
stable until completion. This is the hand-off point for SHITE's shared number
conversion service, now implemented separately in `shite_number_text.vhdl`.
See [numeric text and cell rendering](numeric-text-implementation.md) for its
interface, algorithms, rendering mode and resource measurements. Instantiate
one converter, shared between the formula codec and the cell-text renderer.

For parsing (`number_format = 0`):

- Read `number_length` bytes from `number_source`.
- Interpret `number_negative` as an additional leading sign, and use
  `number_decimal_separator`.
- Return `number_result_value`, `number_result_kind` (0 integer, 1 F64), and
  `number_result_scale` (the FIX byte for an integer).
- For an invalid literal return a nonzero `number_error` and a zero-based
  `number_error_position` relative to that numeric token.

The codec chooses I8/I32/I64 from the returned signed value, or emits F64, and
appends FIX when required. It does not perform the conversion arithmetic itself.

For formatting (`number_format = 1`):

- Convert `number_value`, `number_kind` and `number_scale` to canonical text,
  observing `number_decimal_separator`.
- Write at `number_destination`, within `number_capacity` bytes.
- Return the count in `number_result_length`, or a nonzero `number_error`.

The service owns exact decimal/F64 conversion, scale-preserving syntax and
signed-zero spelling. It must preserve the draft's decimal-vs-exponent literal
distinction. Unsupported numeric spellings return a conversion error, not
silently substituted values. Capacity failures can use CODEC_CAPACITY.

The testbench supports both recorded conversion fixtures and the actual RTL
converter. Fixtures isolate the codec's numeric protocol and binary emission;
the real-converter run exercises end-to-end formula transformations. Separate
numeric tests cover conversion arithmetic and display rounding.

## Bounds and error positions

Defaults are 32 parser/IF frames, 64 pending operators, a 32-value execution
stack, 128 reconstruction fragments and a 65535-byte table scan bound.
Lengths and output capacities are 16-bit. Encoded counts and identifiers are
limited to 32767.

Compilation walks its completed bytecode before publishing it, checking value
stack depth, IF structure and reconstructed-parenthesis depth. This rejects
flat input expressions whose fully parenthesised output would exceed the
configured nesting limit when recompiled. Reconstruction applies the same
checks. CELLS stores a long plain-cell argument run as one value.

All stacks share a synchronous 512-by-32-bit RAM with the default generics.
Only the active parser/operator/IF frames are cached in registers. Frame slots
use a power-of-two stride to avoid address multipliers. Reference-to-text
division is serial shift/subtract, not a general hardware divider.

Errors in `shite_codec_pkg.vhdl`:

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Syntax |
| 2 | Unknown function/name |
| 3 | Numeric conversion |
| 4 | Invalid cell-reference spelling |
| 5 | Function arity |
| 6 | Stack, nesting or reconstruction depth |
| 7 | Output/count capacity |
| 8 | Malformed or unsupported bytecode structure |
| 9 | Malformed/unterminated table or scan bound |
| 10 | RAM/address error |
| 11 | Aborted |

Positions are zero-based byte offsets: source text for compilation and input
bytecode for reconstruction. Compilation's final structural/resource check
reports end-of-source if no individual source token is retained for the fault.
The numeric service can supply more precise within-token positions.

## Validation

Run the standalone suite without modifying the shared SSNAIL runner:

```sh
python3 tests/test_shite_codec.py
```

This runs the 503 codec jobs twice: with fixtures and with the shared numeric
converter, plus three real-service fault/abort cases. The latter uses a
RAM-port ownership mux in the testbench; it does
not change the codec's interface or instantiate an FPU inside it.

It generates independent expected bytecode/text vectors and runs GHDL with an
irregular-latency eight-byte RAM adapter. Cases include unaligned buffers,
numeric kinds, coordinate limits and short/long boundaries, locale tables,
aliases, long names, string quoting, 127/128 counts, large CELLS lists, nested
IF in all three positions, host calls, canonical recompilation, random formula
trees, truncated bytecode, capacity failures, abort and memory errors. Output
guards and service completion are checked. The production core also analyses
and synthesises as VHDL-93c; the file-driven testbench uses VHDL-2008.

Area can be measured independently of transport and arithmetic integration:

```sh
ghdl -a --std=93c --workdir=/tmp src/vhdl/shite_codec_pkg.vhdl src/vhdl/shite_formula_codec.vhdl
ghdl --synth --std=93c --workdir=/tmp --out=verilog shite_formula_codec > /tmp/shite_codec.v
yosys -p 'read_verilog /tmp/shite_codec.v; synth_xilinx -top shite_formula_codec; stat'
```

The initial synthesis measurements are approximately 4.8k estimated logic
cells, 2.6k flip-flops, one RAMB18E1 and no DSPs, excluding the shared numeric
service and RAM/command transport. These are synthesis estimates, not routed
timing or a claim of a proven minimum. A first register-stack version was about
21k estimated logic cells and 11k flip-flops; serial stack RAM and shared RAM
access reduced those costs substantially.
