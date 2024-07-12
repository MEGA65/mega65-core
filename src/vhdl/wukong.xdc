################################################################################
# General configuration options.
################################################################################
set_property CFGBVS                         VCCO    [current_design];
set_property CONFIG_VOLTAGE                 3.3     [current_design];
set_property BITSTREAM.CONFIG.UNUSEDPIN     PULLUP  [current_design];
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH  4       [current_design];
set_property CONFIG_MODE                    SPIx4   [current_design];
set_property BITSTREAM.CONFIG.CONFIGRATE    50      [current_design];

################################################################################
# System clock.
################################################################################
set_property -dict {PACKAGE_PIN M21 IOSTANDARD LVCMOS33} [get_ports clk_in];
create_clock -period 20.000 [get_ports clk_in];

################################################################################
# Clock and timing constraints.
################################################################################
create_generated_clock -name clock81p [get_pins clocks/mmcm_adv0/CLKOUT2]
create_generated_clock -name clock41  [get_pins clocks/mmcm_adv0/CLKOUT3]
create_generated_clock -name clock27  [get_pins clocks/mmcm_adv0/CLKOUT4]
create_generated_clock -name clock270 [get_pins clocks/mmcm_adv0/CLKOUT6]
create_generated_clock -name clock60  [get_pins AUDIO_TONE/CLOCK/MMCM/CLKOUT1]

# Fix 12.288MHz clock generation clock domain crossing.
set_false_path -from [get_clocks clock41] -to [get_clocks clock60]

################################################################################
# QSPI flash
################################################################################
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {qspi_db[0]}];
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {qspi_db[1]}];
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {qspi_db[2]}];
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {qspi_db[3]}];
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33                } [get_ports qspi_csn    ];

################################################################################
# Buttons.
################################################################################
set_property -dict {PACKAGE_PIN H7  IOSTANDARD LVCMOS33} [get_ports reset_button];
#set_property -dict {PACKAGE_PIN M6  IOSTANDARD LVCMOS33} [get_ports button2     ];

################################################################################
# LEDs.
################################################################################
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports led         ];
#set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports led2        ];

################################################################################
# Internal SD-card interface.
################################################################################
set_property -dict {PACKAGE_PIN J8 IOSTANDARD LVCMOS33} [get_ports int_sd_mosi ];
set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33} [get_ports int_sd_clock];
set_property -dict {PACKAGE_PIN J6 IOSTANDARD LVCMOS33} [get_ports int_sd_reset];
set_property -dict {PACKAGE_PIN M5 IOSTANDARD LVCMOS33} [get_ports int_sd_miso ];

################################################################################
# External SD-card interface.
################################################################################
#set_property -dict {PACKAGE_PIN J8 IOSTANDARD LVCMOS33} [get_ports ext_sd_mosi ];
#set_property -dict {PACKAGE_PIN L4 IOSTANDARD LVCMOS33} [get_ports ext_sd_clock];
#set_property -dict {PACKAGE_PIN J6 IOSTANDARD LVCMOS33} [get_ports ext_sd_reset];
#set_property -dict {PACKAGE_PIN M5 IOSTANDARD LVCMOS33} [get_ports ext_sd_miso ];

################################################################################
# USB serial interface.
################################################################################
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports uart_txd];
set_property -dict {PACKAGE_PIN F3 IOSTANDARD LVCMOS33} [get_ports rsrx    ];

################################################################################
# HDMI interface.
################################################################################
set_property -dict {PACKAGE_PIN C4 IOSTANDARD TMDS_33} [get_ports tmds_clk_n      ];
set_property -dict {PACKAGE_PIN D4 IOSTANDARD TMDS_33} [get_ports tmds_clk_p      ];
set_property -dict {PACKAGE_PIN D1 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[0]}];
set_property -dict {PACKAGE_PIN E1 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}];
set_property -dict {PACKAGE_PIN E2 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[1]}];
set_property -dict {PACKAGE_PIN F2 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[1]}];
set_property -dict {PACKAGE_PIN G1 IOSTANDARD TMDS_33} [get_ports {tmds_data_n[2]}];
set_property -dict {PACKAGE_PIN G2 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[2]}];

