#ifndef CRC32ACCL_H
#define CRC32ACCL_H

#include <stdint.h>

#define CRC32_ZP 0x5c

extern void cdecl make_crc32_tables(void);
extern void cdecl update_crc32(unsigned char len, unsigned char *buf);

#define init_crc32() *(uint32_t *)CRC32_ZP = 0xffffffffUL
#define get_crc32() ~(*(uint32_t *)CRC32_ZP)

#endif /* CRC32ACCL_H */