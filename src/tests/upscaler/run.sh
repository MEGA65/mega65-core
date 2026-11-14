#!/bin/bash
# run.sh - simulate the upscaler (src/vhdl/upscaler.vhdl) behind the MEGA65's
# frame generator with nvc, and check what comes out (check.py).
#
#   src/tests/upscaler/run.sh              every case below
#   src/tests/upscaler/run.sh pal          one of them
#
# The cases:
#   pal     PAL, 624 lines a frame (as the MEGA65 has it without interlace)
#   ntsc    NTSC, 526 lines
#   pali    PAL with interlace on: 625 lines, and 720p comes out exactly
#           1980 x 750
#   switch  PAL, then NTSC, the upscaler on all the while
#   hd      NTSC, the 720p picture asked for by hd_en and taken from the
#           hd_ outputs, upscale_en off (HDMI at 720p, VGA as it is)
#   whole   NTSC in frames of whole lines (752, now and then 753), as for
#           a display told that the rate varies
#   narrow  NTSC in frames of whole lines with the picture narrower, 680
#           pixels for 912 (for a 21:9 display that stretches it)
#   palnarrow  PAL with the picture narrower, 688 pixels for 924
#   74p22   PAL with a 74.2268 MHz clock (900 MHz / 12.125, what the
#           boards without a 74.25 MHz clock have) in place of 74.25 MHz
# About a minute each. Needs nvc (https://www.nickg.me.uk/nvc/) 1.10 or
# later and python3.
set -e
here=$(cd "$(dirname "$0")" && pwd)
vhdl=$here/../../vhdl
work=${TMPDIR:-/tmp}/tb_upscaler.$$
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT
cd "$work"

nvc --work=xpm:xpm -a "$here/sim_xpm.vhdl"
nvc -L . --std=2008 --work=work:work -a "$here/sim_ram.vhdl" "$vhdl/frame_generator.vhdl" \
    "$vhdl/upscaler.vhdl" "$vhdl/tb_upscaler.vhdl"

# one <name> <pal|ntsc> <first frame checked> <generics...>
one() {
    name=$1; std=$2; first=$3; shift 3
    how=""; case " $* " in *" NARROW=true "*) how=narrow ;; esac
    g=""; for a in "$@"; do g="$g -g $a"; done
    rm -f "$name.out" "$name.out.in"
    nvc -L . --std=2008 --work=work:work -e $g -gOUTFILE="$name.out" tb_upscaler >/dev/null
    nvc -L . --std=2008 --work=work:work -r tb_upscaler >"$name.log" 2>&1 || { cat "$name.log"; exit 1; }
    echo "== $name"
    python3 "$here/check.py" "$name.out" $std $first $how
}

fail=0
for c in ${@:-pal ntsc pali switch hd whole narrow palnarrow 74p22}; do
    case $c in
    pal)    one pal pal 2 ENABLE_AT=3 FRAMES=5 || fail=1 ;;
    ntsc)   one ntsc ntsc 2 PAL=false ENABLE_AT=4 FRAMES=5 || fail=1 ;;
    pali)   one pali pal 2 INTERLACE=true ENABLE_AT=4 FRAMES=5 || fail=1 ;;
    switch) one switch ntsc 8 ENABLE_AT=2 SWITCH_AT=5 FRAMES=11 DUMP_FRAME=10 || fail=1 ;;
    hd)     one hd ntsc 2 PAL=false HD_ONLY=true ENABLE_AT=4 FRAMES=5 || fail=1 ;;
    whole)  one whole ntsc 2 PAL=false WHOLE_LINES=true ENABLE_AT=4 FRAMES=14 DUMP_FRAME=12 || fail=1 ;;
    narrow) one narrow ntsc 2 PAL=false WHOLE_LINES=true NARROW=true ENABLE_AT=4 FRAMES=8 DUMP_FRAME=6 || fail=1 ;;
    palnarrow) one palnarrow pal 2 NARROW=true ENABLE_AT=3 FRAMES=5 || fail=1 ;;
    74p22)  one 74p22 pal 2 HALF81=6172840fs HALF74=6736111fs ENABLE_AT=4 FRAMES=12 DUMP_FRAME=10 || fail=1 ;;
    *)      echo "no such case: $c"; exit 2 ;;
    esac
done
exit $fail
