## This file is a general .xdc for the Nexys4 rev B board
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

## Clock signal
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports CLK_IN]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK_IN]
 
## LED on TE0725
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports led]

## QSPI Flash on TE0725 has the same pinout as the Nexys4 boards
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports {QspiDB[0]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {QspiDB[1]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {QspiDB[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {QspiDB[3]}]
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33} [get_ports QspiCSn]

# WiFi header UART
#set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS33} [get_ports wifitx]
#set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports wifirx]

# VGA port
# XXX - HSYNC and VSYNC pins are swapped on MEGAphone schematic of 20190326
#set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports vga_vsync]
#set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports vga_hsync]
#set_property -dict {PACKAGE_PIN M3 IOSTANDARD LVCMOS33} [get_ports {vga_red[0]}]
#set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports {vga_red[1]}]
#set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports {vga_red[2]}]
#set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {vga_red[3]}]
#set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports {vga_green[0]}]
#set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports {vga_green[1]}]
#set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {vga_green[2]}]
#set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports {vga_green[3]}]
#set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports {vga_blue[0]}]
#set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports {vga_blue[1]}]
#set_property -dict {PACKAGE_PIN M4 IOSTANDARD LVCMOS33} [get_ports {vga_blue[2]}]
#set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports {vga_blue[3]}]

#USB-RS232 Interface
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports monitor_rx]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports monitor_tx]

##Micro SD Connector
#set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33} [get_ports sdReset]
#set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports sdMISO]
#set_property -dict {PACKAGE_PIN T8 IOSTANDARD LVCMOS33} [get_ports sdMOSI]
#set_property -dict {PACKAGE_PIN R8 IOSTANDARD LVCMOS33} [get_ports sdClock]

##PWM Audio Amplifier
#set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports headphone_left]
#set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports headphone_right]

## Hyper RAM : 1.8V allows for higher speed, but requires differential clock pair
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS18} [get_ports {hr_d[0]}]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS18} [get_ports {hr_d[1]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS18} [get_ports {hr_d[2]}]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS18} [get_ports {hr_d[3]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS18} [get_ports {hr_d[4]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS18} [get_ports {hr_d[5]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS18} [get_ports {hr_d[6]}]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS18} [get_ports {hr_d[7]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS18} [get_ports hr_rwds]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS18} [get_ports hr_rsto]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS18} [get_ports hr_reset]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS18} [get_ports hr_int]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS18} [get_ports hr_clk_p]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS18} [get_ports hr_clk_n]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS18} [get_ports hr_cs0]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS18} [get_ports hr_cs1]

## Pin prober for working out pin assignments
# Because VHDL is a pain, and wants consecutive ranges in pin arrays,
# I am populating the gaps with dummy pins, all of which have a numerical component of >= 10
# to make them easy to spot.
# Candidate pins from Bank 14:
# R11, R12, R13, M13, R18, N14, P14, N17, P18, N15, N16,
# P15, R15, T14, T15, R16, T16, V15, V16, U16, V17, T11,
# U11, U12, V12, V11, U14, V14, T13, U13, T10
# POF Fibre port (Bank 16 and Bank 14):
# C11, C10, D10, R10
# Bank 15:
# G13,
# Dummy pins yet to be used:
# G14, C14, B13, B14, C12, B12, B11, A11, F13, F14,
# D12, D13, B16, B17, A15, E15, E16, D15, C15, H16, G16,
# F15, H14, G14, K13, J13, J14, H15, C16, K15, J15, K16

# Power/GND x 2
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[1]}]
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[2]}]

set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[3]}]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[4]}]

# Power/GND x 2
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[5]}]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[6]}]

set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[7]}]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[8]}]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[9]}]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[10]}]
set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[11]}]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[12]}]
set_property -dict {PACKAGE_PIN J3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[13]}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[14]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[15]}]
set_property -dict {PACKAGE_PIN H1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[16]}]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[17]}]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[18]}]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[19]}]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[20]}]
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[21]}]
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[22]}]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[23]}]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[24]}]
set_property -dict {PACKAGE_PIN B3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[25]}]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[26]}]
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[27]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[28]}]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[29]}]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[30]}] 
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[31]}]
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[32]}]
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[33]}]
set_property -dict {PACKAGE_PIN B7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[34]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[35]}]
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[36]}]
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[37]}]
set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[38]}]
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[39]}]
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[40]}]
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[41]}]
set_property -dict {PACKAGE_PIN E7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[42]}]
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[43]}]
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[44]}]

# Power/GND x 2
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS18} [get_ports {fpga_pins[45]}]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS18} [get_ports {fpga_pins[46]}]

set_property -dict {PACKAGE_PIN C7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[47]}]
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[48]}]

# Power/GND x 4
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[49]}]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[50]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[51]}]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[52]}]

set_property -dict {PACKAGE_PIN T8 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[53]}]
set_property -dict {PACKAGE_PIN R8 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[54]}]

# Power/GND x 2
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[55]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[56]}]

set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[57]}]
set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[58]}]
set_property -dict {PACKAGE_PIN N6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[59]}]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[60]}]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[61]}]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[62]}]
set_property -dict {PACKAGE_PIN V6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[63]}]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[64]}]
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[65]}]
set_property -dict {PACKAGE_PIN R7 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[66]}]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[67]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[68]}]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[69]}]
set_property -dict {PACKAGE_PIN R5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[70]}]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 24} [get_ports {fpga_pins[71]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[72]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[73]}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 24} [get_ports {fpga_pins[74]}]
set_property -dict {PACKAGE_PIN V1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[75]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[76]}]
set_property -dict {PACKAGE_PIN N5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[77]}]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[78]}]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[79]}]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[80]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[81]}]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[82]}]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[83]}]
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[84]}]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[85]}]
set_property -dict {PACKAGE_PIN M4 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[86]}]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[87]}]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[88]}]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[89]}]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[90]}]
set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[91]}]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[92]}]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[93]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[94]}]

# Power/GND x 2
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[95]}]
set_property -dict {PACKAGE_PIN C10 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[96]}]

set_property -dict {PACKAGE_PIN M3 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[97]}]
set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports {fpga_pins[98]}]

# Power/GND x 2
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS18} [get_ports {fpga_pins[99]}]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS18} [get_ports {fpga_pins[100]}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

