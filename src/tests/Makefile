CC65=   /usr/local/bin/cc65
CL65=   /usr/local/bin/cl65
COPTS=  -t c64 -O -Or -Oi -Os --cpu 6502
LOPTS=  

%.s:	%.c $(HEADERS) $(DATAFILES)
	$(CC65) $(COPTS) -o $@ $<



all:	vicii.prg

vicii.prg:	Makefile vicii.s
	$(CL65) $(COPTS) $(LOPTS) -o vicii.prg vicii.s

eth_mdio.prg:	Makefile eth_mdio.s
	$(CL65) $(COPTS) $(LOPTS) -o eth_mdio.prg eth_mdio.s
