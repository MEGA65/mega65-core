## This file is a general .xdc for the Nexys4 rev B board
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

## Clock signal
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports CLK_IN]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK_IN]

## Make Ethernet clocks unrelated to other clocks to avoid erroneous timing
## violations, and hopefully make everything synthesise faster.
set_clock_groups -asynchronous \
     -group { cpuclock hdmi_clk_OBUF vdac_clk_OBUF clock162 clock325 } \
     -group { CLKFBOUT clk_fb_eth clock100 clock200 eth_clock_OBUF } \

# Deal with more false paths crossing ethernet / cpu clock domains
set_false_path -from [get_clocks cpuclock] -to [get_clocks ethclock]
set_false_path -from [get_clocks ethclock] -to [get_clocks cpuclock]

# HDMI output
############## HDMIOUT define##################

set_property PACKAGE_PIN A3 [get_ports TMDS_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_n]
set_property PACKAGE_PIN A4 [get_ports TMDS_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_p]

set_property PACKAGE_PIN B2 [get_ports {TMDS_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[0]}]
set_property PACKAGE_PIN B3 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[0]}]

set_property PACKAGE_PIN A1 [get_ports {TMDS_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[1]}]
set_property PACKAGE_PIN B1 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[1]}]

set_property PACKAGE_PIN C1 [get_ports {TMDS_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[2]}]
set_property PACKAGE_PIN C2 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[2]}]

## LED on TE0725
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports led]

## Flop/secure mode LED
set_property -dict { PACKAGE_PIN T8 IOSTANDARD LVCMOS33 } [get_ports flopled]
## IR LED
set_property -dict { PACKAGE_PIN R8 IOSTANDARD LVCMOS33 } [get_ports irled]

## QSPI Flash on TE0725 has the same pinout as the Nexys4 boards
set_property -dict {PACKAGE_PIN K17 IOSTANDARD LVCMOS33} [get_ports {QspiDB[0]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {QspiDB[1]}]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports {QspiDB[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {QspiDB[3]}]
set_property -dict {PACKAGE_PIN L13 IOSTANDARD LVCMOS33} [get_ports QspiCSn]
set_property PULLUP true [get_ports {Qspidb[0]}]
set_property PULLUP true [get_ports {Qspidb[1]}]
set_property PULLUP true [get_ports {Qspidb[2]}]
set_property PULLUP true [get_ports {Qspidb[3]}]

# Accelerometer and speaker amplifier controller
set_property -dict {PACKAGE_PIN P3 IOSTANDARD LVCMOS33} [get_ports i2c1sda]
set_property -dict {PACKAGE_PIN M4 IOSTANDARD LVCMOS33} [get_ports i2c1scl]

# I2S Audio data for speakers
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports i2s_mclk]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports i2s_bclk]
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33} [get_ports i2s_sync]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports i2s_speaker]

# MiniPCIe modem port 1
set_property -dict {PACKAGE_PIN T1 IOSTANDARD LVCMOS33} [get_ports modem1_pcm_clk_in]
set_property -dict {PACKAGE_PIN N4 IOSTANDARD LVCMOS33} [get_ports modem1_pcm_sync_in]
set_property -dict {PACKAGE_PIN R1 IOSTANDARD LVCMOS33} [get_ports modem1_pcm_data_in]
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports modem1_pcm_data_out]

# MiniPCIe modem port 2
set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports modem2_pcm_clk_in]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports modem2_pcm_sync_in]
set_property -dict {PACKAGE_PIN R2 IOSTANDARD LVCMOS33} [get_ports modem2_pcm_data_out]
set_property -dict {PACKAGE_PIN M3 IOSTANDARD LVCMOS33} [get_ports modem2_pcm_data_in]

