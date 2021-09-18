## This file is a general .xdc for the Nexys4 rev B board
## To use it in a project:
## - uncomment the lines corresponding to used pins
## - rename the used ports (in each line, after get_ports) according to the top level signal names in the project

## Clock signal
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports CLK_IN]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK_IN]

## Work around MMCM placement problem
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clocks1/CLKOUT0]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clocks1/CLKOUT0]

## Make Ethernet clocks unrelated to other clocks to avoid erroneous timing
## violations, and hopefully make everything synthesise faster.
set_clock_groups -asynchronous \
     -group { cpuclock hdmi_clk_OBUF vdac_clk_OBUF clock162 clock325 } \
     -group { CLKFBOUT clk_fb_eth clock100 clock200 eth_clock_OBUF } \

# Deal with more false paths crossing ethernet / cpu clock domains
set_false_path -from [get_clocks cpuclock] -to [get_clocks ethclock]
set_false_path -from [get_clocks ethclock] -to [get_clocks cpuclock]

## Switches
set_property -dict { PACKAGE_PIN U9 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN U8 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN R7 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN R6 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]
set_property -dict { PACKAGE_PIN R5 IOSTANDARD LVCMOS33 } [get_ports {sw[4]}]
set_property -dict { PACKAGE_PIN V7 IOSTANDARD LVCMOS33 } [get_ports {sw[5]}]
set_property -dict { PACKAGE_PIN V6 IOSTANDARD LVCMOS33 } [get_ports {sw[6]}]
set_property -dict { PACKAGE_PIN V5 IOSTANDARD LVCMOS33 } [get_ports {sw[7]}]
set_property -dict { PACKAGE_PIN U4 IOSTANDARD LVCMOS33 } [get_ports {sw[8]}]
set_property -dict { PACKAGE_PIN V2 IOSTANDARD LVCMOS33 } [get_ports {sw[9]}]
set_property -dict { PACKAGE_PIN U2 IOSTANDARD LVCMOS33 } [get_ports {sw[10]}]
set_property -dict { PACKAGE_PIN T3 IOSTANDARD LVCMOS33 } [get_ports {sw[11]}]
set_property -dict { PACKAGE_PIN T1 IOSTANDARD LVCMOS33 } [get_ports {sw[12]}]
set_property -dict { PACKAGE_PIN R3 IOSTANDARD LVCMOS33 } [get_ports {sw[13]}]
set_property -dict { PACKAGE_PIN P3 IOSTANDARD LVCMOS33 } [get_ports {sw[14]}]
set_property -dict { PACKAGE_PIN P4 IOSTANDARD LVCMOS33 } [get_ports {sw[15]}]

## LEDs
set_property -dict { PACKAGE_PIN T8 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN V9 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN R8 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN T6 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN T5 IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
set_property -dict { PACKAGE_PIN T4 IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
set_property -dict { PACKAGE_PIN U7 IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
set_property -dict { PACKAGE_PIN U6 IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
set_property -dict { PACKAGE_PIN V4 IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
set_property -dict { PACKAGE_PIN U3 IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
set_property -dict { PACKAGE_PIN V1 IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
set_property -dict { PACKAGE_PIN R1 IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
set_property -dict { PACKAGE_PIN P5 IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
set_property -dict { PACKAGE_PIN U1 IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
set_property -dict { PACKAGE_PIN R2 IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
set_property -dict { PACKAGE_PIN P2 IOSTANDARD LVCMOS33 } [get_ports {led[15]}]

#set_property -dict { PACKAGE_PIN K5  IOSTANDARD LVCMOS33 } [get_ports RGB1_Red]
#set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports RGB1_Green]
#set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports RGB1_Blue]
#set_property -dict { PACKAGE_PIN K6  IOSTANDARD LVCMOS33 } [get_ports RGB2_Red]
#set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports RGB2_Green]
#set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports RGB2_Blue]

##7 segment display
set_property -dict { PACKAGE_PIN L3 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[0]}]
set_property -dict { PACKAGE_PIN N1 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[1]}]
set_property -dict { PACKAGE_PIN L5 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[2]}]
set_property -dict { PACKAGE_PIN L4 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[3]}]
set_property -dict { PACKAGE_PIN K3 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[4]}]
set_property -dict { PACKAGE_PIN M2 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[5]}]
set_property -dict { PACKAGE_PIN L6 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[6]}]

set_property -dict { PACKAGE_PIN M4 IOSTANDARD LVCMOS33 } [get_ports {sseg_ca[7]}]

set_property -dict { PACKAGE_PIN N6 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[0]}]
set_property -dict { PACKAGE_PIN M6 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[1]}]
set_property -dict { PACKAGE_PIN M3 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[2]}]
set_property -dict { PACKAGE_PIN N5 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[3]}]
set_property -dict { PACKAGE_PIN N2 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[4]}]
set_property -dict { PACKAGE_PIN N4 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[5]}]
set_property -dict { PACKAGE_PIN L1 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[6]}]
set_property -dict { PACKAGE_PIN M1 IOSTANDARD LVCMOS33 } [get_ports {sseg_an[7]}]

