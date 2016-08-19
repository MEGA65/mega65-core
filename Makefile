all:
	./compile.sh

clean:
	( cd src ; make clean )
	( cd vhdl ; make clean )
