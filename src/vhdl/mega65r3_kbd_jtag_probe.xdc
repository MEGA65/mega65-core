### Magic comment to allow monitor_load JTAG to automatically use the correct
### part boundary scan information.
### monitor_load:hint:part:xc7ar200tfbg484

## Clock signal (100MHz)
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports CLK_IN]
create_clock -period 10.000 -name CLK_IN [get_ports CLK_IN]
create_generated_clock -name clock41 [get_pins clocks1/mmcm_adv0/CLKOUT3]

## C65 keyboard connector JTAG-like pins
##
## One pinprober instance cycles through pins 1..4, which are plumbed to:
##   1 = kb_tck, 2 = kb_tdo, 3 = kb_tms, 4 = kb_tdi
## The remaining 78 pinprober outputs are intentionally unused.
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports kb_tck]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports kb_tdo]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports kb_tms]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports kb_tdi]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports kb_jtagen]
