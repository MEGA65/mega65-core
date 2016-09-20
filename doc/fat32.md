## This is the 'fat32 / sdcard' documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Hardware Overview](#hardware-overview)  
[Memory Layout](#memory-layout)  

## Introduction

The system uses an SD-card for accessing files during boot-up and during operation.

URLs used for reference include:
https://www.pjrc.com/tech/8051/ide/fat32.html
https://en.wikipedia.org/wiki/Design_of_the_FAT_file_system
https://www.win.tue.nl/~aeb/linux/fs/fat/fat-1.html (LFN)

We require the ability to interface with the FAT32 file system (located on the sdcard), using both low-level and high-level sub-routines.

This document describes:  
* the common understanding of FAT32, and
* details of HOW-WE-IMPLEMENT both the low-level and high-level sub-routines.

## Hardware overview

A block diagram showing the hardware and firmware that is used to implement the FAT32 file access is shown below.

[![sdcard](./images/sdcard-small.jpg)](./images/sdcard.jpg)  
Click the image above for a hi-res JPG, else the [PDF link](./images/monitor.pdf).

## Memory Layout

There are a number of memory-mapped registers:
$D680 - SD-controller status/command
            fastio_rdata(7) <= half_speed;
            fastio_rdata(6) <= sdio_error;
            fastio_rdata(5) <= sdio_fsm_error;
            fastio_rdata(4) <= sdhc_mode;
            fastio_rdata(3) <= sector_buffer_mapped;
            fastio_rdata(2) <= sd_reset;
            fastio_rdata(1) <= sdio_busy;
            fastio_rdata(0) <= sdio_busy;

The $D680 register is not fully understood, but is believed to be as follows:
When reading from $D680, the above status-information is recieved from the sd-controller.

When writing to $D680, the below control-information is given to the sd-controller.
$00 - reset the sdcard
$01 - cancel reset
$10 - reset the sdcard (with flags)
$11 - cancel reset (with flags)
$02 - read the sector pointed to at sd_address[3..0] into the sector_buffer
$03 - write the sector_buffer to the sector pointed to at sd_address[3..0]
$40 - clr sdhc mode
$41 - set sdhc mode
$42 - clr half speed mode
$43 - set half speed mode
$81 - set sector_buffer mapped
$82 - clr sector_buffer mapped
The above info sourced from sdcardio.vhdl

$D681 - sd_address  LOW-Byte
$D682 - sd_address  mid-Byte
$D683 - sd_address  mid-Byte
$D684 - sd_address HIGH-Byte
These registers are to control the sd-controller. You write data to these registers. Reading makes no sense(?).
An address of $1BC00800 would be stored in these registers as:
$D681 - $00
$D682 - $08
$D683 - $C0
$D684 - $1B

$D685-$D68F - are not currently understood, but seem to be related to the sdcard.

As specified in "kickstart.a65", memory location $BB00-$BBFF contains data describing the file systems collected.
	#dos_disk_table#
This table is #$FF bytes in size, divided into 8x sections.
Each section is therefore #$20 bytes in size.
Refer to ##dos_disk_table## below for details.

The next page in memory is $BC00-$BCFF, which contains data used for processing the file system. Entries include:
dos_disk_count
dos_disk_cwd_cluster
dos_dirent_longfilename
dos_dirent_shortfilename
dos_requested_filename
dos_file_descriptors
dos_current_file_descriptor
dos_error_code

<i>The next 2x pages in memory is $BDxx-$BExx, which are not relevant to the FAT32 file system.</i>

The last page in KICKSTART-memory is $BFxx-$BFxx, which is the Zero-Page (ZP) for the Hypervisor. Entries include:
dos_scratch_vector
dos_scratch_byte_1
zptempv2
checkpoint_y
sdcounter
This area can be used for temporary variables or ZP-adressing.

The 512-byte buffer is mapped to $DE00 and aliased as "sd_sectorbuffer". This buffer therefore runs through to $DE00+$200=$DFFF

## SDCARD FAT32 Overview

There is assembly code in kickstart.a65 that is executed during boot, and this code is also accessible when the machine starts up.
The kickstart assembly code is processes by the processor just like any other normal program running on the machine.
The kickstart assembly code interfaces to the SDCARD controller using just 5x memory-mapped registers and a 512-byte shared buffer.
The 5x registers used to interface the SDCARD controller are $D680-$D684.
D680 seems not aliased, but is found in the iomap.txt, and is a control/status register between assembly code and the VHDL SDCARD firmware.
D681-3 are aliased as "sd_address_byte{0-3}", and are mapped in directly to the SDCARD CONTROLLER.

To perform a read from the SDCARD, you setup the 4x "sd_address_bytes" to the sector you want, and toggle a bit on the $D680 register. When the SDCARD CONTROLLER is done, a bit in $D680 becomes clearer (or set, i forget).
Then, you need to switch the 512-buffer, performed by calling the "sd_map_sectorbuffer" subroutine.

Upon startup, basically the KICKUP code performs the following:
1. resets the SDCARD
1. reads the Master Boot Record (very first chunk of the card)
1. inspects the partition table in the MBR
1. for each partition (and there are four primary partitions)
  1. inspects the file-system and check for a FAT32 partition type
  1. if it is FAT32, it looks further into the Volume ID and performs some checks
  1. if it is FAT32, accepts this partition and records information about it.
1. for a detailled walkthrough of the above 5-steps, see ##below##
1. displays on-screen some information about the SDCARD,
1. loads some files from SDCARD into memory, including CHARROM and KERNALROM, refer to ##LOAD##
1. optionally mounts a disk-image is it if found, refer to ##MOUNT##
1. then JUMPs to the reset-vector within the Kernal.

## SDCARD FAT32 Details

The following initialisation sequence is followed:
1. reset the sdcard, refer to ##sdreset
1. try and read the Master Boot Record (MBR), refer to ##readmbr
1. scan the MBR and look for partitions, refer to ##scanparts
1. record details of any FAT32 partitions found
1. leave behind some information in a data-structure to inform other sub-routines what (if any) file-system is accessable, refer to ##dos_disk_table

To load a file from the SDCARD, you need to:
1. setup a pointer and then call the "dos_setname" function,
1. setup the "dos_file_loadaddress" pointer to define where the file is loaded to,
1. call "dos_readfileintomemory" and check the status bit when it returns.

When the "dos_readfileintomemory" function is called, the following things happen:
1. search the partition for a matching filename
  1. when file is found, leave a pointer pointing to its location
1. close the file
1. open the file
1. map in the sectorbuffer
1. LOOP#1: read a sector
1. LOOP#2: copy the sector (200 bytes) into the load-address, loop to LOOP#2 until done
1. advance to the next sector, and check if more data to load from file, if so, goto LOOP#1.
1. close the file

-------------------------------------------
##sdreset

The SD-card reset function (sdreset:) is situated in the kickstart code.
Basically, it tries to see if the sdcard is high-capacity (SDHC) or not (SD).
Currently SDHC is not working. Currently SD is working.
Basically, it clears the reset-bit in $D680 then delays for a number of clock-cycles (sdtimeoutreset:). It then checks to see if the sd-controller is ready (sdreadytest:) by checking if bit-0 and bit-1 are set in $d680. Then, it sets the reset-bit in $D680 then again delays, and waits for the sd-controller to become ready.
The routine then waits a while (re2done:), and maps in the sector buffer. It issues a 'read' by writing $02 into $D680 then waits for the sd-controller to complete the read.
Before returning, it sets the carry flag to indicate success.
Ben-401 suggests that the sdcard-resetting should be auto-performed by the sd-controller.
##readmbr

The "readmbr:" routine is only called during the kickstart process. It is likely that this routine will be called more-than-once to allow hot-swap of sdcards.
This routine first calls "sdreset:", followed by setting the sd_address to $00000000. It then jumps to the "sd_readsector:" routine below.
Also please refer to the "dos_read_mbr:" routine.

##sd_readsector
This routine is called many times throughout the disk-access.
It issues a command to the sd-controller, to read the sector on the sdcard pointed to by the sd_address[3..0].
When reading the MBR, the sd_address is $00000000.
Basically, the most direct path (without errors is):
1. check if the card is busy (read $D680.0)
1. ask for the sector to be read (write $02 -> $d680)
1. wait for sd-controller to become ready (not-busy)
1. at "rsread:" i think there is another check to see if the sd-controller is busy (redundant)
1. then a check if $200 (512) bytes were read. NOTE that the reference to "d689" is not understood.
1. Before returning, it sets the carry flag to indicate success.

During the above routine, many errors/abnomalities may occur and the execution path may branch to a delay because the sdcard was not ready, or if the incorrent number of chars read was returned.

At this point, the MBR (sector $00000000) would be in the sector_buffer.
Continuing on through the kickstart boot-process, execution would continue at "gotmbr:".

##gotmbr
Calls "dos_clearall:" which marks the four file-descriptors as empty. Refer to ##file-descriptors.
Then calls "dos_read_partitiontable:" which is described in detail below.
At this point, the four primary-partitions on the sdcard would have been examined, and their details stored in the "dos_disk_table:" (see below).
Then this routine attempts to change-directory-into the "dos_default_disk" by calling "dos_cdroot" function. This is described in detail below.

If the "dos_cdroot:" function returns true, then the MEGA65 has file-system properties and files etc can be loaded (and 'saved' in the future). In this case, the kickstart execution continues at "mountsystemdiskok:" where files are loaded from the FAT32 partition marked as the "dos_default_disk".

This concludes the *toplevel* description of the kickstart-code with respect to the fat32/sdcard implementation.
Details below are for the *lower-level* description of the kickstart-code with respect to the fat32/sdcard implementation.

===================================================================

##dos_read_partitiontable
Following "gotmbr:", the partition table is examined.
First, some data-structures are cleared by calling "dos_initialise_disklist:". This routine just sets the dos_disk_count to zero.
Then, the "dos_read_mbr:" routine is called, which is very similar to the "readmbr:" routine above. I suggest that some re-organisation could be done here. Basically this just sets sd_address to $00000000 and calls the "sd_readsector" routine then calls "sd_map_sectorbuffer:". Refer below for details on the "sd_map_sectorbuffer" routine.
Then, the MBR is again sitting in the sector_buffer.
It first checks for the signature $AA55 in location $1FE of the MBR.
It then looks at each of the four partition entries, located at $1BE, $1CE, $1DE and $1EE respectively. For each entry, it calls "dos_consider_partition_entry:" which is detailled below. Basically it just checks is it looks like a FAT32 partition and if so, records special information about that partition into the data-structure called "dos_disk_table". Refer below for details of the "dos_disk_table" and the "dos_disk_openpartition:" routine.

##dos_consider_partition_entry
This routine makes use of a preset vector (or pointer) located in "dos_scratch_vector", which points to the start of the partition entry to be considered. Offsets in the Y-register are then used to access information in the partition entry.
First, a check that the $04'th byte is either $0B or $0C denoting FAT32. If so, execution continues at "partitionisinteresting:". If not, the routine returns.

At "partitionisinteresting:", we begin to record details about the partition from the MBR's partition-entry into our dos_disk_table.
We index through the dos_disk_table using the X-register.
We populate the following fields (refer dos_disk_table for details):

at "dcpe1:"
dos_disk_tableoffset with source_data (description)
+00,01,02,03 with MBR:partition_address+$08 (partition_lba_begin)
+04,05,06,07 with MBR:partition_address+$0C (number_of_sectors)

We then call "dos_disk_openpartition:" which populates other fields in the dos_disk_table from data within the partition itself (ie not from the MBR). Refer ##dos_disk_openpartition below for this detail.

We then examine the MBR:partition_address+$00 (boot_flag) and see if the partition is bootable. NOTE that only one primary partition on a device can be bootable. If the partition is bootable, we record in "dos_default_disk:" the value of the entry we are populating within the dos_disk_table (ie $00..$07).
NOTE that this logic does not seem to be correct.



##dos_disk_openpartition
This routine relies on the "dos_disk_count" to be set to a valid value, namely the partition entry within the "dos_disk_table" that we are about to open.
Additionally, it is assumed that the "dos_disk_table" for this entry already has the data populated at offsets +$00 and +$04 within the dos_disk_table.

This routine looks into the "Volume ID" of the specified partition, which is pointed to by the address stored in "partition_lba_begin" within offset +00 of the dos_disk_table.

At "ddop1:", the "partition_lba_begin" is copied from the dos_disk_table into the sd_address[3..0] registers.
In our example, the value at "partition_lba_begin" is "$00000800" and has units of 'sector'.

NOTE that there is a difference between SD and SDHC cards, namely that the SD cards are accessed by byte-address, whereas the SDHC are accessed directly by their sector-address. In this regard, we need to convert the sector-address now in sd_address[3..0] to the byte-address. We do this using the "sd_fix_sectornumber:" routine which just multiplies the sector-address by $200. Further details of this are below in ##sdcardmode, but basically results in the byte-address of $00100000.

Then the sdcard is issues with the read-command, which reads the sector at the location within the sd_address[3..0], followed by mapping the sector_buffer.

Now, in a similar way to the MBR being examined, the Volume-ID will now be examined at about "ddop1a:".
First, a check is performed to see if the signature bytes $AA55 appear at the end of the sector.

Then, the byte at offset-11 is checked for ZERO.
BG does not agree with this.

Then, the number-of-FATs is stored into the dos_disk_table at offset +$17.
+17 with VID:+$10 (number_of_fats)

Then, the number of reserved-sectors (2 bytes) is stored into the dos_disk_table at offset +$0D.
+0D,0E with VID:+$0E (number of reserved (system) sectors)

Then, the number of sectors-per-fat (4 bytes) is stored into the dos_disk_table at offset +$09.
+09,0A,0B,0C with VID:+$24 (number of sectors per fat)

Then, a check is made to see if the number-of-reserved-clusters is less than 255. It does this by checking the next three bytes and ensuring those are zero. This is just before the "ddop11ok:" label.
Ben401 suggests that this check is actually checking the root-directory-first-cluster, which is not related to the number-of-reserved-clusters.

Then, the root-directory-first-cluster (4 bytes) is stored into the dos_disk_table at offset +$0F.
+0F with VID:+$2C (root-directory-first-cluster)
Ben401: why only one byte when the address is four bytes.

Then, at around "ddop2:", a calculation is made to find the cluster_0 of the root-directory.
The formula used is "fs_fat32_system_sectors + (2x number_of_fats) + fs_start_sector"
First, "fs_fat32_system_sectors[1.0]" is copied into dos_disk_table[18-19], then upper two bytes set to zero.
Second, added to dos_disk_table[18-1B] is the number of sectors per one fat.
Third, added to dos_disk_table[18-1B] is the number of sectors per one fat, yes this is done twice because there are two FATs.

Fourth, we do something strange. We calculate the number_of_data_sectors being equal to "total number of sectors in the partition" minus the "number of reserved sectors". BG does not agree with this calculation. The code suggests:
dos_disk_table[12..15] = "number_of_sectors_in_partition" minus "dos_disk_table[18..1B]"
NOTE that "dos_disk_table[18..1B]" currently holds the value calculated above in 'Third, ...'
NOTE that this calculation suggests that it clobbers a value in dos_disk_table[16], but I cannot see that it clobbers anything.

Then, the number of sectors-per-cluster (1 byte) is stored into the dos_disk_table at offset +$16. This is at "get_sec_per_cluster:".
+16 with VID:+$0D (sectors-per-cluster)

Then, ad "ddop14:", I do not follow what is going on.

At "ddop_gotclustercount:", an apparently clobbered variable gets re-instated (dos_disk_table[16]=fs_fat32_sectors_per_cluster}

Then, at about "ddop16:", the code seems to copy the four bytes of "rootDirFirstCluster" and store each over the top of the other at dos_disk_table+$10.
+10 with rootDirFirstCluster.
BG: Yes, this does seem to clash with dos_disk_table+$0f
NOTE that dos_disk_table+$11 seems to never get set.

Then, just before "dos_return_success:", the value in dos_disk_table+$08 is set to indicate the type of file-system just parsed.
+08 with $0f (fs_type_and_source)

The "dos_disk_openpartition" function then returns.

##dos_disk_table
Each section of the dos_disk_table is $20 bytes, allowing for 8 entries. (Q: why 8x when there are only four primary partitions on a sdcard?, A:to allow other devices to appear like /dev/sdc3 and /dev/sdd1 for example).

Each section is made up as follows: (sourced from the "kickstart.a65 file describing $BB00)

When accessing one-of-the-eight entries, you first need to get the value in "dos_disk_table_offset:", then multiply that value by $20 (left-shift 5x times). Then add to that result the desired offset specified in an alias located at "fs_dos_disk_table_offsets:".
Basically,
Offsets        Description
+00,01,02,03 = starting sector (fs_start_sector:)
+04,05,06,07 = sector_count (fs_sector_count:)
+08          = file-system type (fs_type_and_source:)
+09,0A,0B,0C = FAT32 specific, length of fat (fs_fat32_length_of_fat:)
+0D,0E       = FAT32 specific, system sectors (fs_fat32_system_sectors:)
+0F          = FAT32 specific, reserved clusters (fs_fat32_reserved_clusters)
+10,11       = FAT32 specific, root directory cluster (fs_fat32_root_dir_cluster:)
+12,13,14,15 = FAT32 specific, cluster count 
+16          = FAT32 specific, sectors per cluster (fs_fat32_sectors_per_cluster:)
+17          = FAT32 specific, # copies of the fat (fs_fat32_fat_copies:)
+18,19,1A,1B = FAT32 specific, first sector of data cluster zero (fs_fat32_cluster0_sector:)
+1C,1D,1E,1F = FAT32 specific, unallocated

##sd_map_sectorbuffer
There are two functions, "sd_map_sectorbuffer:" and "sd_unmap_sectorbuffer:".
These functions just either store #$81 or #$82 respectively into the sdcard-control-register of $D680.
I understand that the $D680 register is mapped directly to the sd-card-controller, and that these functions may swap the pointers between the two 512-byte buffers.

##dos_cdroot
This function does some sanity-checks on the chosen "dos_default_disk", and stores values in "dos_disk_cwd_cluster[3..0]".
I do not think that the "dos_disk_cwd_cluster" registers are currently used.
I do not think that this routine impacts the current code at all.

##dos_default_disk
This is a register that holds an index into the dos_disk_table. It should have values between "00" and "07" as we currently only allow 8x disk-devices.

##sdcardmode

There are four dos-file-descriptors. Each is 16-bytes.
A dos-file-descriptor is invalid/unallocated when the first byte is $FF.

dos_file_descriptors:
	.byte $FF,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0	; each is 16 bytes

When you try and load a file, first the directory is searched for the filename.
The directory (or better referred to as FAT) is searched.
When the FAT is searched, each $20-byte entry is examined.
Currently:
- check for attrib=0f -> goto LFN (long file name)
- check for attrib-bit-6 set -> goto HIDDEN
- check for attrib-bit-3 set -> ???
- check for attrib-bit-2 set -> ???
- check for attrib-bit-1 set -> ???


========================================
Master Boot Record (MBR)
========================================
00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
--<snip>--
000001b0  00 00 00 00 00 00 00 00  33 1e 67 5e 00 00 00 01  |........3.g^....|
000001c0  24 01 0c 14 9c 0d 00 08  00 00 00 a0 0f 00 00 00  |$...............|
000001d0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
000001e0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
000001f0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 55 aa  |..............U.|
----------------------------------------
BYTE-OFFSET	Description
00000000	start or disk/MBR
000001be	1st partition record
000001ce	2nd partition record
000001de	3rd partition record
000001ee	4th partition record
000001fe	AA55
----------------------------------------
xx=dont-care
000001be+0	xx boot flag

000001be+1	xx chs_begin
000001be+2	xx "
000001be+3	xx "

000001be+4	0c type (FAT32)

000001be+5	xx chs_end
000001be+6	xx "
000001be+7	xx "

000001be+8	00 partition_lba_begin ($00000800)
000001be+9	08 "
000001be+A	00 "
000001be+B	00 "

000001be+C	xx number_of_sectors
000001be+D	xx "
000001be+E	xx "
000001be+F	xx "

partition_lba_begin = 00000800'th sector
sector 800 x $200 bytes/sector = 00100000'th byte = start of Volume ID

========================================
Volume ID (FIRST SECTOR OF FILE SYSTEM)
========================================
00100000  eb 58 90 6d 6b 66 73 2e  66 61 74 00 02 08 38 02  |.X.mkfs.fat...8.|
00100010  02 00 00 00 00 f8 00 00  3d 00 20 00 81 00 00 00  |........=. .....|
00100020  00 a0 0f 00 e6 03 00 00  00 00 00 00 02 00 00 00  |................|
00100030  01 00 06 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00100040  80 00 29 5a cd d1 1b 4c  4f 55 44 20 20 20 20 20  |..)Z...LOUD     |
00100050  20 20 46 41 54 33 32 20  20 20 0e 1f be 77 7c ac  |  FAT32   ...w|.|
00100060  22 c0 74 0b 56 b4 0e bb  07 00 cd 10 5e eb f0 32  |".t.V.......^..2|
00100070  e4 cd 16 cd 19 eb fe 54  68 69 73 20 69 73 20 6e  |.......This is n|
00100080  6f 74 20 61 20 62 6f 6f  74 61 62 6c 65 20 64 69  |ot a bootable di|
00100090  73 6b 2e 20 20 50 6c 65  61 73 65 20 69 6e 73 65  |sk.  Please inse|
001000a0  72 74 20 61 20 62 6f 6f  74 61 62 6c 65 20 66 6c  |rt a bootable fl|
001000b0  6f 70 70 79 20 61 6e 64  0d 0a 70 72 65 73 73 20  |oppy and..press |
001000c0  61 6e 79 20 6b 65 79 20  74 6f 20 74 72 79 20 61  |any key to try a|
001000d0  67 61 69 6e 20 2e 2e 2e  20 0d 0a 00 00 00 00 00  |gain ... .......|
001000e0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
--<snip>--
001001e0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
001001f0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 55 aa  |..............U.|

----------------------------------------
00100000	xx Volume ID
00100000+B	00 bytes_per_sector ($0200=#512)
00100000+C	02 "

00100000+D	08 sectors_per_cluster (#08)

00100000+E	38 number_reserved_sectors ($0238)
00100000+F	02 "

00100000+10	02 number_of_FATs (#02)

00100000+24	e6 sectors_per_FAT ($000003e6)
00100000+25	03 "
00100000+26	00 "
00100000+27	00 "

00100000+2C	02 root_dir_first_cluster ($00000002)
00100000+2D	00 "
00100000+2E	00 "
00100000+2F	00 "

00100000+1FE	55 signature ($AA55)
00100000+1FF	AA "

----------------------------------------
calculate:
 fat_begin_lba = partition_lba_begin + number_reserved_sectors
               = $00000800           + $0238
               = $00000A38
 convert to BYTE-OFFSET
               = "         x bytes_per_sector
               = $00000A38 x $0200
               = $00147000'th byte
               = where the FAT begins (first copy of FAT)
----------------------------------------
calculate:
 cluster_begin_lba = partition_lba_begin + number_reserved_sectors + (number_of_FATs * sectors_per_FAT)
                   = $00000800           + $0238                   + ($02            * $000003e6)
                   = $00000800           + $0238                   + $000007cc
                   = 00001204
 convert to BYTE-OFFSET
                   = "         x bytes_per_sector
                   = $00001204 x $0200
                   = $00240800'th byte
                   = where the data-clusters begins

========================================
1ST FAT
========================================
00147000  f8 ff ff 0f ff ff ff ff  f8 ff ff 0f 04 00 00 00  |................|
00147010  05 00 00 00 06 00 00 00  ff ff ff 0f 08 00 00 00  |................|
00147020  09 00 00 00 0a 00 00 00  0b 00 00 00 0c 00 00 00  |................|
00147030  0d 00 00 00 0e 00 00 00  0f 00 00 00 10 00 00 00  |................|
00147040  11 00 00 00 12 00 00 00  13 00 00 00 14 00 00 00  |................|
00147050  15 00 00 00 16 00 00 00  17 00 00 00 18 00 00 00  |................|
00147060  19 00 00 00 1a 00 00 00  1b 00 00 00 1c 00 00 00  |................|
00147070  1d 00 00 00 1e 00 00 00  1f 00 00 00 20 00 00 00  |............ ...|
00147080  21 00 00 00 22 00 00 00  23 00 00 00 24 00 00 00  |!..."...#...$...|
00147090  25 00 00 00 26 00 00 00  ff ff ff 0f 28 00 00 00  |%...&.......(...|
001470a0  29 00 00 00 2a 00 00 00  2b 00 00 00 2c 00 00 00  |)...*...+...,...|
001470b0  2d 00 00 00 2e 00 00 00  2f 00 00 00 30 00 00 00  |-......./...0...|
001470c0  31 00 00 00 32 00 00 00  33 00 00 00 34 00 00 00  |1...2...3...4...|
001470d0  35 00 00 00 36 00 00 00  37 00 00 00 38 00 00 00  |5...6...7...8...|
--<snip>--
00148170  5d 04 00 00 5e 04 00 00  5f 04 00 00 60 04 00 00  |]...^..._...`...|
00148180  61 04 00 00 62 04 00 00  63 04 00 00 64 04 00 00  |a...b...c...d...|
00148190  65 04 00 00 66 04 00 00  67 04 00 00 68 04 00 00  |e...f...g...h...|
001481a0  69 04 00 00 6a 04 00 00  6b 04 00 00 6c 04 00 00  |i...j...k...l...|
001481b0  6d 04 00 00 6e 04 00 00  6f 04 00 00 70 04 00 00  |m...n...o...p...|
001481c0  71 04 00 00 72 04 00 00  73 04 00 00 74 04 00 00  |q...r...s...t...|
001481d0  75 04 00 00 76 04 00 00  77 04 00 00 78 04 00 00  |u...v...w...x...|
001481e0  79 04 00 00 7a 04 00 00  7b 04 00 00 7c 04 00 00  |y...z...{...|...|
001481f0  7d 04 00 00 7e 04 00 00  7f 04 00 00 80 04 00 00  |}...~...........|
00148200  81 04 00 00 82 04 00 00  83 04 00 00 84 04 00 00  |................|
00148210  85 04 00 00 86 04 00 00  87 04 00 00 88 04 00 00  |................|
00148220  89 04 00 00 8a 04 00 00  8b 04 00 00 8c 04 00 00  |................|
00148230  8d 04 00 00 8e 04 00 00  8f 04 00 00 90 04 00 00  |................|
00148240  91 04 00 00 92 04 00 00  93 04 00 00 94 04 00 00  |................|
00148250  95 04 00 00 96 04 00 00  97 04 00 00 ff ff ff 0f  |................|
00148260  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00148270  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00148280  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00148290  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
001482a0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|

========================================
2nd FAT
========================================
Also, note that there is a 2nd FAT, located directly after the 1st FAT.

FAT#1 location = $0800 + $0238
FAT#2 location = $0800 + $0238 + sectors_per_FAT
               = $0800 + $0238 + $03e6
               = $0E1E
 convert to BYTE-OFFSET
               = "         x bytes_per_sector
               = $00000E1E x $0200
               = $001C3C00'th byte
               = where the 2nd FAT is located.

This is verified below: (and 1st-FAT is same as 2nd-FAT)

----------------------------------------
001c3c00  f8 ff ff 0f ff ff ff ff  f8 ff ff 0f 04 00 00 00  |................|
001c3c10  05 00 00 00 06 00 00 00  ff ff ff 0f 08 00 00 00  |................|
001c3c20  09 00 00 00 0a 00 00 00  0b 00 00 00 0c 00 00 00  |................|
001c3c30  0d 00 00 00 0e 00 00 00  0f 00 00 00 10 00 00 00  |................|
001c3c40  11 00 00 00 12 00 00 00  13 00 00 00 14 00 00 00  |................|
001c3c50  15 00 00 00 16 00 00 00  17 00 00 00 18 00 00 00  |................|
001c3c60  19 00 00 00 1a 00 00 00  1b 00 00 00 1c 00 00 00  |................|
001c3c70  1d 00 00 00 1e 00 00 00  1f 00 00 00 20 00 00 00  |............ ...|
001c3c80  21 00 00 00 22 00 00 00  23 00 00 00 24 00 00 00  |!..."...#...$...|
001c3c90  25 00 00 00 26 00 00 00  ff ff ff 0f 28 00 00 00  |%...&.......(...|
001c3ca0  29 00 00 00 2a 00 00 00  2b 00 00 00 2c 00 00 00  |)...*...+...,...|
001c3cb0  2d 00 00 00 2e 00 00 00  2f 00 00 00 30 00 00 00  |-......./...0...|
001c3cc0  31 00 00 00 32 00 00 00  33 00 00 00 34 00 00 00  |1...2...3...4...|
001c3cd0  35 00 00 00 36 00 00 00  37 00 00 00 38 00 00 00  |5...6...7...8...|
001c3ce0  39 00 00 00 3a 00 00 00  3b 00 00 00 3c 00 00 00  |9...:...;...<...|
001c3cf0  3d 00 00 00 3e 00 00 00  3f 00 00 00 40 00 00 00  |=...>...?...@...|
001c3d00  41 00 00 00 42 00 00 00  43 00 00 00 44 00 00 00  |A...B...C...D...|
001c3d10  45 00 00 00 46 00 00 00  47 00 00 00 48 00 00 00  |E...F...G...H...|
001c3d20  49 00 00 00 4a 00 00 00  4b 00 00 00 4c 00 00 00  |I...J...K...L...|
001c3d30  4d 00 00 00 4e 00 00 00  4f 00 00 00 50 00 00 00  |M...N...O...P...|
001c3d40  51 00 00 00 52 00 00 00  53 00 00 00 54 00 00 00  |Q...R...S...T...|
001c3d50  55 00 00 00 56 00 00 00  57 00 00 00 58 00 00 00  |U...V...W...X...|
001c3d60  59 00 00 00 5a 00 00 00  5b 00 00 00 5c 00 00 00  |Y...Z...[...\...|
001c3d70  5d 00 00 00 5e 00 00 00  5f 00 00 00 60 00 00 00  |]...^..._...`...|
001c3d80  61 00 00 00 62 00 00 00  63 00 00 00 64 00 00 00  |a...b...c...d...|
001c3d90  65 00 00 00 66 00 00 00  67 00 00 00 68 00 00 00  |e...f...g...h...|
--<snip>--
001c4d10  45 04 00 00 46 04 00 00  47 04 00 00 48 04 00 00  |E...F...G...H...|
001c4d20  49 04 00 00 4a 04 00 00  4b 04 00 00 4c 04 00 00  |I...J...K...L...|
001c4d30  4d 04 00 00 4e 04 00 00  4f 04 00 00 50 04 00 00  |M...N...O...P...|
001c4d40  51 04 00 00 52 04 00 00  53 04 00 00 54 04 00 00  |Q...R...S...T...|
001c4d50  55 04 00 00 56 04 00 00  57 04 00 00 58 04 00 00  |U...V...W...X...|
001c4d60  59 04 00 00 5a 04 00 00  5b 04 00 00 5c 04 00 00  |Y...Z...[...\...|
001c4d70  5d 04 00 00 5e 04 00 00  5f 04 00 00 60 04 00 00  |]...^..._...`...|
001c4d80  61 04 00 00 62 04 00 00  63 04 00 00 64 04 00 00  |a...b...c...d...|
001c4d90  65 04 00 00 66 04 00 00  67 04 00 00 68 04 00 00  |e...f...g...h...|
001c4da0  69 04 00 00 6a 04 00 00  6b 04 00 00 6c 04 00 00  |i...j...k...l...|
001c4db0  6d 04 00 00 6e 04 00 00  6f 04 00 00 70 04 00 00  |m...n...o...p...|
001c4dc0  71 04 00 00 72 04 00 00  73 04 00 00 74 04 00 00  |q...r...s...t...|
001c4dd0  75 04 00 00 76 04 00 00  77 04 00 00 78 04 00 00  |u...v...w...x...|
001c4de0  79 04 00 00 7a 04 00 00  7b 04 00 00 7c 04 00 00  |y...z...{...|...|
001c4df0  7d 04 00 00 7e 04 00 00  7f 04 00 00 80 04 00 00  |}...~...........|
001c4e00  81 04 00 00 82 04 00 00  83 04 00 00 84 04 00 00  |................|
001c4e10  85 04 00 00 86 04 00 00  87 04 00 00 88 04 00 00  |................|
001c4e20  89 04 00 00 8a 04 00 00  8b 04 00 00 8c 04 00 00  |................|
001c4e30  8d 04 00 00 8e 04 00 00  8f 04 00 00 90 04 00 00  |................|
001c4e40  91 04 00 00 92 04 00 00  93 04 00 00 94 04 00 00  |................|
001c4e50  95 04 00 00 96 04 00 00  97 04 00 00 ff ff ff 0f  |................|
001c4e60  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|



========================================
From the first 4-bytes (32-bits) of the FAT,
which is the reserved cluster#0,
we see:
001c3c00  f8 ff ff 0f ($0ffffff8)
which tells us that:
f8 = it is a partitioned disk

From the second 4-bytes (32-bits) of the FAT,
which is the reserved cluster#1,
we see:
001c3c04  ff ff ff ff ($ffffffff)
which tells us that:
this is the end of the reserved section...

From the third 4-bytes (32-bits) of the FAT,
which is the cluster in location $02,
we see:
001c3c08  f8 ff ff 0f ($0ffffff8)
which tells us that:
this is the last cluster chain for the root directory,
so the root-directory does not span into another cluster.

From the fourth 4-bytes (32-bits) of the FAT,
which is the cluster chain in location $03,
we see:
001c3c0c  04 00 00 00 ($00000004)
which tells us that:
the data within cluster-#3 continues onto the cluster-$04.

Similarly, cluster-#4 -> cluster-#5

From the sixth 4-bytes (32-bits) of the FAT,
which is the sixth cluster chain (in location $05),
we see:
001c3c14  06 00 00 00 ($00000006)
which tells us that:
the data within cluster-#6 continues onto the cluster-$04.
... too hard, head hurts...


========================================
Data-clusters
========================================
And it can be calculated that the data-clusters follow directly from the 2nd FAT

FAT#2 location + sectors_per_FAT = $0E1E + $03e6
                                 = $1204
                                 = cluster_begin_lba (same result as above)
 convert to BYTE-OFFSET
                                 = "         x bytes_per_sector
                                 = $00001204 x $0200
                                 = $00240800'th byte
                                 = where the data-clusters begin.

----------------------------------------
00240800  4c 4f 55 44 2d 31 47 20  20 20 20 08 00 00 00 00  |LOUD-1G    .....|
00240810  00 00 00 00 00 00 d1 74  28 49 00 00 00 00 00 00  |.......t(I......|
00240820  4b 49 43 4b 55 50 20 20  4d 36 35 20 00 00 fd 28  |KICKUP  M65 ...(|
00240830  28 49 28 49 00 00 1c 27  28 49 03 00 00 40 00 00  |(I(I...'(I...@..|
00240840  4d 45 47 41 36 35 20 20  52 4f 4d 20 00 a6 d4 74  |MEGA65  ROM ...t|
00240850  28 49 28 49 00 00 02 63  22 45 07 00 00 00 02 00  |(I(I...c"E......|
00240860  4d 45 47 41 36 35 20 20  44 38 31 20 10 ba d5 74  |MEGA65  D81 ...t|
00240870  28 49 28 49 00 00 a0 66  0f 49 27 00 00 80 0c 00  |(I(I...f.I'.....|
00240880  e5 48 41 52 52 4f 4d 32  4d 36 35 20 00 9d d7 74  |.HARROM2M65 ...t|
00240890  28 49 28 49 00 00 9c 4e  ed 46 ef 00 00 10 00 00  |(I(I...N.F......|
002408a0  42 4f 4f 54 4c 4f 47 4f  4d 36 35 20 00 ae d8 74  |BOOTLOGOM65 ...t|
002408b0  28 49 28 49 00 00 0e 24  22 49 f0 00 00 10 00 00  |(I(I...$"I......|
002408c0  42 49 54 34 46 30 42 20  42 49 54 20 18 b9 d9 74  |BIT4F0B BIT ...t|
002408d0  28 49 28 49 00 00 0e 51  1a 49 f1 00 ec 60 3a 00  |(I(I...Q.I...`:.|
002408e0  e5 48 41 52 52 4f 4d 20  4d 36 35 20 00 9d d7 74  |.HARROM M65 ...t|
002408f0  28 49 28 49 00 00 9c 4e  ed 46 98 04 00 10 00 00  |(I(I...N.F......|
00240900  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00240910  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00240920  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00240930  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|

first data-cluster holds the entries of the filenames.


The End.


