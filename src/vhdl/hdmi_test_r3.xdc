## This file is a general .ucf for the Nexys4 DDR Rev C board
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used signals according to the project

### Magic comment to allow monitor_load JTAg to automatically use the correct
### part boundary scan information.
### monitor_load:hint:part:xc7ar200tfbg484

## Clock signal (100MHz)
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports CLK_IN]

create_clock -period 10.000 -name CLK_IN [get_ports CLK_IN]

#set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clocks1/CLKOUT0]

# General purpose LED on mother board
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports led]

# CBM-488/IEC serial port
set_property -dict {PACKAGE_PIN AB21 IOSTANDARD LVCMOS33} [get_ports iec_reset]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports iec_atn]
set_property -dict {PACKAGE_PIN Y21 IOSTANDARD LVCMOS33} [get_ports iec_data_en]
set_property -dict {PACKAGE_PIN Y22 IOSTANDARD LVCMOS33} [get_ports iec_data_o]
set_property -dict {PACKAGE_PIN AB22 IOSTANDARD LVCMOS33 PULLUP true} [get_ports iec_data_i]
set_property -dict {PACKAGE_PIN AA21 IOSTANDARD LVCMOS33} [get_ports iec_clk_en]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports iec_clk_o]
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 PULLUP true} [get_ports iec_clk_i]
set_property -dict {PACKAGE_PIN U20 IOSTANDARD LVCMOS33} [get_ports iec_srq_o]
set_property -dict {PACKAGE_PIN AA18 IOSTANDARD LVCMOS33} [get_ports iec_srq_i]
set_property -dict {PACKAGE_PIN AB20 IOSTANDARD LVCMOS33} [get_ports iec_srq_en]


# C64 Cartridge port control lines
# *_dir=1 means FPGA->Port, =0 means Port->FPGA
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports cart_ctrl_dir]
#set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports cart_ctrl_en]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports cart_haddr_dir]
set_property -dict {PACKAGE_PIN L21 IOSTANDARD LVCMOS33} [get_ports cart_laddr_dir]
set_property -dict {PACKAGE_PIN V22 IOSTANDARD LVCMOS33} [get_ports cart_data_dir]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports cart_addr_en]
set_property -dict {PACKAGE_PIN U21 IOSTANDARD LVCMOS33} [get_ports cart_data_en]

# C64 Cartridge port
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports cart_phi2]
set_property -dict {PACKAGE_PIN AA19 IOSTANDARD LVCMOS33} [get_ports cart_dotclock]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports cart_reset]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports cart_nmi]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports cart_irq]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports cart_dma]
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33} [get_ports cart_exrom]
set_property -dict {PACKAGE_PIN N13 IOSTANDARD LVCMOS33} [get_ports cart_ba]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports cart_rw]
set_property -dict {PACKAGE_PIN AB18 IOSTANDARD LVCMOS33} [get_ports cart_roml]
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS33} [get_ports cart_romh]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports cart_io1]
set_property -dict {PACKAGE_PIN W22 IOSTANDARD LVCMOS33} [get_ports cart_game]
set_property -dict {PACKAGE_PIN AA20 IOSTANDARD LVCMOS33} [get_ports cart_io2]
set_property -dict {PACKAGE_PIN W21 IOSTANDARD LVCMOS33} [get_ports {cart_d[7]}]
set_property -dict {PACKAGE_PIN W20 IOSTANDARD LVCMOS33} [get_ports {cart_d[6]}]
set_property -dict {PACKAGE_PIN V18 IOSTANDARD LVCMOS33} [get_ports {cart_d[5]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {cart_d[4]}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {cart_d[3]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33} [get_ports {cart_d[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {cart_d[1]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {cart_d[0]}]
set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33} [get_ports {cart_a[15]}]
set_property -dict {PACKAGE_PIN N22 IOSTANDARD LVCMOS33} [get_ports {cart_a[14]}]
set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {cart_a[13]}]
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS33} [get_ports {cart_a[12]}]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {cart_a[11]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports {cart_a[10]}]
set_property -dict {PACKAGE_PIN H20 IOSTANDARD LVCMOS33} [get_ports {cart_a[9]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {cart_a[8]}]
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS33} [get_ports {cart_a[7]}]
set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS33} [get_ports {cart_a[6]}]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD LVCMOS33} [get_ports {cart_a[5]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {cart_a[4]}]
set_property -dict {PACKAGE_PIN M22 IOSTANDARD LVCMOS33} [get_ports {cart_a[3]}]
set_property -dict {PACKAGE_PIN K21 IOSTANDARD LVCMOS33} [get_ports {cart_a[2]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {cart_a[1]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {cart_a[0]}]

# C65 Keyboard
#

#set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports kb_tck]
#set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports kb_tdo]
#set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports kb_tms]
#set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports kb_tdi]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports kb_io0]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports kb_io1]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports kb_io2]
#set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports kb_jtagen]

# Test points
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports testpoint[1]]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports testpoint[2]]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports testpoint[3]]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports testpoint[4]]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports testpoint[5]]
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVCMOS33} [get_ports testpoint[6]]
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports testpoint[7]]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports testpoint[8]]