##Buttons
set_property  -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports btnCpuReset]
set_property  -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property  -dict { PACKAGE_PIN F15 IOSTANDARD LVCMOS33 } [get_ports {btn[4]}]
set_property  -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property  -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]
set_property  -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]

##Pmod Header JA
set_property -dict { PACKAGE_PIN B13 IOSTANDARD LVCMOS33 } [get_ports {jalo[1]}]
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports {jalo[2]}]
set_property -dict { PACKAGE_PIN D17 IOSTANDARD LVCMOS33 } [get_ports {jalo[3]}]
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 } [get_ports {jalo[4]}]
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports {jahi[7]}]
set_property -dict { PACKAGE_PIN C17 IOSTANDARD LVCMOS33 } [get_ports {jahi[8]}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports {jahi[9]}]
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports {jahi[10]}]

##Pmod Header JB
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports {jblo[1]}]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports {jblo[2]}]
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports {jblo[3]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {jblo[4]}]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports {jbhi[7]}]
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 } [get_ports {jbhi[8]}]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports {jbhi[9]}]
set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 } [get_ports {jbhi[10]}]

##Pmod Header JC
set_property -dict { PACKAGE_PIN K2 IOSTANDARD LVCMOS33 } [get_ports {jclo[1]}]
set_property -dict { PACKAGE_PIN E7 IOSTANDARD LVCMOS33 } [get_ports {jclo[2]}]
set_property -dict { PACKAGE_PIN J3 IOSTANDARD LVCMOS33 } [get_ports {jclo[3]}]
set_property -dict { PACKAGE_PIN J4 IOSTANDARD LVCMOS33 } [get_ports {jclo[4]}]
#set_property -dict { PACKAGE_PIN K1 IOSTANDARD LVCMOS33 } [get_ports {jchi[7]}]
#set_property -dict { PACKAGE_PIN E6 IOSTANDARD LVCMOS33 } [get_ports {jchi[8]}]
set_property -dict { PACKAGE_PIN J2 IOSTANDARD LVCMOS33 } [get_ports {jchi[9]}]
set_property -dict { PACKAGE_PIN G6 IOSTANDARD LVCMOS33 } [get_ports {jchi[10]}]

##Pmod Header JD
set_property -dict { PACKAGE_PIN H4 IOSTANDARD LVCMOS33 } [get_ports {jdlo[1]}]
set_property -dict { PACKAGE_PIN H1 IOSTANDARD LVCMOS33 } [get_ports {jdlo[2]}]
set_property -dict { PACKAGE_PIN G1 IOSTANDARD LVCMOS33 } [get_ports {jdlo[3]}]
set_property -dict { PACKAGE_PIN G3 IOSTANDARD LVCMOS33 } [get_ports {jdlo[4]}]
set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports {jdhi[7]}]
set_property -dict { PACKAGE_PIN G4 IOSTANDARD LVCMOS33 } [get_ports {jdhi[8]}]
set_property -dict { PACKAGE_PIN G2 IOSTANDARD LVCMOS33 } [get_ports {jdhi[9]}]
set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports {jdhi[10]}]

##Pmod Header JXADC
#set_property -dict { PACKAGE_PIN A13 IOSTANDARD LVCMOS33 } [get_ports {JXADC[0]}]
#set_property -dict { PACKAGE_PIN A15 IOSTANDARD LVCMOS33 } [get_ports {JXADC[1]}]
#set_property -dict { PACKAGE_PIN B16 IOSTANDARD LVCMOS33 } [get_ports {JXADC[2]}]
#set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports {JXADC[3]}]
#set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports {JXADC[4]}]
#set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports {JXADC[5]}]
#set_property -dict { PACKAGE_PIN B17 IOSTANDARD LVCMOS33 } [get_ports {JXADC[6]}]
#set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports {JXADC[7]}]

##VGA Connector
set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports {vgared[0]}]
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports {vgared[1]}]
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports {vgared[2]}]
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports {vgared[3]}]
set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports {vgablue[0]}]
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports {vgablue[1]}]
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports {vgablue[2]}]
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports {vgablue[3]}]
set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports {vgagreen[0]}]
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports {vgagreen[1]}]
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports {vgagreen[2]}]
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports {vgagreen[3]}]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports hsync]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports vsync]

