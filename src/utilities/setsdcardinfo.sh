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

# first check of device is mounted, if so, ERROR
if [ `mount | grep $1 | wc -l` -gt 0 ]; then
  echo "dev $1 is mounted -> umount it"
  exit 1
else
  echo "dev $1 is NOT mounted, good."
fi

echo -e "\n========================="
echo "zero first 10M of ${1}"
sudo dd if=/dev/zero of=$1 bs=10240 count=1024

echo -e "\n========================="
echo "Creating partition..."
# Print current partition information
# New, Primary, One, <default>, size
# Type, W95 FAT32,
sudo fdisk -c=dos --sector-size 512 $1 <<END-FDISK-TEMPLATE
p
n
p
1

+500M
t
b
w
END-FDISK-TEMPLATE

# display new partition layout
echo -e "\n========================="
echo "New layout"
sudo fdisk -l $1

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
sudo mkfs.vfat -v -c -F 32 -h 129 -n LOUD -R 568 -s 8 -S 512 /dev/sdc1

# display new format information
echo -e "\n========================="
echo "New format of partition '1'"
sudo fsck.vfat -v -n ${1}1

exit 0;
