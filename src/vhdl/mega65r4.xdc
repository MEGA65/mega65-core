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

create_generated_clock -name clock325 [get_pins clocks1/mmcm_adv0/CLKOUT0]
create_generated_clock -name clock81p [get_pins clocks1/mmcm_adv0/CLKOUT2]
create_generated_clock -name clock41  [get_pins clocks1/mmcm_adv0/CLKOUT3]
create_generated_clock -name clock27  [get_pins clocks1/mmcm_adv0/CLKOUT4]
create_generated_clock -name clock163 [get_pins clocks1/mmcm_adv0/CLKOUT5]
create_generated_clock -name clock270 [get_pins clocks1/mmcm_adv0/CLKOUT6]

create_generated_clock -name clock50  [get_pins clocks1/mmcm_adv1_eth/CLKOUT1]
create_generated_clock -name clock200 [get_pins clocks1/mmcm_adv1_eth/CLKOUT2]

create_generated_clock -name clock60  [get_pins AUDIO_TONE/CLOCK/MMCM/CLKOUT1]

#set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clocks1/CLKOUT0]

# General purpose LED on mother board
set_property -dict {PACKAGE_PIN U22 IOSTANDARD LVCMOS33} [get_ports led]
# On board LEDs direct connected to main FPGA on R4, not via MAX10
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports led_g]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports led_r]


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

# DIP Switches direct connected to main FPGA on R4, not via MAX10
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports dipsw[0]]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports dipsw[1]]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports dipsw[2]]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports dipsw[3]]

# Reset button on the side of the machine(?) connected to main FPGA on R4, not via MAX10
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports reset_button]

# C64 Cartridge port control lines
# *_dir=1 means FPGA->Port, =0 means Port->FPGA
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports cart_ctrl_dir]
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports cart_ctrl_en]
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
# Place Cartidge near IO Pins
create_pblock pblock_cart
add_cells_to_pblock pblock_cart [get_cells [list slow_devices0/cartport0]]
resize_pblock pblock_cart -add {SLICE_X0Y137:SLICE_X7Y185}

# C65 Keyboard
#

set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports kb_tck]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports kb_tdo]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports kb_tms]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports kb_tdi]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS33} [get_ports kb_io0]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS33} [get_ports kb_io1]
set_property -dict {PACKAGE_PIN C13 IOSTANDARD LVCMOS33} [get_ports kb_io2]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports kb_jtagen]
# Place Keyboard close to I/O pins
create_pblock pblock_kbd0
add_cells_to_pblock pblock_kbd0 [get_cells [list kbd0]]
resize_pblock pblock_kbd0 -add {SLICE_X0Y225:SLICE_X7Y243}

# Paddles
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports paddle[0]]
set_property -dict {PACKAGE_PIN G15 IOSTANDARD LVCMOS33} [get_ports paddle[1]]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports paddle[2]]
set_property -dict {PACKAGE_PIN J22 IOSTANDARD LVCMOS33} [get_ports paddle[3]]
set_property -dict {PACKAGE_PIN H22 IOSTANDARD LVCMOS33} [get_ports paddle_drain]

# Output lines on joysticks allow pulling the joystick lines low on R4
# However, these pins are also shared with the new DBG header, except for DBG10-11
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports dbg[10]]
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports dbg[11]]

# Joystick port power control/sensing
set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports joystick_5v_disable]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports joystick_5v_powergood]


# Joystick port A
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports fa_down]
# DBG3
set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33} [get_ports fa_down_drain_n]
set_property -dict {PACKAGE_PIN C14 IOSTANDARD LVCMOS33} [get_ports fa_up]
# DBG1
set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports fa_up_drain_n]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports fa_left]
# DBG2
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports fa_left_drain_n]
set_property -dict {PACKAGE_PIN F13 IOSTANDARD LVCMOS33} [get_ports fa_right]
# DBG5
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports fa_right_drain_n]
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS33} [get_ports fa_fire]
# DBG0
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports fa_fire_drain_n]

