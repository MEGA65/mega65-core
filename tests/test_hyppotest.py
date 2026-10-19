"""Run real test scripts through hyppotest, including failure and isolation cases."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class HyppoTestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="mega65-hyppotest-")
        cls.addClassCleanup(cls.build.cleanup)
        cls.binary = Path(cls.build.name) / "hyppotest"
        flags = shlex.split(os.environ.get("HYPPOTEST_CFLAGS", "-g -O1"))
        result = subprocess.run(shlex.split(os.environ.get("CC", "cc")) + flags + [
            str(ROOT / "src/tools/hyppotest.c"), "-lpng", "-o", str(cls.binary)
        ], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)

    def run_script(self, text, expected=0, options=()):
        temp = tempfile.TemporaryDirectory(prefix="case-", dir=self.build.name)
        self.addCleanup(temp.cleanup)
        directory = Path(temp.name)
        script = directory / "case.test"
        script.write_text(text)
        # Exercise spaces and shell punctuation without invoking a shell.
        output = directory / "logs with 'quotes' and $dollars"
        output.mkdir()
        result = subprocess.run([str(self.binary), "--output-dir", str(output),
                                 str(script), *options], cwd=directory,
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertFalse(list(output.glob(".hyppotest-*")))
        return result, output

    def test_failure_exit_and_summary_survive_later_passing_tests(self):
        result, output = self.run_script('''
test "bad register"
let a = $01
ignore all regs
expect a = $02
check registers
test end
test "good register"
let a = $03
ignore all regs
expect a = $03
check registers
test end
''', expected=1)
        self.assertIn("SUMMARY: 1 passed, 1 failed", result.stdout)
        self.assertIn("Register A contains $01 instead of $02",
                      (output / "FAIL.bad_register").read_text())
        self.assertTrue((output / "PASS.good_register").exists())

    def test_anonymous_failure_and_parse_error_exit(self):
        for text in ("let a = $01\nexpect a = $02\ncheck registers\n",
                     "unrecognised directive\n"):
            with self.subTest(text=text):
                self.run_script(text, expected=1)

    def test_test_filter_and_no_match(self):
        script = '''
test "unselected failure"
this must not run
test end
test "selected success"
let a = $42
ignore all regs
expect a = $42
check registers
test end
'''
        result, _ = self.run_script(script, options=("selected success",))
        self.assertIn("SUMMARY: 1 passed, 0 failed", result.stdout)
        result, _ = self.run_script(script, expected=2, options=("missing",))
        self.assertIn("No tests selected", result.stderr)
        self.run_script("# empty suite\n", expected=2)

    def test_memory_isolation_and_repeated_nested_calls(self):
        # Repeated RTS/PLA exercise stack history; repeated calls exercise
        # instruction-history cleanup. Run with sanitizers to catch heap damage.
        text = []
        for i in range(40):
            text.append(f'''
test "fresh machine {i}"
poke $2000 $AD $00 $30 $20 $10 $20 $60
poke $2010 $48 $68 $60
jsr $2000
expect a = $00
ignore reg sp
ignore reg f
expect pc = $0001
check registers
jsr $2000
expect a = $00
ignore reg sp
ignore reg f
expect pc = $0001
check registers
poke $3000 $A5
poke $FFD3680 $5A
test end
''')
        result, _ = self.run_script("".join(text))
        self.assertIn("SUMMARY: 40 passed, 0 failed", result.stdout)

    def test_parallel_logs_are_independent(self):
        processes = []
        for value in (0x12, 0x34):
            directory = Path(self.build.name) / f"parallel-{value}"
            directory.mkdir()
            script = directory / "case.test"
            script.write_text(f'''test "parallel"
define call_{value} as $2000
poke $2000 $A9 ${value:02X} $60
jsr call_{value}
ignore all regs
expect a = ${value:02X}
check registers
test end
''')
            process = subprocess.Popen([str(self.binary), "--output-dir", str(directory), str(script)],
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            processes.append((process, directory, value))
        for process, directory, value in processes:
            stdout, stderr = process.communicate(timeout=20)
            self.assertEqual(process.returncode, 0, stdout + stderr)
            log = (directory / "PASS.parallel").read_text()
            self.assertIn(f"call_{value}", log)
            self.assertFalse(list(directory.glob(".hyppotest-*")))

    def test_assembler_failure_is_a_test_failure(self):
        result, output = self.run_script('''test "assembler failure"
assemble with acme
    rts
end assemble
test end
''', expected=1, options=("--acme", "/no/such/acme"))
        self.assertIn("acme failed", (output / "FAIL.assembler_failure").read_text())

    def test_scripted_reads_hold_last_value_and_ignore_inspection(self):
        self.run_script('''test "read sequence"
define status as $FFD3680
define busy as $02
mock read status busy busy $00
expect write status $01
poke status $A5
assert memory status = $A5
assert memory status = $05 mask $0F
assert reads status = $00
poke $2000 $A9 $01 $8D $80 $D6 $AD $80 $D6 $8D $00 $30 $AD $80 $D6 $8D $01 $30 $AD $80 $D6 $8D $02 $30 $AD $80 $D6 $8D $03 $30 $60
jsr $2000
assert pc = $0001
assert a = $00
assert f = $02 mask $02
assert flag z is set
assert flag n is clear
assert memory $3000 = $02
assert memory $3001 = $02
assert memory $3002 = $00
assert memory $3003 = $00
assert memory status = $01
assert reads status = $04
check writes
test end
''')

    def test_write_expectations_check_global_order_and_ignore_setup(self):
        self.run_script('''test "write order"
expect write $FFD3680 $00
expect write $FFD3681 $05
expect write $FFD3680 $01
poke $FFD3680 $CC
poke $2000 $A9 $00 $8D $80 $D6 $A9 $05 $8D $81 $D6 $A9 $01 $8D $80 $D6 $8D $20 $D0 $60
jsr $2000
check writes
test end
''')

    def test_missing_wrong_extra_and_out_of_order_writes_fail(self):
        cases = [
            ("expect write $FFD3680 $01\n", "Missing write #1"),
            ("expect write $FFD3680 $00\npoke $2000 $A9 $01 $8D $80 $D6 $60\njsr $2000\n", "Write #1"),
            ("expect write $FFD3680 $00\npoke $2000 $A9 $00 $8D $80 $D6 $8D $80 $D6 $60\njsr $2000\n", "Unexpected extra write"),
            ("expect write $FFD3680 $00\nexpect write $FFD3681 $00\npoke $2000 $A9 $00 $8D $81 $D6 $60\njsr $2000\n", "expected $00 to $FFD3680"),
        ]
        for body, message in cases:
            with self.subTest(message=message):
                _, output = self.run_script('test "writes fail"\n' + body + 'test end\n', expected=1)
                self.assertIn(message, (output / "FAIL.writes_fail").read_text())

    def test_mocks_reset_between_tests_and_can_be_replaced(self):
        self.run_script('''test "first mock"
mock read $FFD3680 $11
poke $2000 $AD $80 $D6 $60
jsr $2000
assert a = $11
assert reads $FFD3680 = $01
mock read $FFD3680 $22
jsr $2000
assert a = $22
assert reads $FFD3680 = $01
expect write $FFD3680 $33
poke $2010 $A9 $33 $8D $80 $D6 $60
jsr $2010
test end
test "fresh mocks"
poke $2000 $AD $80 $D6 $60
jsr $2000
assert a = $00
# Previous write expectations must not watch this test.
poke $2010 $A9 $44 $8D $80 $D6 $60
jsr $2010
test end
''')

    def test_assertions_fail_immediately_and_do_not_change_expectations(self):
        for assertion in ("assert a = $02", "assert flag c is set",
                          "assert memory $3000 = $80 mask $80"):
            with self.subTest(assertion=assertion):
                result, output = self.run_script('test "assertion"\n' + assertion + '\ntest end\n', expected=1)
                self.assertIn("Assertion", (output / "FAIL.assertion").read_text())
        self.run_script('''test "expectation unchanged"
let a = $11
ignore all regs
let a = $22
assert a = $22
check registers
test end
''', expected=1)

    def test_bad_new_directives_are_rejected(self):
        for directive in ("mock read $FFD3680", "mock read $FFD3680 $100",
                          "mock read $10000000 $01", "mock read $FFD3680 $01oops",
                          "expect write $FFD3680", "assert reads $FFD3680 = $00",
                          "assert memory $2000 = $00 maks $01", "assert flag q is clear",
                          "assert flag c is maybe", "assert missing = $00",
                          "assert a = $00 mask $100", "check writes extra"):
            with self.subTest(directive=directive):
                self.run_script('test "bad directive"\n' + directive + '\ntest end\n', expected=1)

    def test_mock_limits_fail_without_overrunning_arrays(self):
        cases = [
            ("\n".join(f"mock read ${0x3000 + i:X} $00" for i in range(65)), "Too many read mocks"),
            ("mock read $3000 " + " ".join(["$0"] * 257), "Malformed test directive"),
            (("expect write $3000 " + " ".join(["$0"] * 256) + "\n") * 17, "Too many expected writes"),
        ]
        for body, message in cases:
            with self.subTest(message=message):
                _, output = self.run_script('test "limits"\n' + body + '\ntest end\n', expected=1)
                self.assertIn(message, (output / "FAIL.limits").read_text())

    def test_synchronous_dma_uses_mocks_and_write_expectations(self):
        self.run_script('''test "DMA mock"
mock read $3000 $AA
mock read $3001 $BB
expect write $3100 $AA
expect write $3101 $BB
poke $4000 $00 $02 $00 $00 $30 $00 $00 $31 $00 $00 $00
poke $2000 $A9 $40 $8D $01 $D7 $A9 $00 $8D $02 $D7 $8D $00 $D7 $60
jsr $2000
assert memory $3100 = $AA
assert memory $3101 = $BB
assert reads $3000 = $01
assert reads $3001 = $01
test end
''')

    def test_implicit_test_end_preserves_failure_and_logs(self):
        result, output = self.run_script('''test "first"
assert a = $FF
test "second"
assert a = $00
''', expected=1)
        self.assertIn("SUMMARY: 1 passed, 1 failed", result.stdout)
        self.assertTrue((output / "FAIL.first").exists())
        self.assertTrue((output / "PASS.second").exists())


if __name__ == "__main__":
    unittest.main()
