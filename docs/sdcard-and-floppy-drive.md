# SD-card bulk storage on the MEGA65 (including floppy drive and disk image access)

## Introduction

The MEGA65 uses a built-in SD card interface as its primary mass storage device.
This SD card is formatted using a mostly VFAT32 compatible file system, so that it
is easy to transfer files to and from the MEGA65 in any modern computer.

The MEGA65 also includes a PC-standard 34-pin floppy drive interface, that can be used to
connect DD (720K), HD (1.44MB) and ED (2.88MB) 3.5" floppy drives.  With a little
work, it would also likely be possible to connect 5.25" drives, although this, or the use
of HD or ED disks, would require modification of the DOS that is part of the legacy C65
ROMs.  This is because the MEGA65 provides a compatibility layer for the C65's F018
floppy disk controller that can, at run time, select between using the real floppy drive
or D81 disk images stored on the SD card.

This document gives a general introduction to how these facilities work on the MEGA65,
and their status at the time of writing.

## Partition Types

### Data storage

The MEGA65 supports FAT32 partitions using a Master Boot Record (MBR) aka "DOS FDISK"
disk layout.  No other partition table type is supported.  The only partition types
that are recognised are $0B and $0C, and addressing must use Logical Block Addressing (LBA),
not Cylinder Heads Sectors (CHS) addressing or extreme data corruption and general failure
to work WILL result.  Partitions may consist of upto 2^32 512 byte sectors, i.e., a maximum
size of 2 TB.  This really should be plenty for an 8-bit computer, and currently exceeds the
maximum capacity of an SD HC card.  SD XC cards would be required to reach this limit, but
are not yet supported at the hardware layer, although we would like to add such support once
we have the appropriate technical information.
While there is initial
support for up to four partitions to be mounted at the same time, potentially from multiple SD cards, this is not yet
supported in practice.

These partitions must be formatted using FAT32.  FAT16 and FAT12 are
not supported, nor is the patented so-called "exFAT" file system.  Also, ideally, the cluster
size should be 4KB (8 sectors per cluster), and cannot be more than 64KB (128 sectors per
cluster).  Given that FAT32 really only supports 2^28 clusters, this limits the file system
size to 1 TB when using 4KB clusters.  Again, this is probably not a problem for the time being.

### System data

In addition to data storage partitions, the MEGA65 also has the concept of a system partition.
The partition type for this partition is, naturally, 65 (= $41).  This partition contains
an area to store configuration data, e.g., whether the video signal should default to 50Hz
or 60Hz.  By storing this data in a special partition, it is not necessary to first mount
the FAT file system, which considerably speeds up access.

This partition also holds two other
important and related storage areas: frozen programs and installed service programs.
Frozen programs is exactly what it sounds like: When the MEGA65's built in freeze facility
is used, it saves the entire state of the MEGA65 into a "freeze slot" in the system partition.
The system partition is used for this instead of the FAT file system for several reasons.
Perhaps the most important is that the system partition ensures that every freeze slot is
not fragmented in its storage.  This makes the freeze routine quite a lot simpler and faster.
The installed service programs are a special kind of frozen program that has asked the MEGA65's
operating system to freeze it, and keep it handy for performing some special task. For example,
one service program might be a program that downloads a file from the internet. The MEGA65
operating then provides a special and easy to use mechanism to ask for one of these programs
to be used to fulfill a request from another program.  This makes it easy to include the
functionality of other programs on the MEGA65 using just a few lines of assembly language,
and helping to keep the individual programs small and simple.

## FAT32

The MEGA65 is known to be a bit picky about its FAT32 file system requirements.
It is a bit hit-and-miss to create a file system that the MEGA65 will accept from Windows
or Macintosh computers, although it can be done.  The best approach is to use the
utility menu on the MEGA65 (hold down the ALT or CONTROL keys when powering the MEGA65 on),
and selecting the "FDISK AND FORMAT" utility. This will let you prepare an SD card for use
by typing DELETE EVERYTHING, which will do exactly what it says.  It can take a number of
minutes to fully format an SD card using this utility.  After formatting, you will need to
somehow copy at least one ROM file onto the SD card, before the MEGA65 will be able to boot
to BASIC, unless your MEGA65 bitstream contains such a ROM built in (which is not yet the
case, while we work out various licensing matters).

The MEGA65 supports long file names, in theory at least.  There are some bugs in the implementation,
as well as some fundamental limitations in its implementation. The most important limitation is that
file names are limited to 64 characters.  Any long file name longer than this will definitely be
truncated.  There is also a problem where the long names of files is being ignored or truncated at
14 characters, which is on our list to fix.

At present, there is no way to change the current directory on a mounted FAT file system.
This will change as soon as we have time to implement it.
The built-in FAT32 system support is also currently unable to create or even modify existing files.
It is likely that we will add the ability to modify existing files into the core operating system,
while the creation of files may require use of a service program.  Stay tuned for news on this front.


