#!/bin/bash

# first things first, make the ISE-project-script-file Read-Only for all groups.
# this is done to stop the ISE-GUI from overwriting the file, which may be
# causing the compile-script to fail due to invalid relative addresses.
# a possible fix is to move the mega65.gise (ISE project file) into ./isework
# BG: these commands are likely to be removed once I get around to implementing my 'cleaner' branch
ls -al    isework/container.xst
chmod a-w isework/container.xst
ls -al    isework/container.xst

# ensure these directory exists, if not, make them
LOGDIR="build-logs"
if test ! -e    "./${LOGDIR}"; then
  echo "Creating ./${LOGDIR}"
  mkdir          ./${LOGDIR}
fi
if test ! -e    "./sdcard-files"; then
  echo "Creating ./sdcard-files"
  mkdir          ./sdcard-files
fi
if test ! -e    "./sdcard-files/old-bitfiles"; then
  echo "Creating ./sdcard-files/old-bitfiles"
  mkdir          ./sdcard-files/old-bitfiles
fi

( cd src ; make generated_vhdl firmware ../iomap.txt tools utilities roms)
retcode=$?

if [ $retcode -ne 0 ] ; then
  echo "make failed with return code $retcode" && exit 1
else
  echo "make completed."
  echo " "
fi

# here we need to detect if you have 64 or 32 bit machine
# on a 64-bit installation, both 32 and 64 bit settings files exist.
# on a 32-bit installation, only the settings32 exists.
# -> so first check for the 64-bit settings file.
#       special case/path for Colossus Supercomputer
if [ -e /usr/local/Xilinx/14.7/ISE_DS/settings64.sh ]; then
  echo "Detected 64-bit Xilinx installation on Colossus"
  source /usr/local/Xilinx/14.7/ISE_DS/settings64.sh
#       standard install location for 32/64 bit Xilinx installation
elif [ -e /opt/Xilinx/14.7/ISE_DS/settings64.sh ]; then
  echo "Detected 64-bit Xilinx installation"
  source /opt/Xilinx/14.7/ISE_DS/settings64.sh
#       standard install location for 32/64 bit Xilinx installation
elif [ -e /opt/Xilinx/14.7/ISE_DS/settings32.sh ]; then
  echo "Detected 32-bit Xilinx installation"
  source /opt/Xilinx/14.7/ISE_DS/settings32.sh
else
  echo "Cannot detect a Xilinx installation"
  exit 0;
fi

# time for the output filenames
datetime2=`date +%m%d%H%M`
# gitstring for the output filenames, results in '10bef97' or similar
gitstring=`git describe --always --abbrev=7 --dirty=~`
# git status of 'B'ranch in 'S'hort format, for the output filename
branch=`git status -b -s | head -n 1`
# get from charpos3, for 6 chars
branch2=${branch:3:6}


outfile0="${LOGDIR}/compile-${datetime2}_0.log"
outfile1="${LOGDIR}/compile-${datetime2}_1-xst.log"
outfile2="${LOGDIR}/compile-${datetime2}_2-ngd.log"
outfile3="${LOGDIR}/compile-${datetime2}_3-map.log"
outfile4="${LOGDIR}/compile-${datetime2}_4-par.log"
outfile5="${LOGDIR}/compile-${datetime2}_5-trc.log"
outfile6="${LOGDIR}/compile-${datetime2}_6-bit.log"

ISE_COMMON_OPTS="-intstyle ise"
ISE_NGDBUILD_OPTS="-p xc7a100t-csg324-1 -dd _ngo -sd ipcore_dir -nt timestamp"
ISE_MAP_OPTS="-p xc7a100t-csg324-1 -w -logic_opt on -ol high -t 1 -xt 0 -register_duplication on -r 4 -mt off -ir off -ignore_keep_hierarchy -pr b -lc off -power off"
ISE_PAR_OPTS="-w -ol std -mt off"
ISE_TRCE_OPTS="-v 3 -s 1 -n 3 -fastpaths -xml"

# ensure these directory exists, if not, make them
if test ! -e    "./isework/xst/"; then
  echo "Creating ./isework/xst/"
  mkdir          ./isework/xst/
fi
if test ! -e    "./isework/xst/projnav.tmp/"; then
  echo "Creating ./isework/xst/projnav.tmp/"
  mkdir          ./isework/xst/projnav.tmp
fi

# begin the ISE build:
echo "Beginning the ISE build."
echo " "
echo "Check ./${LOGDIR}/compile-<datetime>-X.log for the log files, X={1,2,3,4,5,6}"
echo " "

# first, put the git-commit-ID in the first log file.
echo ${gitstring} > $outfile0
# put the git-branch-ID in the log file.
echo ${branch}  >> $outfile0
echo ${branch2} >> $outfile0

