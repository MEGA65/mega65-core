"""Exercise the real benchmark C scheduler with a deterministic SD model."""
import os
import re
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
        for case in ("legacy", "native", "uncached", "small", "stats", "bad-mbr",
                     "overflow", "stream-error", "read-error", "stopped-clock"):
            with self.subTest(case=case):
                trace = Path(self.temp.name) / (case + ".trace")
                result = subprocess.run([str(self.binary), case], capture_output=True,
                                        text=True, timeout=10,
                                        env={**os.environ, "SD_BENCH_TRACE": str(trace)})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: " + case, result.stderr)
                if case in ("legacy", "native", "uncached", "small", "stats"):
                    self.check_workloads(case, result.stdout, trace)

    def check_workloads(self, case, output, trace):
        reads = [(int(op, 16), int(sector)) for op, sector in
                 (line.split() for line in trace.read_text().splitlines())]
        self.assertEqual(reads[0], (2, 0))
        position, cached = 1, False
        window = 2 if case == "small" else 16384
        chunk = min(8, window)
        for line in output.splitlines():
            if line in ("CACHE OFF:", "COMMON $02 READS:"):
                cached = False
            elif line == "CACHE ON (REPEAT IS WARM):":
                cached = True
            match = re.fullmatch(r"(REPEAT \$02|SEQUENTIAL|RANDOM 512B|RANDOM 4K|META \$0B|MULTI 07--09)\s+(\d+)\s+[\d.]+\s+(--|\d+)", line)
            if not match:
                continue
            name, count, retries = match.groups()
            count = int(count)
            if cached and name == "REPEAT $02":
                self.assertEqual(reads[position], (2, 2048))
                position += 1
            workload = reads[position:position + count]
            self.assertEqual(len(workload), count)
            if name == "RANDOM 4K":
                self.assertEqual(count % chunk, 0)
            for i, (op, sector) in enumerate(workload):
                if name == "RANDOM 4K":
                    offset = ((i // chunk) * 509 * chunk & (window - 1)) + i % chunk
                elif name in ("RANDOM 512B", "META $0B"):
                    offset = i * 509 & (window - 1)
                elif name == "REPEAT $02":
                    offset = 0
                else:
                    offset = i & (window - 1)
                self.assertEqual(sector, 2048 + offset, (case, name, i))
                if name != "MULTI 07--09":
                    self.assertEqual(op, 0x0b if name == "META $0B" else 2)
            self.assertEqual(retries, str(3 * count) if case == "stats" else "--")
            position += count
        self.assertEqual(position, len(reads))
        self.assertIn("RANDOM 512B", output)
        self.assertIn("RANDOM 4K", output)


if __name__ == "__main__":
    unittest.main()
