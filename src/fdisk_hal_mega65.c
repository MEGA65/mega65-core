#include <stdio.h>
#include <stdlib.h>

#include "fdisk_hal.h"
#include "fdisk_memory.h"

#define POKE(X,Y) (*(unsigned char*)(X))=Y
#define PEEK(X) (*(unsigned char*)(X))

uint16_t sd_sectorbuffer=0xde00L;
uint16_t sd_ctl=0xd680L;
uint16_t sd_addr=0xd681L;

void mega65_fast(void)
{
  POKE(0,65);
}

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
  m65_io_enable();
  
  POKE(sd_ctl,0x81);
}

void sdcard_unmap_sector_buffer(void)
{
  m65_io_enable();
  
  POKE(sd_ctl,0x82);
}

void sdcard_writesector(const uint32_t sector_number, const uint8_t *buffer)
{
  // Copy buffer into the SD card buffer, and then execute the write job
  uint32_t sector_address;
  
  // Memory map the SD card sector buffer
  sdcard_map_sector_buffer();

  // Copy the sector to the buffer
  lcopy((uint32_t)buffer,sd_sectorbuffer,512);

  // Set address to read/write
  sector_address=sector_number*512;
  POKE(sd_addr+0,(sector_address>>0)&0xff);
  POKE(sd_addr+1,(sector_address>>8)&0xff);
  POKE(sd_addr+2,(sector_address>>16)&0xff);
  POKE(sd_addr+3,(sector_address>>24)&0xff);

  // Give write command
  POKE(sd_ctl,0x03);
  
  // Remove SD card sector buffer from memory
  sdcard_unmap_sector_buffer();
  
  write_count++;

  POKE(0xD021,write_count&0xff);
}

void sdcard_erase(const uint32_t first_sector,const uint32_t last_sector)
{
  uint32_t n;
  lfill(sd_sectorbuffer,0,512);

  //  fprintf(stderr,"ERASING SECTORS %d..%d\r\n",first_sector,last_sector);

  for(n=first_sector;n<=last_sector;n++) {
    sdcard_writesector(n,(uint8_t *)sd_sectorbuffer);
    //    fprintf(stderr,"."); fflush(stderr);
  }
  
}
