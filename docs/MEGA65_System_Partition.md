
# MEGA65 System Partition

The MEGA65 System Partition contains a variety of sections used to
hold the configuration and certain operating system components of
the MEGA65.  Essentially any data that the operating system must be
able to write itself, lives here, as the small hypervisor operating
system does not have the ability to write to the FAT32 file system.

The partition type for a MEGA65 system partition is $41 (65 in decimal)

The easiest way to create a MEGA65 System Paratition is to use the
MEGA65-FDISK program.  Currently this deletes the entire disk when
setting up a system partition, so use with caution!

# MEGA65 System Partition Overview

The system partition contains the following structures:

1. System Configuration area (64KB)
2. Boot logo (64KB)
3. Reserved space (to end of first MB)
5. Frozen programs, including directory (variable size)
6. Installed System Services, including directory (variable size)

Other regions may be added later

# System Configuration Area (64KB)

## First sector:

$000-$00A - "MEGA65SYS00" magic string
$00B-$00F - Reserved. Must be all zeroes
$010-$013 - Start sector of freeze program area
$014-$017 - Size of freeze program area (in sectors)
$018-$01B - Size of each freeze slot (in sectors)
$01C-$01D - Number of freeze slots
$01E-$01F - Number of sectors in freeze slot directory
$020-$023 - Start of freeze program area (in sectors)
$024-$027 - Size of service program area (in sectors)
$028-$02B - Size of each service slot (in sectors)
$02C-$02D - Number of service slots
$02E-$02F - Number of sectors in service slot directory


## System Configuration Area

This will evolve over time, however for now, sector 1 contains
an extensible list of configuration options.  As the version field
increases, additional options may be added, and older options may
be ignored, however it is required that backwards binary compatibility
be maintained, so bytes defined in an earlier version may not change
meaning in later versions in an incompatible way.  All unspecified bits and bytes should be zeroed.

$000-$001 - Version of structure
$002 - Set video standard on boot: $00=PAL, $80=NTSC
$003.0 - Enable audio amplifier (only for Nexys4 boards)
$003.5 - Swap stereo channels if set
$003.6 - Play mono audio through both channels if set
$003.7 - Select DAC mode: 0=PDM, 1=PWM
$004.0 - 0=F011 will use disk images from SD card, 1=F011 will use 3.5" internal floppy drive
$005.0 - 0=Disable transparent 1351 emulation for Amiga mouses, 1=Enable use of Amiga mouses as though they were 1351 mouses.
$006-$00B - Ethernet MAC address

## Boot Logo

Not yet implemented, but will allow loading the boot logo each reset.  By placing this in the system partition, we avoid the time it takes to detect and open the FAT32 file system, allowing the boot logo to be shown sooner.

## Reserved Space

The remainder of the first 1MB is reserved.

## Frozen Programs

Each frozen program consists of the 128KB RAM, 128KB "ROM", 32KB colour RAM, 4KB thumbnail and 28KB of saved IO registers, plus a 128 byte directory entry.  The directory entries are all held together at the beginning of the frozen program area.

## Installed System Services

Installed system services are structured identically to frozen programs, but are read-only, and must support the (yet to be documented and implemented) MEGAOS service calling convention.

