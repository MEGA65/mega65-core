# (wait_and_report: wait_on_run, and on failure the runs' errors into this log)
source scripts/wait_and_report.tcl


# Assume that if the Makefile runs this step we have to start all over.
reimport_files
reset_project

launch_runs synth_1 -jobs 2
wait_and_report synth_1

launch_runs impl_1 -to_step write_bitstream
wait_and_report impl_1