# Paddles
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports paddle[0]]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports paddle[1]]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports paddle[2]]
set_property -dict {PACKAGE_PIN J22 IOSTANDARD LVCMOS33} [get_ports paddle[3]]
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS33} [get_ports paddle_drain]

# Joystick port A
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports fa_down]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports fa_up]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports fa_left]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports fa_right]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports fa_fire]

# Joystick port B
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports fb_down]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports fb_up]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS33} [get_ports fb_left]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports fb_right]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports fb_fire]

##VGA Connector

# XXX - Is this needed?
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS33} [get_ports vdac_clk]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports vdac_sync_n]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports vdac_blank_n]

#
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports {vgared[0]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {vgared[1]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {vgared[2]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {vgared[3]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {vgared[4]}]
set_property -dict {PACKAGE_PIN AB17 IOSTANDARD LVCMOS33} [get_ports {vgared[5]}]
set_property -dict {PACKAGE_PIN AA16 IOSTANDARD LVCMOS33} [get_ports {vgared[6]}]
set_property -dict {PACKAGE_PIN AB16 IOSTANDARD LVCMOS33} [get_ports {vgared[7]}]

set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {vgagreen[0]}]
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {vgagreen[1]}]
set_property -dict {PACKAGE_PIN AA15 IOSTANDARD LVCMOS33} [get_ports {vgagreen[2]}]
set_property -dict {PACKAGE_PIN AB15 IOSTANDARD LVCMOS33} [get_ports {vgagreen[3]}]
set_property -dict {PACKAGE_PIN Y13 IOSTANDARD LVCMOS33} [get_ports {vgagreen[4]}]
set_property -dict {PACKAGE_PIN AA14 IOSTANDARD LVCMOS33} [get_ports {vgagreen[5]}]
set_property -dict {PACKAGE_PIN AA13 IOSTANDARD LVCMOS33} [get_ports {vgagreen[6]}]
set_property -dict {PACKAGE_PIN AB13 IOSTANDARD LVCMOS33} [get_ports {vgagreen[7]}]

set_property -dict {PACKAGE_PIN W10 IOSTANDARD LVCMOS33} [get_ports {vgablue[0]}]
set_property -dict {PACKAGE_PIN Y12 IOSTANDARD LVCMOS33} [get_ports {vgablue[1]}]
set_property -dict {PACKAGE_PIN AB12 IOSTANDARD LVCMOS33} [get_ports {vgablue[2]}]
set_property -dict {PACKAGE_PIN AA11 IOSTANDARD LVCMOS33} [get_ports {vgablue[3]}]
set_property -dict {PACKAGE_PIN AB11 IOSTANDARD LVCMOS33} [get_ports {vgablue[4]}]
set_property -dict {PACKAGE_PIN Y11 IOSTANDARD LVCMOS33} [get_ports {vgablue[5]}]
set_property -dict {PACKAGE_PIN AB10 IOSTANDARD LVCMOS33} [get_ports {vgablue[6]}]
set_property -dict {PACKAGE_PIN AA10 IOSTANDARD LVCMOS33} [get_ports {vgablue[7]}]

set_property -dict {PACKAGE_PIN W12 IOSTANDARD LVCMOS33} [get_ports hsync]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports vsync]

# HDMI output
############## HDMIOUT define##################
set_property PACKAGE_PIN Y1 [get_ports TMDS_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_n]
set_property PACKAGE_PIN W1 [get_ports TMDS_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_p]

set_property PACKAGE_PIN AB1 [get_ports {TMDS_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[0]}]
set_property PACKAGE_PIN AA1 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[0]}]

set_property PACKAGE_PIN AB2 [get_ports {TMDS_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[1]}]
set_property PACKAGE_PIN AB3 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[1]}]

set_property PACKAGE_PIN AB5 [get_ports {TMDS_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[2]}]
set_property PACKAGE_PIN AA5 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[2]}]

set_property -dict {PACKAGE_PIN AB7 IOSTANDARD LVCMOS33} [get_ports hdmi_scl]
set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports hdmi_sda]
#set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS33} [get_ports hdmi_enable]
#set_property -dict {PACKAGE_PIN Y8 IOSTANDARD LVCMOS33} [get_ports hdmi_hotplugdetect]
#set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports hdmi_cec_a]

# I2C bus for on-board peripherals
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports fpga_scl]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports fpga_sda]

