#!/bin/bash

# check that we have an ARG as $1
if [ "$1" =  "" ]; then
  echo " "
  echo "Usage:"
  echo " $0 <device> [tag]"
  echo " where <device> is /dev/sdc for example."
  echo " where [tag] is optional, 'working' or 'bad' for example."
  echo " "
  echo "  Will write three files, timestamped, ..."
  echo "  *.fdisk = the fdisk output, and filesystem-check output"
  echo "  *.img   = the raw DATA at the start of the device."
  echo "  *.hd    = BIN to ASCII viewing of the IMG-file"
  echo " "
  echo "  The 'tag' can be used to help keep track of what SDCARD you are processing"
  echo " "
  exit 1
fi

# first check if device is mounted, if so, ERROR
if [ `mount | grep $1 | wc -l` -gt 0 ]; then
  echo "device $1 is mounted -> umount it"
  exit 1
else
  echo "device $1 is NOT mounted, good."
fi


# see if we have an ARG as $2
if [ ! "$2" =  "" ]; then
  echo "fdisk-filename will be appended with \"${2}\""
fi

#no error checking, ie for block-device, etc
# for timestamp
datetime=`date +%m%d.%H%M%S`

# write fdisk info and filesystem-check info
echo "getting fdisk info"
echo "================================ sudo fdisk -l ${1}" >  ./sdcardinfo-${datetime}.fdisk.${2}
                                       sudo fdisk -l ${1}  >> ./sdcardinfo-${datetime}.fdisk.${2}

echo "getting fsck info for ${1} then ${1}1 (ignore open error)"
# first try /dev/sdc
echo "================================ sudo fsck.vfat -v -n ${1}"
echo "================================ sudo fsck.vfat -v -n ${1}" >> ./sdcardinfo-${datetime}.fdisk.${2}
                                       sudo fsck.vfat -v -n ${1}  >> ./sdcardinfo-${datetime}.fdisk.${2}
# then  try /dev/sdc1
echo "================================ sudo fsck.vfat -v -n ${1}1"
echo "================================ sudo fsck.vfat -v -n ${1}1" >> ./sdcardinfo-${datetime}.fdisk.${2}
                                       sudo fsck.vfat -v -n ${1}1  >> ./sdcardinfo-${datetime}.fdisk.${2}

# write the first 100MB chunk of device to a file
echo "================================"
echo "getting dd info, first 100MB of device"
sudo dd if=$1 of=./sdcardinfo-${datetime}.img bs=10K count=10K

# write the IMG to a text file for viewing/diffing
echo "================================"
echo "converting dd to ASCII"
hexdump -v -C ./sdcardinfo-${datetime}.img > ./sdcardinfo-${datetime}.hdump

# display
echo "================================"
cat ./sdcardinfo-${datetime}.fdisk.${2}
echo " "
head -n 32 ./sdcardinfo-${datetime}.hdump
echo " "

# done
echo "================================"
echo "see ./sdcardinfo-${datetime}.*"
