#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <strings.h>

#include "fdisk_hal.h"

FILE *sdcard=NULL;

void mega65_fast(void)
{
}

void sdcard_map_sector_buffer(void)
{
}

uint32_t sdcard_getsize(void)
{
  struct stat s;

  int r=fstat(fileno(sdcard),&s);

  if (r) {
    perror("stat");
    exit(-1);
  }

  return s.st_size/512;
}

void sdcard_open(void)
{
  sdcard=fopen("sdcard.img","r+");
  if (!sdcard) {
    fprintf(stderr,"Could not open sdcard.img.\n");
    perror("fopen");
    exit(-1);
  }
}

uint32_t write_count=0;

void sdcard_writesector(const uint32_t sector_number)
{
  const uint8_t *buffer=sector_buffer;
  
  fseek(sdcard,sector_number*512LL,SEEK_SET);
  fwrite(buffer,512,1,sdcard);

  write_count++;
}

void sdcard_erase(const uint32_t first_sector,const uint32_t last_sector)
{
  uint32_t n;
  bzero(sector_buffer,sizeof(512));

  fprintf(stderr,"Erasing sectors %d..%d\n",first_sector,last_sector);
  
  for(n=first_sector;n<=last_sector;n++) sdcard_writesector(n);
  
}
