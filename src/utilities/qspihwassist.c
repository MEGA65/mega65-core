#include <memory.h>
#include <stddef.h>

#include "qspihwassist.h"

/*
 * Address of buffer used by hardware QSPI flash controller.
 */
#define QSPI_FLASH_BUFFER            (0xFFD6E00L)
#define QSPI_FLASH_BUFFER_UPPER_PAGE (QSPI_FLASH_BUFFER + 0x100)

/*
 * Set the number of read latency cycles used by the hardware QSPI flash
 * controller. Any number between 3 and 8 is supported.
 */
static char hw_set_latency_cycles(unsigned char num_latency_cycles)
{
    if (num_latency_cycles < 3 || num_latency_cycles > 8) return 1;
    POKE(0xD680, 0x5A + (num_latency_cycles - 3));
    return 0;
}

char hw_assisted_read_512(unsigned long address, unsigned char * data, unsigned char num_latency_cycles)
{
    // Set the nymber of latency cycles.
    if (hw_set_latency_cycles(num_latency_cycles) != 0)
    {
        return 1;
    }

    // SPI command byte 0x6C.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x53);

    // Wait for hardware assisted read operation to finish.
    while (PEEK(0xD680) & 1);

    // Copy data to buffer provided by the caller.
    if (data != NULL)
    {
        lcopy(QSPI_FLASH_BUFFER, (unsigned long)data, 512);
    }

    return 0;
}

char hw_assisted_verify_512(unsigned long address, const unsigned char * data, unsigned char num_latency_cycles)
{
    // Set the nymber of latency cycles.
    if (hw_set_latency_cycles(num_latency_cycles) != 0)
    {
        return 1;
    }

    // Copy expected data to the buffer used by the hardware QSPI flash
    // controller.
    lcopy((unsigned long)data, QSPI_FLASH_BUFFER, 512);

    // SPI command byte 0x6C.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x56);

    // Wait for hardware assisted verify operation to finish.
    while (PEEK(0xD680) & 1);

    // Return the result to the caller.
    return (PEEK(0xD689) & 0x40) ? 1 : 0;
}

void hw_assisted_erase_parameter_sector(unsigned long address)
{
    // SPI command byte 0x21.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xd680, 0x59);

    // Wait for the hardware QSPI flash controller to tranmit the erase command
    // to the flash device.
    while (PEEK(0xD680) & 1);
}

void hw_assisted_erase_sector(unsigned long address)
{
    // SPI command byte 0xDC.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xd680, 0x58);

    // Wait for the hardware QSPI flash controller to tranmit the erase command
    // to the flash device.
    while (PEEK(0xD680) & 1);
}

void hw_assisted_program_page_256(unsigned long address, const unsigned char * data)
{
    // Copy data to the upper 256 bytes of the 512 byte buffer used by the
    // hardware QSPI flash controller. (Command 0x55 writes the upper 256 bytes
    // of the buffer to flash.)
    lcopy((unsigned long)data, QSPI_FLASH_BUFFER_UPPER_PAGE, 256);

    // SPI command byte 0x34.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x55);

    // Wait for the hardware QSPI flash controller to tranmit the program page
    // command to the flash device.
    while (PEEK(0xD680) & 1);
}

void hw_assisted_program_page_512(unsigned long address, const unsigned char * data)
{
    // Copy data to the buffer used by the hardware QSPI flash controller.
    lcopy((unsigned long)data, QSPI_FLASH_BUFFER, 512);

    // SPI command byte 0x34.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x54);

    // Wait for the hardware QSPI flash controller to tranmit the program page
    // command to the flash device.
    while (PEEK(0xD680) & 1);
}
