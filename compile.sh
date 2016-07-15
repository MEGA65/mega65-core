#!/bin/bash

cd precomp
make fpga
cd ..

source /opt/Xilinx/14.7/ISE_DS/settings64.sh

# time for the output filenames
datetime2=`date +%m%d_%H%M_`

outfile1="compile-${datetime2}1-xst.log"
outfile2="compile-${datetime2}2-ngd.log"
outfile3="compile-${datetime2}3-map.log"
outfile4="compile-${datetime2}4-par.log"
outfile5="compile-${datetime2}5-trc.log"
outfile6="compile-${datetime2}6-bit.log"

ISE_COMMON_OPTS="-intstyle ise"
ISE_NGDBUILD_OPTS="-p xc7a100t-csg324-1 -dd _ngo -sd ipcore_dir -nt timestamp"
ISE_MAP_OPTS="-p xc7a100t-csg324-1 -w -logic_opt on -ol high -t 1 -xt 0 -register_duplication on -r 4 -mt off -ir off -ignore_keep_hierarchy -pr b -lc off -power off"
ISE_PAR_OPTS="-w -ol std -mt off"
ISE_TRCE_OPTS="-v 3 -s 1 -n 3 -fastpaths -xml"

#if test ! -e "./xst/"; then
#  echo "Creating ./xst/"
#  mkdir ./xst/
#fi
#if test ! -e "./xst/projnav.tmp/"; then
#  echo "Creating ./xst/projnav.tmp/"
#  mkdir ./xst/projnav.tmp
#fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: xst, see container.syr"
xst ${ISE_COMMON_OPTS} -ifn "./isework/container.xst" -ofn "./isework/container.syr"> $outfile1
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "xst failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: ngdbuild, see container.bld"
ngdbuild ${ISE_COMMON_OPTS} ${ISE_NGDBUILD_OPTS} -uc ./src/container.ucf ./isework/container.ngc ./isework/container.ngd > $outfile2
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "ngdbuild failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: map, see container_map.mrp"
map ${ISE_COMMON_OPTS} ${ISE_MAP_OPTS} -o ./isework/container_map.ncd ./isework/container.ngd ./isework/container.pcf > $outfile3
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "map failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: par, see container.par"
par ${ISE_COMMON_OPTS} ${ISE_PAR_OPTS} ./isework/container_map.ncd ./isework/container.ncd ./isework/container.pcf > $outfile4
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "par failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: trce, see container.twr"
trce ${ISE_COMMON_OPTS} ${ISE_TRCE_OPTS} ./isework/container.twx ./isework/container.ncd -o ./isework/container.twr ./isework/container.pcf -ucf ./src/container.ucf > $outfile5
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "trce failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: bitgen, see container.bgn"
bitgen ${ISE_COMMON_OPTS} -f ./isework/container.ut ./isework/container.ncd > $outfile6
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "bitgen failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Finished!"
echo "Refer to compile[1-6].*.log for the output of each Xilinx command."

# now timestamp the file and rename with git-status
gitstring=`git describe --always --abbrev=7 --dirty=~`
echo "cp ./iseword/container.bit ./bit$datetime2$gitstring.bit"
cp       ./iseword/container.bit ./bit$datetime2$gitstring.bit
ls -al                           ./bit$datetime2$gitstring.bit
