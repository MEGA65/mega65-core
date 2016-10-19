#!/bin/bash

# status of 'B'ranch in 'S'hort format
branch=`git status -b -s | head -n 1`
# get from charpos3, for 6 chars
branch2=${branch:3:6}
version=`git describe --always --abbrev=7 --dirty=+DIRTY`

datetime=`date +%m%d-%H%M`
stringout="${branch2},${version},${datetime}"
echo $stringout
cat > vhdl/version.vhdl <<ENDTEMPLATE
library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package version is

  constant gitcommit : string := "${stringout}";

end version;
ENDTEMPLATE
echo "wrote: vhdl/version.vhdl"

# note that the following string should be no more than 40 chars [TBC]
echo 'msg_gitcommit: .byte "GIT: '${stringout}'",0' > version.a65
echo "wrote: version.a65"
