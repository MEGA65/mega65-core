
COPT=	-Wall -g -std=c99
CC=	gcc
OPHIS=	../Ophis/bin/ophis -4

ASSETS=		assets
SRCDIR=		src
VHDLSRCDIR=	$(SRCDIR)/vhdl

SDCARD_DIR=	sdcard-files

KICKSTARTSRCS = $(SRCDIR)/kickstart.a65 \
		$(SRCDIR)/kickstart_machine.a65 \
		$(SRCDIR)/kickstart_process_descriptor.a65 \
		$(SRCDIR)/kickstart_dos.a65 \
		$(SRCDIR)/kickstart_task.a65 \
		$(SRCDIR)/kickstart_virtual_f011.a65 \
		$(SRCDIR)/kickstart_mem.a65

# if you want your PRG to appear on "MEGA65.D81", then put your PRG in "./d81-files"
# ie: COMMANDO.PRG
#
# if you want your .a65 source code compiled and then embedded within "MEGA65.D81", then put
# your source.a65 in the 'utilities' directory, and ensure it is listed below.
#
# NOTE: that all files listed below will be embedded within the "MEGA65.D81".
#
UTILITIES=	$(SRCDIR)/utilities/ethertest.prg \
		$(SRCDIR)/utilities/etherload.prg \
		$(SRCDIR)/utilities/test01prg.prg \
		$(SRCDIR)/utilities/c65test02prg.prg \
		$(SRCDIR)/utilities/c65-rom-910111-fastload-patch.prg \
		d81-files/* \
		$(SRCDIR)/utilities/diskmenu.prg

TOOLDIR=	$(SRCDIR)/tools
TOOLS=	$(TOOLDIR)/etherkick/etherkick \
	$(TOOLDIR)/etherload/etherload \
	$(TOOLDIR)/hotpatch/hotpatch \
	$(TOOLDIR)/monitor_load \
	$(TOOLDIR)/monitor_save \
	$(TOOLDIR)/on_screen_keyboard_gen \
	$(TOOLDIR)/pngprepare/pngprepare

all:	sdcard-files/utility.d81 bin/mega65r1.bit bin/nexys4.bit bin/nexys4ddr.bit bin/test_touch.bit

generated_vhdl:	$(SIMULATIONVHDL)


# files destined to go on the SD-card to serve as firmware for the MEGA65
firmware:	$(SDCARD_DIR)/BANNER.M65 \
		bin/KICKUP.M65 \
		bin/COLOURRAM.BIN \
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

C65VHDL=		$(SIDVHDL) \
			$(VHDLSRCDIR)/iomapper.vhdl \
			$(VHDLSRCDIR)/cia6526.vhdl \
			$(VHDLSRCDIR)/c65uart.vhdl \
			$(VHDLSRCDIR)/UART_TX_CTRL.vhd \
			$(VHDLSRCDIR)/gs4510.vhdl \
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

OVERLAYVHDL=		$(VHDLSRCDIR)/matrix_compositor.vhdl \
			$(VHDLSRCDIR)/terminalemulator.vhdl \
			$(VHDLSRCDIR)/visual_keyboard.vhdl \
			$(VHDLSRCDIR)/uart_charrom.vhdl \
			$(VHDLSRCDIR)/oskmem.vhdl \

SERMONVHDL=		$(VHDLSRCDIR)/ps2_to_uart.vhdl \
			$(VHDLSRCDIR)/uart_monitor.vhdl \
			$(VHDLSRCDIR)/uart_rx.vhdl \

M65VHDL=		$(VHDLSRCDIR)/container.vhd \
			$(VHDLSRCDIR)/machine.vhdl \
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
			$(VHDLSRCDIR)/ghdl_ram18x2k.vhdl \
			$(VHDLSRCDIR)/ghdl_ram8x4096.vhdl \
			$(VHDLSRCDIR)/ghdl_ram8x512.vhdl \
			$(VHDLSRCDIR)/ghdl_ram9x4k.vhdl \
			$(VHDLSRCDIR)/ghdl_screen_ram_buffer.vhdl \
			$(VHDLSRCDIR)/ghdl_videobuffer.vhdl \
			$(VHDLSRCDIR)/ghdl_ram36x1k.vhdl

NEXYSVHDL=		$(VHDLSRCDIR)/slowram.vhdl \
			$(M65VHDL)


SIMULATIONVHDL=		$(VHDLSRCDIR)/cpu_test.vhdl \
			$(VHDLSRCDIR)/fake_expansion_port.vhdl \
			$(M65VHDL)


simulate:	$(SIMULATIONVHDL)
	ghdl -i $(SIMULATIONVHDL)
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
	$(VHDLSRCDIR)/matrix_compositor.vhdl \
	$(VHDLSRCDIR)/uart_charrom.vhdl \
	$(VHDLSRCDIR)/terminalemulator.vhdl
mmsimulate:	$(MMFILES) $(TOOLDIR)/osk_image
	ghdl -i $(MMFILES)
	ghdl -m test_matrix
	( ./test_matrix || ghdl -r test_matrix ) 2>&1 | $(TOOLDIR)/osk_image matrix.png

tools/osk_image:	tools/osk_image.c
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/osk_image $(TOOLDIR)/osk_image.c -lpng

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
# PGS program for testing the F011 floppy write, etc.
tests/test_fdc_equal_flag.prg:	tests/test_fdc_equal_flag.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: tests/test_fdc_equal_flag.a65)
	$(OPHIS) tests/test_fdc_equal_flag.a65 -l tests/test_fdc_equal_flag.list -m tests/test_fdc_equal_flag.map


# ============================ done moved, print-warn, clean-target
# ophis converts the *.a65 file (assembly text) to *.prg (assembly bytes)
utilities/ethertest.prg:	utilities/ethertest.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/ethertest.prg)
	$(OPHIS) utilities/ethertest.a65 -l utilities/ethertest.list -m utilities/ethertest.map


# ============================ done moved, print-warn, clean-target
# ophis converts the (two) *.a65 file (assembly text) to *.prg (assembly bytes)
# the "l" option created a verbose listing of the output
# NOTE that to get to compile i needed to comment out the ".scope" in the "diskmenu.a65" file
diskmenu.prg:	diskmenuprg.a65 diskmenu.a65 utilities/etherload.prg
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu.prg and diskmenuprg.list)
	$(OPHIS) diskmenuprg.a65 -l diskmenuprg.list -m diskmenuprg.map

bin/megacart.crt:	$(SRCDIR)/megacartstub.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu.prg and diskmenuprg.list)
	$(OPHIS) $(SRCDIR)/megacartstub.a65 -l megacart.list -m megacart.map

$(SRCDIR)/mega65-fdisk/m65fdisk.prg:	
	( cd $(SRCDIR)/mega65-fdisk ; make )

bin/border.prg:	$(SRCDIR)/border.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: border.prg)
	$(OPHIS) $(SRCDIR)/border.a65


# ============================ done moved, print-warn, clean-target
# we do not use this initial version anymore, but remains here for learning from
diskchooser:	diskchooser.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskchooser)
	$(OPHIS) diskchooser.a65


# ============================ done moved, print-warn, clean-target
#??? diskmenu_c000.bin yet b0rken
bin/KICKUP.M65:	$(KICKSTARTSRCS) bin/diskmenu_c000.bin $(SRCDIR)/version.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: KICKUP.M65 and kickstart.list)
	$(OPHIS) $(SRCDIR)/kickstart.a65 -l kickstart.list -m kickstart.map


# ============================ done moved, print-warn, clean-target
bin/diskmenu_c000.bin:	$(SRCDIR)/diskmenuc000.a65 $(SRCDIR)/diskmenu.a65 $(SRCDIR)/utilities/etherload.prg
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu_c000.bin and diskmenuc000.list)
	$(OPHIS) $(SRCDIR)/diskmenuc000.a65 -l diskmenuc000.list -m diskmenuc000.map


# ============================ done moved, print-warn, clean-target
thumbnail.prg:	showthumbnail.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: thumbnail.prg)
	$(OPHIS) showthumbnail.a65 -m showthumbnail.map -l showthumbnail.list


# ============================ done moved, print-warn, clean-target
utilities/etherload.prg:	utilities/etherload.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/etherload.prg)
	$(OPHIS) utilities/etherload.a65 -l utilities/etherload.list -m utilities/etherload.map


# ============================ done moved, print-warn, clean-target
utilities/test01prg.prg:	utilities/test01prg.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/test01prg.prg)
	$(OPHIS) utilities/test01prg.a65 -l utilities/test01prg.list -m utilities/test01prg.map


# ============================ done moved, print-warn, clean-target
utilities/c65test02prg.prg:	utilities/c65test02prg.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/c65test02prg.prg)
	$(OPHIS) utilities/c65test02prg.a65 -l utilities/c65test02prg.list -m utilities/c65test02prg.map


utilities/c65-rom-910111-fastload-patch.prg:	utilities/c65-rom-910111-fastload-patch.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/c65-rom-910111-fastload-patch.prg)
	$(OPHIS) utilities/c65-rom-910111-fastload-patch.a65 -l utilities/c65-rom-910111-fastload-patch.list -m utilities/c65-rom-910111-fastload-patch.map


# ============================ done moved, print-warn, clean-target
# keep this in _unused for time being
etherload_stub.bin:	etherload_stub.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: etherload_stub.bin)
	$(OPHIS) etherload_stub.a65


# ============================ done moved, print-warn, clean-target
# keep this in _unused for time being
etherload_done.bin:	etherload_done.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: etherload_done.bin)
	$(OPHIS) etherload_done.a65


# ============================ done moved, print-warn, clean-target
# dejavus.f65 seems to be a font tile
textmodetest.prg:	textmodetest.a65 textmodetest-dejavus.f65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: textmodetest.prg)
	$(OPHIS) textmodetest.a65 -l textmodetest.list


# ============================ done moved, print-warn, clean-target
# makerom is a python script that reads two files (arg[1,2]) and generates one (arg[3]).
# the line below would generate the kickstart.vhdl file, (note no file extention on arg[3])
# two files are read (arg[1] and arg[2]) and somehow compared, looking for THEROM and ROMDATA
$(VHDLSRCDIR)/kickstart.vhdl:	$(TOOLDIR)/makerom/rom_template.vhdl bin/KICKUP.M65 $(TOOLDIR)/makerom/makerom
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/kickstart.vhdl)
#       script                arg[1]                          arg[2]     arg[3]                  arg[4]
	$(TOOLDIR)/makerom/makerom $(TOOLDIR)/makerom/rom_template.vhdl bin/KICKUP.M65 $(VHDLSRCDIR)/kickstart kickstart

$(VHDLSRCDIR)/colourram.vhdl:	$(TOOLDIR)/makerom/colourram_template.vhdl COLOURRAM.BIN $(TOOLDIR)/makerom/makerom
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/colourram.vhdl)
	$(TOOLDIR)/makerom/makerom $(TOOLDIR)/makerom/colourram_template.vhdl COLOURRAM.BIN $(VHDLSRCDIR)/colourram ram8x32k

$(VHDLSRCDIR)/shadowram.vhdl:	$(TOOLDIR)/mempacker/mempacker $(SDCARD_DIR)/BANNER.M65
	$(TOOLDIR)/mempacker/mempacker -n shadowram -s 131071 -f $(VHDLSRCDIR)/shadowram.vhdl $(SDCARD_DIR)/BANNER.M65@3D00

$(VHDLSRCDIR)/oskmem.vhdl:	$(TOOLDIR)/mempacker/mempacker bin/asciifont.bin bin/osdmap.bin
	$(TOOLDIR)/mempacker/mempacker -n oskmem -s 4095 -f $(VHDLSRCDIR)/oskmem.vhdl bin/asciifont.bin@0000 bin/osdmap.bin@0800

bin/osdmap.bin:	$(TOOLDIR)/on_screen_keyboard_gen $(SRCDIR)/keyboard.txt
	 $(TOOLDIR)/on_screen_keyboard_gen $(SRCDIR)/keyboard.txt > bin/osdmap.bin

bin/asciifont.bin:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/ascii00-7f.png
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: asciifont.bin)
#       exe          option  infile      outfile
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/ascii00-7f.png bin/asciifont.bin


# unsure why the below is commented out
#slowram.vhdl:	c65gs.rom makeslowram slowram_template.vhdl
#	./makeslowram slowram_template.vhdl c65gs.rom slowram


# ============================ done moved, print-warn, clean-target
# c-code that makes an executable that seems to extract images from the c65gs via lan
# and displays the images on the users screen using vncserver
# does not currently compile
videoproxy:	videoproxy.c
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: videoproxy)
	$(CC) $(COPT) -o videoproxy videoproxy.c -lpcap


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
tools/etherload/etherload:	tools/etherload/etherload.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(TOOLDIR)/etherload/etherload)
	$(CC) $(COPT) -o $(TOOLDIR)/etherload/etherload $(TOOLDIR)/etherload/etherload.c $(SOCKLIBS)


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
tools/etherkick/etherkick:	tools/etherkick/etherkick.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(TOOLDIR)/etherkick/etherkick)
	$(CC) $(COPT) -o $(TOOLDIR)/etherkick/etherkick ./tools/etherkick/etherkick.c $(SOCKLIBS)


# ============================ print-warn, clean-target
tools/hotpatch/hotpatch:	tools/hotpatch/hotpatch.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(TOOLDIR)/hotpatch/hotpatch)
	$(CC) $(COPT) -o $(TOOLDIR)/hotpatch/hotpatch $(TOOLDIR)/hotpatch/hotpatch.c

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that processes images, and can make a vhdl file
$(TOOLDIR)/pngprepare/pngprepare:	$(TOOLDIR)/pngprepare/pngprepare.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(TOOLDIR)/pngprepare/pngprepare)
	$(CC) $(COPT) -I/usr/local/include -L/usr/local/lib -o $(TOOLDIR)/pngprepare/pngprepare $(TOOLDIR)/pngprepare/pngprepare.c -lpng

# ============================ done *deleted*, Makefile-dep, print-warn, clean-target
# unix command to generate the 'iomap.txt' file that represents the registers
# within both the c64 and the c65gs
# note that the iomap.txt file already comes from github.
# note that the iomap.txt file is often recreated because version.vhdl is updated.
iomap.txt:	$(VHDLSRCDIR)/*.vhdl 
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: ../iomap.txt)
	# Force consistent ordering of items according to natural byte values
	export LC_ALL=C
	egrep "IO:C6|IO:GS" $(VHDLSRCDIR)/*.vhdl | cut -f3- -d: | sort -u -k2 > iomap.txt

CRAMUTILS=	bin/border.prg $(SRCDIR)/mega65-fdisk/m65fdisk.prg
COLOURRAM.BIN:	$(TOOLDIR)/utilpacker/utilpacker $(CRAMUTILS)
	$(TOOLDIR)/utilpacker/utilpacker COLOURRAM.BIN $(CRAMUTILS)

tools/utilpacker/utilpacker:	$(TOOLDIR)/utilpacker/utilpacker.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(TOOLDIR)/utilpacker/utilpacker)
	$(CC) $(COPT) -o $(TOOLDIR)/utilpacker/utilpacker $(TOOLDIR)/utilpacker/utilpacker.c

# ============================ done moved, Makefile-dep, print-warn, clean-target
# script to extract the git-status from the ./.git filesystem, and to embed that string
# into two files (*.vhdl and *.a65), that is wrapped with the template-file
# NOTE that we should use make to build the ISE project so that the
# version information is updated.
# for now we will always update the version info whenever we do a make.
.PHONY: version.vhdl version.a65
$(VHDLSRCDIR)/version.vhdl version.a65:
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/version.vhdl and version.a65)
	./version.sh

# i think 'charrom' is used to put the pngprepare file into a special mode that
# generates the charrom.vhdl file that is embedded with the contents of the 8x8font.png file
$(VHDLSRCDIR)/charrom.vhdl:	$(TOOLDIR)/pngprepare/pngprepare $(ASSETS)/8x8font.png
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/charrom.vhdl)
#       exe          option  infile      outfile
	$(TOOLDIR)/pngprepare/pngprepare charrom $(ASSETS)/8x8font.png $(VHDLSRCDIR)/charrom.vhdl

$(SDCARD_DIR)/BANNER.M65:	$(TOOLDIR)/pngprepare/pngprepare assets/mega65_320x64.png
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/BANNER.M65)

	/usr/bin/convert -colors 128 -depth 8 +dither assets/mega65_320x64.png bin/mega65_320x64_128colour.png
	$(TOOLDIR)/pngprepare/pngprepare logo bin/mega65_320x64_128colour.png $(SDCARD_DIR)/BANNER.M65

# disk menu program for loading from SD card to $C000 on boot by kickstart
$(SDCARD_DIR)/C000UTIL.BIN:	$(SRCDIR)/diskmenu_c000.bin
	cp $(SRCDIR)/diskmenu_c000.bin $(SDCARD_DIR)/C000UTIL.BIN

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to be the 'load-wedge'
# for the serial-monitor
monitor_drive:	monitor_drive.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_drive)
	$(CC) $(COPT) -o monitor_drive monitor_drive.c

tools/monitor_load:	tools/monitor_load.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_load)
	$(CC) $(COPT) -o $(TOOLDIR)/monitor_load $(TOOLDIR)/monitor_load.c

tools/monitor_save:	tools/monitor_save.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_save)
	$(CC) $(COPT) -o $(TOOLDIR)/monitor_save $(TOOLDIR)/monitor_save.c

tools/on_screen_keyboard_gen:	tools/on_screen_keyboard_gen.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: on_screen_keyboard_gen)
	$(CC) $(COPT) -o $(TOOLDIR)/on_screen_keyboard_gen $(TOOLDIR)/on_screen_keyboard_gen.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read from the serial port, and
# dump that to a file.
# makes use of the serial monitor within the fpga
read_mem:	read_mem.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: read_mem)
	$(CC) $(COPT) -o read_mem read_mem.c

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read serial commands from serial-port
chargen_debug:	chargen_debug.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: chargen_debug)
	gcc -Wall -o chargen_debug chargen_debug.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to disassemble assembly code
dis4510:	dis4510.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: dis4510)
	$(CC) $(COPT) -o dis4510 dis4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that seems to emulate assembly code
# currently does not compile
em4510:	em4510.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: em4510)
	$(CC) $(COPT) -o em4510 em4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# Generate VHDL instruction and addressing mode tables for 4510 CPU
4510tables:	4510tables.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: 4510tables)
	$(CC) $(COPT) -o 4510tables 4510tables.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think this one needs 64net.opc
c65-rom-disassembly.txt:	dis4510 c65-dos-context.bin c65-rom-annotations.txt
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-rom-disassembly.txt)
	./dis4510 c65-dos-context.bin 2000 c65-rom-annotations.txt > c65-rom-disassembly.txt


# ============================ done moved, Makefile-dep, print-warn, clean-target
# BG added this because the file "c65-911001-rom-annotations.txt" is missing
c65-911001-rom-annotations.txt:	c65-rom-annotations.txt
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-911001-rom-annotations.txt)
	cp c65-rom-annotations.txt c65-911001-rom-annotations.txt


# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think this one needs 64net.opc
c65-rom-911001.txt:	dis4510 c65-911001-dos-context.bin c65-911001-rom-annotations.txt
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-rom-911001.txt)
	./dis4510 c65-911001-dos-context.bin 2000 c65-911001rom-annotations.txt > c65-rom-911001.txt


# unsure, but see 'man dd',
# reads c65-rom-910111.bin and generates c65-dos*.bin
# needed to create c65-rom-910111.bin for this to work, need to ask PGS where is the correct file
c65-dos-context.bin:	c65-rom-910111.bin
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-dos-context.bin)
	dd if=c65-rom-910111.bin bs=8192  skip=9  count=3 >  c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=16384 skip=0  count=1 >> c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=4096  skip=12 count=1 >> c65-dos-context.bin
	dd if=/dev/zero          bs=4096          count=1 >> c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=8192  skip=15 count=1 >> c65-dos-context.bin

# unsure, but see 'man dd',
# reads 911001.bin and outputs c65-911001*.bin
# needed to create 911001.bin for this to work, need to ask PGS where is the correct file
c65-911001-dos-context.bin:	911001.bin Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-911001-dos-context.bin)
	dd if=911001.bin bs=8192  skip=9  count=3 >  c65-911001-dos-context.bin
	dd if=911001.bin bs=16384 skip=0  count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=4096  skip=12 count=1 >> c65-911001-dos-context.bin
	dd if=/dev/zero  bs=4096          count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=8192  skip=15 count=1 >> c65-911001-dos-context.bin

modeline:	Makefile modeline.c
	$(CC) $(COPT) -o modeline modeline.c $(LOPT)

clean:
	rm -f KICKUP.M65 kickstart.list kickstart.map
	rm -f diskmenu.prg diskmenuprg.list diskmenuprg.map
	rm -f diskmenu_c000.bin diskmenuc000.list diskmenuc000.map
	rm -f $(TOOLDIR)/etherkick/etherkick
	rm -f $(TOOLDIR)/etherload/etherload
	rm -f $(TOOLDIR)/hotpatch/hotpatch
	rm -f $(TOOLDIR)/pngprepare/pngprepare
	rm -f utilities/etherload.prg utilities/etherload.list utilities/etherload.map
	rm -f utilities/ethertest.prg utilities/ethertest.list utilities/ethertest.map
	rm -f utilities/test01prg.prg utilities/test01prg.list utilities/test01prg.map
	rm -f utilities/c65test02prg.prg utilities/c65test02prg.list utilities/c65test02prg.map
	rm -f iomap.txt
	rm -f utility.d81
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
