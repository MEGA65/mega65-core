#include <hal.h>
#include <memory.h>
#include <stddef.h>

#include "qspiflash.h"

/*
 * Address of buffer used by hardware QSPI flash controller.
 */
#define QSPI_FLASH_BUFFER (0xFFD6A00L)

char qspi_flash_reset(void)
{
    POKE(0xD680, 0x60);
    while (PEEK(0xD6CC) & 1);
    if (PEEK(0xD6CC) & 0x0F)
    {
        return 1;
    }

    return 0;
}

char qspi_flash_read(unsigned long address, unsigned char * data, unsigned int size)
{
    if (data == NULL)
    {
        return 1;
    }

    if (size > 512)
    {
        return 1;
    }

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD6CD, size >> 0);
    POKE(0xD6CE, size >> 8);
    POKE(0xD680, 0x61);

    while (PEEK(0xD6CC) & 1);
    if (PEEK(0xD6CC) & 0x0F)
    {
        return 1;
    }

    if (data != NULL)
    {
        lcopy(QSPI_FLASH_BUFFER, (unsigned long)data, size);
    }

    return 0;
}

char qspi_flash_verify(unsigned long address, unsigned char * data, unsigned int size)
{
    if (data == NULL)
    {
        return 1;
    }

    if (size > 512)
    {
        return 1;
    }

    lcopy((unsigned long)data, QSPI_FLASH_BUFFER, size);

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD6CD, size >> 0);
    POKE(0xD6CE, size >> 8);
    POKE(0xD680, 0x62);

    while (PEEK(0xD6CC) & 1);

    return (PEEK(0xD6CC) & 0x1F) ? 1 : 0;
}

char qspi_flash_erase(enum qspi_flash_erase_block_size erase_block_size, unsigned long address)
{
    unsigned char erase_command;

    if (erase_block_size == qspi_flash_erase_block_size_4k)
        erase_command = 0x64;
    else if (erase_block_size == qspi_flash_erase_block_size_32k)
        erase_command = 0x67;
    else if (erase_block_size == qspi_flash_erase_block_size_64k)
        erase_command = 0x68;
    else if (erase_block_size == qspi_flash_erase_block_size_256k)
        erase_command = 0x6A;
    else
        return 1;

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, erase_command);

    while (PEEK(0xD6CC) & 1);

    return (PEEK(0xD6CC) & 0x0F) ? 1 : 0;
}

char qspi_flash_program(unsigned long address, const unsigned char * data, unsigned int size)
{
    if (size > 512)
    {
        return 1;
    }

    if (data == NULL)
    {
        return 1;
    }

    lcopy((unsigned long)data, QSPI_FLASH_BUFFER, size);

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD6CD, size >> 0);
    POKE(0xD6CE, size >> 8);
    POKE(0xD680, 0x63);

    while (PEEK(0xD6CC) & 1);

    return (PEEK(0xD6CC) & 0x0F) ? 1 : 0;
}

char qspi_flash_get_size(unsigned int * size)
{
    *size = PEEK(0xD6C2);
    return 0;
}

char qspi_flash_get_erase_block_size_support(enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported)
{
    unsigned char mask = PEEK(0xD6C3);
    switch (erase_block_size)
    {
    case qspi_flash_erase_block_size_4k:   *is_supported = (mask & 0x01) ? TRUE : FALSE; break;
    case qspi_flash_erase_block_size_32k:  *is_supported = (mask & 0x08) ? TRUE : FALSE; break;
    case qspi_flash_erase_block_size_64k:  *is_supported = (mask & 0x10) ? TRUE : FALSE; break;
    case qspi_flash_erase_block_size_256k: *is_supported = (mask & 0x40) ? TRUE : FALSE; break;
    default:                               *is_supported = FALSE; break;
    }
    return 0;
}

char qspi_flash_get_max_erase_block_size(enum qspi_flash_erase_block_size * max_erase_block_size)
{
    enum qspi_flash_erase_block_size result = qspi_flash_erase_block_size_last;
    int i;

    if (max_erase_block_size == NULL)
    {
        return -1;
    }

    for (i = 0; i < qspi_flash_erase_block_size_last; ++i)
    {
        BOOL is_supported;

        if (qspi_flash_get_erase_block_size_support((enum qspi_flash_erase_block_size) i, &is_supported) != 0)
        {
            return -1;
        }

        if (is_supported)
        {
            result = (enum qspi_flash_erase_block_size) i;
        }
    }

    if (result == qspi_flash_erase_block_size_last)
    {
        return -1;
    }

    *max_erase_block_size = result;
    return 0;
}

char get_erase_block_size_in_bytes(enum qspi_flash_erase_block_size erase_block_size, unsigned long * size)
{
    if (size == NULL)
    {
        return -1;
    }

    switch (erase_block_size)
    {
    case qspi_flash_erase_block_size_4k:
        *size = 1UL << 12;
        return 0;
    case qspi_flash_erase_block_size_32k:
        *size = 1UL << 15;
        return 0;
    case qspi_flash_erase_block_size_64k:
        *size = 1UL << 16;
        return 0;
    case qspi_flash_erase_block_size_256k:
        *size = 1UL << 18;
        return 0;
    default:
        return -1;
    }
}

