#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ghdl >/dev/null || { echo >&2 "ghdl is required for the buffer VHDL testbench"; exit 1; }
# The self-contained buffer entity lives in the same .vhdl source as ssnail.
# Extract only its design units so the test has no dependencies on the main
# SSNAIL package files or the rest of the MEGA65 tree.
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
awk '/^library ieee;/{inside=1} inside{print} /^end banked;/{exit}' \
  src/vhdl/ssnail.vhdl > "$workdir/ssnail_output_buffer.vhdl"
cp tests/tb_ssnail_output_buffer.vhdl "$workdir/"
cd "$workdir"
ghdl -a --std=08 ssnail_output_buffer.vhdl tb_ssnail_output_buffer.vhdl
ghdl -e --std=08 tb_ssnail_output_buffer
ghdl -r --std=08 tb_ssnail_output_buffer --assert-level=error
