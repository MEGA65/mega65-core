#!/usr/bin/env python3
"""Run every SSNAIL and LUMP testbench (and optionally the PC-tool tests).

    ./run_ssnail_tests.py                       # all VHDL testbenches
    ./run_ssnail_tests.py --tools ../ssnail_tools   # ... plus the Python tool tests
    ./run_ssnail_tests.py tb_ssnail_step1        # just the named benches
    ./run_ssnail_tests.py --list

Builds in a scratch directory with GHDL (VHDL-93, as mega65-core), so the
source tree is never touched.  Exits non-zero if anything fails.

Needs: ghdl, python3, git.  tb_ssnail_step1 also needs the SSNAIL tools (they
generate its test program and expected results with the reference emulator).
They are taken from ./SSNAIL, a plain clone of github.com/mega65/SSNAIL (not a
submodule), which is made on first use; --update pulls it, and --tools or
SSNAIL_TOOLS point at a checkout elsewhere.  Add SSNAIL/ to .gitignore.

Testbenches:
    tb_sdram_lump     LUMP port on sdram_controller (identical_clocks=1)
    tb_sdram_train    SDRAM read capture training: arbitrary capture clock
                      phase and board delays, retraining, manual steps
    tb_ssnail         SSNAIL shell: COPY/SYNC/HALT, faults, STEP, IRQ
    tb_ssnail_load    load port: segments, unaligned blocks, masking, ERROR
    tb_ssnail_step1   scalar/control instructions vs the reference emulator
    tb_ssnail_fpu     the FP unit, bit-exact against numpy (83k vectors)
    tb_ssnail_step2   DEQROW (all formats), VADD, VMUL, CVT16 vs the emulator's
                      hardware-numerics mode
    tb_ssnail_step3   GEMV (Q8_0, Q4_0, accumulate, F16 output) vs the same
    tb_ssnail_step4   RMSNORM, LAYERNORM, SILUMUL, GELU, MEANROWS vs the same
    tb_ssnail_step5   ROPE, ARGMAX, ATTN (F16/F32 KV, grouped-query) vs the same
    tb_ssnail_perf    GEMV v2 results and speed (fails if more than 25% slower)
    tb_hyperram_lump  the real HyperRAM controller with the Cypress device
                      model: CPU path and LUMP reads/writes in slow mode
                      ($60, the R6 today), fast reads ($62), fast command
                      and reads ($63) and all fast ($67); and CR0 set from
                      the MEGA65 side ($BFFFFF8/9): 3 clocks slow, 6 fixed fast

Not covered: the HyperRAM LUMP port (the s27kl0641 model needs the IEEE
VITAL libraries, which most GHDL builds lack).
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

GHDL_FLAGS = ["--std=93c", "-fexplicit", "-fsynopsys"]
COMMON = ["debugtools.vhdl", "cputypes.vhdl", "lump_queue.vhdl"]
VITAL_URL = "https://raw.githubusercontent.com/ghdl/ghdl/master/libraries/vital2000/"
VITAL_FILES = ["timing_p.vhdl", "timing_b.vhdl", "prmtvs_p.vhdl", "prmtvs_b.vhdl",
               "memory_p.vhdl", "memory_b.vhdl"]


# name: (sources after COMMON, top entity, [generic sets], success marker)
BENCHES = {
    # identical_clocks=1 only: the bench's identical_clocks=0 mode fakes
    # clock162r as an inverted clock, which shifts the controller's existing
    # CPU read path and the LUMP path alike by one word -- not representative
    # of the hardware's real phase-shifted clock.
    "tb_sdram_lump": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "tb_sdram_lump.vhdl"],
                      "tb_sdram_lump", [["-gidentical=1"]],
                      r"ALL SDRAM LUMP TESTS PASSED"),
    # Read capture training: the capture clock starts at an arbitrary phase
    # (as after every MMCM lock), with various board delays; and with no
    # phase shifter connected (training skipped, old behaviour).
    "tb_sdram_train": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "tb_sdram_train.vhdl"],
                       "tb_sdram_train",
                       [["-gphi0_ps=0", "-gdm_ps=4000", "--stop-time=4ms"],
                        ["-gphi0_ps=2500", "-gdm_ps=3500", "--stop-time=4ms"],
                        ["-gphi0_ps=4100", "-gdm_ps=1500", "--stop-time=4ms"],
                        ["-gphi0_ps=1300", "-gdm_ps=5600", "--stop-time=4ms"],
                        ["-gphi0_ps=5000", "-gdm_ps=2500", "-gxw_ps=3500", "--stop-time=4ms"],
                        ["-gno_ps=1", "--stop-time=4ms"],
                        ["-gforce_h1c0=1", "--stop-time=4ms"],
                        ["-gboot=1", "--stop-time=4ms"]],
                       r"ALL SDRAM TRAINING TESTS PASSED"),
    "tb_ssnail": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl", "ssnail_tables_pkg.vhdl", "ssnail.vhdl",
                   "tb_ssnail.vhdl"], "tb_ssnail", [[]], r"TB_SSNAIL COMPLETE"),
    "tb_ssnail_load": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl", "ssnail_tables_pkg.vhdl", "ssnail.vhdl",
                        "tb_ssnail_load.vhdl"], "tb_ssnail_load", [[]],
                       r"TB_SSNAIL_LOAD: ALL PASSED"),
    "tb_ssnail_step1": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl",
                         "ssnail_tables_pkg.vhdl", "ssnail.vhdl", "step1_pkg.vhdl", "tb_ssnail_step1.vhdl"],
                        "tb_ssnail_step1", [[]], r"TB_SSNAIL_STEP1: ALL PASSED"),
    "tb_ssnail_fpu": (["ssnail_fpu.vhdl", "tb_ssnail_fpu.vhdl"], "tb_ssnail_fpu", [[]],
                      r"TB_SSNAIL_FPU: ALL PASSED"),
    "tb_ssnail_step2": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl",
                         "ssnail_tables_pkg.vhdl", "ssnail.vhdl", "step2_pkg.vhdl", "tb_ssnail_step2.vhdl"],
                        "tb_ssnail_step2", [[]], r"TB_SSNAIL_STEP2: ALL PASSED"),
    "tb_ssnail_step3": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl",
                         "ssnail_tables_pkg.vhdl", "ssnail.vhdl", "step3_pkg.vhdl", "tb_ssnail_step3.vhdl"],
                        "tb_ssnail_step3", [[]], r"TB_SSNAIL_STEP3: ALL PASSED"),
    "tb_ssnail_step4": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl",
                         "ssnail_tables_pkg.vhdl", "ssnail.vhdl", "step4_pkg.vhdl",
                         "tb_ssnail_step4.vhdl"],
                        "tb_ssnail_step4", [[]], r"TB_SSNAIL_STEP4: ALL PASSED"),
    "tb_ssnail_step5": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl",
                         "ssnail_tables_pkg.vhdl", "ssnail.vhdl", "step5_pkg.vhdl",
                         "tb_ssnail_step5.vhdl"],
                        "tb_ssnail_step5", [[]], r"TB_SSNAIL_STEP5: ALL PASSED"),
    "tb_ssnail_perf": (["sdram_controller.vhdl", "is42s16320f_model.vhdl", "ssnail_fpu.vhdl",
                        "ssnail_tables_pkg.vhdl", "ssnail.vhdl", "perf_pkg.vhdl",
                        "tb_ssnail_perf.vhdl"],
                       "tb_ssnail_perf", [[]], r"TB_SSNAIL_PERF: ALL PASSED"),
}
BENCHES["tb_hyperram_lump"] = (
    VITAL_FILES + ["gen_utils.vhdl", "conversions.vhdl", "s27kl0641.vhdl", "hyperram.vhdl",
                   "tb_hyperram_lump.vhdl"],
    "tb_hyperram_lump",
    [["-gmode=96", "--stop-time=600us"],      # $60: slow (the R6's setting today)
     ["-gmode=98", "--stop-time=600us"],      # $62: fast reads
     ["-gmode=99", "--stop-time=600us"],      # $63: fast command and reads
     ["-gmode=103", "--stop-time=600us"],     # $67: everything fast
     # CR0 written via $BFFFFF8/9, write latencies set automatically:
     ["-gmode=96", "-gcr0=65510", "--stop-time=600us"],   # slow, 3 clocks variable ($FFE6)
     ["-gmode=103", "-gcr0=65310", "--stop-time=600us"],  # fast, 6 clocks fixed ($FF1E)
     # Chained CPU writes in fast mode (3 clocks makes the controller chain
     # them here): the chained-fetch bug lost a byte every few lines
     ["-gmode=103", "-gcr0=65510", "-gn1=256", "--stop-time=900us"],
     # ... and at the default 4 clocks with back-to-back writes, as DMA does
     # (the old controller lost 127 of 1024 bytes here)
     ["-gmode=103", "-gn1=512", "-gwgap=0", "--stop-time=900us"]],
    r"TB_HYPERRAM_LUMP: ALL PASSED")

# Generated inputs: file -> (generator script, needs the SSNAIL tools)
GENERATED = {
    "step1_pkg.vhdl": ("gen_step1.py", True),
    "step2_pkg.vhdl": ("gen_step2.py", True),
    "step3_pkg.vhdl": ("gen_step3.py", True),
    "step4_pkg.vhdl": ("gen_step4.py", True),
    "step5_pkg.vhdl": ("gen_step5.py", True),
    "perf_pkg.vhdl": ("gen_perf.py", True),
    "fpu_vectors.txt": ("gen_fpu_vectors.py", False),
}
NEEDS_DATA = {"tb_ssnail_fpu": ["fpu_vectors.txt"]}
# Things a passing run must not print
BAD = re.compile(r"\(report error\)|\(assertion error\)|\(report failure\)|"
                 r"\(assertion failure\)|^FAIL|bound check failure|"
                 r"cannot find entity", re.M)

# The SDRAM model needs two local changes for GHDL/VHDL-93: to_string() of
# unsigned values, and a smaller memory array (the full 32M-word array of
# signals exhausts GHDL's memory).  Applied to the scratch copy only.
# The HyperRAM device model (s27kl0641.vhdl, from mega65-core) needs the
# VITAL packages, which some GHDL builds (e.g. Debian's) leave out.  They are
# fetched from GHDL's repository once, cached, and compiled into work along
# with the model's support packages.

# Benches whose designs print a great deal: keep only these lines (and errors)
LOG_FILTER = {"tb_hyperram_lump": re.compile(r"tb_hyperram_lump\.vhdl|LUMP: Timed")}

MODEL_PATCHES = [
    ("gen_utils.vhdl", "IEEE.VITAL_primitives", "work.VITAL_primitives"),
    ("gen_utils.vhdl", "IEEE.VITAL_timing", "work.VITAL_timing"),
    ("is42s16320f_model.vhdl", "to_string(addr)", "to_string(std_logic_vector(addr))"),
    ("is42s16320f_model.vhdl", "to_string(cmd)", "to_string(std_logic_vector(cmd))"),
    ("is42s16320f_model.vhdl", "array(0 to (1*1024*1024-1))", "array(0 to (64*1024-1))"),
    # (64K words, so wrap addresses: the read training uses the top row)
    ("is42s16320f_model.vhdl", "ram_array(to_integer(row_addr & col_addr))",
     "ram_array(to_integer(row_addr & col_addr) mod 65536)"),
    ("is42s16320f_model.vhdl", "ram_array(to_integer(write_queue_addr(0)))",
     "ram_array(to_integer(write_queue_addr(0)) mod 65536)"),
]


SSNAIL_REPO = "https://github.com/mega65/SSNAIL.git"
CHECKOUT = "SSNAIL"          # sub-directory (a plain clone, not a submodule)


def tools_in(d):
    """The tools directory within a checkout: its top level, or ssnail_tools/."""
    for c in (d, os.path.join(d, "ssnail_tools")):
        if os.path.exists(os.path.join(c, "ssnail_isa.py")):
            return c
    return None


def find_tools(here, repo, update):
    """$SSNAIL_TOOLS / --tools are handled by the caller.  Otherwise use (and
    clone if needed) the SSNAIL repository in ./SSNAIL next to this script."""
    co = os.path.join(here, CHECKOUT)
    if not os.path.isdir(co):
        print(f"cloning {repo} into {co} ...")
        r = subprocess.run(["git", "clone", "-q", repo, co], capture_output=True, text=True)
        if r.returncode:
            print("git clone failed:\n" + r.stderr.strip())
            return None
    elif update and os.path.isdir(os.path.join(co, ".git")):
        r = subprocess.run(["git", "-C", co, "pull", "-q", "--ff-only"],
                           capture_output=True, text=True)
        print(f"updated {co}" if r.returncode == 0 else
              f"warning: git pull in {co} failed:\n{r.stderr.strip()}")
    return tools_in(co)


# What the testbenches need from the SSNAIL tools: (module, attribute or None)
TOOLS_NEEDED = [("ssnail_isa", "CVT16"), ("ssnail_isa", "GEMV_F16OUT"), ("ssnail_hw", None),
                ("ssnail_hw", "roundf"),      # exact roundf in Q8_0 quantisation (step 3)
                ("ssnail_isa", "SD_END")]     # one memory layout, SDRAM first


def tools_too_old(tools):
    """None if the tools have what the benches need, else a description."""
    r = subprocess.run([sys.executable, "-c",
                        "import importlib, sys; sys.path.insert(0, sys.argv[1]); missing = []\n"
                        "for mod, attr in " + repr(TOOLS_NEEDED) + ":\n"
                        "    try:\n"
                        "        m = importlib.import_module(mod)\n"
                        "        if attr and not hasattr(m, attr): missing.append(mod + '.' + attr)\n"
                        "    except Exception: missing.append(mod)\n"
                        "print(' '.join(missing))", tools],
                       capture_output=True, text=True)
    missing = r.stdout.strip()
    return missing or None


def fetch_vital(build):
    """Put the retargeted VITAL sources in build (cached in ~/.cache)."""
    import urllib.request
    cache = os.path.join(os.path.expanduser("~"), ".cache", "ssnail-tests", "vital")
    os.makedirs(cache, exist_ok=True)
    for f in VITAL_FILES:
        c = os.path.join(cache, f)
        if not os.path.exists(c):
            text = urllib.request.urlopen(VITAL_URL + f, timeout=60).read().decode("latin-1")
            text = re.sub(r"IEEE\.VITAL_", "work.VITAL_", text, flags=re.I)
            open(c, "w", encoding="latin-1").write(text)
        shutil.copy(c, build)


def run_filtered(cmd, cwd, keep, timeout):
    """Run, keeping only lines matching keep (or BAD): some designs print
    hundreds of megabytes of debug output."""
    p = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace")
    kept, t0 = [], time.time()
    for line in p.stdout:
        if keep.search(line) or BAD.search(line):
            kept.append(line)
        if time.time() - t0 > timeout:
            p.kill()
            kept.append("(timed out)\n")
            break
    p.wait()
    return p.returncode, "".join(kept)


def find(name, dirs):
    for d in dirs:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("benches", nargs="*", help="testbenches to run (default: all)")
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--vhdl", action="append", default=[],
                    help=f"directory with the VHDL sources (repeatable; default: {here})")
    ap.add_argument("--tools", default=os.environ.get("SSNAIL_TOOLS"),
                    help="SSNAIL tools directory (default: ./SSNAIL, cloned from "
                         "--repo if absent); needed for tb_ssnail_step1, and its Python "
                         "tests are run too")
    ap.add_argument("--repo", default=SSNAIL_REPO,
                    help=f"where to clone the SSNAIL tools from (default {SSNAIL_REPO})")
    ap.add_argument("--update", action="store_true",
                    help="git pull the ./SSNAIL checkout before testing")
    ap.add_argument("--keep", action="store_true", help="keep the build directory")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        print("\n".join(BENCHES))
        return 0
    if not shutil.which("ghdl"):
        sys.exit("ghdl not found")
    srcdirs = [os.path.abspath(d) for d in (args.vhdl or [here])]
    if not args.tools:
        args.tools = find_tools(here, args.repo, args.update)
    if args.tools:
        print(f"using SSNAIL tools at {args.tools}")
    names = args.benches or list(BENCHES)
    for n in names:
        if n not in BENCHES:
            sys.exit(f"unknown testbench {n}; --list shows them")

    build = tempfile.mkdtemp(prefix="ssnail-tests-")
    results = []
    try:
        # Gather sources into the build directory
        needed = set(COMMON)
        for n in names:
            needed.update(BENCHES[n][0])
            needed.update(NEEDS_DATA.get(n, []))
        missing = []
        if needed & set(VITAL_FILES):
            try:
                fetch_vital(build)
            except Exception as e:
                missing.append(f"the VITAL packages ({e}); they come from {VITAL_URL}")
            open(os.path.join(build, "s27kl0641.mem"), "w").close()   # model preload: none
        for f in sorted(needed):
            if f in GENERATED or f in VITAL_FILES:
                continue
            p = find(f, srcdirs)
            if p is None:
                missing.append(f)
            else:
                shutil.copy(p, build)
        for f, old, new in MODEL_PATCHES:
            p = os.path.join(build, f)
            if os.path.exists(p):
                s = open(p).read().replace(old, new)
                open(p, "w").write(s)
        if args.tools and any(GENERATED[f][1] for f in needed & set(GENERATED)):
            old = tools_too_old(args.tools)
            if old:
                sys.exit(f"The SSNAIL tools at {args.tools} are older than these testbenches "
                         f"(missing: {old}).\nUpdate the SSNAIL repository with the current "
                         f"tools, then run with --update (or git pull in {args.tools}).")
        for f in sorted(needed & set(GENERATED)):
            gscript, needs_tools = GENERATED[f]
            gen = find(gscript, srcdirs)
            if not gen:
                missing.append(f"{gscript} (generates {f})")
                continue
            if needs_tools and not args.tools:
                missing.append(f"the SSNAIL tools (for {f}): ./SSNAIL could not be cloned; "
                               "check access to the repo, or give a checkout with --tools DIR "
                               "or SSNAIL_TOOLS")
                continue
            env = dict(os.environ)
            if args.tools:
                env["SSNAIL_TOOLS"] = os.path.abspath(args.tools)
            r = subprocess.run([sys.executable, gen], cwd=build, env=env,
                               capture_output=True, text=True)
            if r.returncode:
                sys.exit(f"{gscript} failed:\n" + r.stdout + r.stderr)
        if missing:
            sys.exit("missing: " + ", ".join(missing))

        def ghdl(cmd, *rest):
            return subprocess.run(["ghdl", cmd, *GHDL_FLAGS, *rest],
                                  cwd=build, capture_output=True, text=True)

        for n in names:
            srcs, top, gensets, marker = BENCHES[n]
            for f in COMMON + srcs:
                r = ghdl("-a", f)
                if r.returncode:
                    results.append((n, False, f"analysis of {f} failed:\n{r.stderr[-2000:]}"))
                    break
            else:
                r = ghdl("-e", top)
                if r.returncode:
                    results.append((n, False, "elaboration failed:\n" + r.stderr[-2000:]))
                    continue
                for g in gensets:
                    label = n + (" " + " ".join(g) if g else "")
                    t0 = time.time()
                    cmd = ["ghdl", "-r", *GHDL_FLAGS, top, *g, "--ieee-asserts=disable"]
                    if n in LOG_FILTER:
                        rc, log = run_filtered(cmd, build, LOG_FILTER[n], 1800)
                        r = subprocess.CompletedProcess(cmd, rc)
                    else:
                        r = subprocess.run(cmd, cwd=build, capture_output=True, text=True,
                                           timeout=1800)
                        log = r.stdout + r.stderr
                    open(os.path.join(build, label.replace(" ", "_") + ".log"), "w").write(log)
                    ok = r.returncode == 0 and re.search(marker, log) and not BAD.search(log)
                    detail = f"{time.time() - t0:.0f}s"
                    if not ok:
                        bad = [l for l in log.splitlines() if BAD.search(l)][:8]
                        detail += "\n    " + "\n    ".join(bad or ["(completion marker missing)"])
                    results.append((label, bool(ok), detail))

        tabs = find("ssnail_tables_pkg.vhdl", srcdirs)
        gtab = find("gen_tables.py", srcdirs)
        if args.tools and tabs and gtab:
            r = subprocess.run([sys.executable, gtab, "--check"], cwd=os.path.dirname(tabs),
                               env=dict(os.environ, SSNAIL_TOOLS=os.path.abspath(args.tools)),
                               capture_output=True, text=True)
            results.append(("ssnail_tables_pkg.vhdl in sync with tools", r.returncode == 0,
                            "" if r.returncode == 0 else (r.stdout + r.stderr).strip()))
        if args.tools:
            r = subprocess.run(["make", "-s", "-C", args.tools, "test"],
                               capture_output=True, text=True)
            out = r.stdout + r.stderr
            ok = r.returncode == 0 and "FAIL" not in out
            results.append(("ssnail_tools: make test", ok,
                            "" if ok else out[-2000:]))
    finally:
        if args.keep:
            print(f"build directory kept: {build}")
        else:
            shutil.rmtree(build, ignore_errors=True)

    print()
    for label, ok, detail in results:
        print(f"{'PASS' if ok else 'FAIL'}  {label:36s} {detail}")
    allok = all(ok for _, ok, _ in results)
    print("\nALL PASSED" if allok else "\nFAILURES")
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())
