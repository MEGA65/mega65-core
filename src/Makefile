
VHDLSRCDIR=	vhdl

KICKSTARTSRCS = kickstart.a65 \
		kickstart_machine.a65 \
		kickstart_process_descriptor.a65 \
		kickstart_dos.a65 \
		kickstart_task.a65 \
		kickstart_mem.a65

UTILITIES=	utilities/ethertest.prg \
		utilities/etherload.prg \
		utilities/test01prg.prg \
		utilities/c65test02prg.prg \
		tests/test_fdc_equal_flag.prg \
		diskmenu.prg

TOOLS=	etherkick \
	etherload \
	hotpatch

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
		$(VHDLSRCDIR)/version.vhdl


# files destined to go on the SD-card to serve as firmware for the MEGA65
firmware:	BOOTLOGO.M65 \
		KICKUP.M65 \
		MEGA65.D81

# c-programs
tools:	$(TOOLS)

# assembly files (a65 -> prg)
utilities:	$(UTILITIES)


simulate:	diskmenu.prg \
	KICKUP.M65 \
	makerom \
	container.prj \
	thumbnail.prg \
	textmodetest.prg \
	etherload \
	etherkick


# ============================, print-warn, clean target
# verbose, for 1581 format, overwrite
MEGA65.D81:	$(UTILITIES)
	$(warning ~~~~~~~~~~~~~~~~> Making: MEGA65.D81)
#	cbmconvert -v2 -D8o utility.d81 $(UTILITIES)
	cbmconvert -v2 -D8o MEGA65.D81 utilities/ethertest.prg \
                                        utilities/etherload.prg \
                                        utilities/test01prg.prg \
                                        utilities/c65test02prg.prg \
					tests/test_fdc_equal_flag.prg \
                                        diskmenu.prg

# ============================ done moved, print-warn, clean-target
# ophis converts the *.a65 file (assembly text) to *.prg (assembly bytes)
utilities/ethertest.prg:	utilities/ethertest.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/ethertest.prg)
	./../../Ophis/bin/ophis -4 utilities/ethertest.a65 -l utilities/ethertest.list -m utilities/ethertest.map


# ============================ done moved, print-warn, clean-target
# ophis converts the (two) *.a65 file (assembly text) to *.prg (assembly bytes)
# the "l" option created a verbose listing of the output
# NOTE that to get to compile i needed to comment out the ".scope" in the "diskmenu.a65" file
diskmenu.prg:	diskmenuprg.a65 diskmenu.a65 utilities/etherload.prg
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu.prg and diskmenuprg.list)
	./../../Ophis/bin/ophis -4 diskmenuprg.a65 -l diskmenuprg.list -m diskmenuprg.map


# ============================ done moved, print-warn, clean-target
# we do not use this initial version anymore, but remains here for learning from
diskchooser:	diskchooser.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: diskchooser)
	./../../Ophis/bin/ophis -4 diskchooser.a65

test_fdc_equal_flag.prg:	tests/test_fdc_equal_flag.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu.prg and diskmenuprg.list)
	./../../Ophis/bin/ophis -4 tests/test_fdc_equal_flag.a65


# ============================ done moved, print-warn, clean-target
#??? diskmenu_c000.bin yet b0rken
KICKUP.M65:	$(KICKSTARTSRCS) diskmenu_c000.bin version.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: KICKUP.M65 and kickstart.list)
	./../../Ophis/bin/ophis -4 kickstart.a65 -l kickstart.list -m kickstart.map


# ============================ done moved, print-warn, clean-target
diskmenu_c000.bin:	diskmenuc000.a65 diskmenu.a65 utilities/etherload.prg
	$(warning ~~~~~~~~~~~~~~~~> Making: diskmenu_c000.bin and diskmenuc000.list)
	./../../Ophis/bin/ophis -4 diskmenuc000.a65 -l diskmenuc000.list -m diskmenuc000.map


# ============================ done moved, print-warn, clean-target
thumbnail.prg:	showthumbnail.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: thumbnail.prg)
	./../../Ophis/bin/ophis -4 showthumbnail.a65 -m showthumbnail.map -l showthumbnail.list


# ============================ done moved, print-warn, clean-target
utilities/etherload.prg:	utilities/etherload.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/etherload.prg)
	./../../Ophis/bin/ophis -4 utilities/etherload.a65 -l utilities/etherload.list -m utilities/etherload.map


# ============================ done moved, print-warn, clean-target
utilities/test01prg.prg:	utilities/test01prg.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/test01prg.prg)
	./../../Ophis/bin/ophis -4 utilities/test01prg.a65 -l utilities/test01prg.list -m utilities/test01prg.map


# ============================ done moved, print-warn, clean-target
utilities/c65test02prg.prg:	utilities/c65test02prg.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: utilities/c65test02prg.prg)
	./../../Ophis/bin/ophis -4 utilities/c65test02prg.a65 -l utilities/c65test02prg.list -m utilities/c65test02prg.map


