# Fail the build straight after synthesis if a memory that should be LUT RAM
# was built from flip-flops instead.
#
# Vivado treats ram_style as a hint: an access pattern it cannot map to RAM
# (for example a second read at a constant index) silently turns a 1024x32
# array into 32k flip-flops, and the damage only shows hours later as
# congestion and failed timing all over the chip.
#
# Hooked in as the synth_1 STEPS.SYNTH_DESIGN.TCL.POST script of the SSNAIL
# targets.  It can also be run by hand on a synthesised design:
#   open_checkpoint vivado/mega65r6.runs/synth_1/container.dcp
#   source scripts/check_ram_inference.tcl

# Instance glob, array name: every signal with ram_style "distributed" in
# ssnail.vhdl.  Add new ones here.
set ram_checks {
  *ssnail0 {bank0 bank1 bank2 bank3 ring_lo ring_hi csv qv outv sarr
            qx0 qx1 qx2 qx3 dxs wf buf_in bufx bufy bufb
            kq_bs kq_sb0 kq_sb1 kq_sb2 kq_sb3}
}

# A failed inference gives one flip-flop per bit (thousands); a handful can
# be legitimate registers that inherit the array's name.
set ff_limit 128

set bad {}
foreach {inst arrays} $ram_checks {
  foreach a $arrays {
    set ff [get_cells -quiet -hierarchical \
              -filter "NAME =~ ${inst}/${a}_reg* && PRIMITIVE_GROUP == FLOP_LATCH"]
    set ram [get_cells -quiet -hierarchical \
              -filter "NAME =~ ${inst}/${a}_reg* && REF_NAME =~ RAM*"]
    if {[llength $ff] >= $ff_limit} {
      lappend bad "$inst/$a: [llength $ff] flip-flops, [llength $ram] RAM cells"
    } elseif {[llength $ff] > 0} {
      puts "WARNING: check_ram_inference: $inst/$a: [llength $ff] flip-flops (below the limit), [llength $ram] RAM cells"
    } elseif {[llength $ram] == 0} {
      puts "WARNING: check_ram_inference: no cells found for $inst/$a (renamed or removed?)"
    } else {
      puts "check_ram_inference: $inst/$a: [llength $ram] RAM cells, OK"
    }
  }
}

if {[llength $bad] > 0} {
  foreach b $bad { puts "ERROR: check_ram_inference: $b" }
  error "check_ram_inference: memories built from flip-flops instead of RAM (see above, and the synthesis log for the reason)"
}
