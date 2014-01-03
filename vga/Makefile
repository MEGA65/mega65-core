all:	vga.bit

vga.ngd:	vga.vhdl vga.xst fastram.vhdl charrom.vhdl
	xst -intstyle ise -ifn vga.xst -ofn vga.syr

vga_map.ngd:	vga.ngd vga.syr
	map -intstyle ise -p xc7a100t-csg324-1 -w -logic_opt off -ol std -t 1 -xt 0 -register_duplication off -r 4 -mt off -ir off -pr off -lc off -power off -o vga_map.ngd vga.ngd vga.pcf
	par -w -intstyle ise -ol std -mt off vga_map.ncd vga.ncd vga.pcf

vga.bit:	vga_map.ngd vga.ut vga.ncd
	bitgen -intstyle ise -f vga.ut vga.ncd


