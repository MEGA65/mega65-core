#!/bin/bash

# status of 'B'ranch in 'S'hort format
branch=`git status -b -s | head -n 1`
# get from charpos3, for 6 chars
branch2=${branch:3:6}
version=`git describe --always --abbrev=7 --dirty=+DIRTY`

datetime=`date +%Y%m%d.%H`
stringout="${branch2},${version},${datetime}"
echo $stringout
cat > src/vhdl/version.vhdl <<ENDTEMPLATE
library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package version is

  constant gitcommit : string := "${stringout}";

end version;
ENDTEMPLATE
echo "wrote: src/vhdl/version.vhdl"

# note that the following string should be no more than 40 chars [TBC]
echo 'msg_gitcommit: .byte "GIT: '${stringout}'",0' > src/version.a65
echo "wrote: version.a65"

echo -e 'msg_gitcommit:\n\tascii("GIT: '${stringout}'")\n\t.byte 0' > src/version.asm
echo "wrote: version.asm"

echo 'msg_gitcommit: .byte "GIT: '${stringout}'"' > src/monitor/version.a65
echo "wrote: monitor/version.a65"

cat assets/matrix_banner.txt | sed -e 's/GITCOMMITID/'"${stringout}"'/g' | src/tools/format_banner bin/matrix_banner.txt 50
echo "wrote: bin/matrix_banner.txt"
