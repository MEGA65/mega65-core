#!/bin/bash
# run.sh - simulate the HDMI encoder (src/vhdl/vga_to_hdmi.vhdl) with nvc on
# 720 x 480 with sound, and take apart what it sends (decode.py): the data
# islands, every packet's two error codes, an InfoFrame's checksum, and which
# characters have bit 3 of channel 0 low.
#
#   src/tests/hdmi/run.sh           both cases below
#   src/tests/hdmi/run.sh name      one of them
#
# The cases:
#   name  35 frames: the source product descriptor (the name a display may
#         show) goes out in frames 0 and 32
#   vrr   4 frames with vrr high: the FreeSync packet in its place, every
#         frame
#   sound, hdsound  3 whole frames, at 720 x 480 and at 1280 x 720: every
#         sound sample that goes in comes out, once and in order
# Under a minute each. Needs nvc (https://www.nickg.me.uk/nvc/) 1.10 or later
# and python3.
set -e
here=$(cd "$(dirname "$0")" && pwd)
vhdl=$here/../../vhdl
work=${TMPDIR:-/tmp}/tb_hdmi.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cd "$work"

nvc --work=xpm:xpm -a "$here/sim_xpm.vhdl"
nvc -L . --std=2008 --work=work:work -a "$vhdl/types_pkg.vhdl" "$vhdl/hdmi_tx_encoder.vhdl" \
    "$vhdl/vga_to_hdmi.vhdl" "$here/tb_hdmi.vhdl" 2>/dev/null

# one <name> <frames> <vrr> <whole frames written> <hd>
one() {
    nvc -L . --std=2008 --work=work:work -e -gFRAMES=$2 -gFULL_FRAMES=${4:-1} -gVRR=$3 -gHD=${5:-false} -gOUTFILE="$1.out" tb_hdmi >/dev/null 2>&1
    nvc -L . --std=2008 --work=work:work -r tb_hdmi >"$1.log" 2>&1 || { cat "$1.log"; exit 1; }
    echo "== $1"
    python3 "$here/decode.py" "$1.out"
}

fail=0
for c in ${@:-name vrr sound hdsound}; do
    case $c in
    name) one name 35 false || fail=1 ;;
    vrr)  one vrr 4 true || fail=1 ;;
    sound)   one sound 3 false 3 false || fail=1 ;;
    hdsound) one hdsound 3 false 3 true || fail=1 ;;
    *)    echo "no such case: $c"; exit 2 ;;
    esac
done
exit $fail
