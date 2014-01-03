all:	vga.bit

transfer:
	scp Makefile *.ucf *.vhd* 192.168.56.102:vga/
#	ssh 192.168.56.102 "( . .bash_profile ; cd vga ; make )"

vga.ngd:	vga.vhd vga.xst fastram.vhd charrom.vhdl
	xst -intstyle ise -ifn vga.xst -ofn vga.syr

vga_map.ngd:	vga.ngd vga.syr
	map -intstyle ise -p xc7a100t-csg324-1 -w -logic_opt off -ol std -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o vga_map.ncd vga.ngd vga.pcf
	par -w -intstyle ise -ol std -mt off vga_map.ncd vga.ncd vga.pcf

vga.bit:	vga_map.ngd vga.ut vga.ncd
	bitgen -intstyle ise -f vga.ut vga.ncd


