import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class HardwareCellTextTests(unittest.TestCase):
    def test_cell_text(self):
        if not shutil.which("ghdl"):
            self.skipTest("GHDL is not installed")
        sources = [ROOT / "src/vhdl" / name for name in ["shite_codec_pkg.vhdl", "shite_number_pkg.vhdl",
                   "shite_number_integer.vhdl", "shite_number_text.vhdl", "shite_cell_text.vhdl",
                   "tb_shite_cell_text.vhdl"]]
        with tempfile.TemporaryDirectory(prefix="shite-cell-text-") as work:
            for command in [["ghdl", "-a", "--std=08", *map(str, sources)],
                            ["ghdl", "-e", "--std=08", "tb_shite_cell_text"],
                            ["ghdl", "-r", "--std=08", "tb_shite_cell_text", "--assert-level=error"]]:
                completed = subprocess.run(command, cwd=work, capture_output=True, text=True, timeout=180)
                self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertIn("ALL CELL TEXT TESTS PASSED", completed.stdout)
            print(completed.stdout.strip())


if __name__ == "__main__":
    unittest.main()
