############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
############## clock and reset define##################
create_clock -period 20.000 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
set_property PACKAGE_PIN M22 [get_ports sys_clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {video_pll_m0/inst/clk_in1_video_pll}]
############## Switches and LEDs ##############
set_property PACKAGE_PIN H7 [get_ports btncpureset]
set_property IOSTANDARD LVCMOS33 [get_ports btncpureset]
#set_property PACKAGE_PIN J8 [get_ports KEY1]
#set_property IOSTANDARD LVCMOS33 [get_ports KEY1]
set_property PACKAGE_PIN J6 [get_ports LED]
set_property IOSTANDARD LVCMOS33 [get_ports LED]
set_property PACKAGE_PIN H6 [get_ports LED2]
set_property IOSTANDARD LVCMOS33 [get_ports LED2]

############## USB Serial interface ###########
set_property PACKAGE_PIN F3 [get_ports UART_TXD]
set_property IOSTANDARD LVCMOS33 [get_ports UART_TXD]
set_property PACKAGE_PIN E3 [get_ports RsRx]
set_property IOSTANDARD LVCMOS33 [get_ports RsRx]


############## HDMIOUT define##################
set_property PACKAGE_PIN C4 [get_ports TMDS_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_n]
set_property PACKAGE_PIN D4 [get_ports TMDS_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_p]

set_property PACKAGE_PIN D1 [get_ports {TMDS_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[0]}]
set_property PACKAGE_PIN E1 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[0]}]

set_property PACKAGE_PIN E2 [get_ports {TMDS_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[1]}]
set_property PACKAGE_PIN F2 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[1]}]

set_property PACKAGE_PIN G1 [get_ports {TMDS_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[2]}]
set_property PACKAGE_PIN G2 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[2]}]
