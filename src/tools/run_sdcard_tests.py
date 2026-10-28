#!/usr/bin/env python3
"""Run the SD card controller / cache testbenches (MEGA65/mega65-core#890, #953).

    python3 src/tools/run_sdcard_tests.py            # all variants
    python3 src/tools/run_sdcard_tests.py cache      # only names containing "cache"
    python3 src/tools/run_sdcard_tests.py -j 4 --keep
    python3 src/tools/run_sdcard_tests.py --vhdl /tmp/old/src/vhdl   # other sources

The sources are copied first, so editing them during a run does no harm.

Needs ghdl.  Each variant is a testbench plus generics; it passes when the
testbench reports "ALL ... TESTS PASSED" and no FAIL:, error or failure
report.

- tb_sdcard_native and tb_sd_cache are built as VHDL-2008.
- tb_sdcardio_native is built as VHDL-93 with -frelaxed, like the rest of
  the design.  For that, every source in src/vhdl is imported, except
  testbenches and files needing Xilinx libraries (reconfig.vhdl gets a
  stub UNISIM ICAPE2; icape2sim.vhdl's entity of the same name is left
  out).
"""

import argparse
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VHDL = os.path.join(ROOT, "src", "vhdl")     # (a snapshot of it, once main() runs)

# (name, testbench, generics, stop time)
VARIANTS = [
    ("native", "tb_sdcard_native", [], "200ms"),
    ("native-spi", "tb_sdcard_native", ["G_SPI_CARD=true"], "300ms"),
    ("native-stop", "tb_sdcard_native", ["G_STOP_TEST=true"], "300ms"),
    ("native-single-crc", "tb_sdcard_native", ["G_SINGLE_CRC_TEST=true"], "300ms"),
    ("native-long-read", "tb_sdcard_native", ["G_LONG_READ_NAC=40000"], "300ms"),
    ("native-info", "tb_sdcard_native", ["G_INFO_TEST=true"], "300ms"),
    ("native-info-crc", "tb_sdcard_native", ["G_INFO_TEST=true", "G_INFO_BAD_CRC=true"], "300ms"),
    ("native-info-timeout", "tb_sdcard_native", ["G_INFO_TEST=true", "G_INFO_TIMEOUT=true"], "300ms"),
    ("native-info-header", "tb_sdcard_native", ["G_INFO_TEST=true", "G_INFO_BAD_HEADER=true"], "300ms"),
    ("native-bound", "tb_sdcard_native", ["G_BOUND_TEST=true"], "300ms"),
    ("native-bound-sdsc", "tb_sdcard_native", ["G_BOUND_TEST=true", "G_SDHC_CARD=false"], "300ms"),
    ("native-maxcard", "tb_sdcard_native", ["G_MAXCARD_TEST=true"], "300ms"),
    ("native-capfail", "tb_sdcard_native", ["G_CAPFAIL_TEST=true"], "300ms"),
    ("cache", "tb_sd_cache", [], "500ms"),
    ("cache-dual", "tb_sd_cache", ["G_DUAL_TEST=true"], "500ms"),
    ("cache-dual-spi0", "tb_sd_cache", ["G_DUAL_TEST=true", "G_DUAL_SPI0=true"], "800ms"),
    ("cache-dual-spi1", "tb_sd_cache", ["G_DUAL_TEST=true", "G_DUAL_SPI1=true"], "800ms"),
    ("cache-rom", "tb_sd_cache", ["G_ROM_TEST=true", "G_LINES=16"], "2000ms"),
    ("cache-dup", "tb_sd_cache", ["G_DUP_TEST=true", "G_LINES=8"], "300ms"),
    ("cache-close", "tb_sd_cache", ["G_CLOSE_TEST=true"], "500ms"),
    ("cache-fast-card", "tb_sd_cache", ["G_NAC=6", "G_NAC_MULTI=0"], "500ms"),
    ("cache-no-hs", "tb_sd_cache", ["G_HS_OK=false"], "800ms"),
    ("io", "tb_sdcardio_native", [], "500ms"),
    ("io-boot", "tb_sdcardio_native", ["G_BOOT_TEST=true"], "500ms"),
    ("io-error", "tb_sdcardio_native", ["G_ERROR_TEST=true"], "500ms"),
    ("io-nocache", "tb_sdcardio_native", ["G_CACHE_LINES=0"], "500ms"),
    ("io-spi", "tb_sdcardio_native", ["G_SPI_CARD=true"], "800ms"),
    ("io-dual", "tb_sdcardio_native", ["G_DUAL_TEST=true", "G_CARD1_PRESENT=true"], "800ms"),
    ("io-dual-card1", "tb_sdcardio_native", ["G_DUAL_TEST=true", "G_CARD0_PRESENT=false",
                                              "G_CARD1_PRESENT=true"], "800ms"),
    ("io-dual-card0", "tb_sdcardio_native", ["G_DUAL_TEST=true"], "800ms"),
    ("io-dual-spi1", "tb_sdcardio_native", ["G_DUAL_TEST=true", "G_CARD1_PRESENT=true",
                                             "G_CARD1_SPI=true"], "800ms"),
    ("io-info", "tb_sdcardio_native", ["G_INFO_TEST=true"], "500ms"),
    ("io-info-crc", "tb_sdcardio_native", ["G_INFO_TEST=true", "G_INFO_BAD_CRC=true"], "500ms"),
    ("io-bound", "tb_sdcardio_native", ["G_BOUND_TEST=true"], "800ms"),
    ("io-tail", "tb_sdcardio_native", ["G_TAIL_TEST=true"], "800ms"),
    ("io-reinit", "tb_sdcardio_native", ["G_REINIT_TEST=true"], "800ms"),
    ("io-spi23", "tb_sdcardio_native", ["G_SPI23_TEST=true"], "400ms"),
    ("io-stream", "tb_sdcardio_native", ["G_STREAM_TEST=true"], "800ms"),
    ("io-f011", "tb_sdcardio_native", ["G_F011_TEST=true"], "800ms"),
]