#set_property -dict {PACKAGE_PIN AB7 IOSTANDARD LVCMOS33} [get_ports scl_a]
#set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports sda_a]
#set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports cec_a]
set_property -dict {PACKAGE_PIN Y8 IOSTANDARD LVCMOS33} [get_ports hpd_a]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports ct_hpd]
set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS33} [get_ports ls_oe]

# Other things I don't yet know

# FPGA JTAG interface
#set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports fpga_tdi]
#set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports fpga_tdo]
#set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports fpga_tck]
#set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports fpga_tms]
#set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports fpga_init]


#set_property -dict {PACKAGE_PIN G21 IOSTANDARD LVCMOS33} [get_ports grove_scl0]
#set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS33} [get_ports grove_sda0]

# PWM Audio
#
set_property -dict {PACKAGE_PIN L6 IOSTANDARD LVCMOS33} [get_ports pwm_l]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports pwm_r]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports i2s_sd]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports i2s_speaker]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports i2s_mclk]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports i2s_bclk]
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports i2s_sync]


##USB HID (PS/2)
# XXX - Not currently wired on the first prototypes: May break this out on a PMOD or expansion header?
#set_property -dict { PACKAGE_PIN xx IOSTANDARD LVCMOS33 } [get_ports PS2Clk]
#set_property -dict { PACKAGE_PIN xx IOSTANDARD LVCMOS33 } [get_ports PS2Data]

##Quad SPI Flash
#set_property  -dict { PACKAGE_PIN P22 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[0]}]
#set_property  -dict { PACKAGE_PIN R22 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[1]}]
#set_property  -dict { PACKAGE_PIN P21 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[2]}]
#set_property  -dict { PACKAGE_PIN R21 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[3]}]
set_property  -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports QspiCSn]
#set_property PULLUP true [get_ports {Qspidb[0]}]
#set_property PULLUP true [get_ports {Qspidb[1]}]
#set_property PULLUP true [get_ports {Qspidb[2]}]
#set_property PULLUP true [get_ports {Qspidb[3]}]

## Hyper RAM
set_property -dict {PACKAGE_PIN D22 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports hr_clk_p]
set_property -dict {PACKAGE_PIN A21 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[0]}]
set_property -dict {PACKAGE_PIN D21 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[1]}]
set_property -dict {PACKAGE_PIN C20 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[2]}]
set_property -dict {PACKAGE_PIN A20 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[3]}]
set_property -dict {PACKAGE_PIN B20 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[4]}]
set_property -dict {PACKAGE_PIN A19 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[5]}]
set_property -dict {PACKAGE_PIN E21 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[6]}]
set_property -dict {PACKAGE_PIN E22 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports {hr_d[7]}]
set_property -dict {PACKAGE_PIN B21 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports hr_rwds]
set_property -dict {PACKAGE_PIN B22 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr_reset]
set_property -dict {PACKAGE_PIN C22 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr_cs0]

## Pmod Header P1
set_property -dict { PACKAGE_PIN F1 IOSTANDARD LVCMOS33 } [get_ports {p1lo[0]}]
set_property -dict { PACKAGE_PIN D1 IOSTANDARD LVCMOS33 } [get_ports {p1lo[1]}]
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 } [get_ports {p1lo[2]}]
set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports {p1lo[3]}]
set_property -dict { PACKAGE_PIN G1 IOSTANDARD LVCMOS33 } [get_ports {p1hi[0]}]
set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports {p1hi[1]}]
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports {p1hi[2]}]
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports {p1hi[3]}]

## Pmod Header P2
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports {p2lo[0]}]
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports {p2lo[1]}]
set_property -dict { PACKAGE_PIN H4 IOSTANDARD LVCMOS33 } [get_ports {p2lo[2]}]
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports {p2lo[3]}]
set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports {p2hi[0]}]
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports {p2hi[1]}]
set_property -dict { PACKAGE_PIN G4 IOSTANDARD LVCMOS33 } [get_ports {p2hi[2]}]
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports {p2hi[3]}]


# 80 MHz Hyperram bus
set hbus_freq_ns   12
# Set allowable clock drift 
set dqs_in_min_dly -0.5
set dqs_in_max_dly  0.5
 
set hr0_dq_ports    [get_ports hr_d[*]]
# Set 6ns max delay to/from various HyperRAM pins
# (But add 17ns extra, because of weird ways Vivado calculates the apparent latency)
#set_max_delay -from [get_clocks clock163] -to ${hr0_dq_ports} 23
#set_max_delay -to [get_clocks clock163] -from ${hr0_dq_ports} 23
#set_max_delay -from [get_clocks clock163] -to hr_rwds 23
#set_max_delay -to [get_clocks clock163] -from hr_rwds 23

