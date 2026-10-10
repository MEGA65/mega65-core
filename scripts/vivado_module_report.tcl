# Module resource analysis for MEGA65, Vivado 2023.2 compatible.
# Usage: through vivado_module_report.sh, not source directly.
if {[llength $argv] < 3} {
    error "usage: -tclargs <.xpr-or-.dcp> <module-name> <outdir> ?run? ?instance-path?"
}
set source_path [file normalize [lindex $argv 0]]
set module_name [lindex $argv 1]
set outdir [file normalize [lindex $argv 2]]
set run_name [expr {[llength $argv] >= 4 ? [lindex $argv 3] : "synth_1"}]
set instance_path [expr {[llength $argv] >= 5 ? [lindex $argv 4] : ""}]
file mkdir $outdir

if {[string equal -nocase [file extension $source_path] ".dcp"]} {
    puts "Opening checkpoint $source_path"
    open_checkpoint $source_path
} else {
    puts "Opening project $source_path, run $run_name"
    open_project $source_path
    open_run $run_name
}
puts "Design [current_design] / Part [get_property PART [current_design]]"

# Prefer exact instance path when passed. Match RTL module name otherwise,
# including synthesized ORIG_REF_NAME. Don't accidentally merge instances.
if {$instance_path ne ""} {
    set matches [get_cells -hierarchical -quiet $instance_path]
} else {
    set matches [get_cells -hierarchical -quiet -filter "ORIG_REF_NAME == $module_name"]
    if {[llength $matches] == 0} {
        set matches [get_cells -hierarchical -quiet -filter "REF_NAME == $module_name"]
    }
}
if {[llength $matches] != 1} {
    puts stderr "Expected one matching instance, found [llength $matches]:"
    foreach m $matches { puts stderr "  [get_property NAME $m] : [get_property REF_NAME $m]" }
    puts stderr "Try the exact instance path as argument 5."
    error "Cannot identify unique instance for $module_name"
}
set root [lindex $matches 0]
set root_path [get_property NAME $root]
puts "Selected instance: $root_path ([get_property REF_NAME $root])"

# Reports on the specific module, plus full-design baseline for comparing.
report_utilization -file [file join $outdir full_design_utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -hierarchical_min_primitive_count 0 \
    -file [file join $outdir full_design_hierarchy.rpt]
report_utilization -cells $root -file [file join $outdir module_utilization.rpt]
report_utilization -cells $root -hierarchical -hierarchical_depth 5 \
    -hierarchical_min_primitive_count 0 -file [file join $outdir module_hierarchy.rpt]
report_control_sets -cells $root -file [file join $outdir module_control_sets.rpt]
report_control_sets -cells $root -verbose -file [file join $outdir module_control_sets_verbose.rpt]
# report_ram_utilization can be sizable, so generate both a text report and CSV.
report_ram_utilization -cells $root -include_lutram \
    -file [file join $outdir module_ram.rpt] \
    -csv [file join $outdir module_ram.csv]

# Descendant primitive type counts (not physical LUT equivalents).
set cells [get_cells -hierarchical -quiet \
    -filter "NAME =~ ${root_path}/* && IS_PRIMITIVE == 1"]
set primitive_counts [dict create]
set lut_groups [dict create]
set child_groups [dict create]
foreach cell $cells {
    set type [get_property REF_NAME $cell]
    dict incr primitive_counts $type
    set name [get_property NAME $cell]
    set local [string range $name [expr {[string length $root_path] + 1}] end]
    if {[string match "LUT*" $type]} {
        # Name histogram is heuristic: register outputs often give synthesis LUTs
        # their names, but it is not a reliable block-level area attribution.
        set group $local
        if {[regexp {^([^/]+)/} $local -> child]} {
            dict incr child_groups $child
        } else {
            regsub {_i_[0-9]+.*$} $group "" group
            regsub {\[.*$} $group "" group
            dict incr lut_groups $group
        }
    }
}
set fp [open [file join $outdir module_primitives.txt] w]
puts $fp "Instance: $root_path"
puts $fp "Primitive type counts (not physical LUT capacity):"
foreach type [lsort [dict keys $primitive_counts]] {
    puts $fp [format "%-24s %9d" $type [dict get $primitive_counts $type]]
}
close $fp

proc write_sorted_histogram {dict_data filename heading} {
    set sorted {}
    dict for {key cnt} $dict_data { lappend sorted [list $cnt $key] }
    set sorted [lsort -integer -decreasing -index 0 $sorted]
    set fp [open $filename w]
    puts $fp $heading
    foreach item $sorted {
        lassign $item cnt key
        puts $fp [format "%8d  %s" $cnt $key]
    }
    close $fp
}
write_sorted_histogram $lut_groups [file join $outdir module_lut_names.txt] \
    "Heuristic LUT naming groups for direct logic (no nested child hierarchy)"
write_sorted_histogram $child_groups [file join $outdir module_child_luts.txt] \
    "Nested-module LUT primitive counts (not packed LUT equivalents)"

set fp [open [file join $outdir module_dsps.txt] w]
foreach cell $cells {
    if {[string match "DSP*" [get_property REF_NAME $cell]]} {
        puts $fp "[get_property NAME $cell] : [get_property REF_NAME $cell]"
    }
}
close $fp

set fp [open [file join $outdir summary.txt] w]
puts $fp "Vivado [version]"
puts $fp "Source: $source_path"
puts $fp "Design: [current_design]"
puts $fp "Module: $module_name"
puts $fp "Instance: $root_path"
puts $fp "Part: [get_property PART [current_design]]"
puts $fp "Total primitive descendants: [llength $cells]"
puts $fp "See module_utilization.rpt for physical LUT accounting."
puts $fp "WARNING: LUT primitive counts and child groups are NOT packed LUT utilization."
close $fp
puts "Completed. Reports written to $outdir"
close_design
if {[llength [get_projects -quiet]]} { close_project }
