"""Exercise the real benchmark C scheduler with a deterministic SD model."""
import os
import re
from pathlib import Path
import shlex
import shutil
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
        flags = ["-std=c99", "-Wall", "-Wextra", "-Werror"] + shlex.split(os.environ.get("SD_BENCH_HOST_CFLAGS", ""))
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

    def test_menu_card_information_and_bus_selection(self):
        cases = {
            "info-all": "A    Q", "info-bus": "1A    Q", "info-no-mbr": "A    Q",
            "info-error": "C Q", "old-info": "C Q", "legacy-bus": "1B  Q",
            "dual-bus": "1B  Q", "info-init": "N C Q", "info-probe": "P A    Q",
            "info-recover": "X C Q", "limits": "L Q", "info-max": "C Q", "info-sdsc": "C Q",
        }
        for case, keys in cases.items():
            with self.subTest(case=case):
                result = subprocess.run([str(self.binary), case], capture_output=True, text=True,
                                        timeout=10, env={**os.environ, "SD_BENCH_KEYS": keys})
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: " + case, result.stderr)
                if case in ("info-all", "info-bus", "info-no-mbr"):
                    self.assertIn("CAPACITY: 122070.0 MIB", result.stdout)
                    self.assertIn("SERIAL 12345678", result.stdout)
                    self.assertIn("DATE 2023-10", result.stdout)
                    self.assertIn("SD_SPEC 2; BUS WIDTH MASK 5", result.stdout)
                    self.assertIn("SD STATUS $2F (64 BYTES)", result.stdout)
                if case == "info-error": self.assertIn("ERROR 1:", result.stdout)
                if case == "old-info": self.assertIn("CARD INFO COMMANDS NOT SUPPORTED", result.stdout)
                if case == "limits": self.assertIn("SIZE LIMIT OFF", result.stdout)
                if case == "info-max": self.assertIn("512B SECTORS: 4294967296", result.stdout)
                if case == "info-sdsc": self.assertIn("512B SECTORS: 2097152", result.stdout)

    @unittest.skipUnless(shutil.which("cl65") and (ROOT / "src/tools/hyppotest").exists(),
                         "requires cc65 and hyppotest for assembled polling checks")
    def test_assembled_polling_handles_sticky_and_stale_errors(self):
        output = Path(self.temp.name)
        for name in ("sd_read_bench.c", "sd_read_bench_asm.s"):
            shutil.copy(ROOT / "src/utilities" / name, output / name)
        prg, symbols = output / "polling.prg", output / "polling.map"
        subprocess.run(["cl65", "-t", "c64", "-Oirs", "--config",
                        str(ROOT / "src/utilities/util-std.cfg"), "-o", str(prg),
                        "--mapfile", str(symbols), str(output / "sd_read_bench.c"),
                        str(output / "sd_read_bench_asm.s")], check=True)
        address = int(re.search(r"\b_sd_bench_command\s+([0-9A-Fa-f]{6})\s+RLA",
                               symbols.read_text()).group(1), 16)
        image = prg.read_bytes()
        raw = output / "polling.bin"
        raw.write_bytes(image[2:])
        cases = [("success", "$00", "$00", 0, 1),
                 ("sticky error with BUSY", "$42", "$00", 1, 1),
                 ("old error while command starts", "$43 $00", "$00 $01", 0, 2),
                 ("timeout", "$03", "$00 $78", 2, 2),
                 ("timeout across frame wrap", "$03", "$FA $73", 2, 2)]
        script = output / "polling.test"
        script.write_text("\n".join(f'''test "{name}"
load {raw} at ${int.from_bytes(image[:2], "little"):04X}
mock read $FFD3680 {status}
mock read $FFD37FA {clock}
expect write $FFD3680 $02
let a = $02
jsr ${address:04X}
assert a = ${result:02X}
assert x = $00
assert pc = $0001
assert reads $FFD37FA = ${reads:02X}
check writes
test end
''' for name, status, clock, result, reads in cases))
        result = subprocess.run([str(ROOT / "src/tools/hyppotest"), "--output-dir", str(output), str(script)],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("SUMMARY: 5 passed, 0 failed", result.stdout + result.stderr)

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
