#!/bin/bash

# try git describe --always --abbrev=40 --dirty=+DIRTY
version=`git log | head | grep commit | head -1 | cut -f2 -d" "``[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
echo $version
cat > version.vhdl <<ENDTEMPLATE
library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package version is

  constant gitcommit : string := "${version}";

end version;
ENDTEMPLATE

# try git describe --always --abbrev=7 --dirty=*+DIRTY
version=`git log | head | grep commit | head -1 | cut -f2 -d" " | tr "abcdef" "ABCDEF" | cut -c1-15`\*`[[ $(git diff --shortstat 2> /dev/null | tail -n1) != "" ]] && echo "+DIRTY"`
echo $version
echo 'msg_gitcommit: .byte "GIT COMMIT: '${version}'",0' > version.a65
