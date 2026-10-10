#!/usr/bin/env bash
# Run from any working directory; install this file and vivado_module_report.tcl
# into the MEGA65 repository's scripts/ directory (or invoke them in place).
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  scripts/vivado_module_report.sh <module> [target] [output-dir] [run] [exact-instance]

Examples (from mega65-core root):
  scripts/vivado_module_report.sh ssnail mega65r6
  scripts/vivado_module_report.sh hyperram mega65r6
  scripts/vivado_module_report.sh ssnail mega65r6 reports/ssnail-baseline
  scripts/vivado_module_report.sh ssnail mega65r6 reports/ssnail-impl impl_1
  scripts/vivado_module_report.sh ssnail path/to/post_opt.dcp reports/ssnail-opt
  scripts/vivado_module_report.sh ssnail mega65r6 reports/ssnail synth_1 m0.machine0/iomapper0/ssnail_gen.ssnail0

The target defaults to mega65r6 and resolves to vivado/<target>.xpr.
Output defaults to reports/<module> (relative to the repo root).
Explicit .xpr paths and .dcp checkpoint paths are also accepted.
Only an existing run is opened (default synth_1); no synthesis/implementation is launched.
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
target=${2:-mega65r6}
out=${3:-reports/${module}}
run=${4:-synth_1}
instance=${5:-}
# Bare target names refer to vivado/<target>.xpr. Also accept bare .xpr
# filenames, explicit project paths, and checkpoint paths for compatibility.
case "$target" in
  */*|*.dcp) src=$target ;;
  *.xpr)    src="vivado/$target" ;;
  *)        src="vivado/$target.xpr" ;;
esac
# Resolve relative paths relative to the repo, matching MEGA65 Makefile usage.
[[ $src = /* ]] || src="$repo/$src"
[[ $out = /* ]] || out="$repo/$out"
if [[ ! -f "$src" ]]; then
  echo "ERROR: design input not found: $src" >&2
  echo "       For a target name, expected vivado/<target>.xpr under the repository root." >&2
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
