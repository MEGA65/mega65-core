### Magic comment to allow monitor_load JTAG to automatically use the correct
### part boundary scan information.
### monitor_load:hint:part:xc7ar200tfbg484

## Clock signal (100MHz)
set_property -dict {PACKAGE_PIN V13 IOSTANDARD LVCMOS33} [get_ports CLK_IN]
create_clock -period 10.000 -name CLK_IN [get_ports CLK_IN]
create_generated_clock -name clock41 [get_pins clocks1/mmcm_adv0/CLKOUT3]
create_generated_clock -name probe_clock -source [get_pins clocks1/mmcm_adv0/CLKOUT3] -divide_by 10000 [get_pins probe_clock_reg/Q]

## C65 keyboard connector JTAG-like pins
##
## Each pin transmits the pin_id framing pattern followed by its ID byte:
##   1 = kb_tck, 2 = kb_tdo, 3 = kb_tms, 4 = kb_tdi
## The pin_id clock is divided from clock41 by 5000, giving about 4.2ms per
## pin_id bit slot.
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports kb_tck]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33} [get_ports kb_tdo]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports kb_tms]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports kb_tdi]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports kb_jtagen]
