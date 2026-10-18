# Shared numeric conversion and scalar cell rendering

This is an implementation handoff, not an edit to the canonical README or
the other agent's evaluator. At the overlap check, `shite.vhdl` contained
F64 arithmetic and conversions for evaluation, but no text-number converter
or FORMAT_CELLS implementation. Those files and the shared runner are left
alone. The new components are standalone, like the formula codec.

## Sharing rather than duplicating

Use one `shite_number_text` instance for all three jobs:

1. Formula compilation: decimal text to I64/FIX or F64.
2. Formula reconstruction: exact, type-preserving canonical numeric text.
3. Cell rendering: display text, rounded according to the cell format.

`shite_cell_text` adds the scalar-cell presentation layer. It requests the same
converter through an external service interface; it does not contain another
numeric conversion instance. The formula codec and renderer are mutually
exclusive clients selected by the command sequencer. The active client gives
up the eight-byte RAM port until numeric completion. Testbenches demonstrate
that ownership mux with the actual converter, not a software conversion stub.

The evaluator's F64 datapath is not copied. Exact decimal parsing and shortest
printing need more precision than successive rounded F64 arithmetic provides.
Instead, a small byte-serial integer engine supplies the conversion-specific
wide arithmetic. It has no general multiplier, divider, barrel shifter or FPU.
It uses one 2048-by-8 synchronous block RAM: four unsigned integers of up to
4096 bits. Only their lengths and the active byte/carry reside in registers.
Two-, five- and ten-times operations use fixed shifts and addition. Division
by ten advances one dividend bit at a time; comparison, subtraction and copying
walk the bytes serially. Working registers are reused between conversion modes.

The speed/area tradeoff is deliberate. Extreme binary64 magnitudes can require
millions of clocks per conversion. There are no large powers-of-ten ROMs,
parallel conversion pipelines, DSP requirements or per-cell conversion units.

## Numeric service

Sources, destinations, counts, byte lanes and the held-valid RAM handshake
are identical to the formula codec's numeric-service contract. Map the codec's
`number_*` outputs to the corresponding converter job inputs:

| Codec signal | Converter input |
|---|---|
| `number_start` | `start` |
| `number_format`, `number_negative` | `format`, `negative` |
| `number_source`, `number_destination` | `source`, `destination` |
| `number_length`, `number_capacity` | `input_length`, `capacity` |
| `number_value`, `number_kind`, `number_scale` | `value`, `kind`, `scale` |
| `number_decimal_separator` | `decimal_separator` |

Map the converter's `done`, `error`, `error_position`, `result_length`,
`result_value`, `result_kind`, and `result_scale` back to their `number_*`
counterparts. Integer kind is 0, F64 kind is 1. Request parameters are latched
on `start`; completion pulses `done`. All clients must share reset with the
converter. A client's abort drains the outstanding conversion; the converter
also has its own abort input, which drains its current RAM/integer operation.
Results after an error are invalid, and `result_length` is zero.

### Parsing

- Decimal without E/e is signed I64, with FIX equal to its number of fractional
  digits. Leading/trailing decimal-point forms and an optional leading sign
  are accepted. The caller's `negative` flag is an additional sign inversion.
- At most 18 fractional places and the signed-I64 magnitude limits apply to
  the no-exponent form. Trailing zeros are retained in FIX. Too-large values
  are errors, not silently promoted to F64.
- An exponent selects F64, including `1E0`. Conversion uses an exact integer
  ratio and binary quotient bits, followed by round-to-nearest, ties-to-even.
  A finite-overflow result is CODEC_NUMBER. Subnormal results are flushed to
  signed zero after rounding; a value rounding up to the minimum normal is
  retained. An underflowing negative literal preserves its zero sign.
- A maximum 65535-byte input is streamed. The first 800 significant decimal
  digits are accumulated, with a sticky bit for nonzero discarded digits and
  an adjusted decimal power. Binary64 rounding boundaries have finite decimal
  expansions with fewer than 800 significant digits; the extra tail can
  therefore only change an otherwise exact boundary comparison. Exponents
  saturate beyond a bound larger than any compensation by the input length.
- Syntax errors identify the offending byte. End-of-literal validation,
  including magnitude/scale errors, reports the input length. Positions are
  relative to the numeric token; the formula codec adds its source offset.

### Canonical printing

- I64 and decimal FIX print as ordinary decimal, with every scale digit,
  including trailing zeros. The minimum signed integer is supported without
  overflowing an intermediate signed absolute value.
- Finite, normal F64 uses an exact-ratio, rounding-interval digit generator.
  It stops at the first precision with a decimal value inside the original
  binary64 value's rounding interval. Power-of-two boundary asymmetry and
  inclusion/exclusion for even/odd significands are taken into account. If
  both adjacent decimal candidates fit, choose the closer, ties-to-even.
- The spelling is normalized scientific form: `1E0`, `1.25E0`, `1E-3`,
  `-0E0`. There is always an E, no positive exponent sign, and no exponent
  leading zeros. This minimizes significant digits, not necessarily the
  total number of characters across all possible exponent placements.
- Subnormal input bit patterns print as signed zero, consistently with SHITE's
  flush rule. NaN and infinity return CODEC_NUMBER.
- Binary FIX is supported for display, not canonical formula printing: the
  formula grammar has no spelling that preserves that FIX byte. Such a
  reconstruction returns CODEC_NUMBER rather than inventing a lossy decimal.
  COMPILE never generates binary FIX, so this does not affect its round trip.

### Display printing

Set `format=1`, `display=1` and supply `display_style`, `display_decimals`,
and `display_width`. This emits raw ASCII, without padding or decoration:

