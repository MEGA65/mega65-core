.SUFFIXES: .bin .prg
.PRECIOUS:	%.ngd %.ncd %.twx vivado/%.xpr bin/%.bit bin/%.mcs bin/%.M65 bin/%.BIN

#COPT=	-Wall -g -std=gnu99 -fsanitize=address -fno-omit-frame-pointer -fsanitize-address-use-after-scope
#CC=	clang
COPT=	-Wall -g -std=gnu99
CC=	gcc

OPHIS=	Ophis/bin/ophis
OPHISOPT=	-4
OPHIS_MON= Ophis/bin/ophis -c

JAVA = java
KICKASS_JAR = KickAss/KickAss.jar

VIVADO=	./vivado_wrapper

CC65=  cc65/bin/cc65
CA65=  cc65/bin/ca65 --cpu 4510
LD65=  cc65/bin/ld65 -t none
CL65=  cc65/bin/cl65 --config src/tests/vicii.cfg
GHDL=  ghdl/build/bin/ghdl

CBMCONVERT=	cbmconvert/cbmconvert

ASSETS=		assets
SRCDIR=		src
BINDIR=		bin
UTILDIR=	$(SRCDIR)/utilities
TESTDIR=	$(SRCDIR)/tests
VHDLSRCDIR=	$(SRCDIR)/vhdl
VERILOGSRCDIR=	$(SRCDIR)/verilog

SDCARD_DIR=	sdcard-files