##Micro SD Connector
set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports sdReset]
#set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports sdCD]
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports sdClock]
set_property -dict { PACKAGE_PIN C1 IOSTANDARD LVCMOS33 } [get_ports sdMOSI]
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports sdMISO]
#set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports {sdData[1]}]
#set_property -dict { PACKAGE_PIN F1 IOSTANDARD LVCMOS33 } [get_ports {sdData[2]}]
#set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports {sdData[3]}]

##Accelerometer
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports aclMISO]
set_property -dict { PACKAGE_PIN B14 IOSTANDARD LVCMOS33 } [get_ports aclMOSI]
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports aclSCK]
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports aclSS]
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports aclInt1]
set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports aclInt2]

##Temperature Sensor
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports tmpSCL]
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports tmpSDA]
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 } [get_ports tmpInt]
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 } [get_ports tmpCT]

##Omnidirectional Microphone
set_property -dict { PACKAGE_PIN J5 IOSTANDARD LVCMOS33 } [get_ports micClk]
set_property -dict { PACKAGE_PIN H5 IOSTANDARD LVCMOS33 } [get_ports micData]
set_property -dict { PACKAGE_PIN F5 IOSTANDARD LVCMOS33 } [get_ports micLRSel]

##PWM Audio Amplifier
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports ampPWM]
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports ampSD]

##USB-RS232 Interface
set_property -dict { PACKAGE_PIN C4 IOSTANDARD LVCMOS33 } [get_ports RsRx]
set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports UART_TXD]
#set_property -dict { PACKAGE_PIN D3 IOSTANDARD LVCMOS33 } [get_ports RsCts]
#set_property -dict { PACKAGE_PIN E5 IOSTANDARD LVCMOS33 } [get_ports RsRts]

##USB HID (PS/2)
set_property -dict { PACKAGE_PIN F4 IOSTANDARD LVCMOS33 PULLUP true } [get_ports ps2clk]
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 PULLUP true }  [get_ports ps2data]

##SMSC Ethernet PHY
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports eth_mdc]
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports eth_mdio]
set_property -dict { PACKAGE_PIN B3  IOSTANDARD LVCMOS33 } [get_ports eth_reset]
# the below eth_rxdv was called PhyCrs, unsure if this is correct, need to check
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports eth_rxdv]
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports eth_rxer]
# BG: i think the eth_Rxd<0> and <1> are swapped around, as the DDR-board ucf from Nexys shows these swapped, need to check
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[0]}]
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports {eth_rxd[1]}]
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports eth_txen]
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports {eth_txd[0]}]
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports {eth_txd[1]}]
set_property -dict { PACKAGE_PIN D5  IOSTANDARD LVCMOS33 } [get_ports eth_clock]
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports eth_interrupt]

##Quad SPI Flash
#set_property  -dict { PACKAGE_PIN E9  IOSTANDARD LVCMOS33 } [get_ports {QspiSCK}]
set_property  -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[0]}]
set_property  -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[1]}]
set_property  -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[2]}]
set_property  -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {QspiDB[3]}]
set_property  -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports QspiCSn]

##Cellular RAM
#set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports RamCLK]
#set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports RamADVn]
#set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 } [get_ports RamCEn]
#set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports RamCRE]
#set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports RamOEn]
#set_property -dict { PACKAGE_PIN R11 IOSTANDARD LVCMOS33 } [get_ports RamWEn]
#set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports RamLBn]
#set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports RamUBn]
#set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports RamWait]

#set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports {MemDB[0]}]
#set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {MemDB[1]}]
#set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {MemDB[2]}]
#set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 } [get_ports {MemDB[3]}]
#set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[4]}]
#set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 } [get_ports {MemDB[5]}]
#set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[6]}]
#set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[7]}]
#set_property -dict { PACKAGE_PIN F18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[8]}]
#set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[9]}]
#set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports {MemDB[10]}]
#set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[11]}]
#set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 } [get_ports {MemDB[12]}]
#set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 } [get_ports {MemDB[13]}]
#set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports {MemDB[14]}]
#set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 } [get_ports {MemDB[15]}]

#set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[0]}]
#set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[1]}]
#set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[2]}]
#set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[3]}]
#set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[4]}]
#set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[5]}]
#set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[6]}]
#set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[7]}]
#set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[8]}]
#set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[9]}]
#set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[10]}]
#set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[11]}]
#set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[12]}]
#set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[13]}]
#set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[14]}]
#set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[15]}]
#set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[16]}]
#set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[17]}]
#set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[18]}]
#set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[19]}]
#set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[20]}]
#set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[21]}]
#set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {MemAdr[22]}]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 26 [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
