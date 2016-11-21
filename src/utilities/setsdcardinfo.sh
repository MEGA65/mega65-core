#!/bin/bash

# check that we have an ARG as $1
if [ "$1" =  "" ]; then
  echo " "
  echo "Usage:"
  echo " $0 <device>"
  echo " where <device> is /dev/sdc for example."
  echo " "
  echo "  Will (attempt to) format the device, suitable for MEGA65 use"
  echo " "
  exit 1
fi

# minimal error checking, ie for block-device, etc

# output some useful info
echo "using ARG[1]=\"${1}\" and ARG[2]=\"${2}\"."

# first do a simple check to see if device-base is in mount file, if so, ERROR
if [ `mount | grep $1 | wc -l` -gt 0 ]; then
  echo "dev $1 seems mounted -> umount it"
  exit 1
else
  echo "dev $1 is NOT mounted, good."
fi

# print a warning here, ie: about to format a device, maybe user can type "y" to proceed


echo -e "\n========================="
echo "zero first 10M of ${1}"
sudo dd if=/dev/zero of=$1 bs=10240 count=1024

echo -e "\n========================="
echo "Creating partition..."
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

+500M
t
c
w
END-FDISK-TEMPLATE

# display new partition layout
echo -e "\n========================="
echo "New layout"
sudo fdisk -l ${1}
echo " "

# try extract the name of the new partition it just created
DAT1=`sudo fdisk -l ${1} | tail -n 1`
echo "==DAT1=\"${DAT1}\""
DAT2=( ${DAT1[0]} )
echo "==DAT2=\"${DAT2}\""

# format partition 1 as FAT32
echo -e "\n========================="
echo "Formatting"
# verbose, check first
# F fat-size is 32-bits
# h 129 hidden partitions
# n volume name
# R reserved sectors 568
# s sectors-per-cluster 8
# S logical-sector-size 512
sudo mkfs.vfat -v -c -F 32 -h 129 -n LOUD -R 568 -s 8 -S 512 ${DAT2}

# display new format information
echo -e "\n========================="
echo "New format of partition '1'"
sudo fsck.vfat -v -n ${DAT2}

exit 0;