# Joystick port B
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports fb_down]
# DBG6
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports fb_down_drain_n]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports fb_up]
# DBG4
set_property -dict {PACKAGE_PIN N20 IOSTANDARD LVCMOS33} [get_ports fb_up_drain_n]
set_property -dict {PACKAGE_PIN F21 IOSTANDARD LVCMOS33} [get_ports fb_left]
# DBG9
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports fb_left_drain_n]
set_property -dict {PACKAGE_PIN C15 IOSTANDARD LVCMOS33} [get_ports fb_right]
# DBG8
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS33} [get_ports fb_right_drain_n]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33} [get_ports fb_fire]
# DBG7
set_property -dict {PACKAGE_PIN N19 IOSTANDARD LVCMOS33} [get_ports fb_fire_drain_n]

##VGA Connector

# VGA I2C bus
# set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports vga_sda]
# set_property -dict {PACKAGE_PIN W15 IOSTANDARD LVCMOS33} [get_ports vga_scl]

# XXX - Is this needed?
set_property -dict {PACKAGE_PIN AA9 IOSTANDARD LVCMOS33} [get_ports vdac_clk]
set_property -dict {PACKAGE_PIN V10 IOSTANDARD LVCMOS33} [get_ports vdac_sync_n]
set_property -dict {PACKAGE_PIN W11 IOSTANDARD LVCMOS33} [get_ports vdac_blank_n]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports vdac_psave_n]

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
set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS33} [get_ports hdmi_enable_n]
set_property -dict {PACKAGE_PIN Y8 IOSTANDARD LVCMOS33} [get_ports hdmi_hotplugdetect]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports hdmi_cec_a]

# I2C bus for on-board peripherals
set_property -dict {PACKAGE_PIN A15 IOSTANDARD LVCMOS33} [get_ports fpga_scl]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS33} [get_ports fpga_sda]

# HDMI buffer things
#set_property -dict {PACKAGE_PIN AB7 IOSTANDARD LVCMOS33} [get_ports scl_a]
#set_property -dict {PACKAGE_PIN V9 IOSTANDARD LVCMOS33} [get_ports sda_a]
#set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports cec_a]
set_property -dict {PACKAGE_PIN Y8 IOSTANDARD LVCMOS33} [get_ports hpd_a]
set_property -dict {PACKAGE_PIN M15 IOSTANDARD LVCMOS33} [get_ports hdmi_hiz]
set_property -dict {PACKAGE_PIN AB8 IOSTANDARD LVCMOS33} [get_ports ls_oe]

# Other things I don't yet know

# FPGA JTAG interface
#set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports fpga_tdi]
#set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports fpga_tdo]
#set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports fpga_tck]
#set_property -dict {PACKAGE_PIN T13 IOSTANDARD LVCMOS33} [get_ports fpga_tms]
#set_property -dict {PACKAGE_PIN U12 IOSTANDARD LVCMOS33} [get_ports fpga_init]


set_property -dict {PACKAGE_PIN G21 IOSTANDARD LVCMOS33} [get_ports grove_scl]
set_property -dict {PACKAGE_PIN G22 IOSTANDARD LVCMOS33} [get_ports grove_sda]

# Audio DAC
# R4 board hard-wires DAC to serial mode
set_property -dict {PACKAGE_PIN F19 IOSTANDARD LVCMOS33} [get_ports audio_lrclk]
set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports audio_sdata]
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports audio_bick]
set_property -dict {PACKAGE_PIN D16 IOSTANDARD LVCMOS33} [get_ports audio_mclk]
# DAC power down
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS33} [get_ports audio_powerdown_n]
# SMUTE/CSN/I2CFIL
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports audio_smute]
# ACKS/CCLK/SCL
set_property -dict {PACKAGE_PIN L6 IOSTANDARD LVCMOS33} [get_ports audio_scl]
# DIF/CDTI/SDA
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports audio_sda]


