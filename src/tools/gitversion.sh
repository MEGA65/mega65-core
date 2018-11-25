#!/bin/bash

# status of 'B'ranch in 'S'hort format
branch=`git status -b -s | head -n 1 | sed -e 's/(//g' -e 's/)//g' -e's/ /_/g'`
# get from charpos3, for 6 chars
branch2=${branch:3:6}
version=`git describe --always --abbrev=7 --dirty=+DIRTY | sed -e 's/(//g' -e 's/)//g' -e's/ /_/g'`

datetime=`date +%Y%m%d.%H`
stringout="${datetime}-${branch2}-${version}"
echo $stringout

