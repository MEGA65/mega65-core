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
