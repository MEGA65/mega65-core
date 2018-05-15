set bitstream_file [lindex $argv 0]
set mcs_file [lindex $argv 1]
write_cfgmem  -format mcs -size 16 -disablebitswap -interface SPIx1 -loadbit [list up 0x00000000 $bitstream_file] -force -file $mcs_file
