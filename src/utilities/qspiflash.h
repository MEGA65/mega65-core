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
  Flash memory page sizes.
*/
enum qspi_flash_page_size
{
    qspi_flash_page_size_256,
    qspi_flash_page_size_512
};

/*
  Abstract interface definition for QSPI flash drivers.
*/
struct qspi_flash_interface
{
    char (*init) (void * qspi_flash_device);
    char (*read) (void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size);
    char (*verify) (void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size);
    char (*erase) (void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, unsigned long address);
    char (*program) (void * qspi_flash_device, enum qspi_flash_page_size page_size, unsigned long address, const unsigned char * data);
    char (*get_manufacturer) (void * qspi_flash_device, const char ** manufacturer);
    char (*get_size) (void * qspi_flash_device, unsigned int * size);
    char (*get_page_size) (void * qspi_flash_device, enum qspi_flash_page_size * page_size);
    char (*get_erase_block_size_support) (void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported);
};

/*
  Initialize the specified flash device.
*/
char qspi_flash_init(void * qspi_flash_device);

/*
  Read bytes from flash memory starting from the specified address. The read
  bytes are stored in the buffer provided by the caller, or discarded if data
  is NULL.
*/
char qspi_flash_read(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size);

/*
  Read bytes from flash memory and compare against the data provided by the
  caller. If data is NULL, verify that all bytes read from flash are equal to
  zero.
*/
char qspi_flash_verify(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size);

/*
  Erase a block of the specified size. The address does not need to be aligned
  to a block boundary. If an unaligned address is specified, the block that
  contains the address will be erased.
*/
char qspi_flash_erase(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, unsigned long address);

/*
  Program a page in flash memory. The address must be aligned on a page
  boundary. Note that before a page can be programmed, it must be erased
  first. (Programming can only change bits from '1' to '0'; changing bits
  from '0' to '1' requires an erase operation.)
*/
char qspi_flash_program(void * qspi_flash_device, enum qspi_flash_page_size page_size, unsigned long address, const unsigned char * data);

/*
  Return the name of the flash device manufacturer.
*/
char qspi_flash_get_manufacturer(void * qspi_flash_device, const char ** manufacturer);

/*
  Return the size of the flash memory array in megabytes (MB).
*/
char qspi_flash_get_size(void * qspi_flash_device, unsigned int * size);

/*
  Return the page size used by the flash device.
*/
char qspi_flash_get_page_size(void * qspi_flash_device, enum qspi_flash_page_size * page_size);

/*
  Return true iff the flash device supports the specified erase block size.
*/
char qspi_flash_get_erase_block_size_support(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported);

/*
  Covenience function that returns the size of an erase block in bytes.
*/
char get_erase_block_size_in_bytes(enum qspi_flash_erase_block_size erase_block_size, unsigned long * size);

/*
  Convenience function that returns the size of a page in bytes.
*/
char get_page_size_in_bytes(enum qspi_flash_page_size page_size, unsigned int * size);

/*
  Convenience function that returns that largest supported erase block size for
  the specified flash device.
*/
char get_max_erase_block_size(void * qspi_flash_device, enum qspi_flash_erase_block_size * max_erase_block_size);

#endif /* QSPIFLASH_H */