#set_input_delay -clock [get_clocks clock163]             -max ${dqs_in_max_dly} ${hr0_dq_ports}
#set_input_delay -clock [get_clocks clock163] -clock_fall -max ${dqs_in_max_dly} ${hr0_dq_ports} -add_delay
#set_input_delay -clock [get_clocks clock163]             -min ${dqs_in_min_dly} ${hr0_dq_ports} -add_delay
#set_input_delay -clock [get_clocks clock163] -clock_fall -min ${dqs_in_min_dly} ${hr0_dq_ports} -add_delay
#

##SMSC Ethernet PHY
#
#set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {eth_led[1]}]
set_property -dict {PACKAGE_PIN P4 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]
set_property -dict {PACKAGE_PIN L3 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN K3 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN K4 IOSTANDARD LVCMOS33} [get_ports eth_rxdv]
set_property -dict {PACKAGE_PIN J6 IOSTANDARD LVCMOS33} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN L5 IOSTANDARD LVCMOS33} [get_ports eth_mdio]
set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33 SLEW FAST} [get_ports eth_clock]
set_property -dict {PACKAGE_PIN K6 IOSTANDARD LVCMOS33} [get_ports eth_reset]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33 SLEW SLOW DRIVE 4} [get_ports eth_txen]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD LVCMOS33} [get_ports eth_rxer]
#set_property -dict {PACKAGE_PIN K4 IOSTANDARD LVCMOS33} [get_ports eth_crs_dv]

##USB-RS232 Interface
#
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports RsRx]

##Interface to MAX10
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports max10_tx]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports max10_rx]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports reset_from_max10]

##Micro SD Connector (x2 on r2 PCB)
#set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports sd2CD]
#set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports sd2Clock]
#set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports sd2reset]
#set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports sd2MISO]
#set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports sd2MOSI]
#set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[0]}]
#set_property -dict { PACKAGE_PIN H3 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[1]}]
#set_property -dict { PACKAGE_PIN J1 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[2]}]
#set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[3]}]

#set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports sdClock]
#set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports sdReset]
#set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports sdMISO]
#set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports sdMOSI]
#set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports sdWP]
#set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports sdCD]
#set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports {sd_dat[0]}]
#set_property -dict { PACKAGE_PIN C18 IOSTANDARD LVCMOS33 } [get_ports {sd_dat[1]}]
#set_property -dict { PACKAGE_PIN C19 IOSTANDARD LVCMOS33 } [get_ports {sd_dat[2]}]
#set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports {sd_dat[3]}]

## FDC interface
# Output signals
set_property -dict {PACKAGE_PIN P6 IOSTANDARD LVCMOS33} [get_ports f_density]
set_property -dict {PACKAGE_PIN M5 IOSTANDARD LVCMOS33} [get_ports f_motora]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports f_motorb]
set_property -dict {PACKAGE_PIN N5 IOSTANDARD LVCMOS33} [get_ports f_selecta]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS33} [get_ports f_selectb]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports f_stepdir]
set_property -dict {PACKAGE_PIN M3 IOSTANDARD LVCMOS33} [get_ports f_step]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports f_wdata]
set_property -dict {PACKAGE_PIN N3 IOSTANDARD LVCMOS33} [get_ports f_wgate]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports f_side1]

# Input Signals
set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports f_index]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports f_track0]
set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports f_writeprotect]
set_property -dict {PACKAGE_PIN P1 IOSTANDARD LVCMOS33} [get_ports f_rdata]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports f_diskchanged]

# XXX - Do we need something like this?
# CONFIG INTERNAL_VREF_BANK34= 0.900;

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

## Make Ethernet clocks unrelated to other clocks to avoid erroneous timing
## violations, and hopefully make everything synthesise faster.
#set_clock_groups -asynchronous \
#     -group { cpuclock CLKOUT2 CLKOUT3 hdmi_clk_OBUF vdac_clk_OBUF clock163 pixelclock clock325 hr_rwds } \
#     -group { CLKFBOUT clk_fb_eth u_clock50 u_clock500 u_clock50q clock100 clock200 eth_clock_OBUF clk_60 }

# Deal with more false paths crossing ethernet / cpu clock domains
#set_false_path -from [get_clocks hr_rwds] -to [get_clocks clock163]
#set_false_path -from [get_clocks clock163] -to [get_clocks hr_rwds]
#set_false_path -from [get_clocks cpuclock] -to [get_clocks ethclock]
#set_false_path -from [get_clocks ethclock] -to [get_clocks cpuclock]
#set_false_path -from [get_clocks cpuclock] -to [get_clocks clk_u]
#set_false_path -from [get_clocks vdac_clk_OBUF] -to [get_clocks ethclock]
# Fix 12.288MHz clock generation clock domain crossing
#set_false_path -from [get_clocks cpuclock] -to [get_clocks clk_60]
