#ifndef QSPIFLASH_H
#define QSPIFLASH_H

typedef enum { FALSE, TRUE } BOOL;

#define QSPI_FLASH_SUCCESS  ( 0)
#define QSPI_FLASH_ERROR    (-1)

/*
  Uniform erase block sizes.
*/
enum qspi_flash_erase_block_size
{
    qspi_flash_erase_block_size_4k,
    qspi_flash_erase_block_size_32k,
    qspi_flash_erase_block_size_64k,
    qspi_flash_erase_block_size_256k,

    /* This entry should always be last. */
    qspi_flash_erase_block_size_last
};

/*
  Initialize the flash device via the hardware QSPI controller.
*/
char qspi_flash_reset(void);

/*
  Read bytes from flash memory starting from the specified address. The read
  bytes are stored in the buffer provided by the caller.
*/
char qspi_flash_read(unsigned long address, unsigned char * data, unsigned int size);

/*
  Read bytes from flash memory and compare against the data provided by the
  caller.
*/
char qspi_flash_verify(unsigned long address, unsigned char * data, unsigned int size);

/*
  Erase a block of the specified size. The address does not need to be aligned
  to a block boundary. If an unaligned address is specified, the block that
  contains the address will be erased.
*/
char qspi_flash_erase(enum qspi_flash_erase_block_size erase_block_size, unsigned long address);

/*
  Program a page in flash memory. The address must be aligned on a page
  boundary. Note that before a page can be programmed, it must be erased
  first. (Programming can only change bits from '1' to '0'; changing bits
  from '0' to '1' requires an erase operation.)
*/
char qspi_flash_program(unsigned long address, const unsigned char * data, unsigned int size);

/*
  Return the size of the flash memory array in megabytes (MB).
*/
char qspi_flash_get_size(unsigned int * size);

/*
  Return true iff the flash device supports the specified erase block size.
*/
char qspi_flash_get_erase_block_size_support(enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported);

/*
  Convenience function that returns the largest supported erase block size for
  the flash device.
*/
char qspi_flash_get_max_erase_block_size(enum qspi_flash_erase_block_size * max_erase_block_size);

/*
  Convenience function that returns the size of an erase block in bytes.
*/
char get_erase_block_size_in_bytes(enum qspi_flash_erase_block_size erase_block_size, unsigned long * size);

#endif /* QSPIFLASH_H */
