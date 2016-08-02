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
	tests/textmodetest.prg \
	etherload etherkick

ethertest.prg:	ethertest.a65 Makefile
	../Ophis/bin/ophis -4 ethertest.a65

f011test.prg:	f011test.a65 Makefile
	../Ophis/bin/ophis -4 f011test.a65

diskmenu.prg:	diskmenuprg.a65 diskmenu.a65 Makefile
	../Ophis/bin/ophis -4 diskmenuprg.a65 -l diskmenuprg.list

diskchooser:	diskchooser.a65 etherload.prg Makefile
	../Ophis/bin/ophis -4 diskchooser.a65 -l diskchooser.list

version.a65:	*.vhdl *.a65 *.vhd Makefile
	./version.sh

# diskmenu_c000.bin yet b0rken
kickstart65gs.bin:	$(KICKSTARTSRCS) Makefile diskchooser version.a65 diskmenu_c000.bin
	../Ophis/bin/ophis -4 kickstart.a65 -l kickstart.list

diskmenu_c000.bin:	diskmenuc000.a65 diskmenu.a65 etherload.prg diskmenu_sort.a65
	../Ophis/bin/ophis -4 diskmenuc000.a65 -l diskmenuc000.list

thumbnail.prg:	showthumbnail.a65 Makefile
	../Ophis/bin/ophis -4 showthumbnail.a65

etherload.prg:	etherload.a65 Makefile
	../Ophis/bin/ophis -4 etherload.a65

etherload_stub.prg:	etherload_stub.a65 Makefile
	../Ophis/bin/ophis -4 etherload_stub.a65

etherload_done.prg:	etherload_done.a65 Makefile
	../Ophis/bin/ophis -4 etherload_done.a65

tests/textmodetest.prg:	tests/textmodetest.a65 tests/dejavus.f65 Makefile
	../Ophis/bin/ophis -4 tests/textmodetest.a65 -l textmodetest.list


kickstart.vhdl:	rom_template.vhdl diskchooser kickstart65gs.bin makerom
	./makerom rom_template.vhdl kickstart65gs.bin kickstart

#slowram.vhdl:	c65gs.rom makeslowram slowram_template.vhdl
#	./makeslowram slowram_template.vhdl c65gs.rom slowram

videoproxy:	videoproxy.c
	gcc -Wall -g -o videoproxy videoproxy.c -lpcap

etherload:	etherload.c
	gcc -Wall -g -o etherload etherload.c $(SOCKLIBS)

etherkick:	etherkick.c
	gcc -Wall -g -o etherkick etherkick.c $(SOCKLIBS)

iomap.txt:	*.vhdl Makefile
	egrep "IO:C6|IO:GS" *.vhdl | cut -f3- -d: | sort -u -k2 > iomap.txt

transfer:	kickstart.vhdl version.vhdl kickstart65gs.bin makerom makeslowram iomap.txt ipcore_dir
	scp -pr ipcore_dir version.sh Makefile makerom c65gs.rom makerom makeslowram *.a65 *.ucf *.xise *.prj *vhd *vhdl kickstart65gs.bin 192.168.56.102:c64accel/
	scp -p .git/index 192.168.56.102:c64accel/.git/

version.vhdl: version-template.vhdl version.sh .git/index *.vhdl *.vhd 
	./version.sh

SIMULATIONFILES=	viciv.vhdl bitplanes.vhdl bitplane.vhdl cputypes.vhdl sid_voice.vhd sid_coeffs.vhd sid_filters.vhd sid_components.vhd version.vhdl kickstart.vhdl iomapper.vhdl container.vhd cpu_test.vhdl gs4510.vhdl UART_TX_CTRL.vhd uart_rx.vhdl uart_monitor.vhdl machine.vhdl cia6526.vhdl c65uart.vhdl keymapper.vhdl ghdl_ram8x32k.vhdl charrom.vhdl ghdl_chipram8bit.vhdl ghdl_screen_ram_buffer.vhdl ghdl_ram9x4k.vhdl ghdl_ram18x2k.vhdl sdcardio.vhdl ghdl_ram8x512.vhdl ethernet.vhdl ramlatch64.vhdl shadowram.vhdl cputypes.vhdl version.vhdl sid_6581.vhd ghdl_ram128x1k.vhdl ghdl_ram8x4096.vhdl crc.vhdl slowram.vhdl framepacker.vhdl ghdl_videobuffer.vhdl vicii_sprites.vhdl sprite.vhdl ghdl_alpha_blend.vhdl ghdl_farstack.vhdl debugtools.vhdl
simulate:	$(SIMULATIONFILES)
	ghdl -i $(SIMULATIONFILES) 
	ghdl -m cpu_test