# PWM Audio
#
# XXX - Are the following still used?
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports i2s_bclk]


##USB HID (PS/2)
# XXX - Not currently wired on the first prototypes: May break this out on a PMOD or expansion header?
#set_property -dict { PACKAGE_PIN xx IOSTANDARD LVCMOS33 } [get_ports PS2Clk]
#set_property -dict { PACKAGE_PIN xx IOSTANDARD LVCMOS33 } [get_ports PS2Data]

##Quad SPI Flash
set_property  -dict { PACKAGE_PIN P22 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {QspiDB[0]}]
set_property  -dict { PACKAGE_PIN R22 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {QspiDB[1]}]
set_property  -dict { PACKAGE_PIN P21 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {QspiDB[2]}]
set_property  -dict { PACKAGE_PIN R21 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {QspiDB[3]}]
set_property  -dict { PACKAGE_PIN T19 IOSTANDARD LVCMOS33 } [get_ports QspiCSn]

## SDRAM - 32M x 16 bit, 3.3V VCC
set_property -dict {PACKAGE_PIN V8 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_clk]
set_property -dict {PACKAGE_PIN U5 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_cke]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_ras_n]
set_property -dict {PACKAGE_PIN V3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_cas_n]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_we_n]
set_property -dict {PACKAGE_PIN G3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_cs_n]

set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_ba[0]]
set_property -dict {PACKAGE_PIN R4 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_ba[1]]

set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[0]]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[1]]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[2]]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[3]]
set_property -dict {PACKAGE_PIN Y4 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[4]]
set_property -dict {PACKAGE_PIN W6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[5]]
set_property -dict {PACKAGE_PIN W4 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[6]]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[7]]
set_property -dict {PACKAGE_PIN AA8 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[8]]
set_property -dict {PACKAGE_PIN Y2 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[9]]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[10]]
set_property -dict {PACKAGE_PIN Y7 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[11]]
set_property -dict {PACKAGE_PIN Y9 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_a[12]]

set_property -dict {PACKAGE_PIN W2 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dqml]
set_property -dict {PACKAGE_PIN Y6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dqmh]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[0]]
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[1]]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[2]]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[3]]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[4]]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[5]]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[6]]
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[7]]
set_property -dict {PACKAGE_PIN W7 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[8]]
set_property -dict {PACKAGE_PIN AA3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[9]]
set_property -dict {PACKAGE_PIN AA4 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[10]]
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[11]]
set_property -dict {PACKAGE_PIN AA6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[12]]
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[13]]
set_property -dict {PACKAGE_PIN AB6 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[14]]
set_property -dict {PACKAGE_PIN Y3 IOSTANDARD LVCMOS33 PULLUP FALSE SLEW FAST DRIVE 16} [get_ports sdram_dq[15]]

# Constrain input and output times for SDRAM pins
# DQ pins must have an input delay in a fairly narrow range from about 2.9ns to 5.8ns.
# We are being quite conservative here, and requiring it to be much more precisely near
# the middle of this range.
# Clock duration is 6.17 ns
#set_input_delay  -min [expr 3.5] [get_clocks sdram_clk] [get_ports sdram_[*]]
#set_input_delay  -max [expr 5] [get_clocks sdram_clk] [get_ports sdram_dq[*]]
# Max = trace delay (= ~0.2ns?) - Tsu (=1.5ns) =
#set_output_delay  -max [expr 3] [get_clocks sdram_clk] [get_ports sdram_dq[*]]
# Min = - (trace delay + Th) = ~1ns
#set_output_delay  -min [expr -1.5] [get_clocks sdram_clk] [get_ports sdram_[*]]

