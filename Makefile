all:
	scp *vhd *vhdl 192.168.56.102:c64accel/
	ssh 192.168.56.102 "( cd c64accel ; /opt/Xilinx/14.7/ISE_DS/ISE/bin/lin/xst -intstyle ise -ifn \"/home/gardners/c64accel/container.xst\" -ofn \"/home/gardners/c64accel/container.syr\" )"
