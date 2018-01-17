#!/bin/bash

# check that we have an ARG as $1
if [ "$1" =  "" ]; then
  echo " "
  echo "Usage:"
  echo " $0 <filename>"
  echo " where <filename> is ./file for example."
  echo " "
  echo "  Will create an image-file that can be dd'ed onto an sdcard,"
  echo "   or pointed to by the mega65-xemu application."
  echo " "
  echo "  NOTE: that this file currently works on Linux, not OSX"
  echo " "
  exit 1
fi


echo "processing ${1}"

isize=510
echo "creating image-file of size ${isize}M"
dd if=/dev/zero of=${1} bs=${isize} count=1M

psize=500
echo " "
echo "Creating partition of size ${psize}M"
echo "Note: that ${isize} MUST be bigger than ${psize}"
# New partition information
#
# basically we want just one partition, first, primary. Settings are below.
# New, Primary, One, <default>, size
# Type, W95 FAT32,
sudo fdisk -c=dos --sector-size 512 $1 <<END-FDISK-TEMPLATE
p
n
p
1

+${psize}M
t
c
w
END-FDISK-TEMPLATE

# display new partition layout
echo -e "\n========================="
echo "New layout"
sudo fdisk -l ${1}
echo " "

echo "Splitting image-file into two parts; the MBR and the file-system"
dd if=${1} of=${1}mbr bs=1k count=1k
dd if=${1} of=${1}fs  bs=1k skip=1k

# format partition 1 as FAT32
echo -e "\n========================="
echo "Formatting ${1}fs with some *strange* values"
# verbose, check first
# F fat-size is 32-bits
# h 129 hidden partitions
# n volume name
# R reserved sectors 568
# s sectors-per-cluster 8
# S logical-sector-size 512
sudo mkfs.vfat -v -c -F 32 -h 129 -n LOUD -R 568 -s 8 -S 512 ${1}fs

hexdump -C ${1}fs

echo " "
echo "Note that at this stage, the file \"${1}fs\" can be mounted with:"
echo ">\$ sudo mount -o loop ${1}fs <mountpoint>"
echo "We will do this now and copy on some files to the filesystem"

if test ! -e /media/localfile; then
  echo "Creating <mountpoint> to be \"/media/localfile\""
  sudo mkdir /media/localfile
fi
sudo mount -o loop ${1}fs /media/localfile
sudo cp ../../sdcard-files/* /media/localfile
sudo ls -al /media/localfile
sudo umount /media/localfile

echo " "
echo "We now join the MBR and FS together to make the imagefile."
cat ${1}mbr ${1}fs > ${1}.img
echo "done" 

echo " "
echo "And lets display some useful info about the filesystem:"
fsck.vfat -v -n ${1}fs
hexdump -C ${1}fs | tail

