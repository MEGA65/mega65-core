ROUTEEFFORT=	std
#ROUTEEFFORT=	med
#ROUTEEFFORT=	high

KICKSTARTSRCS=kickstart.a65 \
		kickstart_machine.a65 \
		kickstart_process_descriptor.a65 \
		kickstart_dos.a65 \
		kickstart_task.a65 \
		kickstart_mem.a65

UNAME := $(@shell uname)
ifeq ($(UNAME),MINGW32_NT-6.1)
SOCKLIBS = -l ws2_32
else
SOCKLIBS =
endif

all:	ghdl-frame-gen \
	makerom \
	container.prj \
	thumbnail.prg \
	tests/textmodetest.prg \
	gs4510.vhdl viciv.vhdl \
	kickstart65gs.bin \
	etherload etherkick

ethertest.prg:	ethertest.a65 Makefile
	../Ophis/bin/ophis -4 ethertest.a65

f011test.prg:	f011test.a65 Makefile
	../Ophis/bin/ophis -4 f011test.a65

diskchooser:	diskchooser.a65 etherload.prg Makefile
	../Ophis/bin/ophis -4 diskchooser.a65 -l diskchooser.list

kickstart65gs.bin:	$(KICKSTARTSRCS) Makefile diskchooser
	../Ophis/bin/ophis -4 kickstart.a65 -l kickstart.list

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
	gcc -Wall -g -o etherkick etherkick.c

iomap.txt:	*.vhdl Makefile
	egrep "IO:C6|IO:GS" *.vhdl | cut -f3- -d: | sort -k2 > iomap.txt

transfer:	kickstart.vhdl version.vhdl kickstart65gs.bin makerom makeslowram iomap.txt ipcore_dir
	scp -pr ipcore_dir version.sh Makefile makerom c65gs.rom makerom makeslowram *.a65 *.ucf *.xise *.prj *vhd *vhdl kickstart65gs.bin 192.168.56.101:c64accel/
	scp -p .git/index 192.168.56.101:c64accel/.git/

version.vhdl: version-template.vhdl version.sh .git/index *.vhdl *.vhd 
	./version.sh

SIMULATIONFILES=	viciv.vhdl cputypes.vhdl sid_voice.vhd sid_coeffs.vhd sid_filters.vhd sid_components.vhd version.vhdl kickstart.vhdl iomapper.vhdl container.vhd cpu_test.vhdl gs4510.vhdl UART_TX_CTRL.vhd uart_rx.vhdl uart_monitor.vhdl machine.vhdl cia6526.vhdl keymapper.vhdl ghdl_ram8x32k.vhdl charrom.vhdl ghdl_chipram8bit.vhdl ghdl_screen_ram_buffer.vhdl ghdl_ram9x4k.vhdl ghdl_ram18x2k.vhdl sdcardio.vhdl ghdl_ram8x512.vhdl ethernet.vhdl ramlatch64.vhdl shadowram.vhdl microcode.vhdl cputypes.vhdl version.vhdl sid_6581.vhd ghdl_ram128x1k.vhdl ghdl_ram8x4096.vhdl crc.vhdl slowram.vhdl framepacker.vhdl ghdl_videobuffer.vhdl vicii_sprites.vhdl sprite.vhdl ghdl_alpha_blend.vhdl ghdl_farstack.vhdl debugtools.vhdl
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
