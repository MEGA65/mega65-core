#!/usr/bin/env python3
"""Runs every SD-over-Ethernet test (#965) and says which passed.

    python3 src/tools/run_netsd_tests.py [--acme PATH] [--hyppotest PATH] [--keep]

  * test_netsd.py, with the C Ascon and again with the pure-Python one
  * tb_ascon_aead128, with vectors from gen_ascon_vectors.py
  * tb_ethernet_netsd (ethernet.vhdl's RMII side of it)
  * tb_sd_eth with sim_netsd.py playing the PC: plain, signed, encrypted, and
    encrypted with a lost and a corrupted frame
  * tb_sd_eth_cache: the sector cache and sdcard_native_dual (G_NET) in front
    of it, encrypted (slow: about 10 minutes)
  * src/hyppo/netsd.test with hyppotest (after assembling Hyppo with acme),
    if both are found (skipped otherwise)

Needs ghdl and a C compiler.  Works in a scratch directory; --keep keeps it.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VHDL = os.path.join(ROOT, "src", "vhdl")
TOOLS = os.path.join(ROOT, "src", "tools")


def run(cmd, cwd, env=None, timeout=1800):
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout + r.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--acme", default=shutil.which("acme") or os.path.join(TOOLS, "acme", "src", "acme"))
    ap.add_argument("--hyppotest", default=os.path.join(TOOLS, "hyppotest"))
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    work = tempfile.mkdtemp(prefix="netsd-tests-")
    results = []

    def note(name, ok, out=""):
        results.append((name, ok))
        print("%s %s" % ("PASS" if ok else "FAIL", name), flush=True)
        if not ok:
            print(out[-3000:])

    # Python
    for env_extra, name in (({}, "test_netsd (C Ascon)"), ({"NETSD_PURE_PYTHON": "1"}, "test_netsd (Python Ascon)")):
        env = dict(os.environ, **env_extra)
        rc, out = run([sys.executable, os.path.join(TOOLS, "test_netsd.py")], work, env)
        note(name, rc == 0, out)

    # Ascon core
    d = os.path.join(work, "ascon")
    os.makedirs(d)
    rc, out = run([sys.executable, os.path.join(TOOLS, "gen_ascon_vectors.py"), "ascon_vectors.txt"], d)
    if rc == 0:
        rc, out = run(["ghdl", "-a", "--std=08", os.path.join(VHDL, "ascon_aead128.vhdl"),
                       os.path.join(VHDL, "tb_ascon_aead128.vhdl")], d)
    if rc == 0:
        rc, out = run(["ghdl", "-e", "--std=08", "tb_ascon_aead128"], d)
    if rc == 0:
        rc, out = run(["ghdl", "-r", "--std=08", "tb_ascon_aead128"], d)
    note("tb_ascon_aead128", rc == 0 and "PASS" in out and "0 errors" in out, out)

    # Ethernet, RMII side
    d = os.path.join(work, "eth")
    os.makedirs(d)
    files = ["debugtools.vhdl", "ghdl_ram8x2048.vhdl", "eth_beacon_ram.vhdl", "crc.vhdl",
             "ethernet_miim.vhdl", "asym_ram.vhdl", "eth_netsd_buf.vhdl", "ethernet.vhdl",
             "tb_ethernet_netsd.vhdl"]
    flags = ["--std=93c", "-fsynopsys", "-frelaxed"]
    rc, out = run(["ghdl", "-a"] + flags + [os.path.join(VHDL, f) for f in files], d)
    if rc == 0:
        rc, out = run(["ghdl", "-e"] + flags + ["tb_ethernet_netsd"], d)
    if rc == 0:
        rc, out = run(["ghdl", "-r"] + flags + ["tb_ethernet_netsd", "--ieee-asserts=disable"], d)
    note("tb_ethernet_netsd", rc == 0 and "PASS" in out and "FAIL" not in out, out)

    # sd_eth against netsd.py
    d = os.path.join(work, "sdeth")
    os.makedirs(d)
    rc, out = run(["ghdl", "-a", "--std=08"] + [os.path.join(VHDL, f) for f in
                  ("ascon_aead128.vhdl", "eth_netsd_buf.vhdl", "sd_eth.vhdl", "tb_sd_eth.vhdl")], d)
    if rc == 0:
        rc, out = run(["ghdl", "-e", "--std=08", "tb_sd_eth"], d)
    for args in (["--flags", "0"], ["--flags", "1"], ["--flags", "3"],
                 ["--flags", "3", "--drop", "15", "--corrupt", "7"]):
        name = "tb_sd_eth " + " ".join(args)
        if rc != 0:
            note(name, False, out)
            continue
        r, o = run([sys.executable, os.path.join(TOOLS, "sim_netsd.py"), d] + args, d)
        note(name, r == 0, o)

    # the sector cache and the dual controller in front of it, as in the core
    d = os.path.join(work, "sdeth_cache")
    os.makedirs(d)
    rc, out = run(["ghdl", "-a", "--std=08", "-fsynopsys"] + [os.path.join(VHDL, f) for f in
                  ("ascon_aead128.vhdl", "sd_eth.vhdl", "sdcard_native.vhdl", "sd_cache.vhdl",
                   "eth_netsd_buf.vhdl", "tb_sd_eth_cache.vhdl")], d)
    if rc == 0:
        rc, out = run(["ghdl", "-e", "--std=08", "-fsynopsys", "tb_sd_eth_cache"], d)
    if rc == 0:
        rc, out = run([sys.executable, os.path.join(TOOLS, "sim_netsd.py"), d, "--tb", "tb_sd_eth_cache",
                       "--flags", "3"], d, timeout=3600)
    note("tb_sd_eth_cache --flags 3", rc == 0, out)

    # Hyppo
    if os.path.exists(a.acme) and os.path.exists(a.hyppotest):
        d = os.path.join(work, "hyppo")
        os.makedirs(os.path.join(d, "bin"))
        os.makedirs(os.path.join(d, "src", "hyppo"))
        ver = os.path.join(ROOT, "src", "version.asm")
        if not os.path.exists(ver):
            run(["sh", os.path.join(ROOT, "src", "version.sh")], os.path.join(ROOT, "src"))
        rc, out = run([a.acme, "--cpu", "m65", "--setpc", "0x8000", "-l", "src/hyppo/HICKUP.sym",
                       "-I", os.path.join(ROOT, "src", "hyppo"), "-DDEBUG_HYPPO=0",
                       os.path.join(ROOT, "src", "hyppo", "main.asm")], d)
        # (main.asm writes bin/HICKUP.M65 relative to the working directory)
        if rc == 0:
            rc, out = run([a.hyppotest, "--output-dir", d, os.path.join(ROOT, "src", "hyppo", "netsd.test")], d)
        note("hyppo netsd.test", rc == 0, out)
    else:
        print("skip hyppo netsd.test (no acme or hyppotest; --acme, --hyppotest)")

    if a.keep:
        print("kept", work)
    else:
        shutil.rmtree(work, ignore_errors=True)
    bad = [n for n, ok in results if not ok]
    print("%d passed, %d failed" % (len(results) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
