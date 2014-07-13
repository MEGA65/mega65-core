ROUTEEFFORT=	std
#ROUTEEFFORT=	med
#ROUTEEFFORT=	high

all:	ghdl-frame-gen \
	makerom kernel.vhdl \
	container.prj \
	gs4510.vhdl viciv.vhdl
#	scp *.xise *.prj *vhd *vhdl 192.168.56.102:c64accel/
#	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/xst -intstyle ise -ifn \"/home/gardners/c64accel/container.xst\" -ofn \"/home/gardners/c64accel/container.syr\" )"
#	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/map -intstyle ise -p xc7a100t-csg324-1 -w -logic_opt off -ol "$(ROUTEEFFORT)" -xe n -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o container_map.ncd container.ngd container.pcf )"
#	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/par -w -intstyle ise -ol "$(ROUTEEFFORT)" -xe n -mt off container_map.ncd container.ngd container.pcf )"
	/opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/xst -intstyle ise -ifn \"/home/gardners/c64accel/container.xst\" -ofn \"/home/gardners/c64accel/container.syr\"
	/opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/map -intstyle ise -p xc7a100t-csg324-1 -w -logic_opt off -ol "$(ROUTEEFFORT)" -xe n -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o container_map.ncd container.ngd container.pcf
	/opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/par -w -intstyle ise -ol "$(ROUTEEFFORT)" -xe n -mt off container_map.ncd container.ngd container.pcf

diskchooser:	diskchooser.a65 Makefile
	../Ophis/bin/ophis -4 diskchooser.a65 -l diskchooser.list

kickstart65gs.bin:	kickstart.a65 Makefile diskchooser
	../Ophis/bin/ophis -4 kickstart.a65 -l kickstart.list

kickstart.vhdl:	rom_template.vhdl kickstart65gs.bin makerom
	./makerom rom_template.vhdl kickstart65gs.bin kickstart

transfer:	kickstart.vhdl version.vhdl
	scp -p Makefile makerom kernel65.a65 *.ucf *.xise *.prj *vhd *vhdl 192.168.56.101:c64accel/

version.vhdl: version-template.vhdl version.sh .git/index *.vhdl *.vhd 
	./version.sh

SIMULATIONFILES=	kickstart.vhdl iomapper.vhdl container.vhd cpu_test.vhdl viciv.vhdl gs4510.vhdl debugtools.vhdl UART_TX_CTRL.vhd uart_rx.vhdl uart_monitor.vhdl machine.vhdl cia6526.vhdl keymapper.vhdl ghdl_ram8x64k.vhdl charrom.vhdl ghdl_chipram8bit.vhdl ghdl_screen_ram_buffer.vhdl ghdl_ram9x4k.vhdl sdcardio.vhdl ghdl_ram8x512.vhdl ramlatch64.vhdl shadowram.vhdl microcode.vhdl cputypes.vhdl version.vhdl sid_6581.vhd sid_coeffs.vhd sid_components.vhd sid_filters.vhd sid_voice.vhd
simulate:	$(SIMULATIONFILES)
	ghdl -c $(SIMULATIONFILES) -r cpu_test

testcia:	tb_cia.vhdl cia6526.vhdl debugtools.vhdl
	ghdl -c tb_cia.vhdl cia6526.vhdl debugtools.vhdl -r tb_cia

testadder:	tb_adder.vhdl debugtools.vhdl
	ghdl -c tb_adder.vhdl debugtools.vhdl -r tb_adder

monitor_drive:	monitor_drive.c Makefile
	gcc -g -Wall -o monitor_drive monitor_drive.c

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
