#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

#include "fdisk_hal.h"

FILE *sdcard=NULL;

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

void sdcard_writesector(const uint32_t sector_number, const uint8_t *buffer)
{
}

void sdcard_erase(const uint32_t first_sector,const uint32_t last_sector)
{
}