# Adam's better way:
set Trefclk 10.0 ; # 100 MHz reference clock input to MMCM
set Tpcb    0.2  ; # assume 30mm @ 150mm/ns, assume traces all matched
set Tsu     1.5  ; # input setup time
set Th      0.8  ; # input hold time
set Tac3    5.4  ; # access (clock to output) time for CAS latency 3
set Toh3    2.5  ; # output hold time for CAS latency 3

#create_clock -name clki -period $Trefclk [get_ports clki]
create_generated_clock -name sdram_clk -multiply_by 1 -source [get_pins OBUF_SDCLK/I] [get_ports sdram_clk]

# As we setup dq a cycle before, and hold it a cycle after, we can actually
# relax sdram_dq output quite a bit, instead of constraining it
# This is what we would need if we didn't do that:
#   set_output_delay -max [expr $Tpcb+$Tsu]   -clock sdram_clk [get_ports sdram_dq]
#   set_output_delay -min [expr -($Th-$Tpcb)] -clock sdram_clk [get_ports sdram_dq]
# Instead we can do something like this:
#  set_output_delay -max [expr -(6.17-$Tpcb+$Tsu)]   -clock sdram_clk [get_ports sdram_dq]
#  set_output_delay -min [expr 6.17-($Th-$Tpcb)] -clock sdram_clk [get_ports sdram_dq]
# or just use a multi-cycle path (and keeping the first correct delays)
set_output_delay -max [expr $Tpcb+$Tsu]   -clock sdram_clk [get_ports sdram_dq]
set_output_delay -min [expr -($Th-$Tpcb)] -clock sdram_clk [get_ports sdram_dq]

# One of the following seems to cause unwarranted delay by 5.6 ns, preventing timing closure
#set_multicycle_path 2 -setup -start -from clock162 -to sdram_clk -through [get_ports sdram_dq[*]]
#set_multicycle_path 1 -hold  -start -from clock162 -to sdram_clk -through [get_ports sdram_dq[*]]
#set_input_delay  -max [expr $Tpcb+$Tac3]  -clock sdram_clk [get_ports sdram_dq]
#set_input_delay  -min [expr $Tpcb+$Toh3]  -clock sdram_clk [get_ports sdram_dq]

# Relax timing of cache lines between 162MHz SDRAM and 40.5MHz CPU:
set ratio 4; # ratio of launch to latch clock
set n_setup [expr $ratio]
set n_hold  [expr $ratio-1]
set_multicycle_path $n_setup -setup -start -from clock162 -to u_clock41
set_multicycle_path $n_hold  -hold  -start -from clock162 -to u_clock41


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
# Place HyperRAM close to I/O pins
create_pblock pblock_hyperram
add_cells_to_pblock pblock_hyperram [get_cells [list hyperram0]]
resize_pblock pblock_hyperram -add {SLICE_X0Y186:SLICE_X35Y224}
resize_pblock pblock_hyperram -add {SLICE_X8Y175:SLICE_X23Y186}

set tPCB    0.1  ; # assume 15mm @ 150mm/ns VoP, and that trace lengths are matched

# 100MHz HyperRAM timings
set tCKDmax  5.5  ; # clock to data valid, max
set tCKDImin 0.0  ; # clock to data invalid, min

set hyperram_inputs {hr_d[*] hr_rwds}

# HyperRAM clock is generated by 325MHz logic, runs at 81.25MHz
create_generated_clock -name hr_clk -divide_by 4 -source [get_pins clocks1/mmcm_adv0/CLKOUT0] [get_ports hr_clk_p]
# set_property IOB TRUE [get_ports hr_clk_p]

# read timing
set_input_delay  -max [expr $tPCB+$tCKDmax]  -clock hr_clk [get_ports $hyperram_inputs]
set_input_delay  -min [expr $tPCB+$tCKDImin] -clock hr_clk [get_ports $hyperram_inputs]
set_multicycle_path 2 -setup -end -from hr_clk -to clock163
set_multicycle_path 1 -hold  -end -from hr_clk -to clock163

