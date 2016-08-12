all:
	( cd src ; make )
	( cd vhdl ; make simulate )

clean:
	( cd src ; make clean )
	( cd vhdl ; make clean )