Some documentation about the FAT file system can be found din the following links. These are relevant
in that they are the documents we have followed in creating our implemenation.
https://www.pjrc.com/tech/8051/ide/fat32.html
https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system
https://www.win.tue.nl/~aeb/linux/fs/fat/fat-1.html (LFN)

## Accessing files

There are two principal ways to access files on an SD card on a MEGA65.

### 1581 Disk Images (D81 files)

The first is to place the files
in a 1581 disk image (D81 file), and then mount that disk image using the F018 floppy controller
compatibility sub-system.  This can be accomplished from the (yet to be written) MEGA65 freeze menu,
or using the ```DISKMENU``` utility program.  Until the freeze menu is implemented, there is a catch-22
here if you don't have the ```DISKMENU``` utility program on the D81 file that is currently loaded,
as you won't be able to load it until you have already changed disks.  For this and many other reasons,
implementing the freeze menu is a priority for us.

NOTE: At present, 1541 disk image files are not supported, as the C65 (and thus the MEGA65) does not have
a built-in 1541.  That said, it is on our list to implement a complete 1541 in the FPGA precisely so
that D64 files can be used (and potentially real disks with the floppy disk interface).

NOTE: The disk image files must be contiguous on the SD card, i.e., they cannot be fragmented.  If you can't
mount a disk image, try putting the SD card in another computer and (after making a backup in case there are
compatibility problems between the MEGA65 and your computer's FAT32 file system implementations), run a
"de-frag" program.  A cheat's approach here is to simply copy the D81 file to another name, delete the original,
and rename the copy to the original.  On most modern computers the operating system will try to allocate a
contiguous region of disk as part of this process, unless the file system is relatively full.

## Native FAT32 file system access

It is also possible to write programs that use the MEGA65's native FAT32 file system application programming
interface (API).  This is the interface that the ```DISKMENU``` utility uses to get the list of available
1581 disk image files.  This API is not currently well documented, but is generally similar to that of very
early versions of DOS.  There are a total of four file descriptors available for simultaneous use by a program.
(Having a 1581 disk image mounted does not consume a file descriptor).

## Low-level SD card access

It is also possible to access the SD card interface on a low-level basis.  But note that we will soon
be implementing IO protection on the MEGA65. This will mean that if your program has not asked the Hypervisor
for permission to directly modify the SD card, the SD card registers will not be accessible.

The short version of how to access the SD card directly is as follows:

0. Make sure you have enabled MEGA65 IO register visibility by writing $47 and then $53 to $D02F
1. Before first access, or if the SD card has been changed or reported an error condition, write $00 followed by $01 to $D680.  Then wait until when reading $D680 the bottom two bits are clear.
2. To read or write a sector, you need to first put the sector number (if SDHC card) or sector number x 512 (if SDSC card) to $D681, $D682, $D683 and $D684,
with the lowest order byte going into $D681.  You can tell if an SDHC card is in use by checking bit 4 of the value of $D680. If it is a 1,
then it is an SDHC card.
3. To read a sector, write $02 to $D680, and then read $D680 until the bottom two bits are clear.  If they haven't cleared after a couple of seconds, you can be sure that some error has occurred.
4. To write a sector, write $03 to $D680, and otherwise follow the same process as for reading a sector.

Read and write operations use a 512 sector buffer at $FFD6E00 - $FFD6FFF.  Because this is not located in the normal IO area, you have to
either use 32-bit ZP indirect operationsi or the DMA controller to access it. However, for convenience, you can also make the sector buffer temporarily appear at $D800-$DFFF, over the top of the CIAs and colour RAM.  This is achieved by writing $81 to $D680, and is cancelled by writing $82 to $D680.  You can tell if it is mapped by checking bit 3 of $D680. If it is set, then the sector buffer is visible at $D800-$DFFF.

## SD card access on power-up

Upon startup, basically the MEGA65 core operating system performs the following:

1. resets the SDCARD
1. reads the Master Boot Record (very first sector of the card)
1. inspects the partition table in the MBR
1. for each partition (and there are four primary partition slots in an MBR)
  1. If it is a MEGA65 system partition, activates it, and loads the configuration data, if valid.
  1. inspects the file-system and check for a FAT32 partition type
  1. if it is FAT32, it looks further into the Volume ID and performs some checks
  1. if it is FAT32, accepts this partition and records information about it.
1. displays on-screen some information about the SDCARD,
1. loads some files from SDCARD into memory, if present:
  1. HICKUP.M65 - upgrades the core operating system ROM of the MEGA65
  1. CHARROM.M65 - replaces the built in default character set with the provided one
  1. MEGA65.ROM - provides a 128KB C65-style ROM file to be loaded
1. optionally mounts a disk-image is it if found
  1. MEGA65.D81 - if present, is automatically mounted.  This can be overriden by running the MEGA65 configuration utility which is
available when you hold down the ALT or CONTROL keys when powering the MEGA65 on.
1. then JUMPs to the reset-vector within the Kernal.