NONDDR="nonddr" # filename to indicate target is Nexys4 (non-ddr) board
# if the file exists, target the non-ddr board
if test -e ${NONDDR}; then
  echo "Compiling for the Nexys4 (non-DDR) board."
  UCF_TARGET_FPGA="./src/vhdl/container-nonddr.ucf"
  # format a tag to either be "_nonddr" or an empty-string, for the output filename BIT-file
  NONDDR_TAG="_${NONDDR}"
else
  echo "Compiling for the Nexys4DDR board (the default)."
  echo "To compile for the Nexys4 (non-DDR) board, the \"./${NONDDR}\" file must exist"
  UCF_TARGET_FPGA="./src/vhdl/container-ddr.ucf"
  NONDDR_TAG=""
fi
echo "Compiling for the Nexys4${NONDDR_TAG} board" >> $outfile0

echo " "
cat ./src/version.a65
pwd
echo " "

#
# ISE: synthesize
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: xst, see container.syr"
xst ${ISE_COMMON_OPTS} -ifn "./isework/container.xst" -ofn "./isework/container.syr" >> $outfile1
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "xst failed with return code $retcode" && exit 1
fi

#
# ISE: ngdbuild
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: ngdbuild, see container.bld"
ngdbuild ${ISE_COMMON_OPTS} ${ISE_NGDBUILD_OPTS} -uc ${UCF_TARGET_FPGA} ./isework/container.ngc ./isework/container.ngd > $outfile2
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "ngdbuild failed with return code $retcode" && exit 1
fi

#
# ISE: map
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: map, see container_map.mrp"
map ${ISE_COMMON_OPTS} ${ISE_MAP_OPTS} -o ./isework/container_map.ncd ./isework/container.ngd ./isework/container.pcf > $outfile3
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "map failed with return code $retcode" && exit 1
fi

#
# ISE: place and route
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: par, see container.par"
par ${ISE_COMMON_OPTS} ${ISE_PAR_OPTS} ./isework/container_map.ncd ./isework/container.ncd ./isework/container.pcf > $outfile4
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "par failed with return code $retcode" && exit 1
fi

#
# ISE: trace
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: trce, see container.twr"
trce ${ISE_COMMON_OPTS} ${ISE_TRCE_OPTS} ./isework/container.twx ./isework/container.ncd -o ./isework/container.twr ./isework/container.pcf -ucf ./src/containerNULL.ucf > $outfile5
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "trce failed with return code $retcode" && exit 1
fi

#
# ISE: bitgen
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Starting: bitgen, see container.bgn"
bitgen ${ISE_COMMON_OPTS} -g SPI_buswidth:4 -g ConfigRate:33 -f ./isework/container.ut ./isework/container.ncd > $outfile6
retcode=$?
if [ $retcode -ne 0 ] ; then
  echo "bitgen failed with return code $retcode" && exit 1
fi

#
# ISE -> all done
#
datetime=`date +%Y%m%d_%H:%M:%S`
echo "==> $datetime Finished!"
echo "Refer to compile[1-6].*.log for the output of each Xilinx command."

# find interesting build stats and append them to the 0.log file.
echo "From $outfile1: =================================================" >> $outfile0
 tail -n 9 $outfile1 >> $outfile0
echo "From $outfile2: =================================================" >> $outfile0
 grep "Total" $outfile2 >> $outfile0
echo "From $outfile3: =================================================" >> $outfile0
 tail -n 8 $outfile3 >> $outfile0
echo "From $outfile4: =================================================" >> $outfile0
 grep "Generating Pad Report" -A 100 $outfile4 >> $outfile0
echo "From $outfile5: =================================================" >> $outfile0
 tail -n 1 $outfile5 >> $outfile0
echo "From $outfile6: =================================================" >> $outfile0
 echo "Nil" >> $outfile0

echo " "
# now prepare the sdcard-output directory by moving any existing bit-file
for filename in ./sdcard-files/*.bit; do
  echo "mv ${filename} ./sdcard-files/old-bitfiles"
        mv ${filename} ./sdcard-files/old-bitfiles
done

# now copy the bit-file to the sdcard-output directory, and timestamp it with time and git-status
echo "cp ./isework/container.bit ./sdcard-files/bit${datetime2}_${branch2}_${gitstring}.bit"
cp       ./isework/container.bit ./sdcard-files/bit${datetime2}_${branch2}_${gitstring}.bit
echo "Generating .MCS SPI flash file from .BIT file..."
promgen -spi -p mcs -w -o ./sdcard-files/bit${datetime2}_${branch2}_${gitstring}.mcs -s 16384 -u 0 isework/container.bit

# # and the KICKUP file
# echo "cp ./src/KICKUP.M65 ./sdcard-files"
#       cp ./src/KICKUP.M65 ./sdcard-files

echo " "
ls -al ./sdcard-files
