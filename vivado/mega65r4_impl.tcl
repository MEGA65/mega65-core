
# Incremental builds seem to work not as expected, so we start over!
reimport_files
reset_project

launch_runs synth_1 -jobs 2
wait_on_run synth_1

launch_runs impl_1
wait_on_run impl_1