## PMOD power rail enables
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {pmod1en}]
set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports {pmod2en}]

## Pmod Header P1
# B35_L5_N
set_property -dict { PACKAGE_PIN F1 IOSTANDARD LVCMOS33 } [get_ports {p1lo[0]}]
# B35_L3_N
set_property -dict { PACKAGE_PIN D1 IOSTANDARD LVCMOS33 } [get_ports {p1lo[1]}]
# B35_L2_N
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 } [get_ports {p1lo[2]}]
# B35_L1_N
set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports {p1lo[3]}]
# B16_L17_P
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports {p1hi[0]}]
# B35_L3_P
set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports {p1hi[1]}]
# B35_L2_P
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports {p1hi[2]}]
# B35_L1_P
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports {p1hi[3]}]

## Pmod Header P2
# B35_L6_P
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports {p2lo[0]}]
# B35_L6_N
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports {p2lo[1]}]
# B35_L12_P
set_property -dict { PACKAGE_PIN H4 IOSTANDARD LVCMOS33 } [get_ports {p2lo[2]}]
# B35_L10_N
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports {p2lo[3]}]
# B35_L4_P
set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports {p2hi[0]}]
# B35_L4_N
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports {p2hi[1]}]
# B35_L12_N
set_property -dict { PACKAGE_PIN G4 IOSTANDARD LVCMOS33 } [get_ports {p2hi[2]}]
# B35_L10_P
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports {p2hi[3]}]


## Hyper RAM on trap-door PMOD
## Pinout is for one of these: https://github.com/blackmesalabs/hyperram
## If no SLEW or DRIVE directive, then reading external hyperram sometimes results in two
## dummy bytes being read at the start of a read transfer.
#set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr2_clk_p]
#set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr2_clk_n]
#set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[0]}]
#set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[1]}]
#set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[2]}]
#set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[3]}]
#set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[4]}]
#set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[5]}]
#set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[6]}]
#set_property -dict {PACKAGE_PIN D1 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports {hr2_d[7]}]
#set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr2_rwds]
#set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr2_reset]
#set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33 PULLUP FALSE} [get_ports hr2_cs0]

# 80 MHz Hyperram bus
set hbus_freq_ns   12
# Set allowable clock drift
set dqs_in_min_dly -0.5
set dqs_in_max_dly  0.5

set hr0_dq_ports    [get_ports hr_d[*]]
set hr2_dq_ports    [get_ports hr2_d[*]]
# Set 6ns max delay to/from various HyperRAM pins
# (But add 17ns extra, because of weird ways Vivado calculates the apparent latency)
set_max_delay -from [get_clocks clock163] -to ${hr0_dq_ports} 23
set_max_delay -from [get_clocks clock163] -to ${hr2_dq_ports} 23
set_max_delay -to [get_clocks clock163] -from ${hr0_dq_ports} 23
set_max_delay -to [get_clocks clock163] -from ${hr2_dq_ports} 23
set_max_delay -from [get_clocks clock163] -to hr_rwds 23
set_max_delay -from [get_clocks clock163] -to hr2_rwds 23
set_max_delay -to [get_clocks clock163] -from hr_rwds 23
set_max_delay -to [get_clocks clock163] -from hr2_rwds 23

#set_input_delay -clock [get_clocks clock163]             -max ${dqs_in_max_dly} ${hr0_dq_ports}
#set_input_delay -clock [get_clocks clock163] -clock_fall -max ${dqs_in_max_dly} ${hr0_dq_ports} -add_delay
#set_input_delay -clock [get_clocks clock163]             -min ${dqs_in_min_dly} ${hr0_dq_ports} -add_delay
#set_input_delay -clock [get_clocks clock163] -clock_fall -min ${dqs_in_min_dly} ${hr0_dq_ports} -add_delay
#
#set_input_delay -clock [get_clocks clock163]             -max ${dqs_in_max_dly} ${hr2_dq_ports}
#set_input_delay -clock [get_clocks clock163] -clock_fall -max ${dqs_in_max_dly} ${hr2_dq_ports} -add_delay
#set_input_delay -clock [get_clocks clock163]             -min ${dqs_in_min_dly} ${hr2_dq_ports} -add_delay
#set_input_delay -clock [get_clocks clock163] -clock_fall -min ${dqs_in_min_dly} ${hr2_dq_ports} -add_delay

