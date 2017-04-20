/*
  Extremely simplified FDISK + FORMAT utility for the MEGA65.
  This program is designed to be compilable both for the MEGA65
  using CC65, and also for UNIX-like operating systems for testing.
  All hardware dependent features will be in fdisk_hal_mega65.c and
  fdisk_hal_unix.c, respectively. I.e., this file contains only the
  hardware independent logic.

  This program gets the size of the SD card, and then calculates an
  appropriate MBR, DOS Boot Sector, FS Information Sector, FATs and
  root directory, and puts them in place.

  XXX - We should also create the MEGA65 system partitions for
  installed services, and for task switching.

*/

#include <stdio.h>

#include "fdisk_hal.h"

uint8_t sector_buffer[512];

int main(int argc,char **argv)
{
  sdcard_open();
  uint32_t sdcard_sectors = sdcard_getsize();

  // Calculate sectors for partition
  uint32_t partition_sectors=0;

  // Calculate clusters for file system, and FAT size
  uint32_t fs_clusters=0;
  uint32_t rootdir_sector=0;
  uint32_t fat_sectors=0;
  uint32_t fat1_sector=0;
  uint32_t fat2_sector=0;
  uint8_t volumename[11];
  
  // MBR is always the first sector of a disk
  build_mbr();
  sdcard_writesector(0,sector_buffer);

  // Blank intervening sectors
  sdcard_erase(0+1,0x0800-1);
  
  // Partition starts at fixed position of sector 2048, i.e., 1MB
  build_dosbootsector(volume_name);
  sdcard_writesector(0x0800,sector_buffer);
  sdcard_writesector(0x0806,sector_buffer); // Backup boot sector at partition + 6

  // FAT32 FS Information block
  build_fs_information_sector(fs_clusters);
  sdcard_writesector(0x0801,sector_buffer);

  // FATs
  build_empty_fat();
  sdcard_writesector(fat1_sector,sector_buffer);
  sdcard_writesector(fat2_sector,sector_buffer);

  // Root directory
  build_root_dir(volume_name);
  sdcard_writesector(rootdir_sector,sector_buffer);

  // Make sure all other sectors are empty
  sdcard_erase(0x0801+1,0x0806-1);
  sdcard_erase(0x0806+1,fat1_sector-1);
  sdcard_erase(fat1_sector+1,fat2_sector-1);
  sdcard_erase(fat2_sector+1,rootdir_sector-1);
  sdcard_erase(rootdir_sector+1,rootdir_sector+1+sectors_per_cluster-1);

  return 0;
}
