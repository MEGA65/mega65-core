#!/bin/bash

shorten_name () {
  name=$1
  # issue branch?
  if [[ $name =~ ^([0-9]+)-(.+)$ ]]; then
    name="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  fi
  # developemnt + extra?
  if [[ $name =~ ^development-(.+)$ ]]; then
    name="dev-${BASH_REMATCH[1]}"
  fi
  # release + version?
  if [[ $name =~ ^release-([0-9])\.([0-9][0-9]?)$ ]]; then
    name="r-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}000"
  fi
  # cut after 6 chars
  echo ${name:0:6}
}

# ###############################
# get branch name
#
if [[ -n $JENKINS_SERVER_COOKIE ]]; then
  if [[ -e JENKINS_BUILD_ID && -e JENKINS_BUILD_VERSION ]]; then
    LAST_BUILD=$(cat JENKINS_BUILD_ID)
    if [[ $BRANCH_NAME_$BUILD_ID = $LAST_BUILD ]]; then
      echo "(JENKINS) reusing version for this target:"
      cat JENKINS_BUILD_VERSION
      exit
    fi
  fi
  branch=${BRANCH_NAME}
else
  branch=`git rev-parse --abbrev-ref HEAD`
fi
freeze_branch=$(shorten_name $branch)
#echo ${branch}
#
# if branchname is long, just use the first X-chars and last X-chars, ie "abcde...vwxyz"
branchlen=$(( ${#branch} ))
#echo ${branchlen}
#
if [ ${branchlen} -gt 13 ] ; then
  branch_abcde=${branch:0:5}
  branch_v_pos=$(( ${branchlen}-5 ))
  branch_vwxyz=${branch:${branch_v_pos}:5}
  echo "${branch_abcde} ${branch_v_pos} ${branch_vwxyz}"
  branch="${branch_abcde}...${branch_vwxyz}"
fi

# ###############################
# get git-commit and the dirty-flag
#
# exclude all tags from strings!
commit_id=`git describe --always --abbrev=7 --dirty=~ --exclude="*"`
commit_id_no_dirt=`git describe --always --abbrev=7 --exclude="*"`
version32=`git describe --always --abbrev=8 --exclude="*"`
datestamp=$(expr $(expr $(date +%Y) - 2020) \* 366 + `date +%j`)


# ###############################
# get timestamp
#
datetime=`date +%Y%m%d.%H`


# ###############################
# and put it all together
#
stringout="${branch},${datetime},${commit_id}"
freezerout="${datetime}-${freeze_branch}-${commit_id_no_dirt}"
fileout="${datetime}-${freeze_branch}-${commit_id}"

echo "Generated version strings"
echo "-------------------------"
echo "internal: ${stringout}"
echo "freezer:  ${freezerout}"
echo "file:     ${fileout}"
echo "-------------------------"

# ###############################
# generate the source file(s)
#
cat > src/vhdl/version.vhdl <<ENDTEMPLATE
library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package version is

  constant gitcommit : string := "${stringout}";
  constant fpga_commit : unsigned(31 downto 0) := x"${version32}";
  constant fpga_datestamp : unsigned(15 downto 0) := to_unsigned(${datestamp},16);

end version;
ENDTEMPLATE
echo "wrote: src/vhdl/version.vhdl"

cat > src/utilities/version.h <<ENDTEMPLATE
#ifndef _VERSION_H
#define _VERSION_H
static char *utilVersion="${freezerout}";
#endif
ENDTEMPLATE
echo "wrote: src/utilities/version.h"

# ###############################
# note that the following string should be no more than 40 chars [TBC]
#
echo "${fileout}" > src/version.txt
echo "wrote: src/version.txt"

echo 'msg_gitcommit: .byte "GIT:'${stringout}'",0' > src/version.a65
echo "wrote: src/version.a65"

echo -e 'msg_gitcommit:\n\t!text "GIT: '${stringout}'"\n\t!8 0' > src/version.asm
echo "wrote: src/version.asm"

echo 'msg_gitcommit: .byte "GIT: '${stringout}'"' > src/monitor/version.a65
echo "wrote: src/monitor/version.a65"

echo -e ".segment \"CODE\"\n_version:\n  .asciiz \"v:${freezerout}\"" > src/utilities/version.s
echo "wrote: src/utilities/version.s"

cat assets/matrix_banner.txt | sed -e 's/GITCOMMITID/'"${stringout}"'/g' | src/tools/format_banner bin/matrix_banner.txt 50
echo "wrote: bin/matrix_banner.txt"

if [[ -n $JENKINS_SERVER_COOKIE ]]; then
  echo $BRANCH_NAME_$BUILD_ID > JENKINS_BUILD_ID
  echo "-------------------------" > JENKINS_BUILD_VERSION
  echo "internal: ${stringout}" >> JENKINS_BUILD_VERSION
  echo "freezer:  ${freezerout}" >> JENKINS_BUILD_VERSION
  echo "file:     ${fileout}" >> JENKINS_BUILD_VERSION
  echo "-------------------------" >> JENKINS_BUILD_VERSION
fi
