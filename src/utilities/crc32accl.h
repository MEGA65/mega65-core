#ifndef CRC32ACCL_H
#define CRC32ACCL_H

#include <stdint.h>

// 4 bytes of zero page that are used for storing the CRC32 sum
#define CRC32_ZP 0x5c

// create 1024 byte of CRC32 lookup tables in two 512 byte large buffers
// MAKE SURE THE PROVIDED BUFFERS ARE LARGE ENOUGH, THERE IS NO CHECK!
extern void cdecl make_crc32_tables(unsigned char *t1, unsigned char *t2);

// update CRC32 with bytes from buffer
// WARNING: if len is 0, 256 bytes are processed!
extern void cdecl update_crc32(unsigned char len, unsigned char *buf);

// initialise CRC32 to all bits 1
#define init_crc32() *(uint32_t *)CRC32_ZP = 0xffffffffUL

// return 1s-complement of CRC32
#define get_crc32() ~(*(uint32_t *)CRC32_ZP)

#endif /* CRC32ACCL_H */