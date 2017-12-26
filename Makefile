.SUFFIXES: .bin .prg 
.PRECIOUS:	%.ngd %.ncd %.twx

COPT=	-Wall -g -std=c99
CC=	gcc
OPHIS=	../Ophis/bin/ophis -4

ASSETS=		assets
SRCDIR=		src
BINDIR=		bin
UTILDIR=	$(SRCDIR)/utilities
VHDLSRCDIR=	$(SRCDIR)/vhdl

SDCARD_DIR=	sdcard-files

KICKSTARTSRCS = $(SRCDIR)/kickstart.a65 \
		$(SRCDIR)/kickstart_machine.a65 \
		$(SRCDIR)/kickstart_process_descriptor.a65 \
		$(SRCDIR)/kickstart_dos.a65 \
		$(SRCDIR)/kickstart_task.a65 \
		$(SRCDIR)/kickstart_virtual_f011.a65 \
		$(SRCDIR)/kickstart_debug.a65 \
		$(SRCDIR)/kickstart_mem.a65

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
		d81-files/* \
		$(UTILDIR)/diskmenu.prg

TOOLDIR=	$(SRCDIR)/tools
TOOLS=	$(TOOLDIR)/etherkick/etherkick \
	$(TOOLDIR)/etherload/etherload \
	$(TOOLDIR)/hotpatch/hotpatch \
	$(TOOLDIR)/monitor_load \
	$(TOOLDIR)/monitor_save \
	$(TOOLDIR)/on_screen_keyboard_gen \
	$(TOOLDIR)/pngprepare/pngprepare

all:	$(SDCARD_DIR)/MEGA65.D81 $(BINDIR)/mega65r1.mcs $(BINDIR)/nexys4.mcs $(BINDIR)/nexys4ddr.mcs $(BINDIR)/touch_test.mcs

generated_vhdl:	$(SIMULATIONVHDL)


# files destined to go on the SD-card to serve as firmware for the MEGA65
firmware:	$(SDCARD_DIR)/BANNER.M65 \
		$(BINDIR)/KICKUP.M65 \
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
			$(VHDLSRCDIR)/sid_coeffs.vhd \
			$(VHDLSRCDIR)/sid_components.vhd \
			$(VHDLSRCDIR)/sid_filters.vhd \
			$(VHDLSRCDIR)/sid_voice.vhd \

CPUVHDL=		$(VHDLSRCDIR)/gs4510.vhdl

NOCPUVHDL=		$(VHDLSRCDIR)/nocpu.vhdl

C65VHDL=		$(SIDVHDL) \
			$(VHDLSRCDIR)/iomapper.vhdl \
			$(VHDLSRCDIR)/cia6526.vhdl \
			$(VHDLSRCDIR)/c65uart.vhdl \
			$(VHDLSRCDIR)/UART_TX_CTRL.vhd \
			$(VHDLSRCDIR)/cputypes.vhdl \

VICIVVHDL=		$(VHDLSRCDIR)/viciv.vhdl \
			$(VHDLSRCDIR)/sprite.vhdl \
			$(VHDLSRCDIR)/vicii_sprites.vhdl \
			$(VHDLSRCDIR)/bitplane.vhdl \
			$(VHDLSRCDIR)/bitplanes.vhdl \
			$(VHDLSRCDIR)/victypes.vhdl \
			$(VHDLSRCDIR)/pal_simulation.vhdl \
			$(VHDLSRCDIR)/ghdl_alpha_blend.vhdl \
			$(OVERLAYVHDL)

PERIPHVHDL=		$(VHDLSRCDIR)/sd.vhdl \
			$(VHDLSRCDIR)/sdcardio.vhdl \
			$(VHDLSRCDIR)/ethernet.vhdl \
			$(VHDLSRCDIR)/ghdl_fpgatemp.vhdl \
			$(VHDLSRCDIR)/expansion_port_controller.vhdl \
			$(VHDLSRCDIR)/slow_devices.vhdl \
			$(KBDVHDL)

KBDVHDL=		$(VHDLSRCDIR)/keymapper.vhdl \
			$(VHDLSRCDIR)/keyboard_complex.vhdl \
			$(VHDLSRCDIR)/keyboard_to_matrix.vhdl \
			$(VHDLSRCDIR)/matrix_to_ascii.vhdl \
			$(VHDLSRCDIR)/widget_to_matrix.vhdl \
			$(VHDLSRCDIR)/ps2_to_matrix.vhdl \
			$(VHDLSRCDIR)/keymapper.vhdl \
			$(VHDLSRCDIR)/virtual_to_matrix.vhdl \

OVERLAYVHDL=		$(VHDLSRCDIR)/rain.vhdl \
			$(VHDLSRCDIR)/visual_keyboard.vhdl \
			$(VHDLSRCDIR)/uart_charrom.vhdl \
			$(VHDLSRCDIR)/oskmem.vhdl \
			$(VHDLSRCDIR)/termmem.vhdl \

SERMONVHDL=		$(VHDLSRCDIR)/ps2_to_uart.vhdl \
			$(VHDLSRCDIR)/uart_monitor.vhdl \
			$(VHDLSRCDIR)/uart_rx.vhdl \

M65VHDL=		$(VHDLSRCDIR)/machine.vhdl \
			$(VHDLSRCDIR)/ddrwrapper.vhdl \
			$(VHDLSRCDIR)/framepacker.vhdl \
			$(VHDLSRCDIR)/kickstart.vhdl \
			$(VHDLSRCDIR)/version.vhdl \
			$(C65VHDL) \
			$(VICIVVHDL) \
			$(PERIPHVHDL) \
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
			$(VHDLSRCDIR)/ghdl_ram8x512.vhdl \
			$(VHDLSRCDIR)/ghdl_ram9x4k.vhdl \
			$(VHDLSRCDIR)/ghdl_screen_ram_buffer.vhdl \
			$(VHDLSRCDIR)/ghdl_videobuffer.vhdl \
			$(VHDLSRCDIR)/ghdl_ram36x1k.vhdl

NEXYSVHDL=		$(VHDLSRCDIR)/slowram.vhdl \
			$(CPUVHDL) \
			$(M65VHDL)


SIMULATIONVHDL=		$(VHDLSRCDIR)/cpu_test.vhdl \
			$(VHDLSRCDIR)/fake_expansion_port.vhdl \
			$(CPUVHDL) \
			$(M65VHDL)

NOCPUSIMULATIONVHDL=	$(VHDLSRCDIR)/cpu_test.vhdl \
			$(VHDLSRCDIR)/fake_expansion_port.vhdl \
			$(NOCPUVHDL) \
			$(M65VHDL)


simulate:	$(SIMULATIONVHDL)
	ghdl -i $(SIMULATIONVHDL)
	ghdl -m cpu_test
	./cpu_test || ghdl -r cpu_test

nocpu:	$(NOCPUSIMULATIONVHDL)
	ghdl -i $(NOCPUSIMULATIONVHDL)
	ghdl -m cpu_test
	./cpu_test || ghdl -r cpu_test


KVFILES=$(VHDLSRCDIR)/test_kv.vhdl $(VHDLSRCDIR)/keyboard_to_matrix.vhdl $(VHDLSRCDIR)/matrix_to_ascii.vhdl \
	$(VHDLSRCDIR)/widget_to_matrix.vhdl $(VHDLSRCDIR)/ps2_to_matrix.vhdl $(VHDLSRCDIR)/keymapper.vhdl \
	$(VHDLSRCDIR)/keyboard_complex.vhdl $(VHDLSRCDIR)/virtual_to_matrix.vhdl
kvsimulate:	$(KVFILES)
	ghdl -i $(KVFILES)
	ghdl -m test_kv
	./test_kv || ghdl -r test_kv

OSKFILES=$(VHDLSRCDIR)/test_osk.vhdl \
	$(VHDLSRCDIR)/visual_keyboard.vhdl \
	$(VHDLSRCDIR)/oskmem.vhdl
osksimulate:	$(OSKFILES) $(TOOLDIR)/osk_image
	ghdl -i $(OSKFILES)
	ghdl -m test_osk
	( ./test_osk || ghdl -r test_osk ) 2>&1 | $(TOOLDIR)/osk_image

MMFILES=$(VHDLSRCDIR)/test_matrix.vhdl \
	$(VHDLSRCDIR)/rain.vhdl \
	$(VHDLSRCDIR)/lfsr16.vhdl \
	$(VHDLSRCDIR)/uart_charrom.vhdl \
	$(VHDLSRCDIR)/test_osk.vhdl \
	$(VHDLSRCDIR)/visual_keyboard.vhdl \
	$(VHDLSRCDIR)/oskmem.vhdl \
	$(VHDLSRCDIR)/termmem.vhdl

mmsimulate:	$(MMFILES) $(TOOLDIR)/osk_image
	ghdl -i $(MMFILES)
	ghdl -m test_matrix
	( ./test_matrix || ghdl -r test_matrix ) 2>&1 | $(TOOLDIR)/osk_image matrix.png

$(TOOLDIR)/osk_image:	$(TOOLDIR)/osk_image.c
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/osk_image $(TOOLDIR)/osk_image.c -lpng

$(TOOLDIR)/frame2png:	$(TOOLDIR)/frame2png.c
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/frame2png $(TOOLDIR)/frame2png.c -lpng

vfsimulate:	$(VHDLSRCDIR)/frame_test.vhdl $(VHDLSRCDIR)/video_frame.vhdl
	ghdl -i $(VHDLSRCDIR)/frame_test.vhdl $(VHDLSRCDIR)/video_frame.vhdl
	ghdl -m frame_test
	./frame_test || ghdl -r frame_test


# =======================================================================
# =======================================================================
# =======================================================================
# =======================================================================

# ============================
$(SDCARD_DIR)/CHARROM.M65:
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/CHARROM.M65)
	wget -O $(SDCARD_DIR)/CHARROM.M65 http://www.zimmers.net/anonftp/pub/cbm/firmware/characters/c65-caff.bin

# ============================
$(SDCARD_DIR)/MEGA65.ROM:
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/MEGA65.ROM)
	wget -O $(SDCARD_DIR)/MEGA65.ROM http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c65/910111-390488-01.bin

# ============================, print-warn, clean target
# verbose, for 1581 format, overwrite
$(SDCARD_DIR)/MEGA65.D81:	$(UTILITIES)
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/MEGA65.D81)
	cbmconvert -v2 -D8o $(SDCARD_DIR)/MEGA65.D81 $(UTILITIES)

# ============================ done moved, print-warn, clean-target
# ophis converts the *.a65 file (assembly text) to *.prg (assembly bytes)
%.prg:	%.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $@)
	$(OPHIS) $< -l $*.list -m $*.map -o $*.prg

%.bin:	%.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $@)
	$(OPHIS) $< -l $*.list -m $*.map -o $*.prg

$(UTILDIR)/diskmenu.prg:	$(UTILDIR)/diskmenuprg.a65 $(UTILDIR)/diskmenu.a65 $(UTILDIR)/etherload.prg
	$(OPHIS) $< -l $*.list -m $*.map	

$(SRCDIR)/mega65-fdisk/m65fdisk.prg:	
	( cd $(SRCDIR)/mega65-fdisk ; make )

$(BINDIR)/border.prg: 	$(SRCDIR)/border.a65
	$(OPHIS) $< -l $(BINDIR)/border.list -m $*.map -o $(BINDIR)/border.prg

# ============================ done moved, print-warn, clean-target
#??? diskmenu_c000.bin yet b0rken
$(BINDIR)/KICKUP.M65:	$(KICKSTARTSRCS) $(BINDIR)/diskmenu_c000.bin $(SRCDIR)/version.a65
	$(OPHIS) $< -l $*.list -m $*.map

# ============================ done moved, print-warn, clean-target
$(BINDIR)/diskmenu_c000.bin:	$(UTILDIR)/diskmenuc000.a65 $(UTILDIR)/diskmenu.a65 $(BINDIR)/etherload.prg
	$(OPHIS) $< -l $*.list -m $*.map -o $*.bin

$(BINDIR)/etherload.prg:	$(UTILDIR)/etherload.a65
	$(OPHIS) $< -l $*.list -m $*.map -o $*.prg


# ============================ done moved, print-warn, clean-target
# makerom is a python script that reads two files (arg[1,2]) and generates one (arg[3]).
# the line below would generate the kickstart.vhdl file, (note no file extention on arg[3])
# two files are read (arg[1] and arg[2]) and somehow compared, looking for THEROM and ROMDATA
$(VHDLSRCDIR)/kickstart.vhdl:	$(TOOLDIR)/makerom/rom_template.vhdl $(BINDIR)/KICKUP.M65 $(TOOLDIR)/makerom/makerom
#       script                arg[1]                          arg[2]     arg[3]                  arg[4]
	$(TOOLDIR)/makerom/makerom $(TOOLDIR)/makerom/rom_template.vhdl $(BINDIR)/KICKUP.M65 $(VHDLSRCDIR)/kickstart kickstart

$(VHDLSRCDIR)/colourram.vhdl:	$(TOOLDIR)/makerom/colourram_template.vhdl $(BINDIR)/COLOURRAM.BIN $(TOOLDIR)/makerom/makerom
	$(TOOLDIR)/makerom/makerom $(TOOLDIR)/makerom/colourram_template.vhdl $(BINDIR)/COLOURRAM.BIN $(VHDLSRCDIR)/colourram ram8x32k

$(VHDLSRCDIR)/shadowram.vhdl:	$(TOOLDIR)/mempacker/mempacker $(SDCARD_DIR)/BANNER.M65
	$(TOOLDIR)/mempacker/mempacker -n shadowram -s 131071 -f $(VHDLSRCDIR)/shadowram.vhdl $(SDCARD_DIR)/BANNER.M65@3D00

$(VHDLSRCDIR)/oskmem.vhdl:	$(TOOLDIR)/mempacker/mempacker $(BINDIR)/asciifont.bin $(BINDIR)/osdmap.bin $(BINDIR)/matrixfont.bin
	$(TOOLDIR)/mempacker/mempacker -n oskmem -s 4095 -f $(VHDLSRCDIR)/oskmem.vhdl $(BINDIR)/asciifont.bin@0000 $(BINDIR)/osdmap.bin@0800 $(BINDIR)/matrixfont.bin@0E00

$(VHDLSRCDIR)/termmem.vhdl:	$(TOOLDIR)/mempacker/mempacker $(BINDIR)/asciifont.bin $(BINDIR)/matrix_banner.txt
	$(TOOLDIR)/mempacker/mempacker -n termmem -s 4095 -f $(VHDLSRCDIR)/termmem.vhdl $(BINDIR)/asciifont.bin@000 $(BINDIR)/matrix_banner.txt@A24

$(BINDIR)/osdmap.bin:	$(TOOLDIR)/on_screen_keyboard_gen $(SRCDIR)/keyboard.txt
	 $(TOOLDIR)/on_screen_keyboard_gen $(SRCDIR)/keyboard.txt > $(BINDIR)/osdmap.bin

$(BINDIR)/asciifont.bin:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/ascii00-7f.png
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/ascii00-7f.png $(BINDIR)/asciifont.bin

$(BINDIR)/matrixfont.bin:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/matrix.png
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/matrix.png $(BINDIR)/matrixfont.bin

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that processes images, and can make a vhdl file
$(TOOLDIR)/pngprepare/pngprepare:	$(TOOLDIR)/pngprepare/pngprepare.c Makefile
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/pngprepare/pngprepare $(TOOLDIR)/pngprepare/pngprepare.c -lpng

# ============================ done *deleted*, Makefile-dep, print-warn, clean-target
# unix command to generate the 'iomap.txt' file that represents the registers
# within both the c64 and the c65gs
# note that the iomap.txt file already comes from github.
# note that the iomap.txt file is often recreated because version.vhdl is updated.
iomap.txt:	$(VHDLSRCDIR)/*.vhdl 
	# Force consistent ordering of items according to natural byte values
	LC_ALL=C egrep "IO:C6|IO:GS" $(VHDLSRCDIR)/*.vhdl | cut -f3- -d: | sort -u -k2 > iomap.txt

CRAMUTILS=	$(BINDIR)/border.prg $(SRCDIR)/mega65-fdisk/m65fdisk.prg
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
$(VHDLSRCDIR)/version.vhdl src/version.a65 $(BINDIR)/matrix_banner.txt:	.git	./src/version.sh $(ASSETS)/matrix_banner.txt
	./src/version.sh

# i think 'charrom' is used to put the pngprepare file into a special mode that
# generates the charrom.vhdl file that is embedded with the contents of the 8x8font.png file
$(VHDLSRCDIR)/charrom.vhdl:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/8x8font.png
#       exe          option  infile      outfile
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/8x8font.png $(VHDLSRCDIR)/charrom.vhdl

$(SDCARD_DIR)/BANNER.M65:	$(TOOLDIR)/pngprepare/pngprepare assets/mega65_320x64.png
	/usr/$(BINDIR)/convert -colors 128 -depth 8 +dither assets/mega65_320x64.png $(BINDIR)/mega65_320x64_128colour.png
	$(TOOLDIR)/pngprepare/pngprepare logo $(BINDIR)/mega65_320x64_128colour.png $(SDCARD_DIR)/BANNER.M65

# disk menu program for loading from SD card to $C000 on boot by kickstart
$(SDCARD_DIR)/C000UTIL.BIN:	$(SRCDIR)/diskmenu_c000.bin
	cp $(SRCDIR)/diskmenu_c000.bin $(SDCARD_DIR)/C000UTIL.BIN

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to be the 'load-wedge'
# for the serial-monitor
monitor_drive:	monitor_drive.c Makefile
	$(CC) $(COPT) -o monitor_drive monitor_drive.c

$(TOOLDIR)/monitor_load:	$(TOOLDIR)/monitor_load.c Makefile
	$(CC) $(COPT) -o $(TOOLDIR)/monitor_load $(TOOLDIR)/monitor_load.c

$(TOOLDIR)/monitor_save:	$(TOOLDIR)/monitor_save.c Makefile
	$(CC) $(COPT) -o $(TOOLDIR)/monitor_save $(TOOLDIR)/monitor_save.c

$(TOOLDIR)/on_screen_keyboard_gen:	$(TOOLDIR)/on_screen_keyboard_gen.c Makefile
	$(CC) $(COPT) -o $(TOOLDIR)/on_screen_keyboard_gen $(TOOLDIR)/on_screen_keyboard_gen.c

%.ngc %.syr:	$(VHDLSRCDIR)/*.vhdl $(SIMULATIONVHDL)
	echo MOOSE $@ from $<
#	@rm -f $*.ngc $*.syr $*.ngr
	mkdir -p xst/projnav.tmp
	./run_ise $* xst

#-----------------------------------------------------------------------------

%.ngd %.bld: %.ngc
	echo MOOSE $@ from $<
#	@rm -f $*.ngd $*.bld
	./run_ise $* ngdbuild

#-----------------------------------------------------------------------------

%.mapncd %.pcf: %.ngd
	echo MOOSE $@ from $<
#	@rm -f $*.mapncd $*.pcf
	./run_ise $* map

#-----------------------------------------------------------------------------

%.ncd %.unroutes %.par %.twr: %.mapncd
	echo MOOSE $@ from $<
#	@rm -f $*.ncd $*.unroutes $*.par $*.twr
	./run_ise $* par

#-----------------------------------------------------------------------------

bin/%.bit:	isework/%.ncd
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
	./run_ise $(subst bin/,,$*) bitgen

%.mcs:	%.bit
	./run_ise $* promgen



clean:
	rm -f KICKUP.M65 kickstart.list kickstart.map
	rm -f $(UTILDIR)/diskmenu.prg diskmenuprg.list diskmenuprg.map
	rm -f diskmenu_c000.bin diskmenuc000.list diskmenuc000.map
	rm -f $(TOOLDIR)/etherkick/etherkick
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
	rm -f $(VHDLSRCDIR)/kickstart.vhdl $(VHDLSRCDIR)/charrom.vhdl $(VHDLSRCDIR)/version.vhdl version.a65
	rm -f monitor_drive monitor_load read_mem ghdl-frame-gen chargen_debug dis4510 em4510 4510tables
	rm -f c65-rom-911001.txt c65-911001-rom-annotations.txt c65-dos-context.bin c65-911001-dos-context.bin
	rm -f thumbnail.prg
	rm -f textmodetest.prg textmodetest.list etherload_done.bin etherload_stub.bin
	rm -f videoproxy

cleangen:
	rm $(VHDLSRCDIR)/kickstart.vhdl $(VHDLSRCDIR)/charrom.vhdl *.M65
