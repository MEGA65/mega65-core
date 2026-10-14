# Vivado: summarise WHERE setup timing fails in an existing routed run.
# report_timing_summary only shows the worst few paths per clock pair; this
# lists every failing endpoint once, groups them by register, and ranks the
# nets that the worst paths share (a common high-fanout net shows up here).
#
# Standalone (from the repository root):
#   ./vivado_wrapper -mode batch -source scripts/timing_hotspots.tcl \
#       -tclargs mega65r6 mega65r6.hotspots.txt
# Or, with a design already open, set hotspot_out and source this file.

if {![info exists hotspot_out]} {
    set target [lindex $argv 0]
    if {$target eq ""} { set target mega65r6 }
    set hotspot_out [lindex $argv 1]
    if {$hotspot_out eq ""} { set hotspot_out "${target}.hotspots.txt" }
    open_project [file normalize [file join vivado "${target}.xpr"]]
    open_run impl_1
}
if {![info exists hotspot_max_paths]} { set hotspot_max_paths 30000 }
if {![info exists hotspot_net_paths]} { set hotspot_net_paths 3000 }
if {![info exists hotspot_detail_groups]} { set hotspot_detail_groups 40 }

# Register name without bit indices and pin: foo/bar_reg[3][7]/D -> foo/bar_reg[*][*]
proc hs_group {pin} {
    set n [regsub {/[^/]+$} $pin ""]
    regsub -all {\[[0-9]+\]} $n {[*]} n
    # LUTRAM slices: ring_lo_reg_256_319_0_2 -> ring_lo_reg_*
    regsub {(_reg)_[0-9_]+$} $n {\1_*} n
    return $n
}

set fh [open $hotspot_out w]
set paths [get_timing_paths -setup -max_paths $hotspot_max_paths -nworst 1 \
               -unique_pins -slack_lesser_than 0]
set npaths [llength $paths]
puts $fh "Failing setup endpoints reported: $npaths (limit $hotspot_max_paths)"
puts $fh ""

# ---- Per endpoint list, and group statistics -------------------------------
array set g_n {}; array set g_worst {}; array set g_tns {}; array set g_lv {}
array set g_clk {}; array set g_src {}
set lines {}
foreach p $paths {
    set s  [get_property SLACK $p]
    set sp [get_property STARTPOINT_PIN $p]
    set ep [get_property ENDPOINT_PIN $p]
    set lv [get_property LOGIC_LEVELS $p]
    set sc [get_property STARTPOINT_CLOCK $p]
    set ec [get_property ENDPOINT_CLOCK $p]
    set dd [get_property DATAPATH_DELAY $p]
    lappend lines [format "%8.3f %3d %7.3f %-10s %-10s %s <- %s" $s $lv $dd $sc $ec $ep $sp]
    set g [hs_group $ep]
    if {![info exists g_n($g)]} {
        set g_n($g) 0; set g_worst($g) 0.0; set g_tns($g) 0.0; set g_lv($g) 0
        set g_clk($g) "$sc->$ec"
    }
    incr g_n($g)
    set g_tns($g) [expr {$g_tns($g) + $s}]
    if {$s < $g_worst($g)} { set g_worst($g) $s; set g_src($g) $sp }
    if {$lv > $g_lv($g)} { set g_lv($g) $lv }
    set sg [hs_group $sp]
    set k "$sg => $g"
    if {![info exists pair_n($k)]} { set pair_n($k) 0; set pair_tns($k) 0.0; set pair_w($k) 0.0 }
    incr pair_n($k)
    set pair_tns($k) [expr {$pair_tns($k) + $s}]
    if {$s < $pair_w($k)} { set pair_w($k) $s }
}

# Ascending by the values in global array arrname (most negative first)
proc hs_by_tns {arrname a b} {
    upvar #0 $arrname t
    if {$t($a) < $t($b)} { return -1 } elseif {$t($a) > $t($b)} { return 1 }
    return 0
}

puts $fh "==== Endpoint groups, by total negative slack ===="
puts $fh [format "%6s %10s %8s %4s  %-20s %s" count TNS worst lvls clocks "endpoint group  (worst startpoint)"]
foreach g [lsort -command {hs_by_tns g_tns} [array names g_n]] {
    puts $fh [format "%6d %10.3f %8.3f %4d  %-20s %s  (%s)" $g_n($g) $g_tns($g) \
                  $g_worst($g) $g_lv($g) $g_clk($g) $g $g_src($g)]
}
puts $fh ""

puts $fh "==== Startpoint group => endpoint group, by worst slack (top 150) ===="
puts $fh [format "%6s %10s %8s  %s" count TNS worst "startpoint group => endpoint group"]
set i 0
foreach k [lsort -command {hs_by_tns pair_w} [array names pair_n]] {
    puts $fh [format "%6d %10.3f %8.3f  %s" $pair_n($k) $pair_tns($k) $pair_w($k) $k]
    if {[incr i] >= 150} { break }
}
puts $fh ""

# ---- Nets shared by the worst paths --------------------------------------
puts $fh "==== Nets on the worst $hotspot_net_paths failing paths (top 80 by path count) ===="
array set net_n {}
set i 0
foreach p $paths {
    foreach n [get_nets -quiet -of_objects $p] {
        if {[info exists net_n($n)]} { incr net_n($n) } else { set net_n($n) 1 }
    }
    if {[incr i] >= $hotspot_net_paths} { break }
}
proc hs_by_count {a b} {
    upvar #0 net_n t
    return [expr {$t($b) - $t($a)}]
}
set i 0
foreach n [lsort -command hs_by_count [array names net_n]] {
    set fo "?"
    catch { set fo [expr {[get_property FLAT_PIN_COUNT [get_nets $n]] - 1}] }
    puts $fh [format "%6d paths  fanout %6s  %s" $net_n($n) $fo $n]
    if {[incr i] >= 80} { break }
}
puts $fh ""

# ---- One detailed path for each of the worst groups -----------------------
puts $fh "==== Pblock utilisation, then the worst path of each of the top $hotspot_detail_groups endpoint groups: see the end ===="
puts $fh ""
puts $fh "==== All failing endpoints: slack levels datapath srcclk dstclk endpoint <- startpoint ===="
foreach l $lines { puts $fh $l }
puts $fh ""
close $fh

# Fill of each placement block: a crowded pblock forces long routes inside it
if {[catch {report_utilization -pblocks [get_pblocks] -file $hotspot_out -append} why]} {
    puts "SKIPPED pblock utilisation: $why"
}

set i 0
set done_groups {}
foreach p $paths {
    set g [hs_group [get_property ENDPOINT_PIN $p]]
    if {[lsearch -exact $done_groups $g] >= 0} { continue }
    lappend done_groups $g
    report_timing -of_objects $p -input_pins -file $hotspot_out -append
    if {[incr i] >= $hotspot_detail_groups} { break }
}
puts "Timing hotspots written to $hotspot_out"
