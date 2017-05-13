#include <sys/types.h>
#include <ctype.h>
#include <stdint.h>

uint32_t sdcard_getsize(void);
void sdcard_open(void);
void sdcard_writesector(const uint32_t sector_number, const uint8_t *buffer);
void sdcard_erase(const uint32_t first_sector,const uint32_t last_sector);
void mega65_fast(void);
