#include <stdio.h>
#include <stdlib.h>

#include "fdisk_hal.h"

uint8_t *sd_sectorbuffer=(uint8_t *)0xde00;
uint8_t *sd_ctl=(uint8_t *)0xd680;
uint8_t *sd_addr=(uint8_t *)0xd681;

uint32_t sdcard_getsize(void)
{
  // XXX - Just say 1GB for now.
  return (0x40000000/512);
}

void sdcard_open(void)
{
  // On real MEGA65, there is nothing to do here.
}

uint32_t write_count=0;

void sdcard_map_sector_buffer(void)
{
  *sd_ctl = 0x81;
}

void sdcard_unmap_sector_buffer(void)
{
  *sd_ctl = 0x82;
}

void sdcard_writesector(const uint32_t sector_number, const uint8_t *buffer)
{
  // Copy buffer into the SD card buffer, and then execute the write job
  uint16_t i;
  uint32_t sector_address;
  
  // Memory map the SD card sector buffer
  sdcard_map_sector_buffer();

  // Copy the sector to the buffer
  for(i=0;i<512;i++) sd_sectorbuffer[i]=buffer[i];

  // Set address to read/write
  sector_address=sector_number*512;
  sd_addr[0]=(sector_address>>0)&0xff;
  sd_addr[1]=(sector_address>>8)&0xff;
  sd_addr[2]=(sector_address>>16)&0xff;
  sd_addr[3]=(sector_address>>24)&0xff;

  // Give write command
  *sd_ctl = 0x03;
  
  // Remove SD card sector buffer from memory
  sdcard_unmap_sector_buffer();
  
  write_count++;
}

uint8_t z[512];

void sdcard_erase(const uint32_t first_sector,const uint32_t last_sector)
{
  uint32_t n;
  for(n=0;n<512;n++) z[n]=0;

  fprintf(stderr,"Erasing sectors %d..%d\n",first_sector,last_sector);
  
  for(n=first_sector;n<=last_sector;n++) sdcard_writesector(n,z);
  
}
