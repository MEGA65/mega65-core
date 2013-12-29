ROUTEEFFORT=	std
#ROUTEEFFORT=	med
#ROUTEEFFORT=	high

all:	makerom kernel65.vhdl \
	container.prj \
	cpu6502.vhdl alu6502.vhdl bcdadder.vhdl spartan6blockram.vhdl
	scp *.xise *.prj *vhd *vhdl 192.168.56.102:c64accel/
	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/xst -intstyle ise -ifn \"/home/gardners/c64accel/container.xst\" -ofn \"/home/gardners/c64accel/container.syr\" )"
	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/map -intstyle ise -p xc7a100t-csg324-1 -w -logic_opt off -ol "$ROUTEEFFORT" -xe n -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o container_map.ncd container.ngd container.pcf )"
	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/par -w -intstyle ise -ol "$ROUTEEFFORT" -xe n -mt off container_map.ncd container.ngd container.pcf )"

kernel65.bin:	kernel65.a65
	Ophis-2.0-standalone/ophis kernel65.a65

kernel65.vhdl:	rom_template.vhdl kernel65.bin makerom
	./makerom rom_template.vhdl kernel65.bin kernel65

simulate:	bcdadder.vhdl alu6502.vhdl cpu6502.vhdl kernel65.vhdl iomapper.vhdl container.vhd cpu_test.vhdl
	ghdl -c bcdadder.vhdl alu6502.vhdl cpu6502.vhdl kernel65.vhdl iomapper.vhdl container.vhd cpu_test.vhdl -r cpu_test
