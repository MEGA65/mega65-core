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


if __name__ == "__main__":
    unittest.main()
