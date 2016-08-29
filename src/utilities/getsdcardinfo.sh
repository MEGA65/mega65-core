#!/bin/bash

# check that we have an ARG as $1
if [ "$1" =  "" ]; then
  echo " "
  echo "Usage:"
  echo " $0 <device>"
  echo " where <device> is /dev/sdc for example."
  echo " "
  echo "  Will write three files, timestamped, ..."
  echo "  *.fdisk = the fdisk output, and filesystem-check output"
  echo "  *.img   = the raw DATA at the start of the device."
  echo "  *.hd    = BIN to ASCII viewing of the IMG-file"
  echo " "
  exit 1
fi

#no error checking, ie for block-device, etc
# for timestamp
datetime=`date +%m%d.%H%M%S`

# write fdisk info and filesystem-check info
echo "getting fdisk info"
sudo fdisk -l $1      > ./sdcardinfo-${datetime}.fdisk

echo "================================ "             >> ./sdcardinfo-${datetime}.fdisk
echo "getting fsck info"
# first try /dev/sdc
sudo fsck.fat -v -n $1 >> ./sdcardinfo-${datetime}.fdisk
# then  try /dev/sdc1
sudo fsck.fat -v -n ${1}1 >> ./sdcardinfo-${datetime}.fdisk

# write to file the first 100MB chunk of device
echo "getting dd info, first 100MB of device"
sudo dd if=$1 of=./sdcardinfo-${datetime}.img bs=10K count=10K

# write the IMG to a text file for viewing/diffing
echo "converting dd to ASCII"
hexdump -v -C ./sdcardinfo-${datetime}.img > ./sdcardinfo-${datetime}.hdump

# display
cat ./sdcardinfo-${datetime}.fdisk
echo " "
head -n 20 ./sdcardinfo-${datetime}.hdump
echo " "

# done
echo "see ./sdcardinfo-${datetime}.*"