- Style 1 fixed, 2 scientific, 3 percent, 4 integer; styles 0 and 5 use general.
- Fixed/integer/percent conversion rounds the exact magnitude at the requested
  decimal place, half away from zero. Percent scales by 100 before rounding
  and appends `%`. Binary FIX uses its exact power-of-two denominator.
- Scientific uses the requested places after its leading digit, half away
  from zero, including a carry into the exponent.
- General tries 17 (F64) or 19 (integer kinds) down to 1 significant digits,
  retaining full-width I64 values when they fit, and rounding again from the
  original exact ratio at each precision, not from previously rounded text.
  Prefer ordinary decimal if it fits, otherwise scientific. Remove redundant
  fractional zeros. `display_width` is a width budget for general mode, not
  a request for padding; an impossible budget returns CODEC_CAPACITY.

Display decimals are 0..15. Invalid styles/scales are numeric errors. A cell
renderer turns these into `#NUM!`, not a failed transport job.

## Scalar cell text

`shite_cell_text` accepts a resolved cell kind/value, its eight-byte format,
text pointer/count when appropriate, output pointer/capacity, and column width.
Formula result lookup and kind resolution remain the sheet walker's job: pass
the stored result as F64/I64/text/error/blank, not the outer FORMULA kind.
I32 is sign-extended; UNCOMPILED displays its stored text. Missing cells are
passed as EMPTY. Hidden width 0 completes without accessing RAM or conversion.

The caller supplies a disjoint 512-byte AtticRAM `scratch` area. Numeric
conversion writes its raw text there; the renderer scans it and streams the
decorated, padded field to the output. No on-chip character buffer is needed.
For numeric service requests, connect the renderer's `number_*` parameters to
the same converter with `format=1`, `display=1`, `negative=0`, and capacity 512.
It issues no RAM transactions until that request completes.

Implemented presentation:

- General, fixed, scientific, percent and integer numeric text; decimal and
  binary scale metadata; EN/DE decimal/group punctuation.
- Thousands grouping outside scientific form; negative minus/parentheses;
  prefix/suffix characters; negative/normal colour selection.
- A general-mode retry with a smaller numeric width when grouping consumes
  extra columns, rather than prematurely replacing a fitting rounded number
  by hashes. Numeric overflow of the field gives `#` in every column.
- Left/centre/right alignment; default numeric right, other kinds left.
  Overlong text/errors clip according to alignment; blanks pad with spaces.
- All nine specified error names. Numeric conversion failures display #NUM!;
  RAM failures and abort still fail the job.
- ASCII output, or byte screen codes with upper/lower character-set selection.
  Format prefix/suffix bytes are already screen codes; ASCII mode maps their
  letter codes back to ASCII. `colour` returns the selected four-bit colour.

Input text, scratch, and output must be disjoint, with caller ownership until
completion. Counts/addresses are bounds-checked, but overlap is a caller rule.
Text can exceed 1024 bytes; only the visible clipped portion is read.

### Integration and remaining specification decisions

This is **not** the full `$43 FORMAT_CELLS` command. It does not traverse rows,
resolve formula result fields, inspect/clear CHANGED, apply row/colour strides,
write a colour plane, or generate 16-bit screen attributes. The sheet/transport
adapter can call this scalar renderer and expand its byte characters as needed.
There is no change to SSNAIL dispatch, LUMP adapters or the evaluator.

Format byte 3's bit 3 is currently not an extra zero-padding mode: all fractional
values already retain a leading zero. The canonical draft says "leading zeros"
without specifying how many, or how they interact with signs/grouping/alignment.
Please arbitrate that meaning before adding hardware for it. Numeric style 5
currently uses general conversion; its distinct coercion/alignment semantics,
if desired, likewise need definition. Non-ASCII text and inverse-ASCII mappings
for graphical prefix/suffix screen codes need a character-set policy; this
implementation maps ordinary ASCII letters/punctuation, not Unicode.

## Validation and area

Standalone tests, without modifying the shared SSNAIL runner:

```sh
python3 tests/test_shite_number_text.py
python3 tests/test_shite_codec.py
python3 tests/test_shite_cell_text.py
```

They compare RTL against Python integer, binary64 and Decimal results, with
variable-latency eight-byte RAM. Coverage includes I64 extrema, scale retention,
normal/subnormal rounding boundaries, F64 midpoint ties, shortest printing and
reparse, exponent extremes, signed zero, random values, binary FIX display,
half-away display rounding, locale punctuation, cell presentation, capacity and
address bounds, memory errors, abort, and output guards. The codec's 503 cases
run both with numeric fixtures and with actual conversion hardware, with three
extra cases for memory faults and abort during numeric handoff. Numeric
tests include long mantissas whose discarded tail changes a midpoint decision.
The serial extreme-value tests can take several minutes in GHDL.

Production files analyse and synthesize with VHDL-93c; testbenches use 2008.
Initial standalone GHDL/Yosys `synth_xilinx` estimates:

| Component | Estimated logic cells | Flip-flops | RAMB18 | DSP |
|---|---:|---:|---:|---:|
| Shared numeric converter, including its integer engine | 3159 | 1449 | 1 | 0 |
| Scalar cell renderer, excluding that shared service | 708 | 658 | 0 | 0 |

These are synthesis estimates, not routed timing or a proven area minimum.
Instantiate the numeric converter once, not once per client. Formula codec
stack storage is another RAMB18, as documented separately. Further integration
can share the byte RAM adapter/address machinery rather than retaining separate
standalone client adapters where that saves useful area.
