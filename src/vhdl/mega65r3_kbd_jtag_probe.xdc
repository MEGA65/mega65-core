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
## kb_tck and kb_tms transmit slowed pin_id streams.
## kb_tdi drives a slow 1011001010010110 loopback test pattern.
## kb_tdo is sampled; if it matches kb_tdi for long enough, led_g/led_r blink
## alternately. If it does not match, both LEDs stay off.
## kb_jtagen toggles every 2 seconds.
## The pin_id clock is divided from clock41 by 5000, giving about 4.2ms per
## pin_id bit slot.
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports kb_tck]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33 PULLDOWN true} [get_ports kb_tdo]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports kb_tms]
set_property -dict {PACKAGE_PIN D15 IOSTANDARD LVCMOS33} [get_ports kb_tdi]
set_property -dict {PACKAGE_PIN B13 IOSTANDARD LVCMOS33} [get_ports kb_jtagen]

## On-board LEDs direct connected to the main FPGA.
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports led_g]
set_property -dict {PACKAGE_PIN V20 IOSTANDARD LVCMOS33} [get_ports led_r]
