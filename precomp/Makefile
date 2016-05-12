ROUTEEFFORT=	std
#ROUTEEFFORT=	med
#ROUTEEFFORT=	high

KICKSTARTSRCS=kickstart.a65 \
		kickstart_machine.a65 \
		kickstart_process_descriptor.a65 \
		kickstart_dos.a65 \
		kickstart_task.a65 \
		kickstart_mem.a65

# Unlikely anyone uses Windows 9x anymore
ifeq ($(OS),Windows_NT)
SOCKLIBS = -l ws2_32
else
SOCKLIBS =
endif

fpga:	kickstart.vhdl \
	charrom.vhdl

all:	ghdl-frame-gen \
	diskmenu.prg \
	kickstart65gs.bin \
	makerom \
	container.prj \
	thumbnail.prg \
	textmodetest.prg \
	etherload etherkick

# ============================ done moved, print-warn, clean-target
# ophis converts the *.a65 file (assembly text) to *.prg (assembly bytes)
ethertest.prg:	ethertest.a65
	$(warning making ethertest.prg)
	./../../Ophis/bin/ophis -4 ethertest.a65


# does not exist, so will not be included in the build
f011test.prg:	f011test.a65 
	./../../Ophis/bin/ophis -4 f011test.a65


# ============================ done moved, print-warn, clean-target
# ophis converts the (two) *.a65 file (assembly text) to *.prg (assembly bytes)
# the "l" option created a verbose listing of the output
# NOTE that to get to compile i needed to comment out the ".scope" in the "diskmenu.a65" file
diskmenu.prg:	diskmenuprg.a65 diskmenu.a65
	$(warning making diskmenu.prg and diskmenuprg.list)
	./../../Ophis/bin/ophis -4 diskmenuprg.a65 -l diskmenuprg.list


# ============================ done moved, print-warn, clean-target
diskchooser:	diskchooser.a65 etherload.prg
	$(warning making diskchooser)
	./../../Ophis/bin/ophis -4 diskchooser.a65 -l diskchooser.list


# this seems duplicated with the "version.vhdl", so will remove this one
#version.a65:	*.a65 *.vhd Makefile
#	./version.sh


# ============================ done moved, print-warn, clean-target
#??? diskmenu_c000.bin yet b0rken
kickstart65gs.bin:	$(KICKSTARTSRCS) diskchooser version.a65
	$(warning making kickstart65gs.bin and kickstart.list)
	./../../Ophis/bin/ophis -4 kickstart.a65 -l kickstart.list


# ============================ done moved, print-warn, clean-target
diskmenu_c000.bin:	diskmenuc000.a65 diskmenu.a65 etherload.prg
	$(warning making diskmenu_c000.bin and diskmenuc000.list)
	./../../Ophis/bin/ophis -4 diskmenuc000.a65 -l diskmenuc000.list


# ============================ done moved, print-warn, clean-target
thumbnail.prg:	showthumbnail.a65
	$(warning making thumbnail.prg)
	./../../Ophis/bin/ophis -4 showthumbnail.a65


# ============================ done moved, print-warn, clean-target
etherload.prg:	etherload.a65
	$(warning making etherload.prg)
	./../../Ophis/bin/ophis -4 etherload.a65


# ============================ done moved, print-warn, clean-target
etherload_stub.bin:	etherload_stub.a65
	$(warning making etherload_stub.bin)
	./../../Ophis/bin/ophis -4 etherload_stub.a65


# ============================ done moved, print-warn, clean-target
etherload_done.bin:	etherload_done.a65
	$(warning making etherload_done.bin)
	./../../Ophis/bin/ophis -4 etherload_done.a65


# ============================ done moved, print-warn, clean-target
# dejavus.f65 seems to be a font tile
textmodetest.prg:	textmodetest.a65 textmodetest-dejavus.f65
	$(warning making textmodetest.prg)
	./../../Ophis/bin/ophis -4 textmodetest.a65 -l textmodetest.list