testcia:	tb_cia.vhdl cia6526.vhdl debugtools.vhdl
	ghdl -c tb_cia.vhdl cia6526.vhdl debugtools.vhdl -r tb_cia

testadder:	tb_adder.vhdl debugtools.vhdl
	ghdl -c tb_adder.vhdl debugtools.vhdl -r tb_adder

monitor_drive:	monitor_drive.c Makefile
	gcc -g -Wall -o monitor_drive monitor_drive.c

monitor_load:	monitor_load.c Makefile
	gcc -g -Wall -o monitor_load monitor_load.c

read_mem:	read_mem.c Makefile
	gcc -g -Wall -o read_mem read_mem.c

ghdl-frame-gen:	ghdl-frame-gen.c
	gcc -Wall -o ghdl-frame-gen ghdl-frame-gen.c

chargen_debug:	chargen_debug.c
	gcc -Wall -o chargen_debug chargen_debug.c

dis4510:	dis4510.c
	gcc -g -Wall -o dis4510 dis4510.c

em4510:	em4510.c
	gcc -g -Wall -o em4510 em4510.c

4510tables:	4510tables.c
	gcc -g -Wall -o 4510tables 4510tables.c

c65-rom-disassembly.txt:	dis4510 c65-dos-context.bin c65-rom-annotations.txt
	./dis4510 c65-dos-context.bin 2000 c65-rom-annotations.txt > c65-rom-disassembly.txt

c65-rom-911001.txt:	dis4510 c65-911001-dos-context.bin c65-911001-rom-annotations.txt
	./dis4510 c65-911001-dos-context.bin 2000 c65-911001rom-annotations.txt > c65-rom-911001.txt


c65-dos-context.bin:	c65-rom-910111.bin Makefile
	dd if=c65-rom-910111.bin bs=8192 skip=9 count=3 > c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=16384 skip=0 count=1 >> c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=4096 skip=12 count=1 >> c65-dos-context.bin
	dd if=/dev/zero bs=4096 count=1 >> c65-dos-context.bin
	dd if=c65-rom-910111.bin bs=8192 skip=15 count=1 >> c65-dos-context.bin

c65-911001-dos-context.bin:	911001.bin Makefile
	dd if=911001.bin bs=8192 skip=9 count=3 > c65-911001-dos-context.bin
	dd if=911001.bin bs=16384 skip=0 count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=4096 skip=12 count=1 >> c65-911001-dos-context.bin
	dd if=/dev/zero bs=4096 count=1 >> c65-911001-dos-context.bin
	dd if=911001.bin bs=8192 skip=15 count=1 >> c65-911001-dos-context.bin

pngprepare:	pngprepare.c Makefile
	gcc -g -Wall -I/usr/local/include -L/usr/local/lib -o pngprepare pngprepare.c -lpng

charrom.vhdl:	pngprepare 8x8font.png
	./pngprepare charrom 8x8font.png charrom.vhdl

BOOTLOGO.G65:	pngprepare mega65_64x64.png
	./pngprepare logo mega65_64x64.png BOOTLOGO.G65

clean:
	rm -f *.gise *.bgn *.bld *.cmd_log *.drc *.lso *.ncd *.ngc *.ngd *.ngr *.pad *.par *.pcf *.ptwx *.stx *.syr *.twr *.twx *.unroutes *.ut *.xpi *.xst *.xwbt
	rm -f *.map *.mrp *.psr *.xrpt *.csv *.list *.log *.xml
	rm -f container_summary.* container_usage.* usage_statistics_webtalk.* par_usage_statistics.*
	rm -f ipcore_dir/*.asy ipcore_dir/*.gise ipcore_dir/*.ncf ipcore_dir/*.sym ipcore_dir/*.xdc
	rm -f ipcore_dir/*.cgp ipcore_dir/*.txt ipcore_dir/*.log

cleangen:
	rm kickstart.vhdl charrom.vhdl kickstart65gs.bin

test_diskmenu_sort.prg:	test_diskmenu_sort.a65 diskmenu_sort.a65 Makefile
	../Ophis/bin/ophis -4 test_diskmenu_sort.a65 -l test_diskmenu_sort.list
