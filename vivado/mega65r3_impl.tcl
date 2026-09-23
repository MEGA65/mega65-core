
# Incremental builds seem to work not as expected, so we start over!
reimport_files
reset_project

launch_runs synth_1 -jobs 2
wait_on_run synth_1

launch_runs impl_1
wait_on_run impl_1

# Open the completed implementation to apply bitstream properties
open_run impl_1

# Set desired bitstream configuration properties
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]

# Now write the bitstream manually
write_bitstream -force vivado/mega65r3.runs/impl_1/container.bit