# ============================ done moved, print-warn, clean-target
# makerom is a python script that reads two files and generates one.
# the line below would generate the kickstart.vhdl file, (note no file extention on arg[3])
# two files are read (arg[1] and arg[2]) and somehow compared, look for THEROM and ROMDATA
kickstart.vhdl:	rom_template.vhdl diskchooser kickstart65gs.bin makerom
	$(warning making kickstart.vhdl)
	./makerom rom_template.vhdl kickstart65gs.bin kickstart


# unsure why the below is commented out
#slowram.vhdl:	c65gs.rom makeslowram slowram_template.vhdl
#	./makeslowram slowram_template.vhdl c65gs.rom slowram


# ============================ done moved, print-warn, clean-target
# c-code that makes an executable that seems to extract images from the c65gs via lan
# and displays the images on the users screen using vncserver
# does not currently compile
videoproxy:	videoproxy.c
	$(warning making videoproxy)
	gcc -Wall -g -o videoproxy videoproxy.c -lpcap


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
etherload:	etherload.c
	$(warning making etherload)
	gcc -Wall -g -o etherload etherload.c $(SOCKLIBS)


# ============================ done moved, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# to the fpga via ethernet
etherkick:	etherkick.c
	$(warning making etherkick)
	gcc -Wall -g -o etherkick etherkick.c $(SOCKLIBS)