################################################################################
# C64 keyboard interface on J12.
################################################################################
set_property -dict {PACKAGE_PIN AB26 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[3]}]; # J12:3  | IO_L3P_T0_DQS_13
set_property -dict {PACKAGE_PIN AB24 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[6]}]; # J12:5  | IO_L9P_T1_DQS_13
set_property -dict {PACKAGE_PIN AA24 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[5]}]; # J12:7  | IO_L7P_T1_13
set_property -dict {PACKAGE_PIN AA22 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[4]}]; # J12:9  | IO_L8P_T1_13
set_property -dict {PACKAGE_PIN Y25  IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[7]}]; # J12:11 | IO_L5P_T0_13
set_property -dict {PACKAGE_PIN W25  IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[2]}]; # J12:13 | IO_L4P_T0_13
set_property -dict {PACKAGE_PIN Y22  IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[1]}]; # J12:15 | IO_L11P_T1_SRCC_13
set_property -dict {PACKAGE_PIN W21  IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports {portb_pins[0]}]; # J12:17 | IO_L14P_T2_SRCC_13
set_property -dict {PACKAGE_PIN V26  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[0]}]; # J12:19 | IO_L2P_T0_13
set_property -dict {PACKAGE_PIN U25  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[6]}]; # J12:21 | IO_L1P_T0_13
set_property -dict {PACKAGE_PIN V24  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[5]}]; # J12:23 | IO_L6P_T0_13
set_property -dict {PACKAGE_PIN V23  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[4]}]; # J12:25 | IO_L10P_T1_13
set_property -dict {PACKAGE_PIN V18  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[3]}]; # J12:27 | IO_L19P_T3_13
set_property -dict {PACKAGE_PIN U22  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[2]}]; # J12:29 | IO_L12P_T1_MRCC_13
set_property -dict {PACKAGE_PIN U21  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[1]}]; # J12:31 | IO_L13P_T2_MRCC_13
set_property -dict {PACKAGE_PIN T20  IOSTANDARD LVCMOS33 DRIVE 16       } [get_ports {porta_pins[7]}]; # J12:33 | IO_L15P_T2_DQS_13

################################################################################
# Control port 1 (PMOD) (J10).
################################################################################
set_property -dict {PACKAGE_PIN D5 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fa_up   ]; # J10:1  | IO_L13N_T2_MRCC_35
set_property -dict {PACKAGE_PIN G5 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fa_left ]; # J10:2  | IO_L12P_T1_MRCC_35
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fa_down ]; # J10:7  | IO_L13P_T2_MRCC_35
set_property -dict {PACKAGE_PIN E6 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fa_right]; # J10:8  | IO_L1P_T0_AD4P_35
set_property -dict {PACKAGE_PIN D6 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fa_fire ]; # J10:9  | IO_L1N_T0_AD4N_35
#set_property -dict {PACKAGE_PIN G7 IOSTANDARD LVCMOS33} [get_ports {pmod_j10[2]}]; # J10:3  | IO_L3N_T0_DQS_AD5N_35
#set_property -dict {PACKAGE_PIN G8 IOSTANDARD LVCMOS33} [get_ports {pmod_j10[3]}]; # J10:4  | IO_L2N_T0_AD12N_35
#set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {pmod_j10[7]}]; # J10:10 | IO_L5N_T0_AD13N_35

################################################################################
# Control port 2 (PMOD) (J11).
################################################################################
set_property -dict {PACKAGE_PIN H4 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fb_up   ]; # J11:1  | IO_L9N_T1_DQS_AD7N_35
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fb_left ]; # J11:2  | IO_L11N_T1_SRCC_35
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fb_down ]; # J11:7  | IO_L9P_T1_DQS_AD7P_35
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fb_right]; # J11:8  | IO_L11P_T1_SRCC_35
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33 PULLTYPE PULLUP} [get_ports fb_fire ]; # J11:9  | IO_L16P_T2_35
#set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {pmod_j11[2]}]; # J11:3  | IO_L16N_T2_35
#set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {pmod_j11[3]}]; # J11:4  | IO_L15N_T2_DQS_35
#set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports {pmod_j11[7]}]; # J11:10 | IO_L15P_T2_DQS_35