UNISIM_STUB = """
library ieee;
use ieee.std_logic_1164.all;
package vcomponents is
  component ICAPE2 is
    generic (DEVICE_ID : bit_vector := X"03651093"; ICAP_WIDTH : string := "X32";
             SIM_CFG_FILE_NAME : string := "NONE");
    port (O : out std_logic_vector(31 downto 0); CLK : in std_ulogic; CSIB : in std_ulogic;
          I : in std_logic_vector(31 downto 0); RDWRB : in std_ulogic);
  end component;
end package;
"""

NATIVE_08 = ["sdcard_native.vhdl", "sdcard_native_model.vhdl", "sd_cache.vhdl"]


def run(cmd, cwd, log=None):
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if log:
        with open(log, "a") as f:
            f.write("$ " + " ".join(cmd) + "\n" + p.stdout)
    return p.returncode, p.stdout


def build_08(work, tb):
    os.makedirs(work, exist_ok=True)
    files = [os.path.join(VHDL, f) for f in NATIVE_08 + [tb + ".vhdl"]]
    rc, out = run(["ghdl", "-a", "--std=08", "-fsynopsys"] + files, work, os.path.join(work, "build.log"))
    if rc:
        return False, out
    rc, out = run(["ghdl", "-e", "--std=08", "-fsynopsys", tb], work, os.path.join(work, "build.log"))
    return rc == 0, out


