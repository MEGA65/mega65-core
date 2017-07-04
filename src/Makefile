
VHDLSRCDIR=	vhdl

SDCARD_DIR=	../sdcard-files

KICKSTARTSRCS = kickstart.a65 \
		kickstart_machine.a65 \
		kickstart_process_descriptor.a65 \
		kickstart_dos.a65 \
		kickstart_task.a65 \
		kickstart_mem.a65

# if you want your PRG to appear on "MEGA65.D81", then put your PRG in "./src/utilities/userPRGs"
# ie: COMMANDO.PRG
#
# if you want your .a65 source code compiled and then embedded within "MEGA65.D81", then put
# your source.a65 in the 'utilities' directory, and ensure it is listed below.
#
# NOTE: that all files listed below will be embedded within the "MEGA65.D81".
#
UTILITIES=	utilities/ethertest.prg \
		utilities/etherload.prg \
		utilities/test01prg.prg \
		utilities/c65test02prg.prg \
		utilities/c65-rom-910111-fastload-patch.prg \
		utilities/userPRGs/* \
		tests/test_fdc_equal_flag.prg \
		diskmenu.prg \

TOOLS=	tools/etherkick/etherkick \
	tools/etherload/etherload \
	tools/hotpatch/hotpatch \
	tools/pngprepare/pngprepare

all:
	$(warning ~~~~~~~~~~~~~~~~> The 'all'-target is not implemented in the makefile yet, refer to ./../compile.sh)
	$(warning You need to explicitly know what to make, else use ./../compile.sh)
	$(warning Common targets are: generated_vhdl, firmware, tools, utilities)
	$(warning Other  targets are: simulate, utility.d81)


fpga:
	$(warning ~~~~~~~~~~~~~~~~> The 'fpga'-target is not implemented in the makefile yet, refer to ./../compile.sh)
	$(warning ISE build to go here, ie xst, ngdbuild, map, par, bitgen)

generated_vhdl:	$(VHDLSRCDIR)/kickstart.vhdl \
		$(VHDLSRCDIR)/charrom.vhdl \
		$(VHDLSRCDIR)/version.vhdl \
		$(VHDLSRCDIR)/colourram.vhdl


# files destined to go on the SD-card to serve as firmware for the MEGA65
firmware:	$(SDCARD_DIR)/BOOTLOGO.M65 \
		KICKUP.M65 \
		COLOURRAM.BIN \
		$(SDCARD_DIR)/MEGA65.D81 \
		$(SDCARD_DIR)/C000UTIL.BIN

roms:		$(SDCARD_DIR)/CHARROM.M65 \
		$(SDCARD_DIR)/MEGA65.ROM

# c-programs
tools:	$(TOOLS)

# assembly files (a65 -> prg)
utilities:	$(UTILITIES)


SIMULATIONFILES=	vhdl/UART_TX_CTRL.vhd vhdl/bitplane.vhdl vhdl/bitplanes.vhdl vhdl/c65uart.vhdl vhdl/charrom.vhdl vhdl/cia6526.vhdl vhdl/container.vhd vhdl/cpu_test.vhdl vhdl/cputypes.vhdl vhdl/crc.vhdl vhdl/ddrwrapper.vhdl vhdl/debugtools.vhdl vhdl/ethernet.vhdl vhdl/framepacker.vhdl vhdl/ghdl_alpha_blend.vhdl vhdl/ghdl_chipram8bit.vhdl vhdl/ghdl_farstack.vhdl vhdl/ghdl_ram128x1k.vhdl vhdl/ghdl_ram18x2k.vhdl vhdl/colourram.vhdl vhdl/ghdl_ram8x4096.vhdl vhdl/ghdl_ram8x512.vhdl vhdl/ghdl_ram9x4k.vhdl vhdl/ghdl_screen_ram_buffer.vhdl vhdl/ghdl_videobuffer.vhdl vhdl/gs4510.vhdl vhdl/iomapper.vhdl vhdl/keymapper.vhdl vhdl/kickstart.vhdl vhdl/machine.vhdl vhdl/ramlatch64.vhdl vhdl/sd.vhdl vhdl/sdcardio.vhdl vhdl/shadowram.vhdl vhdl/sid_6581.vhd vhdl/sid_coeffs.vhd vhdl/sid_components.vhd vhdl/sid_filters.vhd vhdl/sid_voice.vhd vhdl/slowram.vhdl vhdl/sprite.vhdl vhdl/uart_monitor.vhdl vhdl/uart_rx.vhdl vhdl/version.vhdl vhdl/vicii_sprites.vhdl vhdl/viciv.vhdl vhdl/ghdl_fpgatemp.vhdl vhdl/victypes.vhdl vhdl/pal_simulation.vhdl vhdl/fake_expansion_port.vhdl vhdl/expansion_port_controller.vhdl vhdl/slow_devices.vhdl vhdl/ps2_to_uart.vhdl vhdl/matrix_compositor.vhdl vhdl/terminalemulator.vhdl vhdl/uart_charrom.vhdl vhdl/uart_rx.vhdl
simulate:	$(SIMULATIONFILES)
	ghdl -i $(SIMULATIONFILES)
	ghdl -m cpu_test
	./cpu_test || ghdl -r cpu_test

vfsimulate:	vhdl/frame_test.vhdl vhdl/video_frame.vhdl
	ghdl -i vhdl/frame_test.vhdl vhdl/video_frame.vhdl
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
	./../../Ophis/bin/ophis -4 tests/test_fdc_equal_flag.a65 -l tests/test_fdc_equal_flag.list -m tests/test_fdc_equal_flag.map


# ============================ done moved, print-warn, clean-target
# ophis converts the *.a65 file (assembly text) to *.prg (assembly bytes)
utilities/ethertest.prg:	utilities/ethertest.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/ethertest.prg)
	./../../Ophis/bin/ophis -4 utilities/ethertest.a65 -l utilities/ethertest.list -m utilities/ethertest.map


# ============================ done moved, print-warn, clean-target
# ophis converts the (two) *.a65 file (assembly text) to *.prg (assembly bytes)
# the "l" option created a verbose listing of the output
# NOTE that to get to compile i needed to comment out the ".scope" in the "diskmenu.a65" file
diskmenu.prg:	diskmenuprg.a65 diskmenu.a65 utilities/etherload.prg
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu.prg and diskmenuprg.list)
	./../../Ophis/bin/ophis -4 diskmenuprg.a65 -l diskmenuprg.list -m diskmenuprg.map

megacart.crt:	megacartstub.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu.prg and diskmenuprg.list)
	./../../Ophis/bin/ophis -4 megacartstub.a65 -l megacart.list -m megacart.map

fdisk.native:	fdisk.c fdisk_hal_unix.c fdisk_hal.h Makefile
	gcc -g -Wall -o fdisk.native fdisk.c fdisk_hal_unix.c

fdisktest:	fdisk.d81 COLOURRAM.BIN
	dd if=/dev/zero of=empty.img bs=1048576 count=200
	../../xemu/build/bin/xmega65.native -8 fdisk.d81 -sdimg empty.img -skipunhandledmem -dmarev 0 -loadcram COLOURRAM.BIN

fdisk.d81:	fdisk.prg
	cbmconvert -v2 -D8o fdisk.d81 fdisk.prg

FDISK_HEADERS=	fdisk_screen.h fdisk_memory.h Makefile
CC65=cc65
COPTS=-O

%.s:	%.c $(FDISK_HEADERS)
	$(CC65) $(COPTS) -o $@ $<

fdisk.prg:	fdisk.s fdisk_hal_mega65.s fdisk_memory.s fdisk_screen.s
	cl65 -t c64 -o fdisk.prg fdisk.s fdisk_hal_mega65.s fdisk_memory.s fdisk_screen.s

border.prg:	border.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: border.prg)
	./../../Ophis/bin/ophis -4 border.a65


# ============================ done moved, print-warn, clean-target
# we do not use this initial version anymore, but remains here for learning from
diskchooser:	diskchooser.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskchooser)
	./../../Ophis/bin/ophis -4 diskchooser.a65


# ============================ done moved, print-warn, clean-target
#??? diskmenu_c000.bin yet b0rken
KICKUP.M65:	$(KICKSTARTSRCS) diskmenu_c000.bin version.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: KICKUP.M65 and kickstart.list)
	./../../Ophis/bin/ophis -4 kickstart.a65 -l kickstart.list -m kickstart.map


# ============================ done moved, print-warn, clean-target
diskmenu_c000.bin:	diskmenuc000.a65 diskmenu.a65 utilities/etherload.prg
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu_c000.bin and diskmenuc000.list)
	./../../Ophis/bin/ophis -4 diskmenuc000.a65 -l diskmenuc000.list -m diskmenuc000.map


# ============================ done moved, print-warn, clean-target
thumbnail.prg:	showthumbnail.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: thumbnail.prg)
	./../../Ophis/bin/ophis -4 showthumbnail.a65 -m showthumbnail.map -l showthumbnail.list


# ============================ done moved, print-warn, clean-target
utilities/etherload.prg:	utilities/etherload.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/etherload.prg)
	./../../Ophis/bin/ophis -4 utilities/etherload.a65 -l utilities/etherload.list -m utilities/etherload.map


# ============================ done moved, print-warn, clean-target
utilities/test01prg.prg:	utilities/test01prg.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/test01prg.prg)
	./../../Ophis/bin/ophis -4 utilities/test01prg.a65 -l utilities/test01prg.list -m utilities/test01prg.map


# ============================ done moved, print-warn, clean-target
utilities/c65test02prg.prg:	utilities/c65test02prg.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/c65test02prg.prg)
	./../../Ophis/bin/ophis -4 utilities/c65test02prg.a65 -l utilities/c65test02prg.list -m utilities/c65test02prg.map


utilities/c65-rom-910111-fastload-patch.prg:	utilities/c65-rom-910111-fastload-patch.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/c65-rom-910111-fastload-patch.prg)
	./../../Ophis/bin/ophis -4 utilities/c65-rom-910111-fastload-patch.a65 -l utilities/c65-rom-910111-fastload-patch.list -m utilities/c65-rom-910111-fastload-patch.map


# ============================ done moved, print-warn, clean-target
# keep this in _unused for time being
etherload_stub.bin:	etherload_stub.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: etherload_stub.bin)
	./../../Ophis/bin/ophis -4 etherload_stub.a65


# ============================ done moved, print-warn, clean-target
# keep this in _unused for time being
etherload_done.bin:	etherload_done.a65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: etherload_done.bin)
	./../../Ophis/bin/ophis -4 etherload_done.a65


# ============================ done moved, print-warn, clean-target
# dejavus.f65 seems to be a font tile
textmodetest.prg:	textmodetest.a65 textmodetest-dejavus.f65
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: textmodetest.prg)
	./../../Ophis/bin/ophis -4 textmodetest.a65 -l textmodetest.list


# ============================ done moved, print-warn, clean-target
# makerom is a python script that reads two files (arg[1,2]) and generates one (arg[3]).
# the line below would generate the kickstart.vhdl file, (note no file extention on arg[3])
# two files are read (arg[1] and arg[2]) and somehow compared, looking for THEROM and ROMDATA
$(VHDLSRCDIR)/kickstart.vhdl:	tools/makerom/rom_template.vhdl KICKUP.M65 tools/makerom/makerom
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/kickstart.vhdl)
#       script                arg[1]                          arg[2]     arg[3]                  arg[4]
	tools/makerom/makerom tools/makerom/rom_template.vhdl KICKUP.M65 $(VHDLSRCDIR)/kickstart kickstart

$(VHDLSRCDIR)/colourram.vhdl:	tools/makerom/colourram_template.vhdl COLOURRAM.BIN tools/makerom/makerom
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/colourram.vhdl)
	tools/makerom/makerom tools/makerom/colourram_template.vhdl COLOURRAM.BIN $(VHDLSRCDIR)/colourram ram8x32k


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
	gcc -Wall -g -o videoproxy videoproxy.c -lpcap


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
tools/etherload/etherload:	tools/etherload/etherload.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/etherload/etherload)
	gcc -Wall -g -o tools/etherload/etherload tools/etherload/etherload.c $(SOCKLIBS)


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
tools/etherkick/etherkick:	tools/etherkick/etherkick.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/etherkick/etherkick)
	gcc -Wall -g -o tools/etherkick/etherkick ./tools/etherkick/etherkick.c $(SOCKLIBS)


# ============================ print-warn, clean-target
tools/hotpatch/hotpatch:	tools/hotpatch/hotpatch.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/hotpatch/hotpatch)
	gcc -Wall -g -o tools/hotpatch/hotpatch tools/hotpatch/hotpatch.c

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that processes images, and can make a vhdl file
tools/pngprepare/pngprepare:	tools/pngprepare/pngprepare.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/pngprepare/pngprepare)
	gcc -g -Wall -I/usr/local/include -L/usr/local/lib -o tools/pngprepare/pngprepare tools/pngprepare/pngprepare.c -lpng

# ============================ done *deleted*, Makefile-dep, print-warn, clean-target
# unix command to generate the 'iomap.txt' file that represents the registers
# within both the c64 and the c65gs
# note that the iomap.txt file already comes from github.
# note that the iomap.txt file is often recreated because version.vhdl is updated.
../iomap.txt:	$(VHDLSRCDIR)/*.vhdl 
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: ../iomap.txt)
	# Force consistent ordering of items according to natural byte values
	export LC_ALL=C
	egrep "IO:C6|IO:GS" $(VHDLSRCDIR)/*.vhdl | cut -f3- -d: | sort -u -k2 > ../iomap.txt

CRAMUTILS=	border.prg fdisk.prg
COLOURRAM.BIN:	tools/utilpacker/utilpacker $(CRAMUTILS)
	tools/utilpacker/utilpacker COLOURRAM.BIN $(CRAMUTILS)

tools/utilpacker/utilpacker:	tools/utilpacker/utilpacker.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/utilpacker/utilpacker)
	gcc -g -Wall -std=gnu99 -o tools/utilpacker/utilpacker tools/utilpacker/utilpacker.c

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
$(VHDLSRCDIR)/charrom.vhdl:	tools/pngprepare/pngprepare 8x8font.png
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/charrom.vhdl)
#       exe          option  infile      outfile
	tools/pngprepare/pngprepare charrom 8x8font.png $(VHDLSRCDIR)/charrom.vhdl

# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think the 'logo' is used to put the pngprepare into a special mode that
# generates the BOOTLOGO.M65 file that is embedded with the contents of the mega65*.png file
$(SDCARD_DIR)/BOOTLOGO.M65:	tools/pngprepare/pngprepare mega65_64x64.png
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: $(SDCARD_DIR)/BOOTLOGO.M65)
#       exe          opt  infile           outfile
	tools/pngprepare/pngprepare logo mega65_64x64.png $(SDCARD_DIR)/BOOTLOGO.M65

# disk menu program for loading from SD card to $C000 on boot by kickstart
$(SDCARD_DIR)/C000UTIL.BIN:	diskmenu_c000.bin
	cp diskmenu_c000.bin $(SDCARD_DIR)/C000UTIL.BIN

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to be the 'load-wedge'
# for the serial-monitor
monitor_drive:	monitor_drive.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_drive)
	gcc -g -Wall -o monitor_drive monitor_drive.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# via the serial monitor to the fpga
# currently has warnings upon compile
monitor_load:	monitor_load.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_load)
	gcc -g -Wall -o monitor_load monitor_load.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read from the serial port, and
# dump that to a file.
# makes use of the serial monitor within the fpga
read_mem:	read_mem.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: read_mem)
	gcc -g -Wall -o read_mem read_mem.c

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
	gcc -g -Wall -o dis4510 dis4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that seems to emulate assembly code
# currently does not compile
em4510:	em4510.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: em4510)
	gcc -g -Wall -o em4510 em4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# Generate VHDL instruction and addressing mode tables for 4510 CPU
4510tables:	4510tables.c Makefile
	$(warning =============================================================)
	$(warning ~~~~~~~~~~~~~~~~> Making: 4510tables)
	gcc -g -Wall -o 4510tables 4510tables.c


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
	rm -f tools/etherkick/etherkick
	rm -f tools/etherload/etherload
	rm -f tools/hotpatch/hotpatch
	rm -f tools/pngprepare/pngprepare
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
