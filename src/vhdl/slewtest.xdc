## This file is a general .xdc for the Nexys4 rev B board
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

# Ignore false paths crossing clock domains in pixel output stage

## Clock signal
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports CLK_IN]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports CLK_IN]

## clock
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 24} [get_ports lcd_dclk]
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports lcd_hsync]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports lcd_vsync]
set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports lcd_display_enable]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports lcd_pwm]

# LCD display
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports {lcd_red[0]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {lcd_red[1]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {lcd_red[2]}]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports {lcd_red[3]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {lcd_red[4]}]
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {lcd_red[5]}]

set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports {lcd_green[0]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS33} [get_ports {lcd_green[1]}]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33} [get_ports {lcd_green[2]}]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD LVCMOS33} [get_ports {lcd_green[3]}]
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33} [get_ports {lcd_green[4]}]
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports {lcd_green[5]}]

set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[0]}]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[1]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[2]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[3]}]
set_property -dict {PACKAGE_PIN H1 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[4]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[5]}]

# Power shutdown line for testing
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS33} [get_ports power_down]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
