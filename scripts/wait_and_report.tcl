# wait_and_report RUN: wait_on_run, and if it (or a run it depends on)
# failed, copy the ERROR and CRITICAL WARNING lines of every run's own log
# (vivado/<target>.runs/<run>/runme.log) into this log before failing, so
# the reason shows in the top-level output, not just "Failed run(s)".
#
#   source scripts/wait_and_report.tcl
#   wait_and_report impl_1

proc report_run_errors {} {
  foreach r [get_runs] {
    set log [file join [get_property DIRECTORY $r] runme.log]
    if {![file exists $log]} { continue }
    set f [open $log r]
    set lines {}
    set n 0
    while {[gets $f line] >= 0} {
      incr n
      if {[regexp {^(ERROR|CRITICAL WARNING):} $line]} {
        lappend lines "  $log:$n: $line"
      }
    }
    close $f
    if {[llength $lines] > 0} {
      puts "==== [get_property NAME $r] ([get_property STATUS $r]): [llength $lines] error / critical warning lines ===="
      # (the first 60: the cause is nearly always among the first few)
      foreach l [lrange $lines 0 59] { puts $l }
    }
  }
}

proc wait_and_report {run} {
  set failed [catch {wait_on_run $run} msg]
  foreach r [get_runs] {
    if {[string match -nocase "*error*" [get_property STATUS $r]]
        || [string match -nocase "*failed*" [get_property STATUS $r]]} {
      set failed 1
    }
  }
  if {$failed} {
    report_run_errors
    error "wait_and_report: $run failed (the run logs' errors are above)"
  }
}
