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
    set errors {}
    set warn_order {}
    array unset warn_count
    array unset warn_first
    set n 0
    while {[gets $f line] >= 0} {
      incr n
      if {[regexp {^ERROR:} $line]} {
        lappend errors "  $log:$n: $line"
      } elseif {[regexp {^CRITICAL WARNING:} $line]} {
        # (one line per distinct warning: the same one repeated, such as
        # the TRNG's ring oscillators' timing loops, would bury the errors)
        if {![info exists warn_count($line)]} {
          set warn_count($line) 0
          set warn_first($line) $n
          lappend warn_order $line
        }
        incr warn_count($line)
      }
    }
    close $f
    if {[llength $errors] == 0 && [llength $warn_order] == 0} { continue }
    puts "==== [get_property NAME $r] ([get_property STATUS $r]): [llength $errors] errors, [llength $warn_order] distinct critical warnings ===="
    # every error, first: the cause is among them
    foreach l $errors { puts $l }
    foreach w [lrange $warn_order 0 29] {
      puts "  $log:$warn_first($w): $w  (x$warn_count($w))"
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
