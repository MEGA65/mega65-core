
# Incremental builds seem to work not as expected, so we start over!
reimport_files
reset_project

launch_runs synth_1 -jobs 2
wait_on_run synth_1

# (to the bitstream: this script has nothing after the run that writes it, as
# the R3's and the R6's have)
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