def build_93(work, tb):
    os.makedirs(work, exist_ok=True)
    stub = os.path.join(work, "unisim_stub.vhdl")
    with open(stub, "w") as f:
        f.write(UNISIM_STUB)
    log = os.path.join(work, "build.log")
    rc, out = run(["ghdl", "-a", "--std=93c", "-fsynopsys", "--work=unisim", "--workdir=" + work, stub],
                  work, log)
    if rc:
        return False, out
    for name in sorted(os.listdir(VHDL)):
        if not name.endswith((".vhdl", ".vhd")):
            continue
        if name.startswith(("tb_", "test_")) or name.endswith("_tb.vhdl") or name == "icape2sim.vhdl":
            continue
        path = os.path.join(VHDL, name)
        with open(path, errors="replace") as f:
            text = f.read()
        if re.search(r"^\s*library\s+(unisim|xpm)\s*;", text, re.M | re.I) and name != "reconfig.vhdl":
            continue
        run(["ghdl", "-i", "--std=93c", "-fsynopsys", "-frelaxed", "--workdir=" + work, path], work)
    run(["ghdl", "-i", "--std=93c", "-fsynopsys", "-frelaxed", "--workdir=" + work,
         os.path.join(VHDL, tb + ".vhdl")], work)
    rc, out = run(["ghdl", "-m", "--std=93c", "-fsynopsys", "-frelaxed", "--workdir=" + work, "-P" + work,
                   "-Wno-binding", "-Wno-hide", "-Wno-others", "-Wno-library", "-Wno-shared", tb], work, log)
    return rc == 0, out


def run_variant(work, variant):
    name, tb, generics, stop = variant
    if tb == "tb_sdcardio_native":
        cmd = ["ghdl", "-r", "--std=93c", "-fsynopsys", "-frelaxed", "--workdir=" + work, "-P" + work, tb]
    else:
        cmd = ["ghdl", "-r", "--std=08", "-fsynopsys", tb]
    cmd += ["-g" + g for g in generics] + ["--stop-time=" + stop]
    t0 = time.time()
    rc, out = run(cmd, work)
    with open(os.path.join(work, name + ".log"), "w") as f:
        f.write(out)
    bad = [l for l in out.splitlines()
           if "FAIL:" in l or "TESTS FAILED" in l or "(report error)" in l or "(report failure)" in l
           or "(assertion error)" in l or "(assertion failure)" in l or ": error:" in l]
    passed = bool(re.search(r"ALL [A-Z0-9 ]*TESTS PASSED", out)) and not bad
    fails = [l.split("): ")[-1][:100] for l in bad][:3]
    return name, passed, time.time() - t0, fails


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("only", nargs="*", help="run only variants whose name contains one of these")
    ap.add_argument("-j", type=int, default=os.cpu_count() or 4, help="parallel runs")
    ap.add_argument("--keep", action="store_true", help="keep the work directory")
    ap.add_argument("--vhdl", default=os.path.join(ROOT, "src", "vhdl"), help="the VHDL sources")
    args = ap.parse_args()
    if not shutil.which("ghdl"):
        sys.exit("ghdl not found")
    variants = [v for v in VARIANTS if not args.only or any(o in v[0] for o in args.only)]
    top = tempfile.mkdtemp(prefix="sdcard-tests-")
    global VHDL
    VHDL = os.path.join(top, "src")
    shutil.copytree(args.vhdl, VHDL, ignore=shutil.ignore_patterns("*.o", "*.cf", "*.prg", "*.png"))
    works = {}
    ok = True
    for tb in sorted({v[1] for v in variants}):
        work = os.path.join(top, tb)
        built, out = (build_93 if tb == "tb_sdcardio_native" else build_08)(work, tb)
        if not built:
            print("BUILD FAILED: %s\n%s" % (tb, "\n".join(out.splitlines()[-20:])))
            ok = False
        works[tb] = work if built else None
    jobs = [(works[v[1]], v) for v in variants if works[v[1]]]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.j) as ex:
        for name, passed, secs, fails in ex.map(lambda a: run_variant(*a), jobs):
            print("%-4s %-22s %6.0fs  %s" % ("PASS" if passed else "FAIL", name, secs,
                                              "" if passed else " | ".join(fails)))
            ok = ok and passed
    if args.keep or not ok:
        print("logs in", top)
    else:
        shutil.rmtree(top)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