# ============================ done moved, print-warn, clean-target
# keep this in _unused for time being
etherload_stub.bin:	etherload_stub.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: etherload_stub.bin)
	./../../Ophis/bin/ophis -4 etherload_stub.a65


# ============================ done moved, print-warn, clean-target
# keep this in _unused for time being
etherload_done.bin:	etherload_done.a65
	$(warning ~~~~~~~~~~~~~~~~> Making: etherload_done.bin)
	./../../Ophis/bin/ophis -4 etherload_done.a65


# ============================ done moved, print-warn, clean-target
# dejavus.f65 seems to be a font tile
textmodetest.prg:	textmodetest.a65 textmodetest-dejavus.f65
	$(warning ~~~~~~~~~~~~~~~~> Making: textmodetest.prg)
	./../../Ophis/bin/ophis -4 textmodetest.a65 -l textmodetest.list


# ============================ done moved, print-warn, clean-target
# makerom is a python script that reads two files (arg[1,2]) and generates one (arg[3]).
# the line below would generate the kickstart.vhdl file, (note no file extention on arg[3])
# two files are read (arg[1] and arg[2]) and somehow compared, looking for THEROM and ROMDATA
$(VHDLSRCDIR)/kickstart.vhdl:	rom_template.vhdl KICKUP.M65 makerom
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/kickstart.vhdl)
#       script    arg[1]            arg[2]            arg[3]
	./makerom rom_template.vhdl KICKUP.M65 $(VHDLSRCDIR)/kickstart kickstart


# unsure why the below is commented out
#slowram.vhdl:	c65gs.rom makeslowram slowram_template.vhdl
#	./makeslowram slowram_template.vhdl c65gs.rom slowram


# ============================ done moved, print-warn, clean-target
# c-code that makes an executable that seems to extract images from the c65gs via lan
# and displays the images on the users screen using vncserver
# does not currently compile
videoproxy:	videoproxy.c
	$(warning ~~~~~~~~~~~~~~~~> Making: videoproxy)
	gcc -Wall -g -o videoproxy videoproxy.c -lpcap


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
etherload:	tools/etherload/etherload.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/etherload/etherload)
	gcc -Wall -g -o tools/etherload/etherload tools/etherload/etherload.c $(SOCKLIBS)


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
etherkick:	tools/etherkick/etherkick.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/etherkick/etherkick)
	gcc -Wall -g -o tools/etherkick/etherkick ./tools/etherkick/etherkick.c $(SOCKLIBS)


# ============================ print-warn, clean-target
hotpatch:	tools/hotpatch/hotpatch.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: tools/hotpatch/hotpatch)
	gcc -Wall -g -o tools/hotpatch/hotpatch tools/hotpatch/hotpatch.c


