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

void clear_sector_buffer(void)
{
  for(int i=0;i<512;i++) sector_buffer[i]=0;
}


/* Build a master boot record that has the single partition we need in
   the correct place, and with the size of the partition set correctly.
*/
void build_mbr(const uint32_t sdcard_sectors,const uint32_t partition_sectors)
{
  clear_sector_buffer();

  // Set disk signature (fixed value)
  sector_buffer[0x1b8]=0x83;
  sector_buffer[0x1b9]=0x7d;
  sector_buffer[0x1ba]=0xcb;
  sector_buffer[0x1bb]=0xa6;

  // FAT32 Partition entry
  sector_buffer[0x1be]=0x00;  // Not bootable by DOS
  sector_buffer[0x1bf]=0x20;  // 3 bytes CHS starting point
  sector_buffer[0x1c0]=0x21;
  sector_buffer[0x1c1]=0x20;
  sector_buffer[0x1c2]=0x0c;  // Partition type (VFAT32)
  sector_buffer[0x1c3]=0xdd;  // 3 bytes CHS end point - SHOULD CHANGE WITH DISK SIZE
  sector_buffer[0x1c4]=0x1e;
  sector_buffer[0x1c5]=0x3f;
  sector_buffer[0x1c6]=0x00;  // LBA starting sector of partition (0x0800 = sector 2,048)
  sector_buffer[0x1c7]=0x08;
  sector_buffer[0x1c8]=0x00;
  sector_buffer[0x1c9]=0x00;
  // LBA size of partition in sectors
  sector_buffer[0x1ca]=(partition_sectors>>0)&0xff;  
  sector_buffer[0x1cb]=(partition_sectors>>8)&0xff;  
  sector_buffer[0x1cc]=(partition_sectors>>16)&0xff;  
  sector_buffer[0x1cd]=(partition_sectors>>24)&0xff;  

  // MBR signature
  sector_buffer[0x1fe]=0x55;
  sector_buffer[0x1ff]=0xaa;
}

void build_dosbootsector(const uint8_t volume_name[11])
{
  clear_sector_buffer();
}

void build_fs_information_sector(const uint8_t fs_clusters)
{
  clear_sector_buffer();
}


void build_empty_fat()
{
  clear_sector_buffer();
}

void build_root_dir(const uint8_t volume_name[11])
{
  clear_sector_buffer();
}

int main(int argc,char **argv)
{
  sdcard_open();
  uint32_t sdcard_sectors = sdcard_getsize();

  // Calculate sectors for partition
  // This is the size of the card, minus 2,048 (=0x0800) sectors
  uint32_t partition_sectors=sdcard_sectors-0x0800;

  // Calculate clusters for file system, and FAT size
  uint32_t fs_clusters=0;
  uint32_t reserved_sectors=576; // not sure why we use this value
  uint32_t rootdir_sector=0;
  uint32_t fat_sectors=0;
  uint32_t fat1_sector=0;
  uint32_t fat2_sector=0;
  uint8_t sectors_per_cluster=8;  // 4KB clusters
  uint8_t volume_name[11];
  
  // Work out maximum number of clusters we can accommodate
  uint32_t sectors_required;
  uint32_t available_sectors=partition_sectors-reserved_sectors;

  fprintf(stderr,"Partition has 0x%x sectors (0x%x available)\n",
	  partition_sectors,available_sectors);
  
  fs_clusters=available_sectors/(sectors_per_cluster);
  fat_sectors=fs_clusters/(512/4); if (fs_clusters%(512/4)) fat_sectors++;
  sectors_required=2*fat_sectors+((fs_clusters-2)*sectors_per_cluster);
  while(sectors_required>available_sectors) {
    uint32_t excess_sectors=sectors_required-available_sectors;
    uint32_t delta=(excess_sectors/(1+sectors_per_cluster));
    if (delta<1) delta=1;
    fprintf(stderr,"%d clusters would take %d too many sectors.\n",
	    fs_clusters,sectors_required-available_sectors);
    fs_clusters-=delta;
    fat_sectors=fs_clusters/(512/4); if (fs_clusters%(512/4)) fat_sectors++;
    sectors_required=2*fat_sectors+((fs_clusters-2)*sectors_per_cluster);
  }
  fprintf(stderr,"Creating file system with %u (0x%x) clusters, %d sectors per FAT.\n",
	  fs_clusters,fs_clusters,fat_sectors);
  
  // MBR is always the first sector of a disk
  build_mbr(sdcard_sectors,partition_sectors);
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
