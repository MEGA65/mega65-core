# Testing assembled code with hyppotest

`src/tools/hyppotest` runs MEGA65 machine code in a small interpreter, with
symbols, breakpoints, instruction history and memory/register checks. It
does not simulate SD bus timing or replace the VHDL controller testbenches.

Build the host tool with `make src/tools/hyppotest`. After assembling Hyppo,
run a suite or select one test by its exact name:

```sh
src/tools/hyppotest src/hyppo/sd_read_errors.test
src/tools/hyppotest src/hyppo/sd_read_errors.test 'SD completion with no error succeeds'
```

The exit status is 0 when all selected tests pass, 1 on test/script failure,
and 2 for invocation errors or no selected tests. A failed test stays failed
even if later calls or tests succeed. Scripts without named `test` blocks
are treated as a single anonymous test; an empty suite is an error.

Each named test starts with cleared RAM, I/O state, breakpoints and history.
It writes `PASS.<test_name>` or `FAIL.<test_name>` in the working directory,
with punctuation in the name replaced by underscores. Failed logs include
the screen state; `log on failure` also includes instruction history.

Use `--output-dir DIR` to place logs in an existing directory. Temporary
logs are unique and renamed atomically. For parallel runs, give each run a
separate output directory, so identically named tests retain both logs.
Paths containing spaces or shell punctuation are supported.

Inline `assemble with acme` blocks require an ACME version supporting
`--cpu m65`. Use `--acme /path/to/acme` when that is not the default `acme`
on PATH. Assembler input/output files live in a private temporary directory
under `$TMPDIR` (or `/tmp`) and are removed after each block. The assembler
is invoked directly, without a shell.

The existing interpreter self-tests and host regression tests can be run as:

```sh
src/tools/hyppotest --acme /path/to/acme src/tools/hyppotest-self.test
python3 -m unittest discover -s tests -p test_hyppotest.py -v
```

The host tests compile their own runner. Set `HYPPOTEST_CFLAGS` to add
compiler diagnostics or sanitizers, for example
`-g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer`.

## Scripted reads and write expectations

Mocks and memory assertions use **physical addresses**, just like `poke`.
For example, HYPPO's CPU address `$D680` maps to `$FFD3680`. Symbols loaded
with `loadhypposymbols` already resolve to their physical hypervisor address.
Numbers use `$` hexadecimal notation; symbols and symbol offsets also work.

```text
test "external card becomes ready"
loadhyppo bin/HICKUP.M65
loadhypposymbols src/hyppo/HICKUP.sym
poke $FFD36CC $53 $01
poke printmessage $60
mock read $FFD3680 $1A $1A $1A $18
expect write $FFD3680 $C1 $00 $01
breakpoint check_sd_bus_mode
jmp sd_boot_probe_cards
assert pc = check_sd_bus_mode
assert reads $FFD3680 = $04
check writes
test end
```

`mock read ADDRESS BYTE...` returns one byte per emulated read at that
address, then keeps returning the last byte. The example returns BUSY three
times and READY thereafter. Separate addresses have independent sequences.
Declaring another mock for the same address replaces it and resets its read
count. Each directive accepts up to 256 values, with up to 64 mocked addresses
per test. Code execution and synchronous DMA use the mocks; setup commands,
assertions and screen/instruction diagnostics do not consume them.

`expect write ADDRESS BYTE...` appends writes to one ordered sequence.
Declare expectations before executing the code. All writes to a named
address are checked, including extra writes after the sequence is exhausted;
writes to other addresses are ignored. Ordering across different named
addresses is checked too. Setup `poke`/load/assembly commands do not consume
expectations. Wrong or extra writes stop execution and fail the test. Missing
writes fail at `check writes` or automatically at the end of the test.
There can be up to 4096 expected writes per test.

Mocks override reads independently of backing memory: writing to a mocked
register still updates its backing byte but does not replace its read
sequence. All mocks and write expectations are discarded between tests.

## Immediate assertions

These commands check only the specified value immediately, without a later
`check regs`/`check mem` or changes to the old expected-state snapshot:

```text
assert pc = sd_resetsequence
assert a = $01
assert flag c is set
assert flag v is clear
assert f = $40 mask $40
assert memory $FFD3680 = $40 mask $40
assert memory buffer = $55
assert reads $FFD3680 = $04
```

Register assertions support A, X, Y, Z, B, F, PC, SP, SPL and SPH. PC/SP
comparisons use 16 bits, including when a HYPPO symbol resolves to a physical
address. Flag assertions support C, Z, I, D, B, E, V and N. An optional
`mask` on register/memory assertions compares only those bits.

Memory assertions inspect backing memory, without consuming mock reads.
`assert reads ADDRESS = COUNT` checks the number of reads consumed by that
address's current mock. Assertion failures remain failures even if execution
continues and later assertions pass. Existing `expect`, `ignore` and
`check` directives retain their original snapshot-based behaviour.
