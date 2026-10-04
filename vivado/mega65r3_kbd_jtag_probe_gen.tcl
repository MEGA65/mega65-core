# Set the reference directory for source file relative paths.
set origin_dir [file dirname [info script]]/..

if { [info exists ::origin_dir_loc] } {
  set origin_dir $::origin_dir_loc
}

set project_name "mega65r3_kbd_jtag_probe"

if { [info exists ::user_project_name] } {
  set project_name $::user_project_name
}

if { $::argc > 0 } {
  for {set i 0} {$i < [llength $::argc]} {incr i} {
    set option [string trim [lindex $::argv $i]]
    switch -regexp -- $option {
      "--origin_dir"   { incr i; set origin_dir [lindex $::argv $i] }
      "--project_name" { incr i; set project_name [lindex $::argv $i] }
      "--help" {
        puts "Usage: mega65r3_kbd_jtag_probe_gen.tcl -tclargs \[--origin_dir <path>\] \[--project_name <name>\]"
        exit 0
      }
      default {
        if { [regexp {^-} $option] } {
          puts "ERROR: Unknown option '$option'"
          return 1
        }
      }
    }
  }
}

create_project -force ${project_name} vivado/ -part xc7a200tfbg484-2

set proj_dir [get_property directory [current_project]]
set obj [current_project]
set_property -name "default_lib" -value "xil_defaultlib" -objects $obj
set_property -name "ip_cache_permissions" -value "read write" -objects $obj
set_property -name "ip_output_repo" -value "$proj_dir/${project_name}.cache/ip" -objects $obj
set_property -name "part" -value "xc7a200tfbg484-2" -objects $obj
set_property -name "simulator_language" -value "Mixed" -objects $obj
set_property -name "source_mgmt_mode" -value "DisplayOnly" -objects $obj
set_property -name "target_language" -value "VHDL" -objects $obj

if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

set source_files [list \
  "[file normalize "$origin_dir/src/vhdl/clocking.vhdl"]" \
  "[file normalize "$origin_dir/src/vhdl/debugtools.vhdl"]" \
  "[file normalize "$origin_dir/src/vhdl/pinprober.vhdl"]" \
  "[file normalize "$origin_dir/src/vhdl/mega65r3_kbd_jtag_probe.vhdl"]" \
]
set source_objs [add_files -fileset sources_1 $source_files]
set_property -name "file_type" -value "VHDL" -objects $source_objs

set obj [get_filesets sources_1]
set_property -name "top" -value "container" -objects $obj

if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

set constraints_file "[file normalize "$origin_dir/src/vhdl/mega65r3_kbd_jtag_probe.xdc"]"
set constraints_obj [add_files -fileset constrs_1 $constraints_file]
set_property -name "file_type" -value "XDC" -objects $constraints_obj

if {[string equal [get_filesets -quiet sim_1] ""]} {
  create_fileset -simset sim_1
}

set obj [get_filesets sim_1]
set_property -name "top" -value "unknown" -objects $obj

if {[string equal [get_runs -quiet synth_1] ""]} {
  create_run -name synth_1 -part xc7a200tfbg484-2 -flow {Vivado Synthesis 2017} -strategy "Vivado Synthesis Defaults" -report_strategy {No Reports} -constrset constrs_1
} else {
  set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
  set_property flow "Vivado Synthesis 2017" [get_runs synth_1]
}
set obj [get_runs synth_1]
set_property -name "needs_refresh" -value "1" -objects $obj
set_property -name "part" -value "xc7a200tfbg484-2" -objects $obj
set_property -name "strategy" -value "Vivado Synthesis Defaults" -objects $obj
current_run -synthesis [get_runs synth_1]

if {[string equal [get_runs -quiet impl_1] ""]} {
  create_run -name impl_1 -part xc7a200tfbg484-2 -flow {Vivado Implementation 2017} -strategy "Vivado Implementation Defaults" -report_strategy {No Reports} -constrset constrs_1 -parent_run synth_1
} else {
  set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
  set_property flow "Vivado Implementation 2017" [get_runs impl_1]
}
set obj [get_runs impl_1]
set_property -name "part" -value "xc7a200tfbg484-2" -objects $obj
set_property -name "strategy" -value "Vivado Implementation Defaults" -objects $obj
current_run -implementation [get_runs impl_1]

puts "INFO: Project created: ${project_name}"
