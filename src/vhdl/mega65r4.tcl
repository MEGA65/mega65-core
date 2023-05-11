## MEGA65R4 constraints
## Moved from XDC to TCL to remove need for commenting/uncommenting.

### Magic comment to allow monitor_load JTAg to automatically use the correct
### part boundary scan information.
### monitor_load:hint:part:xc7ar200tfbg484

set pins {
    { CLK_IN                 V13   LVCMOS33                                  }
    { led                    U22   LVCMOS33                                  }
    { led_g                  V19   LVCMOS33                                  }
    { led_r                  V20   LVCMOS33                                  }
    { iec_reset              AB21  LVCMOS33                                  }
    { iec_atn                N17   LVCMOS33                                  }
    { iec_data_en            Y21   LVCMOS33                                  }
    { iec_data_o             Y22   LVCMOS33                                  }
    { iec_data_i             AB22  LVCMOS33  PULLUP true                     }
    { iec_clk_en             AA21  LVCMOS33                                  }
    { iec_clk_o              Y19   LVCMOS33                                  }
    { iec_clk_i              Y18   LVCMOS33  PULLUP true                     }
    { iec_srq_o              U20   LVCMOS33                                  }
    { iec_srq_i              AA18  LVCMOS33                                  }
    { iec_srq_en             AB20  LVCMOS33                                  }
    { dipsw[0]               N18   LVCMOS33                                  }
    { dipsw[1]               P19   LVCMOS33                                  }
    { dipsw[2]               T16   LVCMOS33                                  }
    { dipsw[3]               U16   LVCMOS33                                  }
    { reset_button           J19   LVCMOS33                                  }
    { cart_ctrl_dir          U17   LVCMOS33                                  }
    { cart_ctrl_en           G18   LVCMOS33                                  }
    { cart_haddr_dir         L18   LVCMOS33                                  }
    { cart_laddr_dir         L21   LVCMOS33                                  }
    { cart_data_dir          V22   LVCMOS33                                  }
    { cart_addr_en           L19   LVCMOS33                                  }
    { cart_data_en           U21   LVCMOS33                                  }
    { cart_phi2              V17   LVCMOS33                                  }
    { cart_dotclock          AA19  LVCMOS33                                  }
    { cart_reset             N14   LVCMOS33                                  }
    { cart_nmi               W17   LVCMOS33                                  }
    { cart_irq               P14   LVCMOS33                                  }
    { cart_dma               P15   LVCMOS33                                  }
    { cart_exrom             R19   LVCMOS33                                  }
    { cart_ba                N13   LVCMOS33                                  }
    { cart_rw                R18   LVCMOS33                                  }
    { cart_roml              AB18  LVCMOS33                                  }
    { cart_romh              T18   LVCMOS33                                  }
    { cart_io1               N15   LVCMOS33                                  }
    { cart_game              W22   LVCMOS33                                  }
    { cart_io2               AA20  LVCMOS33                                  }
    { cart_d[7]              W21   LVCMOS33                                  }
    { cart_d[6]              W20   LVCMOS33                                  }
    { cart_d[5]              V18   LVCMOS33                                  }
    { cart_d[4]              U18   LVCMOS33                                  }
    { cart_d[3]              R16   LVCMOS33                                  }
    { cart_d[2]              P20   LVCMOS33                                  }
    { cart_d[1]              R17   LVCMOS33                                  }
    { cart_d[0]              P16   LVCMOS33                                  }
    { cart_a[15]             H18   LVCMOS33                                  }
    { cart_a[14]             N22   LVCMOS33                                  }
    { cart_a[13]             M20   LVCMOS33                                  }
    { cart_a[12]             H19   LVCMOS33                                  }
    { cart_a[11]             J15   LVCMOS33                                  }
    { cart_a[10]             G20   LVCMOS33                                  }
    { cart_a[9]              H20   LVCMOS33                                  }
    { cart_a[8]              H17   LVCMOS33                                  }
    { cart_a[7]              K22   LVCMOS33                                  }
    { cart_a[6]              J21   LVCMOS33                                  }
    { cart_a[5]              J20   LVCMOS33                                  }
    { cart_a[4]              L20   LVCMOS33                                  }
    { cart_a[3]              M22   LVCMOS33                                  }
    { cart_a[2]              K21   LVCMOS33                                  }
    { cart_a[1]              K18   LVCMOS33                                  }
    { cart_a[0]              K19   LVCMOS33                                  }
    { kb_tck                 E13   LVCMOS33                                  }
    { kb_tdo                 E14   LVCMOS33                                  }
    { kb_tms                 D14   LVCMOS33                                  }
    { kb_tdi                 D15   LVCMOS33                                  }
    { kb_io0                 A14   LVCMOS33                                  }
    { kb_io1                 A13   LVCMOS33                                  }
    { kb_io2                 C13   LVCMOS33                                  }
    { kb_jtagen              B13   LVCMOS33                                  }
    { paddle[0]              H13   LVCMOS33                                  }
    { paddle[1]              G15   LVCMOS33                                  }
    { paddle[2]              J14   LVCMOS33                                  }
    { paddle[3]              J22   LVCMOS33                                  }
    { paddle_drain           H22   LVCMOS33                                  }
    { dbg[10]                H14   LVCMOS33                                  }
    { dbg[11]                G13   LVCMOS33                                  }
    { joystick_5v_disable    D19   LVCMOS33                                  }
    { joystick_5v_powergood  D20   LVCMOS33                                  }
    { fa_down                F16   LVCMOS33                                  }
    { fa_down_drain_n        K14   LVCMOS33                                  }
    { fa_up                  C14   LVCMOS33                                  }
    { fa_up_drain_n          G16   LVCMOS33                                  }
    { fa_left                F14   LVCMOS33                                  }
    { fa_left_drain_n        K13   LVCMOS33                                  }
    { fa_right               F13   LVCMOS33                                  }
    { fa_right_drain_n       L16   LVCMOS33                                  }
    { fa_fire                E17   LVCMOS33                                  }
    { fa_fire_drain_n        J17   LVCMOS33                                  }
    { fb_down                P17   LVCMOS33                                  }
    { fb_down_drain_n        M18   LVCMOS33                                  }
    { fb_up                  W19   LVCMOS33                                  }
    { fb_up_drain_n          N20   LVCMOS33                                  }
    { fb_left                F21   LVCMOS33                                  }
    { fb_left_drain_n        M17   LVCMOS33                                  }
    { fb_right               C15   LVCMOS33                                  }
    { fb_right_drain_n       E18   LVCMOS33                                  }
    { fb_fire                F15   LVCMOS33                                  }
    { fb_fire_drain_n        N19   LVCMOS33                                  }
    { vga_sda                T15   LVCMOS33                                  }
    { vga_scl                W15   LVCMOS33                                  }
    { vdac_clk               AA9   LVCMOS33                                  }
    { vdac_sync_n            V10   LVCMOS33                                  }
    { vdac_blank_n           W11   LVCMOS33                                  }
    { vdac_psave_n           W16   LVCMOS33                                  }
    { vgared[0]              U15   LVCMOS33                                  }
    { vgared[1]              V15   LVCMOS33                                  }
    { vgared[2]              T14   LVCMOS33                                  }
    { vgared[3]              Y17   LVCMOS33                                  }
    { vgared[4]              Y16   LVCMOS33                                  }
    { vgared[5]              AB17  LVCMOS33                                  }
    { vgared[6]              AA16  LVCMOS33                                  }
    { vgared[7]              AB16  LVCMOS33                                  }
    { vgagreen[0]            Y14   LVCMOS33                                  }
    { vgagreen[1]            W14   LVCMOS33                                  }
    { vgagreen[2]            AA15  LVCMOS33                                  }
    { vgagreen[3]            AB15  LVCMOS33                                  }
    { vgagreen[4]            Y13   LVCMOS33                                  }
    { vgagreen[5]            AA14  LVCMOS33                                  }
    { vgagreen[6]            AA13  LVCMOS33                                  }
    { vgagreen[7]            AB13  LVCMOS33                                  }
    { vgablue[0]             W10   LVCMOS33                                  }
    { vgablue[1]             Y12   LVCMOS33                                  }
    { vgablue[2]             AB12  LVCMOS33                                  }
    { vgablue[3]             AA11  LVCMOS33                                  }
    { vgablue[4]             AB11  LVCMOS33                                  }
    { vgablue[5]             Y11   LVCMOS33                                  }
    { vgablue[6]             AB10  LVCMOS33                                  }
    { vgablue[7]             AA10  LVCMOS33                                  }
    { hsync                  W12   LVCMOS33                                  }
    { vsync                  V14   LVCMOS33                                  }
    { TMDS_clk_n             Y1    TMDS_33                                   }
    { TMDS_clk_p             W1    TMDS_33                                   }
    { TMDS_data_n[0]         AB1   TMDS_33                                   }
    { TMDS_data_p[0]         AA1   TMDS_33                                   }
    { TMDS_data_n[1]         AB2   TMDS_33                                   }
    { TMDS_data_p[1]         AB3   TMDS_33                                   }
    { TMDS_data_n[2]         AB5   TMDS_33                                   }
    { TMDS_data_p[2]         AA5   TMDS_33                                   }
    { hdmi_scl               AB7   LVCMOS33                                  }
    { hdmi_sda               V9    LVCMOS33                                  }
    { hdmi_enable_n          AB8   LVCMOS33                                  }
    { hdmi_hotplugdetect     Y8    LVCMOS33                                  }
    { hdmi_cec_a             W9    LVCMOS33                                  }
    { fpga_scl               A15   LVCMOS33                                  }
    { fpga_sda               A16   LVCMOS33                                  }
    { scl_a                  AB7   LVCMOS33                                  }
    { sda_a                  V9    LVCMOS33                                  }
    { cec_a                  W9    LVCMOS33                                  }
    { hpd_a                  Y8    LVCMOS33                                  }
    { hdmi_hiz               M15   LVCMOS33                                  }
    { ls_oe                  AB8   LVCMOS33                                  }
    { grove_scl              G21   LVCMOS33                                  }
    { grove_sda              G22   LVCMOS33                                  }
    { audio_lrclk            F19   LVCMOS33                                  }
    { audio_sdata            E16   LVCMOS33                                  }
    { audio_bick             E19   LVCMOS33                                  }
    { audio_mclk             D16   LVCMOS33                                  }
    { audio_powerdown_n      F18   LVCMOS33                                  }
    { audio_smute            F4    LVCMOS33                                  }
    { audio_acks             L6    LVCMOS33                                  }
    { audio_cdti             W9    LVCMOS33                                  }
    { pwm_l                  L6    LVCMOS33                                  }
    { pwm_r                  F4    LVCMOS33                                  }
    { QspiDB[0]              P22   LVCMOS33  PULLUP TRUE                     }
    { QspiDB[1]              R22   LVCMOS33  PULLUP TRUE                     }
    { QspiDB[2]              P21   LVCMOS33  PULLUP TRUE                     }
    { QspiDB[3]              R21   LVCMOS33  PULLUP TRUE                     }
    { QspiCSn                T19   LVCMOS33                                  }
    { sdram_clk              V8    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_cke              U5    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_ras_n            T5    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_cas_n            V3    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_we_n             G1    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_cs_n             G3    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_ba[0]            U3    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_ba[1]            R4    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[0]             T4    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[1]             R2    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[2]             R3    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[3]             T3    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[4]             Y4    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[5]             W6    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[6]             W4    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[7]             U7    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[8]             AA8   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[9]             Y2    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[10]            R6    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[11]            Y7    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_a[12]            Y9    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dqml             W2    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dqmh             Y6    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[0]            V5    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[1]            T1    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[2]            V4    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[3]            U2    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[4]            V2    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[5]            U1    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[6]            U6    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[7]            T6    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[8]            W7    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[9]            AA3   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[10]           AA4   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[11]           V7    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[12]           AA6   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[13]           W5    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[14]           AB6   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { sdram_dq[15]           Y3    LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_clk_p               D22   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[0]                A21   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[1]                D21   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[2]                C20   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[3]                A20   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[4]                B20   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[5]                A19   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[6]                E21   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_d[7]                E22   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_rwds                B21   LVCMOS33  PULLUP FALSE SLEW FAST DRIVE 16 }
    { hr_reset               B22   LVCMOS33  PULLUP FALSE                    }
    { hr_cs0                 C22   LVCMOS33  PULLUP FALSE                    }
    { p1lo[0]                F1    LVCMOS33                                  }
    { p1lo[1]                D1    LVCMOS33                                  }
    { p1lo[2]                B2    LVCMOS33                                  }
    { p1lo[3]                A1    LVCMOS33                                  }
    { p1hi[0]                A18   LVCMOS33                                  }
    { p1hi[1]                E1    LVCMOS33                                  }
    { p1hi[2]                C2    LVCMOS33                                  }
    { p1hi[3]                B1    LVCMOS33                                  }
    { p2lo[0]                F3    LVCMOS33                                  }
    { p2lo[1]                E3    LVCMOS33                                  }
    { p2lo[2]                H4    LVCMOS33                                  }
    { p2lo[3]                H5    LVCMOS33                                  }
    { p2hi[0]                E2    LVCMOS33                                  }
    { p2hi[1]                D2    LVCMOS33                                  }
    { p2hi[2]                G4    LVCMOS33                                  }
    { p2hi[3]                J5    LVCMOS33                                  }
    { hr2_clk_p              G1    LVCMOS33  PULLUP FALSE                    }
    { hr2_clk_n              F1    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[0]               B2    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[1]               E1    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[2]               G4    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[3]               E3    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[4]               D2    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[5]               B1    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[6]               C2    LVCMOS33  PULLUP FALSE                    }
    { hr2_d[7]               D1    LVCMOS33  PULLUP FALSE                    }
    { hr2_rwds               H4    LVCMOS33  PULLUP FALSE                    }
    { hr2_reset              H5    LVCMOS33  PULLUP FALSE                    }
    { hr2_cs0                J5    LVCMOS33  PULLUP FALSE                    }
    { eth_led[1]             R14   LVCMOS33                                  }
    { eth_rxd[0]             P4    LVCMOS33                                  }
    { eth_rxd[1]             L1    LVCMOS33                                  }
    { eth_txd[0]             L3    LVCMOS33  SLEW SLOW DRIVE 4               }
    { eth_txd[1]             K3    LVCMOS33  SLEW SLOW DRIVE 4               }
    { eth_rxdv               K4    LVCMOS33                                  }
    { eth_mdc                J6    LVCMOS33                                  }
    { eth_mdio               L5    LVCMOS33                                  }
    { eth_clock              L4    LVCMOS33  SLEW FAST                       }
    { eth_reset              K6    LVCMOS33                                  }
    { eth_txen               J4    LVCMOS33  SLEW SLOW DRIVE 4               }
    { eth_rxer               M6    LVCMOS33                                  }
    { eth_crs_dv             K4    LVCMOS33                                  }
    { UART_TXD               L13   LVCMOS33                                  }
    { RsRx                   L14   LVCMOS33                                  }
    { pmod1_en               J16   LVCMOS33                                  }
    { pmod1_flag             K16   LVCMOS33                                  }
    { pmod2_en               M13   LVCMOS33                                  }
    { pmod2_flag             K17   LVCMOS33                                  }
    { board_rev[0]           L15   LVCMOS33                                  }
    { board_rev[1]           M16   LVCMOS33                                  }
    { board_rev[2]           F20   LVCMOS33                                  }
    { board_rev[3]           W9    LVCMOS33                                  }
    { sd2CD                  K1    LVCMOS33                                  }
    { sd2Clock               G2    LVCMOS33                                  }
    { sd2reset               K2    LVCMOS33                                  }
    { sd2MISO                H2    LVCMOS33                                  }
    { sd2MOSI                J2    LVCMOS33                                  }
    { sd2_dat[0]             H2    LVCMOS33                                  }
    { sd2_dat[1]             H3    LVCMOS33                                  }
    { sd2_dat[2]             J1    LVCMOS33                                  }
    { sd2_dat[3]             K2    LVCMOS33                                  }
    { sdClock                B17   LVCMOS33                                  }
    { sdReset                B15   LVCMOS33                                  }
    { sdMISO                 B18   LVCMOS33                                  }
    { sdMOSI                 B16   LVCMOS33                                  }
    { sdWP                   C17   LVCMOS33                                  }
    { sdCD                   D17   LVCMOS33                                  }
    { sd_dat[0]              B18   LVCMOS33                                  }
    { sd_dat[1]              C18   LVCMOS33                                  }
    { sd_dat[2]              C19   LVCMOS33                                  }
    { sd_dat[3]              B15   LVCMOS33                                  }
    { f_density              P6    LVCMOS33                                  }
    { f_motora               M5    LVCMOS33                                  }
    { f_motorb               H15   LVCMOS33                                  }
    { f_selecta              N5    LVCMOS33                                  }
    { f_selectb              G17   LVCMOS33                                  }
    { f_stepdir              P5    LVCMOS33                                  }
    { f_step                 M3    LVCMOS33                                  }
    { f_wdata                N4    LVCMOS33                                  }
    { f_wgate                N3    LVCMOS33                                  }
    { f_side1                M1    LVCMOS33                                  }
    { f_index                M2    LVCMOS33                                  }
    { f_track0               N2    LVCMOS33                                  }
    { f_writeprotect         P2    LVCMOS33                                  }
    { f_rdata                P1    LVCMOS33                                  }
    { f_diskchanged          R1    LVCMOS33                                  }
}

foreach pin $pins {
    set name [lindex $pin 0]
    if  {[llength [get_ports -quiet $name]]} {
        set number [lindex $pin 1]
		if {[llength $pin] == 2} {
			set_property -dict "PACKAGE_PIN $number" [get_ports $name]
		} else {
			set iostandard [lindex $pin 2]
			set misc [lrange $pin 3 end]
			set_property -dict "PACKAGE_PIN $number IOSTANDARD $iostandard $misc" [get_ports $name]
		}
    }
}

## Clock signal (100MHz)
create_clock -period 10.000 -name CLK_IN [get_ports CLK_IN]
#set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clocks1/CLKOUT0]

# C64 Cartridge port
# Place Cartidge near IO Pins
create_pblock pblock_cart
add_cells_to_pblock pblock_cart [get_cells [list slow_devices0/cartport0]]
resize_pblock pblock_cart -add {SLICE_X0Y137:SLICE_X7Y185}

# C65 Keyboard
# Place Keyboard close to I/O pins
create_pblock pblock_kbd0
add_cells_to_pblock pblock_kbd0 [get_cells [list kbd0]]
resize_pblock pblock_kbd0 -add {SLICE_X0Y225:SLICE_X7Y243}

## Hyper RAM

# 80 MHz Hyperram bus
set hbus_freq_ns   12
# Set allowable clock drift 
set dqs_in_min_dly -0.5
set dqs_in_max_dly  0.5
 
set hr0_dq_ports    [get_ports -quiet hr_d[*]]
set hr2_dq_ports    [get_ports -quiet hr2_d[*]]
# Set 6ns max delay to/from various HyperRAM pins
# (But add 17ns extra, because of weird ways Vivado calculates the apparent latency)
if  {[llength $hr0_dq_ports]} {
    set_max_delay -from [get_clocks clock163] -to ${hr0_dq_ports} 23
    set_max_delay -to [get_clocks clock163] -from ${hr0_dq_ports} 23
    set_max_delay -from [get_clocks clock163] -to hr_rwds 23
    set_max_delay -to [get_clocks clock163] -from hr_rwds 23
    # Place HyperRAM close to I/O pins
    create_pblock pblock_hyperram
    add_cells_to_pblock pblock_hyperram [get_cells [list hyperram0]]
    resize_pblock pblock_hyperram -add {SLICE_X0Y186:SLICE_X35Y224}
    resize_pblock pblock_hyperram -add {SLICE_X8Y175:SLICE_X23Y186}
}
if  {[llength $hr2_dq_ports]} {
    set_max_delay -from [get_clocks clock163] -to ${hr2_dq_ports} 23
    set_max_delay -to [get_clocks clock163] -from ${hr2_dq_ports} 23
    set_max_delay -from [get_clocks clock163] -to hr2_rwds 23
    set_max_delay -to [get_clocks clock163] -from hr2_rwds 23
}

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
create_clock -name eth_rx_clock -period  20 -waveform  {0 10} [get_ports {eth_clock}]
set_input_delay -clock [get_clocks eth_rx_clock] -max 15 [get_ports {eth_rxd[1] eth_rxd[0]}]
set_input_delay -clock [get_clocks eth_rx_clock] -min 5  [get_ports {eth_rxd[1] eth_rxd[0]}]

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
#set_false_path -from [get_clocks CLKOUT3] -to [get_clocks u_clock50]
#set_false_path -from [get_clocks u_clock50] -to [get_clocks CLKOUT3]

## Fix 12.288MHz clock generation clock domain crossing
#set_false_path -from [get_clocks CLKOUT3] -to [get_clocks clk_60]