# LCD port
set_property -dict {PACKAGE_PIN V7 IOSTANDARD LVCMOS33 SLEW FAST DRIVE 24} [get_ports lcd_dclk]
set_property -dict {PACKAGE_PIN V6 IOSTANDARD LVCMOS33} [get_ports lcd_hsync]
set_property -dict {PACKAGE_PIN U7 IOSTANDARD LVCMOS33} [get_ports lcd_vsync]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports lcd_display_enable]
set_property -dict {PACKAGE_PIN R3 IOSTANDARD LVCMOS33} [get_ports {lcd_red[0]}]
set_property -dict {PACKAGE_PIN T3 IOSTANDARD LVCMOS33} [get_ports {lcd_red[1]}]
set_property -dict {PACKAGE_PIN T5 IOSTANDARD LVCMOS33} [get_ports {lcd_red[3]}]
set_property -dict {PACKAGE_PIN T4 IOSTANDARD LVCMOS33} [get_ports {lcd_red[2]}]
set_property -dict {PACKAGE_PIN P5 IOSTANDARD LVCMOS33} [get_ports {lcd_red[4]}]
set_property -dict {PACKAGE_PIN N5 IOSTANDARD LVCMOS33} [get_ports {lcd_red[5]}]
set_property -dict {PACKAGE_PIN U1 IOSTANDARD LVCMOS33} [get_ports {lcd_green[0]}]
set_property -dict {PACKAGE_PIN V1 IOSTANDARD LVCMOS33} [get_ports {lcd_green[1]}]
set_property -dict {PACKAGE_PIN U2 IOSTANDARD LVCMOS33} [get_ports {lcd_green[2]}]
set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {lcd_green[3]}]
set_property -dict {PACKAGE_PIN U3 IOSTANDARD LVCMOS33} [get_ports {lcd_green[4]}]
set_property -dict {PACKAGE_PIN U4 IOSTANDARD LVCMOS33} [get_ports {lcd_green[5]}]
set_property -dict {PACKAGE_PIN R5 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[0]}]
set_property -dict {PACKAGE_PIN R6 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[1]}]
set_property -dict {PACKAGE_PIN V5 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[2]}]
set_property -dict {PACKAGE_PIN V4 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[3]}]
set_property -dict {PACKAGE_PIN R7 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[4]}]
set_property -dict {PACKAGE_PIN T6 IOSTANDARD LVCMOS33} [get_ports {lcd_blue[5]}]

# Dedicated lines to OrangeCrab FPGA board
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports fpga_mux1]
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports fpga_mux2]
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports fpga_mux3]
set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports fpga_mux4]

# Touch interface I2C bus
set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports touch_sda]
set_property -dict {PACKAGE_PIN N2 IOSTANDARD LVCMOS33} [get_ports touch_scl]
set_property PULLUP true [get_ports touch_sda]
set_property PULLUP true [get_ports touch_scl]

# MEMS microphones
set_property -dict {PACKAGE_PIN U9 IOSTANDARD LVCMOS33} [get_ports micData0]
set_property -dict {PACKAGE_PIN M6 IOSTANDARD LVCMOS33} [get_ports micData1]
set_property -dict {PACKAGE_PIN U6 IOSTANDARD LVCMOS33} [get_ports micClk]

#USB-RS232 Interface
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports monitor_rx]
set_property -dict {PACKAGE_PIN M18 IOSTANDARD LVCMOS33} [get_ports monitor_tx]

##Micro SD Connector (connected to both SIM/uSD sockets)
set_property -dict {PACKAGE_PIN H2 IOSTANDARD LVCMOS33} [get_ports sdReset]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports sdMISO]
set_property -dict {PACKAGE_PIN K1 IOSTANDARD LVCMOS33} [get_ports sdMOSI]
set_property -dict {PACKAGE_PIN K2 IOSTANDARD LVCMOS33} [get_ports sdClock]

## 2nd SD card bus (connected to spare pins on FPGA for bring-up, since SIM/uSD sockets are mis-wired)
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports sd2Clock]
set_property -dict {PACKAGE_PIN F1 IOSTANDARD LVCMOS33} [get_ports sd2reset]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33} [get_ports sd2MISO]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33} [get_ports sd2MOSI]

##PWM Audio Amplifier
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports headphone_left]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports headphone_right]
# Headphone jack microphone input
set_property -dict {PACKAGE_PIN N6 IOSTANDARD LVCMOS33} [get_ports headphone_mic]