# if you want your PRG to appear on "MEGA65.D81", then put your PRG in "./d81-files"
# ie: COMMANDO.PRG
#
# if you want your .a65 source code compiled and then embedded within "MEGA65.D81", then put
# your source.a65 in the 'utilities' directory, and ensure it is listed below.
#
# NOTE: that all files listed below will be embedded within the "MEGA65.D81".
#
UTILITIES=	$(UTILDIR)/ethertest.prg \
		$(UTILDIR)/etherload.prg \
		$(UTILDIR)/test01prg.prg \
		$(UTILDIR)/c65test02prg.prg \
		$(UTILDIR)/c65-rom-910111-fastload-patch.prg \
		$(UTILDIR)/hdmitest.prg \
		$(UTILDIR)/vfpgatest.prg \
		$(UTILDIR)/sdbitbash.prg \
		d81-files/* \
		$(UTILDIR)/diskmenu.prg

TOOLDIR=	$(SRCDIR)/tools
TOOLS=	$(TOOLDIR)/etherhyppo/etherhyppo \
	$(TOOLDIR)/etherload/etherload \
	$(TOOLDIR)/hotpatch/hotpatch \
	$(TOOLDIR)/monitor_load \
	$(TOOLDIR)/mega65_ftp \
	$(TOOLDIR)/monitor_save \
	$(TOOLDIR)/on_screen_keyboard_gen \
	$(TOOLDIR)/pngprepare/pngprepare \
	$(TOOLDIR)/pngprepare/pngtoscreens \
	$(TOOLDIR)/pngprepare/giftotiles \
	$(TOOLDIR)/i2cstatemapper

all:	$(SDCARD_DIR)/MEGA65.D81 $(BINDIR)/mega65r1.mcs $(BINDIR)/nexys4.mcs $(BINDIR)/nexys4ddr.mcs $(TOOLDIR)/monitor_load $(TOOLDIR)/mega65_ftp $(TOOLDIR)/monitor_save $(SDCARD_DIR)/FREEZER.M65

$(SDCARD_DIR)/FREEZER.M65:
	git submodule init
	git submodule update
	( cd src/mega65-freezemenu && make FREEZER.M65 )
	cp src/mega65-freezemenu/FREEZER.M65 $(SDCARD_DIR)

$(CBMCONVERT):
	git submodule init
	git submodule update
	( cd cbmconvert && make -f Makefile.unix )

$(CC65):
	git submodule init
	git submodule update
	( cd cc65 && make -j 8 )

$(OPHIS):
	git submodule init
	git submodule update

$(GHDL):
	git submodule init
	git submodule update
	( cd ghdl && ./configure --prefix=./build && make && make install )

# Not quite yet with Vivado...
# $(BINDIR)/nexys4.mcs $(BINDIR)/nexys4ddr.mcs $(BINDIR)/lcd4ddr.mcs $(BINDIR)/touch_test.mcs

generated_vhdl:	$(SIMULATIONVHDL)


# files destined to go on the SD-card to serve as firmware for the MEGA65
firmware:	$(SDCARD_DIR)/BANNER.M65 \
		$(BINDIR)/HICKUP.M65 \
		$(BINDIR)/COLOURRAM.BIN \
		$(SDCARD_DIR)/MEGA65.D81 \
		$(SDCARD_DIR)/C000UTIL.BIN

roms:		$(SDCARD_DIR)/CHARROM.M65 \
		$(SDCARD_DIR)/MEGA65.ROM

# c-programs
tools:	$(TOOLS)

# assembly files (a65 -> prg)
utilities:	$(UTILITIES)

SIDVHDL=		$(VHDLSRCDIR)/sid_6581.vhd \
			$(VHDLSRCDIR)/sid_coeffs_mux.vhd \
			$(VHDLSRCDIR)/sid_coeffs.vhd \
			$(VHDLSRCDIR)/sid_components.vhd \
			$(VHDLSRCDIR)/sid_filters.vhd \
			$(VHDLSRCDIR)/sid_voice.vhd \

CPUVHDL=		$(VHDLSRCDIR)/gs4510.vhdl \
			$(VHDLSRCDIR)/multiply32.vhdl \
			$(VHDLSRCDIR)/divider32.vhdl \
			$(VHDLSRCDIR)/shifter32.vhdl

NOCPUVHDL=		$(VHDLSRCDIR)/nocpu.vhdl

C65VHDL=		$(SIDVHDL) \
			$(VHDLSRCDIR)/iomapper.vhdl \
			$(VHDLSRCDIR)/mouse_input.vhdl \
			$(VHDLSRCDIR)/cia6526.vhdl \
			$(VHDLSRCDIR)/c65uart.vhdl \
			$(VHDLSRCDIR)/UART_TX_CTRL.vhd \
			$(VHDLSRCDIR)/cputypes.vhdl \

VICIVVHDL=		$(VHDLSRCDIR)/viciv.vhdl \
			$(VHDLSRCDIR)/pixel_driver.vhdl \
			$(VHDLSRCDIR)/pixel_fifo.vhdl \
			$(VHDLSRCDIR)/frame_generator.vhdl \
			$(VHDLSRCDIR)/sprite.vhdl \
			$(VHDLSRCDIR)/vicii_sprites.vhdl \
			$(VHDLSRCDIR)/bitplane.vhdl \
			$(VHDLSRCDIR)/bitplanes.vhdl \
			$(VHDLSRCDIR)/victypes.vhdl \
			$(VHDLSRCDIR)/pal_simulation.vhdl \
			$(VHDLSRCDIR)/ghdl_alpha_blend.vhdl \
			$(OVERLAYVHDL)

AUDIOVHDL=		$(VHDLSRCDIR)/audio_complex.vhdl \
			$(VHDLSRCDIR)/audio_mixer.vhdl \
			$(VHDLSRCDIR)/pdm_to_pcm.vhdl \
			$(VHDLSRCDIR)/pcm_to_pdm.vhdl \
			$(VHDLSRCDIR)/i2s_clock.vhdl \
			$(VHDLSRCDIR)/i2s_transceiver.vhdl \
			$(VHDLSRCDIR)/pcm_clock.vhdl \
			$(VHDLSRCDIR)/pcm_transceiver.vhdl

VFPGAVHDL=		$(VHDLSRCDIR)/vfpga/overlay_IP.vhdl \
			$(VHDLSRCDIR)/vfpga/vfpga_clock_controller_pausable.vhdl \
			$(VHDLSRCDIR)/vfpga/vfpga_wrapper_8bit.vhdl


PERIPHVHDL=		$(VHDLSRCDIR)/sdcardio.vhdl \
			$(VHDLSRCDIR)/touch.vhdl \
			$(VHDLSRCDIR)/i2c_master.vhdl \
			$(VHDLSRCDIR)/i2c_wrapper.vhdl \
			$(VHDLSRCDIR)/buffereduart.vhdl \
			$(VHDLSRCDIR)/mfm_bits_to_bytes.vhdl \
			$(VHDLSRCDIR)/mfm_decoder.vhdl \
			$(VHDLSRCDIR)/mfm_gaps_to_bits.vhdl \
			$(VHDLSRCDIR)/mfm_gaps.vhdl \
			$(VHDLSRCDIR)/mfm_quantise_gaps.vhdl \
			$(VHDLSRCDIR)/crc1581.vhdl \
			$(VHDLSRCDIR)/ethernet.vhdl \
			$(VHDLSRCDIR)/ethernet_miim.vhdl \
			$(VHDLSRCDIR)/ghdl_fpgatemp.vhdl \
			$(VHDLSRCDIR)/expansion_port_controller.vhdl \
			$(VHDLSRCDIR)/slow_devices.vhdl \
			$(VHDLSRCDIR)/mega65r2_i2c.vhdl \
			$(AUDIOVHDL) \
			$(KBDVHDL)

KBDVHDL=		$(VHDLSRCDIR)/keymapper.vhdl \
			$(VHDLSRCDIR)/keyboard_complex.vhdl \
			$(VHDLSRCDIR)/kb_matrix_ram.vhdl \
			$(VHDLSRCDIR)/keyboard_to_matrix.vhdl \
			$(VHDLSRCDIR)/matrix_to_ascii.vhdl \
			$(VHDLSRCDIR)/widget_to_matrix.vhdl \
			$(VHDLSRCDIR)/ps2_to_matrix.vhdl \
			$(VHDLSRCDIR)/keymapper.vhdl \
			$(VHDLSRCDIR)/virtual_to_matrix.vhdl \

OVERLAYVHDL=		$(VHDLSRCDIR)/rain.vhdl \
			$(VHDLSRCDIR)/lfsr16.vhdl \
			$(VHDLSRCDIR)/visual_keyboard.vhdl \
			$(VHDLSRCDIR)/uart_charrom.vhdl \
			$(VHDLSRCDIR)/oskmem.vhdl \
			$(VHDLSRCDIR)/termmem.vhdl \

1541VHDL=		$(VHDLSRCDIR)/internal1541.vhdl \
			$(VHDLSRCDIR)/driverom.vhdl \
			$(VHDLSRCDIR)/dpram8x4096.vhdl \

SERMONVHDL=		$(VHDLSRCDIR)/ps2_to_uart.vhdl \
			$(VHDLSRCDIR)/dummy_uart_monitor.vhdl \
			$(VHDLSRCDIR)/uart_rx.vhdl \

M65VHDL=		$(VHDLSRCDIR)/machine.vhdl \
			$(VHDLSRCDIR)/ddrwrapper.vhdl \
			$(VHDLSRCDIR)/framepacker.vhdl \
			$(VHDLSRCDIR)/hyppo.vhdl \
			$(VHDLSRCDIR)/version.vhdl \
			$(C65VHDL) \
			$(VICIVVHDL) \
			$(PERIPHVHDL) \
			$(1541VHDL) \
			$(VFPGAVHDL) \
			$(SERMONVHDL) \
			$(MEMVHDL) \
			$(SUPPORTVHDL)

SUPPORTVHDL=		$(VHDLSRCDIR)/debugtools.vhdl \
			$(VHDLSRCDIR)/crc.vhdl \

MEMVHDL=		$(VHDLSRCDIR)/ghdl_chipram8bit.vhdl \
			$(VHDLSRCDIR)/ghdl_farstack.vhdl \
			$(VHDLSRCDIR)/shadowram.vhdl \
			$(VHDLSRCDIR)/colourram.vhdl \
			$(VHDLSRCDIR)/charrom.vhdl \
			$(VHDLSRCDIR)/ghdl_ram128x1k.vhdl \
			$(VHDLSRCDIR)/ghdl_ram32x1024.vhdl \
			$(VHDLSRCDIR)/ghdl_ram18x2k.vhdl \
			$(VHDLSRCDIR)/ghdl_ram8x4096.vhdl \
			$(VHDLSRCDIR)/ghdl_ram8x4096_sync.vhdl \
			$(VHDLSRCDIR)/ghdl_ram32x1024_sync.vhdl \
			$(VHDLSRCDIR)/ghdl_ram8x512.vhdl \
			$(VHDLSRCDIR)/ghdl_ram9x4k.vhdl \
			$(VHDLSRCDIR)/ghdl_screen_ram_buffer.vhdl \
			$(VHDLSRCDIR)/ghdl_videobuffer.vhdl \
			$(VHDLSRCDIR)/ghdl_ram36x1k.vhdl \
			$(VHDLSRCDIR)/asym_ram.vhdl

NEXYSVHDL=		$(VHDLSRCDIR)/slowram.vhdl \
			$(VHDLSRCDIR)/sdcard.vhdl \
			$(CPUVHDL) \
			$(M65VHDL)


SIMULATIONVHDL=		$(VHDLSRCDIR)/cpu_test.vhdl \
			$(VHDLSRCDIR)/fake_expansion_port.vhdl \
			$(VHDLSRCDIR)/fake_sdcard.vhdl \
			$(VHDLSRCDIR)/uart_monitor.vhdl.tmp \
			$(CPUVHDL) \
			$(M65VHDL)

NOCPUSIMULATIONVHDL=	$(VHDLSRCDIR)/cpu_test.vhdl \
			$(VHDLSRCDIR)/fake_expansion_port.vhdl \
			$(NOCPUVHDL) \
			$(M65VHDL)

MONITORVERILOG=		$(VERILOGSRCDIR)/6502_alu.v \
			$(VERILOGSRCDIR)/6502_mux.v \
			$(VERILOGSRCDIR)/6502_reg.v \
			$(VERILOGSRCDIR)/6502_timing.v \
			$(VERILOGSRCDIR)/6502_top.v \
			$(VERILOGSRCDIR)/6502_ucode.v \
			$(VERILOGSRCDIR)/monitor.v \
			$(VERILOGSRCDIR)/monitor_ctrl.v \
			$(VERILOGSRCDIR)/monitor_ctrl_ram.v \
			$(VERILOGSRCDIR)/monitor_mem.v \
			$(VERILOGSRCDIR)/UART_TX_CTRL.v \
			$(VERILOGSRCDIR)/uart_rx.v


simulate:	$(GHDL) $(SIMULATIONVHDL) $(ASSETS)/synthesised-60ns.dat
	$(GHDL) -i $(SIMULATIONVHDL)
	$(GHDL) -m cpu_test
	./cpu_test || $(GHDL) -r cpu_test

nocpu:	$(GHDL) $(NOCPUSIMULATIONVHDL)
	$(GHDL) -i $(NOCPUSIMULATIONVHDL)
	$(GHDL) -m cpu_test
	./cpu_test || $(GHDL) -r cpu_test


KVFILES=$(VHDLSRCDIR)/test_kv.vhdl $(VHDLSRCDIR)/keyboard_to_matrix.vhdl $(VHDLSRCDIR)/matrix_to_ascii.vhdl \
	$(VHDLSRCDIR)/widget_to_matrix.vhdl $(VHDLSRCDIR)/ps2_to_matrix.vhdl $(VHDLSRCDIR)/keymapper.vhdl \
	$(VHDLSRCDIR)/keyboard_complex.vhdl $(VHDLSRCDIR)/virtual_to_matrix.vhdl
kvsimulate:	$(GHDL) $(KVFILES)
	$(GHDL) -i $(KVFILES)
	$(GHDL) -m test_kv
	./test_kv || $(GHDL) -r test_kv

OSKFILES=$(VHDLSRCDIR)/test_osk.vhdl \
	$(VHDLSRCDIR)/visual_keyboard.vhdl \
	$(VHDLSRCDIR)/oskmem.vhdl
osksimulate:	$(GHDL) $(OSKFILES) $(TOOLDIR)/osk_image
	$(GHDL) -i $(OSKFILES)
	$(GHDL) -m test_osk
	( ./test_osk || $(GHDL) -r test_osk ) 2>&1 | $(TOOLDIR)/osk_image

MMFILES=$(VHDLSRCDIR)/test_matrix.vhdl \
	$(VHDLSRCDIR)/rain.vhdl \
	$(VHDLSRCDIR)/lfsr16.vhdl \
	$(VHDLSRCDIR)/uart_charrom.vhdl \
	$(VHDLSRCDIR)/test_osk.vhdl \
	$(VHDLSRCDIR)/visual_keyboard.vhdl \
	$(VHDLSRCDIR)/oskmem.vhdl \
	$(VHDLSRCDIR)/termmem.vhdl

mmsimulate:	$(GHDL) $(MMFILES) $(TOOLDIR)/osk_image
	$(GHDL) -i $(MMFILES)
	$(GHDL) -m test_matrix
	( ./test_matrix || $(GHDL) -r test_matrix ) 2>&1 | $(TOOLDIR)/osk_image matrix.png

MFMFILES=$(VHDLSRCDIR)/mfm_bits_to_bytes.vhdl \
	 $(VHDLSRCDIR)/mfm_decoder.vhdl \
	 $(VHDLSRCDIR)/mfm_gaps_to_bits.vhdl \
	 $(VHDLSRCDIR)/mfm_gaps.vhdl \
	 $(VHDLSRCDIR)/mfm_quantise_gaps.vhdl \
	 $(VHDLSRCDIR)/crc1581.vhdl \
	 $(VHDLSRCDIR)/test_mfm.vhdl

mfmsimulate: $(GHDL) $(MFMFILES) $(ASSETS)/synthesised-60ns.dat
	$(GHDL) -i $(MFMFILES)
	$(GHDL) -m test_mfm
	( ./test_mfm || $(GHDL) -r test_mfm )

pdmsimulate: $(GHDL) $(VHDLSRCDIR)/test_pdm.vhdl $(VHDLSRCDIR)/pdm_to_pcm.vhdl
	$(GHDL) -i $(VHDLSRCDIR)/test_pdm.vhdl $(VHDLSRCDIR)/pdm_to_pcm.vhdl
	$(GHDL) -m test_pdm
	( ./test_pdm || $(GHDL) -r test_pdm )

hyperramsimulate: $(GHDL) $(VHDLSRCDIR)/test_hyperram.vhdl $(VHDLSRCDIR)/hyperram.vhdl $(VHDLSRCDIR)/debugtools.vhdl $(VHDLSRCDIR)/fakehyperram.vhdl $(VHDLSRCDIR)/slow_devices.vhdl $(VHDLSRCDIR)/cputypes.vhdl $(VHDLSRCDIR)/expansion_port_controller.vhdl $(VHDLSRCDIR)/reconfig.vhdl $(VHDLSRCDIR)/icape2sim.vhdl
	$(GHDL) -i $(VHDLSRCDIR)/test_hyperram.vhdl $(VHDLSRCDIR)/hyperram.vhdl $(VHDLSRCDIR)/debugtools.vhdl $(VHDLSRCDIR)/fakehyperram.vhdl $(VHDLSRCDIR)/slow_devices.vhdl $(VHDLSRCDIR)/cputypes.vhdl $(VHDLSRCDIR)/expansion_port_controller.vhdl $(VHDLSRCDIR)/reconfig.vhdl $(VHDLSRCDIR)/icape2sim.vhdl
	$(GHDL) -m test_hyperram
	( ./test_hyperram || $(GHDL) -r test_hyperram )


i2csimulate: $(GHDL) $(VHDLSRCDIR)/test_i2c.vhdl $(VHDLSRCDIR)/i2c_master.vhdl $(VHDLSRCDIR)/i2c_slave.vhdl $(VHDLSRCDIR)/debounce.vhdl $(VHDLSRCDIR)/touch.vhdl $(VHDLSRCDIR)/mega65r2_i2c.vhdl 
	$(GHDL) -i $(VHDLSRCDIR)/test_i2c.vhdl $(VHDLSRCDIR)/i2c_master.vhdl $(VHDLSRCDIR)/i2c_slave.vhdl $(VHDLSRCDIR)/debounce.vhdl $(VHDLSRCDIR)/touch.vhdl $(VHDLSRCDIR)/mega65r2_i2c.vhdl
	$(GHDL) -m test_i2c
	( ./test_i2c || $(GHDL) -r test_i2c )

k2simulate: $(GHDL) $(VHDLSRCDIR)/testkey.vhdl $(VHDLSRCDIR)/mega65kbd_to_matrix.vhdl
	$(GHDL) -i $(VHDLSRCDIR)/testkey.vhdl $(VHDLSRCDIR)/mega65kbd_to_matrix.vhdl
	$(GHDL) -m testkey
	( ./testkey || $(GHDL) -r testkey ) 


fpacksimulate: $(GHDL) $(VHDLSRCDIR)/test_framepacker.vhdl $(VHDLSRCDIR)/framepacker.vhdl
	$(GHDL) -i $(VHDLSRCDIR)/test_framepacker.vhdl $(VHDLSRCDIR)/framepacker.vhdl
	$(GHDL) -m test_framepacker
	( ./test_framepacker || $(GHDL) -r test_framepacker )


MIIMFILES=	$(VHDLSRCDIR)/ethernet_miim.vhdl \
		$(VHDLSRCDIR)/test_miim.vhdl

miimsimulate:	$(GHDL) $(MIIMFILES)
	$(GHDL) -i $(MIIMFILES)
	$(GHDL) -m test_miim
	( ./test_miim || $(GHDL) -r test_miim )

ASCIIFILES=	$(VHDLSRCDIR)/matrix_to_ascii.vhdl \
		$(VHDLSRCDIR)/test_ascii.vhdl

asciisimulate:	$(GHDL) $(ASCIIFILES)
	$(GHDL) -i $(ASCIIFILES)
	$(GHDL) -m test_ascii
	( ./test_ascii || $(GHDL) -r test_ascii )

SPRITEFILES=$(VHDLSRCDIR)/sprite.vhdl $(VHDLSRCDIR)/test_sprite.vhdl $(VHDLSRCDIR)/victypes.vhdl
spritesimulate:	$(GHDL) $(SPRITEFILES)
	$(GHDL) -i $(SPRITEFILES)
	$(GHDL) -m test_sprite
	./test_sprite || $(GHDL) -r test_sprite

$(TOOLDIR)/osk_image:	$(TOOLDIR)/osk_image.c
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/osk_image $(TOOLDIR)/osk_image.c -lpng

$(TOOLDIR)/frame2png:	$(TOOLDIR)/frame2png.c
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/frame2png $(TOOLDIR)/frame2png.c -lpng

$(TOOLDIR)/pngprepare/pngtoscreens:	$(TOOLDIR)/pngprepare/pngtoscreens.c
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/pngprepare/pngtoscreens $(TOOLDIR)/pngprepare/pngtoscreens.c -lpng

vfsimulate:	$(GHDL) $(VHDLSRCDIR)/frame_test.vhdl $(VHDLSRCDIR)/video_frame.vhdl
	$(GHDL) -i $(VHDLSRCDIR)/frame_test.vhdl $(VHDLSRCDIR)/video_frame.vhdl
	$(GHDL) -m frame_test
	./frame_test || $(GHDL) -r frame_test


# =======================================================================
# =======================================================================
# =======================================================================
# =======================================================================

# ============================
$(SDCARD_DIR)/CHARROM.M65:
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/CHARROM.M65)
	mkdir -p $(SDCARD_DIR)
	wget -O $(SDCARD_DIR)/CHARROM.M65 http://www.zimmers.net/anonftp/pub/cbm/firmware/characters/c65-caff.bin

# ============================
$(SDCARD_DIR)/MEGA65.ROM:
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/MEGA65.ROM)
	mkdir -p $(SDCARD_DIR)
	wget -O $(SDCARD_DIR)/MEGA65.ROM http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c65/910111-390488-01.bin

# ============================, print-warn, clean target
# verbose, for 1581 format, overwrite
$(SDCARD_DIR)/MEGA65.D81:	$(UTILITIES) $(CBMCONVERT)
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/MEGA65.D81)
	mkdir -p $(SDCARD_DIR)
	$(CBMCONVERT) -v2 -D8o $(SDCARD_DIR)/MEGA65.D81 $(UTILITIES)

# ============================ done moved, print-warn, clean-target
# ophis converts the *.a65 file (assembly text) to *.prg (assembly bytes)
%.prg:	%.a65 $(OPHIS)
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $@)
	$(OPHIS) $(OPHISOPT) $< -l $*.list -m $*.map -o $*.prg

%.bin:	%.a65 $(OPHIS)
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $@)
	$(OPHIS) $(OPHISOPT) $< -l $*.list -m $*.map -o $*.prg

%.o:	%.s $(CC65)
	$(CA65) $< -l $*.list

$(UTILDIR)/mega65_config.o:      $(UTILDIR)/mega65_config.s $(UTILDIR)/mega65_config.inc $(CC65)
	$(CA65) $< -l $*.list

$(TESTDIR)/vicii.prg:       $(TESTDIR)/vicii.c $(TESTDIR)/vicii_asm.s $(CC65)
	$(CL65) -O -o $*.prg --mapfile $*.map $< $(TESTDIR)/vicii_asm.s

$(TESTDIR)/pulseoxy.prg:       $(TESTDIR)/pulseoxy.c $(CC65)
	$(CL65) -O -o $*.prg --mapfile $*.map $< 

$(TESTDIR)/qspitest.prg:       $(TESTDIR)/qspitest.c $(CC65)
	$(CL65) -O -o $*.prg --mapfile $*.map $< 

$(TESTDIR)/unicorns.prg:       $(TESTDIR)/unicorns.c $(CC65)
	$(CL65) -O -o $*.prg --mapfile $*.map $<

$(TESTDIR)/eth_mdio.prg:       $(TESTDIR)/eth_mdio.c $(CC65)
	$(CL65) -O -o $*.prg --mapfile $*.map $< 

$(TESTDIR)/instructiontiming.prg:       $(TESTDIR)/instructiontiming.c $(TESTDIR)/instructiontiming_asm.s $(CC65)
	$(CL65) -O -o $*.prg --mapfile $*.map $< $(TESTDIR)/instructiontiming_asm.s

$(UTILDIR)/mega65_config.prg:       $(UTILDIR)/mega65_config.o $(CC65)
	$(LD65) $< --mapfile $*.map -o $*.prg

$(UTILDIR)/megaflash.prg:       $(UTILDIR)/megaflash.c $(CC65) $(wildcard $(SRCDIR)/mega65-libc/cc65/src/*.c) $(wildcard $(SRCDIR)/mega65-libc/cc65/src/*.s) $(wildcard $(SRCDIR)/mega65-libc/cc65/include/*.h)
	$(CL65) -I $(SRCDIR)/mega65-libc/cc65/include -O -o $*.prg --mapfile $*.map $< $(wildcard $(SRCDIR)/mega65-libc/cc65/src/*.c) $(wildcard $(SRCDIR)/mega65-libc/cc65/src/*.s)

$(UTILDIR)/i2clist.prg:       $(UTILDIR)/i2clist.c $(CC65)
	$(CL65) $< --mapfile $*.map -o $*.prg

$(UTILDIR)/i2cstatus.prg:       $(UTILDIR)/i2cstatus.c $(CC65)  $(SRCDIR)/mega65-libc/cc65/src/*.c $(SRCDIR)/mega65-libc/cc65/src/*.s $(SRCDIR)/mega65-libc/cc65/include/*.h
	$(CL65) -I $(SRCDIR)/mega65-libc/cc65/include -O -o $*.prg --mapfile $*.map $<  $(SRCDIR)/mega65-libc/cc65/src/*.c $(SRCDIR)/mega65-libc/cc65/src/*.s

$(UTILDIR)/floppystatus.prg:       $(UTILDIR)/floppystatus.c $(CC65)
	$(CL65) $< --mapfile $*.map -o $*.prg

$(UTILDIR)/tiles.prg:       $(UTILDIR)/tiles.o $(CC65)
	$(LD65) $< --mapfile $*.map -o $*.prg

$(UTILDIR)/diskmenuprg.o:      $(UTILDIR)/diskmenuprg.a65 $(UTILDIR)/diskmenu.a65 $(UTILDIR)/diskmenu_sort.a65 $(CC65)
	$(CA65) $< -l $*.list

$(UTILDIR)/diskmenu.prg:       $(UTILDIR)/diskmenuprg.o $(CC65)
	$(LD65) $< --mapfile $*.map -o $*.prg

$(SRCDIR)/mega65-fdisk/m65fdisk.prg:
	( cd $(SRCDIR)/mega65-fdisk ; make )

$(BINDIR)/border.prg: 	$(SRCDIR)/border.a65 $(OPHIS)
	$(OPHIS) $(OPHISOPT) $< -l $(BINDIR)/border.list -m $*.map -o $(BINDIR)/border.prg

# ============================ done moved, print-warn, clean-target
#??? diskmenu_c000.bin yet b0rken
$(BINDIR)/HICKUP.M65: $(SRCDIR)/hyppo/main.asm $(SRCDIR)/version.asm
	$(JAVA) -jar $(KICKASS_JAR) $< -afo

$(SRCDIR)/monitor/monitor_dis.a65: $(SRCDIR)/monitor/gen_dis
	$(SRCDIR)/monitor/gen_dis >$(SRCDIR)/monitor/monitor_dis.a65

$(BINDIR)/monitor.m65:	$(SRCDIR)/monitor/monitor.a65 $(SRCDIR)/monitor/monitor_dis.a65 $(SRCDIR)/monitor/version.a65
	$(OPHIS_MON) $< -l monitor.list -m monitor.map

# ============================ done moved, print-warn, clean-target
$(UTILDIR)/diskmenuc000.o:     $(UTILDIR)/diskmenuc000.a65 $(UTILDIR)/diskmenu.a65 $(UTILDIR)/diskmenu_sort.a65 $(CC65)
	$(CA65) $< -l $*.list

$(BINDIR)/diskmenu_c000.bin:   $(UTILDIR)/diskmenuc000.o $(CC65)
	$(LD65) $< --mapfile $*.map -o $*.bin

$(BINDIR)/etherload.prg:	$(UTILDIR)/etherload.a65 $(OPHIS)
	$(OPHIS) $(OPHISOPT) $< -l $*.list -m $*.map -o $*.prg


# ============================ done moved, print-warn, clean-target
# makerom is a python script that reads two files (arg[1,2]) and generates one (arg[3]).
# the line below would generate the hyppo.vhdl file, (note no file extention on arg[3])
# two files are read (arg[1] and arg[2]) and somehow compared, looking for THEROM and ROMDATA
$(VHDLSRCDIR)/hyppo.vhdl:	$(TOOLDIR)/makerom/rom_template.vhdl $(BINDIR)/HICKUP.M65 $(TOOLDIR)/makerom/makerom
#       script                arg[1]                          arg[2]     arg[3]                  arg[4]
	$(TOOLDIR)/makerom/makerom $(TOOLDIR)/makerom/rom_template.vhdl $(BINDIR)/HICKUP.M65 $(VHDLSRCDIR)/hyppo hyppo

$(VHDLSRCDIR)/colourram.vhdl:	$(TOOLDIR)/makerom/colourram_template.vhdl $(BINDIR)/COLOURRAM.BIN $(TOOLDIR)/makerom/makerom
	$(TOOLDIR)/makerom/makerom $(TOOLDIR)/makerom/colourram_template.vhdl $(BINDIR)/COLOURRAM.BIN $(VHDLSRCDIR)/colourram ram8x32k

$(SRCDIR)/open-roms/build/newc65.rom:	$(SRCDIR)/open-roms/assets/8x8font.png
	( cd $(SRCDIR)/open-roms ; make build/newc65.rom )

$(SRCDIR)/open-roms/assets/8x8font.png:
	git submodule init
	git submodule update
	( cd $(SRCDIR)/open-roms ; git submodule init ; git submodule update )

$(VHDLSRCDIR)/shadowram.vhdl:	$(TOOLDIR)/mempacker/mempacker_new $(SDCARD_DIR)/BANNER.M65 $(ASSETS)/alphatest.bin Makefile $(SDCARD_DIR)/FREEZER.M65  $(SRCDIR)/open-roms/build/newc65.rom $(SRCDIR)/utilities/megaflash.prg
	mkdir -p $(SDCARD_DIR)
	$(TOOLDIR)/mempacker/mempacker_new -n shadowram -s 393215 -f $(VHDLSRCDIR)/shadowram.vhdl $(SDCARD_DIR)/BANNER.M65@57D00 $(SDCARD_DIR)/FREEZER.M65@12000 $(SRCDIR)/open-roms/build/newc65.rom@20000 $(SRCDIR)/utilities/megaflash.prg@50000

$(VERILOGSRCDIR)/monitor_mem.v:	$(TOOLDIR)/mempacker/mempacker_v $(BINDIR)/monitor.m65
	$(TOOLDIR)/mempacker/mempacker_v -n monitormem -w 12 -s 4096 -f $(VERILOGSRCDIR)/monitor_mem.v $(BINDIR)/monitor.m65@0000

$(VHDLSRCDIR)/oskmem.vhdl:	$(TOOLDIR)/mempacker/mempacker $(BINDIR)/asciifont.bin $(BINDIR)/osdmap.bin $(BINDIR)/matrixfont.bin
	$(TOOLDIR)/mempacker/mempacker -n oskmem -s 4095 -f $(VHDLSRCDIR)/oskmem.vhdl $(BINDIR)/asciifont.bin@0000 $(BINDIR)/osdmap.bin@0800 $(BINDIR)/matrixfont.bin@0E00

$(VHDLSRCDIR)/termmem.vhdl:	$(TOOLDIR)/mempacker/mempacker $(BINDIR)/asciifont.bin $(BINDIR)/matrix_banner.txt
	$(TOOLDIR)/mempacker/mempacker -n termmem -s 4095 -f $(VHDLSRCDIR)/termmem.vhdl $(BINDIR)/asciifont.bin@000 /dev/zero@500 $(BINDIR)/matrix_banner.txt@A24

$(BINDIR)/osdmap.bin:	$(TOOLDIR)/on_screen_keyboard_gen $(SRCDIR)/keyboard.txt
	 $(TOOLDIR)/on_screen_keyboard_gen $(SRCDIR)/keyboard.txt > $(BINDIR)/osdmap.bin

$(BINDIR)/asciifont.bin:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/ascii00-7f.png
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/ascii00-7f.png $(BINDIR)/asciifont.bin

$(BINDIR)/matrixfont.bin:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/matrix.png
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/matrix.png $(BINDIR)/matrixfont.bin

$(BINDIR)/charrom.bin:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/8x8font.png
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/8x8font.png $(BINDIR)/charrom.bin

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that processes images, and can make a vhdl file
$(TOOLDIR)/pngprepare/pngprepare:	$(TOOLDIR)/pngprepare/pngprepare.c Makefile
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/pngprepare/pngprepare $(TOOLDIR)/pngprepare/pngprepare.c -lpng

$(TOOLDIR)/pngprepare/giftotiles:	$(TOOLDIR)/pngprepare/giftotiles.c Makefile
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/pngprepare/giftotiles $(TOOLDIR)/pngprepare/giftotiles.c -lgif


# ============================ done *deleted*, Makefile-dep, print-warn, clean-target
# unix command to generate the 'iomap.txt' file that represents the registers
# within both the c64 and the c65gs
# note that the iomap.txt file already comes from github.
# note that the iomap.txt file is often recreated because version.vhdl is updated.
iomap.txt:	$(VHDLSRCDIR)/*.vhdl $(VHDLSRCDIR)/vfpga/*.vhdl
	# Force consistent ordering of items according to natural byte values
	LC_ALL=C egrep "IO:C6|IO:GS" `find $(VHDLSRCDIR) -iname "*.vhdl"` | cut -f3- -d: | sort -u -k2 > iomap.txt

CRAMUTILS=	$(UTILDIR)/mega65_config.prg $(SRCDIR)/mega65-fdisk/m65fdisk.prg
$(BINDIR)/COLOURRAM.BIN:	$(TOOLDIR)/utilpacker/utilpacker $(CRAMUTILS)
	$(TOOLDIR)/utilpacker/utilpacker $(BINDIR)/COLOURRAM.BIN $(CRAMUTILS)

$(TOOLDIR)/utilpacker/utilpacker:	$(TOOLDIR)/utilpacker/utilpacker.c Makefile
	$(CC) $(COPT) -o $(TOOLDIR)/utilpacker/utilpacker $(TOOLDIR)/utilpacker/utilpacker.c

# ============================ done moved, Makefile-dep, print-warn, clean-target
# script to extract the git-status from the ./.git filesystem, and to embed that string
# into two files (*.vhdl and *.a65), that is wrapped with the template-file
# NOTE that we should use make to build the ISE project so that the
# version information is updated.
# for now we will always update the version info whenever we do a make.
.PHONY: version.vhdl version.a65
$(VHDLSRCDIR)/version.vhdl src/monitor/version.a65 src/version.a65 src/version.asm $(BINDIR)/matrix_banner.txt:	.git ./src/version.sh $(ASSETS)/matrix_banner.txt $(TOOLDIR)/format_banner
	./src/version.sh

# i think 'charrom' is used to put the pngprepare file into a special mode that
# generates the charrom.vhdl file that is embedded with the contents of the 8x8font.png file
$(VHDLSRCDIR)/charrom.vhdl:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/8x8font.png
#       exe          option  infile      outfile
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/8x8font.png $(VHDLSRCDIR)/charrom.vhdl

iverilog/driver/iverilog:
	git submodule init
	git submodule update
	cd iverilog ; autoconf ; ./configure ; make
	mkdir -p iverilog/lib/ivl
	ln -s ../../ivlpp/ivlpp iverilog/lib/ivl/ivlpp
	ln -s ../../ivl iverilog/lib/ivl/ivl
	ln -s ../../tgt-vhdl/vhdl.conf iverilog/lib/ivl/vhdl.conf
	ln -s ../../tgt-vhdl/vhdl.tgt iverilog/lib/ivl/vhdl.tgt

$(VHDLSRCDIR)/uart_monitor.vhdl.tmp $(VHDLSRCDIR)/uart_monitor.vhdl:	$(VERILOGSRCDIR)/* iverilog/driver/iverilog Makefile $(VERILOGSRCDIR)/monitor_mem.v
	( cd $(VERILOGSRCDIR) ; ../../iverilog/driver/iverilog  -tvhdl -o ../../$(VHDLSRCDIR)/uart_monitor.vhdl.tmp monitor_*.v asym_ram_sdp.v 6502_*.v UART_TX_CTRL.v uart_rx.v )
	# Now remove the dummy definitions of UART_TX_CTRL and uart_rx, as we will use the actual VHDL implementations of them.
	cat $(VHDLSRCDIR)/uart_monitor.vhdl.tmp | awk 'BEGIN { echo=1; } {if ($$1=="--"&&$$2=="Generated"&&$$3=="from"&&$$4=="Verilog") { if ($$6=="UART_TX_CTRL"||$$6=="uart_rx") echo=0; else echo=1; } if (echo) print; }' > $(VHDLSRCDIR)/uart_monitor.vhdl


$(SDCARD_DIR)/BANNER.M65:	$(TOOLDIR)/pngprepare/pngprepare assets/mega65_320x64.png
	mkdir -p $(SDCARD_DIR)
	/usr/$(BINDIR)/convert -colors 128 -depth 8 +dither assets/mega65_320x64.png $(BINDIR)/mega65_320x64_128colour.png
	$(TOOLDIR)/pngprepare/pngprepare logo $(BINDIR)/mega65_320x64_128colour.png $(SDCARD_DIR)/BANNER.M65

# disk menu program for loading from SD card to $C000 on boot by hyppo
$(SDCARD_DIR)/C000UTIL.BIN:	$(BINDIR)/diskmenu_c000.bin
	mkdir -p $(SDCARD_DIR)
	cp $(BINDIR)/diskmenu_c000.bin $(SDCARD_DIR)/C000UTIL.BIN

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to be the 'load-wedge'
# for the serial-monitor
monitor_drive:	monitor_drive.c Makefile
	$(CC) $(COPT) -o monitor_drive monitor_drive.c

$(TOOLDIR)/monitor_load:	$(TOOLDIR)/monitor_load.c $(TOOLDIR)/fpgajtag/*.c $(TOOLDIR)/fpgajtag/*.h Makefile
	$(CC) $(COPT) -g -Wall -I/usr/include/libusb-1.0 -I/opt/local/include/libusb-1.0 -I/usr/local//Cellar/libusb/1.0.18/include/libusb-1.0/ -o $(TOOLDIR)/monitor_load $(TOOLDIR)/monitor_load.c $(TOOLDIR)/fpgajtag/fpgajtag.c $(TOOLDIR)/fpgajtag/util.c $(TOOLDIR)/fpgajtag/process.c -lusb-1.0 -lz -lpthread

$(BINDIR)/ftphelper.bin:	src/ftphelper.a65
	$(OPHIS) $(OPHISOPT) src/ftphelper.a65

$(TOOLDIR)/ftphelper.c:	$(BINDIR)/ftphelper.bin $(TOOLDIR)/bin2c
	$(TOOLDIR)/bin2c $(BINDIR)/ftphelper.bin helperroutine $(TOOLDIR)/ftphelper.c

$(TOOLDIR)/mega65_ftp:	$(TOOLDIR)/mega65_ftp.c Makefile $(TOOLDIR)/ftphelper.c
	$(CC) $(COPT) -o $(TOOLDIR)/mega65_ftp $(TOOLDIR)/mega65_ftp.c $(TOOLDIR)/ftphelper.c -lreadline

$(TOOLDIR)/test_procedure_format:	Makefile $(TOOLDIR)/test_procedure_format.c
	$(CC) $(COPT) -o $(TOOLDIR)/test_procedure_format $(TOOLDIR)/test_procedure_format.c

$(TOOLDIR)/bitinfo:	$(TOOLDIR)/bitinfo.c Makefile 
	$(CC) $(COPT) -g -Wall -o $(TOOLDIR)/bitinfo $(TOOLDIR)/bitinfo.c

$(TOOLDIR)/bit2core:	$(TOOLDIR)/bit2core.c Makefile 
	$(CC) $(COPT) -g -Wall -o $(TOOLDIR)/bit2core $(TOOLDIR)/bit2core.c

$(TOOLDIR)/monitor_save:	$(TOOLDIR)/monitor_save.c Makefile
	$(CC) $(COPT) -o $(TOOLDIR)/monitor_save $(TOOLDIR)/monitor_save.c

$(TOOLDIR)/on_screen_keyboard_gen:	$(TOOLDIR)/on_screen_keyboard_gen.c Makefile
	$(CC) $(COPT) -o $(TOOLDIR)/on_screen_keyboard_gen $(TOOLDIR)/on_screen_keyboard_gen.c

#-----------------------------------------------------------------------------

# Generate Vivado .xpr from .tcl
vivado/%.xpr: 	vivado/%_gen.tcl | $(VHDLSRCDIR)/*.vhdl $(VHDLSRCDIR)/*.xdc $(SIMULATIONVHDL) $(VERILOGSRCDIR)/*.v $(VERILOGSRCDIR)/monitor_mem.v
	echo MOOSE $@ from $<
	$(VIVADO) -mode batch -source $<

preliminaries: $(VERILOGSRCDIR)/monitor_mem.v $(M65VHDL)

$(BINDIR)/%.bit: 	vivado/%.xpr $(VHDLSRCDIR)/*.vhdl $(VHDLSRCDIR)/*.xdc $(SIMULATIONVHDL) $(VERILOGSRCDIR)/*.v preliminaries
	echo MOOSE $@ from $<
#	@rm -f $@
#	@echo "---------------------------------------------------------"
#	@echo "Checking design for timing errors and unroutes..."
#	@grep -i "all signals are completely routed" $(filter %.unroutes,$^)
#	@grep -iq "timing errors:" $(filter %.twr,$^); \
#	if [ $$? -eq 0 ]; then \
#		grep -i "timing errors: 0" $(filter %.twr,$^); \
#		exit $$?; \
#	fi
#	@echo "Design looks good. Generating bitfile."
#	@echo "---------------------------------------------------------"

	mkdir -p $(SDCARD_DIR)
	$(VIVADO) -mode batch -source vivado/$(subst bin/,,$*)_impl.tcl vivado/$(subst bin/,,$*).xpr
	cp vivado/$(subst bin/,,$*).runs/impl_1/container.bit $@
	# Make a copy named after the commit and datestamp, for easy going back to previous versions
	cp $@ $(BINDIR)/$*-`$(TOOLDIR)/gitversion.sh`.bit

$(BINDIR)/%.mcs:	$(BINDIR)/%.bit
	mkdir -p $(SDCARD_DIR)
	$(VIVADO) -mode batch -source vivado/run_mcs.tcl -tclargs $< $@

$(BINDIR)/ethermon:	$(TOOLDIR)/ethermon.c
	$(CC) $(COPT) -o $(BINDIR)/ethermon $(TOOLDIR)/ethermon.c -I/usr/local/include -lpcap

$(BINDIR)/videoproxy:	$(TOOLDIR)/videoproxy.c
	$(CC) $(COPT) -o $(BINDIR)/videoproxy $(TOOLDIR)/videoproxy.c -I/usr/local/include -lpcap

$(BINDIR)/vncserver:	$(TOOLDIR)/vncserver.c
	$(CC) $(COPT) -O3 -o $(BINDIR)/vncserver $(TOOLDIR)/vncserver.c -I/usr/local/include -lvncserver -lpthread

clean:
	rm -f $(BINDIR)/HICKUP.M65 hyppo.list hyppo.map
	rm -f $(UTILDIR)/diskmenu.prg $(UTILDIR)/diskmenuprg.list $(UTILDIR)/diskmenu.map $(UTILDIR)/diskmenuprg.o
	rm -f $(UTILDIR)/mega65_config.prg $(UTILDIR)/mega65_config.list $(UTILDIR)/mega65_config.map $(UTILDIR)/mega65_config.o
	rm -f $(BINDIR)/diskmenu_c000.bin $(UTILDIR)/diskmenuc000.list $(BINDIR)/diskmenu_c000.map $(UTILDIR)/diskmenuc000.o
	rm -f $(TOOLDIR)/etherhyppo/etherhyppo
	rm -f $(TOOLDIR)/etherload/etherload
	rm -f $(TOOLDIR)/hotpatch/hotpatch
	rm -f $(TOOLDIR)/pngprepare/pngprepare
	rm -f $(UTILDIR)/etherload.prg $(UTILDIR)/etherload.list $(UTILDIR)/etherload.map
	rm -f $(UTILDIR)/ethertest.prg $(UTILDIR)/ethertest.list $(UTILDIR)/ethertest.map
	rm -f $(UTILDIR)/test01prg.prg $(UTILDIR)/test01prg.list $(UTILDIR)/test01prg.map
	rm -f $(UTILDIR)/c65test02prg.prg $(UTILDIR)/c65test02prg.list $(UTILDIR)/c65test02prg.map
	rm -f iomap.txt
	rm -f $(SDCARD_DIR)/utility.d81
	rm -f tests/test_fdc_equal_flag.prg tests/test_fdc_equal_flag.list tests/test_fdc_equal_flag.map
	rm -rf $(SDCARD_DIR)
	rm -f $(VHDLSRCDIR)/hyppo.vhdl $(VHDLSRCDIR)/charrom.vhdl $(VHDLSRCDIR)/version.vhdl version.a65 $(VHDLSRCDIR)/uart_monitor.vhdl
	rm -f $(BINDIR)/monitor.m65 monitor.list monitor.map $(SRCDIR)/monitor/gen_dis $(SRCDIR)/monitor/monitor_dis.a65 $(SRCDIR)/monitor/version.a65
	rm -f $(VERILOGSRCDIR)/monitor_mem.v
	rm -f monitor_drive monitor_load read_mem ghdl-frame-gen chargen_debug dis4510 em4510 4510tables
	rm -f c65-rom-911001.txt c65-911001-rom-annotations.txt c65-dos-context.bin c65-911001-dos-context.bin
	rm -f thumbnail.prg work-obj93.cf
	rm -f textmodetest.prg textmodetest.list etherload_done.bin etherload_stub.bin
	rm -f $(BINDIR)/videoproxy $(BINDIR)/vncserver
	rm -rf vivado/{mega65r1,megaphoner1,nexys4,nexys4ddr,nexys4ddr-widget,pixeltest,te0725}.{cache,runs,hw,ip_user_files,srcs,xpr}

cleangen:
	rm $(VHDLSRCDIR)/hyppo.vhdl $(VHDLSRCDIR)/charrom.vhdl *.M65
