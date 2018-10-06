#!/bin/bash

# status of 'B'ranch in 'S'hort format
branch=`git status -b -s | head -n 1`
# get from charpos3, for 6 chars
branch2=${branch:3:6}
version=`git describe --always --abbrev=7 --dirty=+DIRTY`

datetime=`date +%Y%m%d.%H`
stringout="${datetime}-${branch2}-${version}"
echo $stringout

