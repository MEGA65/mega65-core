#!/bin/bash

# status of 'B'ranch in 'S'hort format
branch=`git status -b -s | head -n 1`
# get from charpos3, for 6 chars
branch2=${branch:3:6}
version=`git describe --always --abbrev=7 --dirty=+DIRTY`
#version=`git log | head | grep commit | head -1 | cut -f2 -d" "``[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
#echo $version
datetime=`date +%m%d_%H%M`
stringout="${branch2},${version},${datetime}"
echo $stringout
cat > ../vhdl/version.vhdl <<ENDTEMPLATE
library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package version is

  constant gitcommit : string := "${stringout}";

end version;
ENDTEMPLATE
echo "wrote: ../vhdl/version.vhdl"

# try git describe --always --abbrev=7 --dirty=*+DIRTY
#version=`git log | head | grep commit | head -1 | cut -f2 -d" " | tr "abcdef" "ABCDEF" | cut -c1-15`\*`[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
#echo $version
echo 'msg_gitcommit: .byte "GIT COMMIT: '${stringout}'",0' > version.a65
echo "wrote: version.a65"
