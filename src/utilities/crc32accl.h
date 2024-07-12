#ifndef CRC32ACCL_H
#define CRC32ACCL_H

#include <stdint.h>

// 4 bytes of zero page that are used for storing the CRC32 sum
#define CRC32_ZP 0x5c

/*
 * make_crc32_tables(uint8_t *t1, uint8_t *t2)
 *
 * Parameters:
 *   *t1: a 512 byte size buffer
 *   *t2: a second 512 byte buffer
 *
 * Initializes the crc32 tables in a user provided
 * 1k of RAM, given as two 512 byte blocks.
 * Note: aligning the memory to pages makes a small
 * difference.
 *
 */
extern void cdecl make_crc32_tables(uint8_t *t1, uint8_t *t2);

/*
 * update_crc32(uint8_t len, uint8_t *buf)
 *
 * Parameters:
 *   len: number of bytes in buffer, 0 means all 256!
 *   *buf: pointer to a 256 byte buffer
 *
 * Updates a running crc32 checksum from the contents of
 * buf.
 *
 */
extern void cdecl update_crc32(uint8_t len, uint8_t *buf);

/*
 * init_crc32()
 *
 * Inititialize CRC32_ZP to $ffffffff.
 *
 */
#define init_crc32() *(uint32_t *)CRC32_ZP = 0xffffffffUL

/*
 * get_crc32()
 *
 * Returns:
 *   current crc32 checksum as uint32_t
 *
 * Takes what is in CRC32_ZP and negates it binary.
 *
 */
#define get_crc32() ~(*(uint32_t *)CRC32_ZP)

#endif /* CRC32ACCL_H */