##SMSC Ethernet PHY
#
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {eth_led[1]}]
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

create_generated_clock -name eth_rx_clock -multiply_by 1 -source [get_pins clocks1/mmcm_adv1_eth/CLKOUT1] [get_ports {eth_clock}]
set_input_delay -clock [get_clocks eth_rx_clock] -max 15 [get_ports {eth_rxd[1] eth_rxd[0]}]
set_input_delay -clock [get_clocks eth_rx_clock] -min 5 [get_ports {eth_rxd[1] eth_rxd[0]}]

##USB-RS232 Interface
#
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports RsRx]

set_property -dict {PACKAGE_PIN  IOSTANDARD LVCMOS33} [get_ports pmod2_en]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports pmod1_flag]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports pmod2_en]
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports pmod2_flag]

# MEGA65 board revision pins = 0100 = 0x4 for R4
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports board_rev[0]]
set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports board_rev[1]]
set_property -dict {PACKAGE_PIN F20 IOSTANDARD LVCMOS33} [get_ports board_rev[2]]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports board_rev[3]]


##Micro SD Connector (x2 on r2 PCB)
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports sd2CD]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports sd2Clock]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports sd2reset]
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports sd2MISO]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports sd2MOSI]
#set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[0]}]
#set_property -dict { PACKAGE_PIN H3 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[1]}]
#set_property -dict { PACKAGE_PIN J1 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[2]}]
#set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 } [get_ports {sd2_dat[3]}]

set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS33} [get_ports sdClock]
set_property -dict {PACKAGE_PIN B15 IOSTANDARD LVCMOS33} [get_ports sdReset]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS33} [get_ports sdMISO]
set_property -dict {PACKAGE_PIN B16 IOSTANDARD LVCMOS33} [get_ports sdMOSI]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports sdWP]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports sdCD]
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

# Deal with more false paths crossing ethernet / cpu clock domains
# New clocking has the clocks with unhelpful names:
# mmcm_adv0:
#    CLKOUT0             => u_clock325,
#    CLKOUT2             => u_clock81p,
#    CLKOUT3             => u_clock41,
#    CLKOUT4             => u_clock27,
#    CLKOUT5             => u_clock162,
#    CLKOUT6             => u_clock270,
# mmcm_adv1_eth:
#    CLKOUT1             => u_clock50,
#    CLKOUT2             => u_clock200,
# note that CLKOUT2 occurs in both, which is annoying since the clock names don't
# seem to have the prefixes on them anymore

# Relax between ethernet and CPU
set_false_path -from [get_clocks clock41] -to [get_clocks clock50]
set_false_path -from [get_clocks clock50] -to [get_clocks clock41]

## Fix 12.288MHz clock generation clock domain crossing
set_false_path -from [get_clocks clock41] -to [get_clocks clock60]

## Make Ethernet clocks unrelated to other clocks to avoid erroneous timing
## violations, and hopefully make everything synthesise faster.
set_clock_groups -asynchronous \
     -group { clock41 clock81p clock27 clock163 clock325 } \
     -group { clock50 clock200}

################################
# neoTRNG properties
################################
set trng_cells [get_cells -hier -regexp .*trng0.* -filter {NAME =~ .*/inv_chain_.* || NAME =~ .*/enable_sreg_.*}]
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -of_objects $trng_cells]
set_disable_timing -to O [get_timing_arcs -of_objects $trng_cells]

