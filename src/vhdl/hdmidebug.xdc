# For MEGA65r2 PCB

## Clock signal (100MHz)
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports CLK_IN]

create_clock -period 10.000 -name CLK_IN [get_ports CLK_IN]

## Buttons
# XXX - Currently resets FPGA, rather than CPU
#
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports btnCpuReset]

# General purpose LED on mother board
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports led]

## Hyper RAM
set_property -dict {PACKAGE_PIN D22 IOSTANDARD LVCMOS33} [get_ports hr_clk_p]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33} [get_ports {hr_d[0]}]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33} [get_ports {hr_d[1]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33} [get_ports {hr_d[2]}]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33} [get_ports {hr_d[3]}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33} [get_ports {hr_d[4]}]
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33} [get_ports {hr_d[5]}]
set_property -dict {PACKAGE_PIN E21 IOSTANDARD LVCMOS33} [get_ports {hr_d[6]}]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33} [get_ports {hr_d[7]}]
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33} [get_ports hr_rwds]
set_property -dict {PACKAGE_PIN B22 IOSTANDARD LVCMOS33} [get_ports hr_reset]
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS33} [get_ports hr_cs0]

# XXX - Do we need something like this?
# CONFIG INTERNAL_VREF_BANK34= 0.900;

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]