# ============================ done *deleted*, Makefile-dep, print-warn, clean-target
# unix command to generate the 'iomap.txt' file that represents the registers
# within both the c64 and the c65gs
# note that the iomap.txt file already comes from github
../iomap.txt:	$(VHDLSRCDIR)/*.vhdl 
	$(warning ~~~~~~~~~~~~~~~~> Making: ../iomap.txt)
	# Force consistent ordering of items according to natural byte values
	export LC_ALL=C
	egrep "IO:C6|IO:GS" $(VHDLSRCDIR)/*.vhdl | cut -f3- -d: | sort -u -k2 > ../iomap.txt

# ============================ done moved, Makefile-dep, print-warn, clean-target
# script to extract the git-status from the ./.git filesystem, and to embed that string
# into two files (*.vhdl and *.a65), that is wrapped with the template-file
# NOTE that we should use make to build the ISE project so that the
# version information is updated.
# for now we will always update the version info whenever we do a make.
.PHONY: version.vhdl version.a65
$(VHDLSRCDIR)/version.vhdl version.a65:
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/version.vhdl and version.a65)
	./version.sh

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that processes images, and can make a vhdl file
pngprepare:	pngprepare.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: pngprepare)
	gcc -g -Wall -I/usr/local/include -L/usr/local/lib -o pngprepare pngprepare.c -lpng

# i think 'charrom' is used to put the pngprepare file into a special mode that
# generates the charrom.vhdl file that is embedded with the contents of the 8x8font.png file
$(VHDLSRCDIR)/charrom.vhdl:	pngprepare 8x8font.png
	$(warning ~~~~~~~~~~~~~~~~> Making: $(VHDLSRCDIR)/charrom.vhdl)
#       exe          option  infile      outfile
	./pngprepare charrom 8x8font.png $(VHDLSRCDIR)/charrom.vhdl

# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think the 'logo' is used to put the pngprepare into a special mode that
# generates the BOOTLOGO.M65 file that is embedded with the contents of the mega65*.png file
BOOTLOGO.M65:	pngprepare mega65_64x64.png
	$(warning ~~~~~~~~~~~~~~~~> Making: BOOTLOGO.M65)
#       exe          opt  infile           outfile
	./pngprepare logo mega65_64x64.png BOOTLOGO.M65

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to be the 'load-wedge'
# for the serial-monitor
monitor_drive:	monitor_drive.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_drive)
	gcc -g -Wall -o monitor_drive monitor_drive.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# via the serial monitor to the fpga
# currently has warnings upon compile
monitor_load:	monitor_load.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: monitor_load)
	gcc -g -Wall -o monitor_load monitor_load.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read from the serial port, and
# dump that to a file.
# makes use of the serial monitor within the fpga
read_mem:	read_mem.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: read_mem)
	gcc -g -Wall -o read_mem read_mem.c

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read serial commands from serial-port
chargen_debug:	chargen_debug.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: chargen_debug)
	gcc -Wall -o chargen_debug chargen_debug.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to disassemble assembly code
dis4510:	dis4510.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: dis4510)
	gcc -g -Wall -o dis4510 dis4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that seems to emulate assembly code
# currently does not compile
em4510:	em4510.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: em4510)
	gcc -g -Wall -o em4510 em4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# Generate VHDL instruction and addressing mode tables for 4510 CPU
4510tables:	4510tables.c Makefile
	$(warning ~~~~~~~~~~~~~~~~> Making: 4510tables)
	gcc -g -Wall -o 4510tables 4510tables.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think this one needs 64net.opc
c65-rom-disassembly.txt:	dis4510 c65-dos-context.bin c65-rom-annotations.txt
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-rom-disassembly.txt)
	./dis4510 c65-dos-context.bin 2000 c65-rom-annotations.txt > c65-rom-disassembly.txt


# ============================ done moved, Makefile-dep, print-warn, clean-target
# BG added this because the file "c65-911001-rom-annotations.txt" is missing
c65-911001-rom-annotations.txt:	c65-rom-annotations.txt
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-911001-rom-annotations.txt)
	cp c65-rom-annotations.txt c65-911001-rom-annotations.txt


# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think this one needs 64net.opc
c65-rom-911001.txt:	dis4510 c65-911001-dos-context.bin c65-911001-rom-annotations.txt
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-rom-911001.txt)
	./dis4510 c65-911001-dos-context.bin 2000 c65-911001rom-annotations.txt > c65-rom-911001.txt


# unsure, but see 'man dd',
# reads c65-rom-910111.bin and generates c65-dos*.bin
# needed to create c65-rom-910111.bin for this to work, need to ask PGS where is the correct file
c65-dos-context.bin:	c65-rom-910111.bin
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
	$(warning ~~~~~~~~~~~~~~~~> Making: c65-911001-dos-context.bin)
	dd if=911001.bin bs=8192  skip=9  count=3 >  c65-911001-dos-context.bin
	dd if=911001.bin bs=16384 skip=0  count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=4096  skip=12 count=1 >> c65-911001-dos-context.bin
	dd if=/dev/zero  bs=4096          count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=8192  skip=15 count=1 >> c65-911001-dos-context.bin


clean:
	rm -f KICKUP.M65 kickstart.list kickstart.map
	rm -f diskmenu.prg diskmenuprg.list diskmenuprg.map
	rm -f diskmenu_c000.bin diskmenuc000.list diskmenuc000.map
	rm -f tools/etherkick/etherkick
	rm -f tools/etherload/etherload
	rm -f tools/hotpatch/hotpatch
	rm -f utilities/etherload.prg utilities/etherload.list utilities/etherload.map
	rm -f utilities/ethertest.prg utilities/ethertest.list utilities/ethertest.map
	rm -f utilities/test01prg.prg utilities/test01prg.list utilities/test01prg.map
	rm -f utilities/c65test02prg.prg utilities/c65test02prg.list utilities/c65test02prg.map
	rm -f iomap.txt
	rm -f utility.d81
	rm -f $(VHDLSRCDIR)/kickstart.vhdl $(VHDLSRCDIR)/charrom.vhdl $(VHDLSRCDIR)/version.vhdl version.a65
	rm -f monitor_drive monitor_load read_mem ghdl-frame-gen chargen_debug dis4510 em4510 4510tables pngprepare BOOTLOGO.M65
	rm -f c65-rom-911001.txt c65-911001-rom-annotations.txt c65-dos-context.bin c65-911001-dos-context.bin
	rm -f thumbnail.prg
	rm -f textmodetest.prg textmodetest.list etherload_done.bin etherload_stub.bin
	rm -f videoproxy

cleangen:
	rm $(VHDLSRCDIR)/kickstart.vhdl $(VHDLSRCDIR)/charrom.vhdl *.M65
