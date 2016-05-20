#!/bin/bash

cd precomp
make fpga
cd ..

source /opt/Xilinx/14.7/ISE_DS/settings64.sh

outfile1="compile1-xst.log"
outfile2="compile2-ngd.log"
outfile3="compile3-map.log"
outfile4="compile4-par.log"
outfile5="compile5-trc.log"
outfile6="compile6-bit.log"

if test ! -e "./xst/"; then
  echo "Creating ./xst/"
  mkdir ./xst/
fi
if test ! -e "./xst/projnav.tmp/"; then
  echo "Creating ./xst/projnav.tmp/"
  mkdir ./xst/projnav.tmp
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: xst, see container.syr"
xst -intstyle ise -ifn "container.xst" -ofn "container.syr" > $outfile1
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "xst failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: ngdbuild, see container.bld"
ngdbuild -intstyle ise -dd _ngo -sd ipcore_dir -nt timestamp -uc container.ucf -p xc7a100t-csg324-1 container.ngc container.ngd > $outfile2
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "ngdbuild failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: map, see container_map.mrp"
map -intstyle ise -p xc7a100t-csg324-1 -w -logic_opt on -ol high -t 1 -xt 0 -register_duplication on -r 4 -mt off -ir off -ignore_keep_hierarchy -pr b -lc off -power off -o container_map.ncd container.ngd container.pcf > $outfile3
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "map failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: par, see container.par"
par -w -intstyle ise -ol std -mt off container_map.ncd container.ncd container.pcf > $outfile4
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "par failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: trce, see container.twr"
trce -intstyle ise -v 3 -s 1 -n 3 -fastpaths -xml container.twx container.ncd -o container.twr container.pcf -ucf container.ucf > $outfile5
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "trce failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: bitgen, see container.bgn"
bitgen -intstyle ise -f container.ut container.ncd > $outfile6
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "bitgen failed with return code $retcode" && exit 1
fi

datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Finished!"
echo "Refer to compile[1-6].*.log for the output of each Xilinx command."

# now timestamp the file
mv ./container.bit ./container$datetime.bit
echo "mv ./container.bit ./container$datetime.bit"
ls -al ./container$datetime.bit
