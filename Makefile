all:	kernel65.bin
	scp *.prj *vhd *vhdl 192.168.56.102:c64accel/
	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/xst -intstyle ise -ifn \"/home/gardners/c64accel/container.xst\" -ofn \"/home/gardners/c64accel/container.syr\" )"

kernel65.bin:	kernel65.a65
	Ophis-2.0-standalone/ophis kernel65.a65

kernel65.vhdl:	rom_template.vhdl kernel65.bin
	./makerom rom_template.vhdl kernel65.bin kernel65
