#include <stdio.h>

#include "fdisk_hal.h"

uint32_t sdcard_getsize(void)
{
  return 0x4000000;
}

void sdcard_open(void)
{
}

void sdcard_writesector(const uint32_t sector_number, const uint8_t *buffer)
{
}

void sdcard_erase(const uint32_t first_sector,const uint32_t last_sector)
{
}
