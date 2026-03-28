#include <hal.h>
#include <memory.h>
#include <stdio.h>

#include "qspiflash.h"
#include "qspihwassist.h"
#include "qspibitbash.h"

#include "mhexes.h"

/*
 * Address of buffer used by hardware QSPI flash controller.
 */
#define QSPI_FLASH_BUFFER            (0xFFD6A00L)

struct s25flxxxl
{
    // Interface.
    const struct qspi_flash_interface interface;
    // Attributes.
    unsigned int size;
    unsigned char read_latency_cycles;
};

static char s25flxxxl_init(void * qspi_flash_device)
{
    struct s25flxxxl * self = (struct s25flxxxl *) qspi_flash_device;

    POKE(0xD680, 0x50);
    while (PEEK(0xD6CC) & 1);
    if (PEEK(0xD6CC) & 0x0F)
    {
        return 1;
    }

    self->size = PEEK(0xD6C2);

#ifdef QSPI_VERBOSE
    mhx_writef("Flash size = %d MB\n", self->size);
    // mhx_writef("Latency cycles = %d\n", self->read_latency_cycles);
    // mhx_writef("Quad mode = %d\n", quad_mode_enabled ? 1 : 0);
    // mhx_writef("Registers = %02X %02X %02X %02X %02X\n", read_status_register_1(), read_status_register_2(), read_configuration_register_1(),
    //     read_configuration_register_2(), read_configuration_register_3());
#endif

    return 0;
}

static char s25flxxxl_read(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    if (data == NULL)
    {
        // Invalid data pointer.
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
    POKE(0xD680, 0x51);

    // Wait for hardware assisted read operation to finish.
    while (PEEK(0xD6CC) & 1);
    if (PEEK(0xD6CC) & 0x0F)
    {
        return 1;
    }

    // Copy data to buffer provided by the caller.
    if (data != NULL)
    {
        lcopy(QSPI_FLASH_BUFFER, (unsigned long)data, size);
    }

    return 0;
}

static char s25flxxxl_verify(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    if (data == NULL)
    {
        // Invalid data pointer.
        return 1;
    }

    if (size > 512)
    {
        return 1;
    }

    // Copy expected data to the buffer used by the hardware QSPI flash
    // controller.
    lcopy((unsigned long)data, QSPI_FLASH_BUFFER, size);

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD6CD, size >> 0);
    POKE(0xD6CE, size >> 8);
    POKE(0xD680, 0x53);

    // Wait for hardware assisted read operation to finish.
    while (PEEK(0xD6CC) & 1);

    return (PEEK(0xD6CC) & 0x1F) ? 1 : 0;
}

static char s25flxxxl_erase(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, unsigned long address)
{
    unsigned char erase_command;

    (void) qspi_flash_device;

    if (erase_block_size == qspi_flash_erase_block_size_4k)
        erase_command = 0x54;
    else if (erase_block_size == qspi_flash_erase_block_size_32k)
        erase_command = 0x55;
    else if (erase_block_size == qspi_flash_erase_block_size_64k)
        erase_command = 0x56;
    else
        return 1;

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, erase_command);

    // Wait for hardware assisted read operation to finish.
    while (PEEK(0xD6CC) & 1);

    return (PEEK(0xD6CC) & 0x0F) ? 1 : 0;
}

static char s25flxxxl_program(void * qspi_flash_device, unsigned long address, const unsigned char * data, unsigned int size)
{
    if (size > 512)
    {
        return 1;
    }

    if (data == NULL)
    {
        return 1;
    }

    // Copy expected data to the buffer used by the hardware QSPI flash
    // controller.
    lcopy((unsigned long)data, QSPI_FLASH_BUFFER, size);

    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD6CD, size >> 0);
    POKE(0xD6CE, size >> 8);
    POKE(0xD680, 0x52);

    // Wait for hardware assisted read operation to finish.
    while (PEEK(0xD6CC) & 1);

    return (PEEK(0xD6CC) & 0x0F) ? 1 : 0;
}

static char s25flxxxl_get_size(void * qspi_flash_device, unsigned int * size)
{
    const struct s25flxxxl * self = (const struct s25flxxxl *) qspi_flash_device;
    *size = self->size;
    return 0;
}

static char s25flxxxl_get_page_size(void * qspi_flash_device, enum qspi_flash_page_size * page_size)
{
    (void) qspi_flash_device;
    *page_size = qspi_flash_page_size_256;
    return 0;
}

static char s25flxxxl_get_erase_block_size_support(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported)
{
    (void) qspi_flash_device;
    *is_supported = (erase_block_size == qspi_flash_erase_block_size_4k || erase_block_size == qspi_flash_erase_block_size_32k || erase_block_size == qspi_flash_erase_block_size_64k);
    return 0;
}

static struct s25flxxxl _s25flxxxl = {{
    s25flxxxl_init,
    s25flxxxl_read,
    s25flxxxl_verify,
    s25flxxxl_erase,
    s25flxxxl_program,
    s25flxxxl_get_size,
    s25flxxxl_get_page_size,
    s25flxxxl_get_erase_block_size_support
}};

void * s25flxxxl = & _s25flxxxl;
