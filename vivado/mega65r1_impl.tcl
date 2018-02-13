
# Assume that if the Makefile runs this step we have to start all over.
reimport_files
reset_project

launch_runs synth_1 -jobs 2
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
