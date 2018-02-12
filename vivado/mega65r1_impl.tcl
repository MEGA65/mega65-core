
# Don't re-launch run if it's already done, otherwise Vivado will
# throw an error and the Makefile will abort.
set runStatus [get_property STATUS [get_runs impl_1]]

set runProgress [get_property PROGRESS [get_runs impl_1]]

if { $runStatus == "write_bitstream Complete!" && $runProgress == "100%"} {

	puts "Skipping bitstream generation"

} else {

	launch_runs impl_1 -to_step write_bitstream
	wait_on_run impl_1

}