# ============================ done *deleted*, Makefile-dep, print-warn, clean-target
# unix command to generate the 'iomap.txt' file that represents the registers
# within both the c64 and the c65gs
# note that the iomap.txt file already comes from github
iomap.txt:	./../*.vhdl 
	$(warning making iomap.txt)
	egrep "IO:C6|IO:GS" ./../*.vhdl | cut -f3- -d: | sort -u -k2 > iomap.txt


# =========
# ========= not included in build as it seems not required
# =========
# performs a secure-copy from one machine to another machine on the network.
# i doubt this is still used, but remains here for historical purposes
transfer:	kickstart.vhdl version.vhdl kickstart65gs.bin makerom makeslowram iomap.txt ipcore_dir
	scp -pr ipcore_dir version.sh Makefile makerom c65gs.rom makerom makeslowram *.a65 *.ucf *.xise *.prj *vhd *vhdl kickstart65gs.bin 192.168.56.101:c64accel/
	scp -p .git/index 192.168.56.101:c64accel/.git/


# ============================ done moved, Makefile-dep, print-warn, clean-target
# script to extract the git-status from the ./.git filesystem, and to embed that string
# into two files (*.vhdl and *.a65), that is wrapped with the template-file
# NOTE that we should use make to build the ISE project so that the
# version information is updated.
# for now we will always update the version info whenever we do a make.
.PHONY: ALWAYS
version.vhdl version.a65: ALWAYS
	$(warning making version.vhdl and version.a65)
	./version.sh


# =========
# ========= not included in build as it seems not required
# =========
# ghdl is an open source simulator for the VHDL language
# cant seem to apt-install-ghdl
SIMULATIONFILES=viciv.vhdl bitplanes.vhdl bitplane.vhdl cputypes.vhdl sid_voice.vhd sid_coeffs.vhd sid_filters.vhd sid_components.vhd \
		version.vhdl kickstart.vhdl iomapper.vhdl container.vhd cpu_test.vhdl gs4510.vhdl \
		UART_TX_CTRL.vhd uart_rx.vhdl uart_monitor.vhdl machine.vhdl cia6526.vhdl c65uart.vhdl keymapper.vhdl \
		ghdl_ram8x32k.vhdl charrom.vhdl ghdl_chipram8bit.vhdl ghdl_screen_ram_buffer.vhdl ghdl_ram9x4k.vhdl ghdl_ram18x2k.vhdl \
		sdcardio.vhdl ghdl_ram8x512.vhdl ethernet.vhdl ramlatch64.vhdl shadowram.vhdl cputypes.vhdl version.vhdl sid_6581.vhd \
		ghdl_ram128x1k.vhdl ghdl_ram8x4096.vhdl crc.vhdl slowram.vhdl framepacker.vhdl \
		ghdl_videobuffer.vhdl vicii_sprites.vhdl sprite.vhdl ghdl_alpha_blend.vhdl ghdl_farstack.vhdl debugtools.vhdl
simulate:	$(SIMULATIONFILES)
	ghdl -i $(SIMULATIONFILES) 
	ghdl -m cpu_test


# =========
# ========= not included in build as it seems not required
# =========
# ghdl is an open source simulator for the VHDL language
# cant seem to apt-install-ghdl
testcia:	tb_cia.vhdl cia6526.vhdl debugtools.vhdl
	ghdl -c tb_cia.vhdl cia6526.vhdl debugtools.vhdl -r tb_cia


# =========
# ========= not included in build as it seems not required
# =========
# ghdl is an open source simulator for the VHDL language
# cant seem to apt-install-ghdl
testadder:	tb_adder.vhdl debugtools.vhdl
	ghdl -c tb_adder.vhdl debugtools.vhdl -r tb_adder


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to be the 'load-wedge'
# for the serial-monitor
monitor_drive:	monitor_drive.c Makefile
	$(warning making monitor_drive)
	gcc -g -Wall -o monitor_drive monitor_drive.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read a file and transferrs that file
# via the serial monitor to the fpga
# currently has warnings upon compile
monitor_load:	monitor_load.c Makefile
	$(warning making monitor_load)
	gcc -g -Wall -o monitor_load monitor_load.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read from the serial port, and
# dump that to a file.
# makes use of the serial monitor within the fpga
read_mem:	read_mem.c Makefile
	$(warning making read_mem)
	gcc -g -Wall -o read_mem read_mem.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to generate a 'frame.bmp' file
ghdl-frame-gen:	ghdl-frame-gen.c Makefile
	$(warning making ghdl-frame-gen)
	gcc -Wall -o ghdl-frame-gen ghdl-frame-gen.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to read serial commands from serial-port
chargen_debug:	chargen_debug.c Makefile
	$(warning making chargen_debug)
	gcc -Wall -o chargen_debug chargen_debug.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes and executable that seems to disassemble assembly code
dis4510:	dis4510.c Makefile
	$(warning making dis4510)
	gcc -g -Wall -o dis4510 dis4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that seems to emulate assembly code
# currently does not compile
em4510:	em4510.c Makefile
	$(warning making em4510)
	gcc -g -Wall -o em4510 em4510.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable, unsure what for
# loads 64net.opc (a list of the opcodes)
4510tables:	4510tables.c Makefile
	$(warning making 4510tables)
	gcc -g -Wall -o 4510tables 4510tables.c


# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think this one needs 64net.opc
c65-rom-disassembly.txt:	dis4510 c65-dos-context.bin c65-rom-annotations.txt
	$(warning making c65-rom-disassembly.txt)
	./dis4510 c65-dos-context.bin 2000 c65-rom-annotations.txt > c65-rom-disassembly.txt


# ============================ done moved, Makefile-dep, print-warn, clean-target
# BG added this because the file "c65-911001-rom-annotations.txt" is missing
c65-911001-rom-annotations.txt:	c65-rom-annotations.txt
	$(warning making c65-911001-rom-annotations.txt)
	cp c65-rom-annotations.txt c65-911001-rom-annotations.txt


# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think this one needs 64net.opc
c65-rom-911001.txt:	dis4510 c65-911001-dos-context.bin c65-911001-rom-annotations.txt
	$(warning making c65-rom-911001.txt)
	./dis4510 c65-911001-dos-context.bin 2000 c65-911001rom-annotations.txt > c65-rom-911001.txt


# unsure, but see 'man dd',
# reads c65-rom-910111.bin and generates c65-dos*.bin
# needed to create c65-rom-910111.bin for this to work, need to ask PGS where is the correct file
c65-dos-context.bin:	c65-rom-910111.bin
	$(warning making c65-dos-context.bin)
	dd if=c65-rom-910111.bin bs=8192  skip=9  count=3 >  c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=16384 skip=0  count=1 >> c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=4096  skip=12 count=1 >> c65-dos-context.bin
	dd if=/dev/zero          bs=4096          count=1 >> c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=8192  skip=15 count=1 >> c65-dos-context.bin

# unsure, but see 'man dd',
# reads 911001.bin and outputs c65-911001*.bin
# needed to create 911001.bin for this to work, need to ask PGS where is the correct file
c65-911001-dos-context.bin:	911001.bin Makefile
	$(warning making c65-911001-dos-context.bin)
	dd if=911001.bin bs=8192  skip=9  count=3 >  c65-911001-dos-context.bin
	dd if=911001.bin bs=16384 skip=0  count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=4096  skip=12 count=1 >> c65-911001-dos-context.bin
	dd if=/dev/zero  bs=4096          count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=8192  skip=15 count=1 >> c65-911001-dos-context.bin

# ============================ done moved, Makefile-dep, print-warn, clean-target
# c-code that makes an executable that processes images, and can make a vhdl file
pngprepare:	pngprepare.c Makefile
	$(warning making pngprepare)
	gcc -g -Wall -I/usr/local/include -L/usr/local/lib -o pngprepare pngprepare.c -lpng

# i think 'charrom' is used to put the pngprepare file into a special mode that
# generates the charrom.vhdl file that is embedded with the contents of the 8x8font.png file
charrom.vhdl:	pngprepare 8x8font.png
	./pngprepare charrom 8x8font.png charrom.vhdl

# ============================ done moved, Makefile-dep, print-warn, clean-target
# i think the 'logo' is used to put the pngprepare into a special mode that
# generates the BOOTLOGO.G65 file that is embedded with the contents of the mega65*.png file
BOOTLOGO.G65:	pngprepare mega65_64x64.png
	$(warning making BOOTLOGO.G65)
#       exe          opt  infile           outfile
	./pngprepare logo mega65_64x64.png BOOTLOGO.G65


clean:
	rm -f *.gise *.bgn *.bld *.cmd_log *.drc *.lso *.ncd *.ngc *.ngd *.ngr *.pad *.par *.pcf *.ptwx *.stx *.syr *.twr *.twx *.unroutes *.ut *.xpi *.xst *.xwbt
	rm -f *.map *.mrp *.psr *.xrpt *.csv *.list *.log *.xml
	rm -f container_summary.* container_usage.* usage_statistics_webtalk.* par_usage_statistics.*
	rm -f ipcore_dir/*.asy ipcore_dir/*.gise ipcore_dir/*.ncf ipcore_dir/*.sym ipcore_dir/*.xdc
	rm -f ipcore_dir/*.cgp ipcore_dir/*.txt ipcore_dir/*.log
	rm -f c65-rom-911001.txt c65-911001-rom-annotations.txt c65-dos-context.bin c65-911001-dos-context.bin
	rm -f thumbnail.prg kickstart65gs.bin diskmenuc000.list diskmenu_c000.bin diskchooser diskchooser.list 
	rm -f textmodetest.prg textmodetest.list etherload_done.bin etherload_stub.bin etherload.prg diskmenu.prg diskmenuprg.list ethertest.prg
	rm -f kickstart.vhdl videoproxy etherload etherkick
	rm -f iomap.txt
	rm -f version.vhdl version.a65
	rm -f monitor_drive monitor_load read_mem ghdl-frame-gen chargen_debug dis4510 em4510 4510tables pngprepare BOOTLOGO.G65

cleangen:
	rm kickstart.vhdl charrom.vhdl kickstart65gs.bin
