"""Exercise the real benchmark C scheduler with a deterministic SD model."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SDReadBenchmarkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="mega65-sd-bench-")
        cls.addClassCleanup(cls.temp.cleanup)
        output = Path(cls.temp.name)
        cc = shlex.split(os.environ.get("CC", "cc"))
        flags = ["-std=c99", "-Wall", "-Wextra", "-Werror"]
        subprocess.run(cc + flags + ["-DSD_BENCH_HOST_TEST",
                       "-Dmain=sd_read_bench_run", "-c",
                       str(ROOT / "src/utilities/sd_read_bench.c"),
                       "-o", str(output / "bench.o")], check=True)
        cls.binary = output / "bench"
        subprocess.run(cc + flags + [str(ROOT / "tests/sd_read_bench_host.c"),
                       str(output / "bench.o"), "-o", str(cls.binary)], check=True)

    def test_controller_modes_bounds_and_failures(self):
        for case in ("legacy", "native", "uncached", "small", "bad-mbr",
                     "overflow", "stream-error", "read-error", "stopped-clock"):
            with self.subTest(case=case):
                result = subprocess.run([str(self.binary), case], capture_output=True,
                                        text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: " + case, result.stderr)


if __name__ == "__main__":
    unittest.main()
