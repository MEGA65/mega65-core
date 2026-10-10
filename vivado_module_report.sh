#!/usr/bin/env bash
# Run from any working directory; install this file and vivado_module_report.tcl
# into the MEGA65 repository's scripts/ directory (or invoke them in place).
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/vivado_module_report.sh <module> [xpr-or-dcp] [output-dir] [run] [exact-instance]

Examples (from mega65-core root):
  scripts/vivado_module_report.sh ssnail vivado/mega65r6.xpr reports/ssnail
  scripts/vivado_module_report.sh hyperram vivado/mega65r6.xpr reports/hyperram
  scripts/vivado_module_report.sh ssnail vivado/mega65r6.xpr reports/ssnail impl_1
  scripts/vivado_module_report.sh ssnail path/to/post_opt.dcp reports/ssnail-opt
  scripts/vivado_module_report.sh ssnail vivado/mega65r6.xpr reports/ssnail synth_1 m0.machine0/iomapper0/ssnail_gen.ssnail0

Project uses the specified *existing* run, default synth_1. No synthesis/implementation is launched.
For a .dcp, run is ignored. An exact-instance argument resolves duplicate module instances.
USAGE
  exit 2
}
[[ $# -ge 1 && $# -le 5 ]] || usage
module=$1
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# This script normally lives under mega65-core/scripts.
if [[ -x "$here/../vivado_wrapper" ]]; then
  repo=$(cd "$here/.." && pwd -P)
elif [[ -x "$here/vivado_wrapper" ]]; then
  repo=$here
else
  echo "ERROR: could not find vivado_wrapper beside this script or in parent directory" >&2
  exit 2
fi
src=${2:-vivado/mega65r6.xpr}
out=${3:-reports/${module}}
run=${4:-synth_1}
instance=${5:-}
# Resolve relative paths relative to the repo, matching MEGA65 Makefile usage.
[[ $src = /* ]] || src="$repo/$src"
[[ $out = /* ]] || out="$repo/$out"
if [[ ! -f "$src" ]]; then
  echo "ERROR: design input not found: $src" >&2
  exit 2
fi
mkdir -p -- "$out"
out=$(cd -- "$out" && pwd -P)
src=$(realpath -- "$src")
tcl="$here/vivado_module_report.tcl"
[[ -f "$tcl" ]] || { echo "ERROR: $tcl missing" >&2; exit 2; }
echo "Analyzing module '$module' using '$src' (run=$run)"
echo "Output: $out"
cd "$repo"
exec "$repo/vivado_wrapper" \
  -mode batch \
  -log "$out/vivado.log" \
  -journal "$out/vivado.jou" \
  -source "$tcl" \
  -tclargs "$src" "$module" "$out" "$run" "$instance"