# Bluetooth PCM audio interface
# XXX - We forgot to add a header on the PCB
#set_property -dict {PACKAGE_PIN  IOSTANDARD LVCMOS33} [get_ports bluetooth_pcm_clk_in]
#set_property -dict {PACKAGE_PIN  IOSTANDARD LVCMOS33} [get_ports bluetooth_pcm_sync_in]
#set_property -dict {PACKAGE_PIN  IOSTANDARD LVCMOS33} [get_ports bluetooth_pcm_data_out]
#set_property -dict {PACKAGE_PIN  IOSTANDARD LVCMOS33} [get_ports bluetooth_pcm_data_in]

## Hyper RAM : 1.8V allows for higher speed, but requires differential clock pair
set_property -dict {PACKAGE_PIN E17 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[0]}]
set_property -dict {PACKAGE_PIN B17 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[1]}]
set_property -dict {PACKAGE_PIN F18 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[2]}]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[3]}]
set_property -dict {PACKAGE_PIN G17 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[4]}]
set_property -dict {PACKAGE_PIN D18 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[5]}]
set_property -dict {PACKAGE_PIN B18 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[6]}]
set_property -dict {PACKAGE_PIN A16 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports {hr_d[7]}]
set_property -dict {PACKAGE_PIN E18 IOSTANDARD LVCMOS18} [get_ports hr_rwds]
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_rsto]
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_reset]
#set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_int]
set_property -dict {PACKAGE_PIN A13 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_clk_p]
set_property -dict {PACKAGE_PIN A14 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_clk_n]
set_property -dict {PACKAGE_PIN A18 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_cs0]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports hr_cs1]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

#set_false_path -from [get_clocks -of_objects [get_pins dotclock1/mmcm_adv_inst/CLKOUT2]] -to [get_clocks -of_objects [get_pins dotclock1/mmcm_adv_inst/CLKOUT3]]
#set_false_path -from [get_clocks -of_objects [get_pins dotclock1/mmcm_adv_inst/CLKOUT3]] -to [get_clocks -of_objects [get_pins dotclock1/mmcm_adv_inst/CLKOUT0]]
set_false_path -from [get_pins {machine0/viciv0/bitplanes_x_start_reg[2]/C}] -to [get_pins machine0/viciv0/vicii_sprites0/bitplanes0/x_in_bitplanes_reg/D]
set_false_path -from [get_pins machine0/iomapper0/block4b.c65uart0/reg_status3_rx_framing_error_reg/C] -to [get_pins {machine0/cpu0/read_data_copy_reg[3]/D}]
set_false_path -from [get_pins machine0/iomapper0/block4b.c65uart0/reg_status0_rx_full_reg/C] -to [get_pins {machine0/cpu0/read_data_copy_reg[0]/D}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprite_bitmap_collisions_reg[6]/C}] -to [get_pins {machine0/cpu0/read_data_copy_reg[6]/D}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprite_sprite_collisions_reg[5]/C}] -to [get_pins {machine0/cpu0/read_data_copy_reg[5]/D}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[12]}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[13]}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[13]}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[15]}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[14]}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[5]}]
set_false_path -from [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/v_bitplane_y_start_reg[5]/C}] -to [get_pins {machine0/viciv0/vicii_sprites0/bitplanes0/p_0_out/A[10]}]

set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[0]/CE}]

set_multicycle_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[4]/CE}] 1
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[2]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[7]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[1]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[3]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[5]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[6]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[0]/S}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[2]/S}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[3]/S}]
set_false_path -from [get_pins machine0/iomapper0/ethernet0/eth_tx_viciv_reg/C] -to [get_pins machine0/iomapper0/ethernet0/eth_tx_trigger_reg/D]
set_false_path -from [get_pins machine0/iomapper0/ethernet0/eth_rx_buffer_last_used_50mhz_reg/C] -to [get_pins machine0/iomapper0/ethernet0/eth_rx_buffer_last_used_int1_reg/D]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/FSM_onehot_eth_tx_state_reg[4]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[4]/S}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[0]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[2]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[3]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/tx_preamble_count_reg[4]/CE}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/eth_txd_int_reg[1]/D}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins {machine0/iomapper0/ethernet0/eth_txd_int_reg[0]/D}]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins machine0/iomapper0/ethernet0/eth_txen_int_reg/D]
set_false_path -from [get_pins machine0/iomapper0/block2.framepacker0/buffer_moby_toggle_reg/C] -to [get_pins machine0/iomapper0/ethernet0/eth_tx_viciv_reg/D]
