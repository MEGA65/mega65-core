#include <memory.h>
#include <stddef.h>

#include "qspihwassist.h"
#include "qspibitbash.h"

void hw_assisted_read_512(unsigned long address, unsigned char * data)
{
    // SPI command byte 0x6C.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x5f); // Set number of dummy cycles
    POKE(0xD680, 0x53); // QSPI Flash Sector read command

    // Wait for hardware assisted read operation to finish.
    while (PEEK(0xD680) & 1);

    // Copy data to buffer provided by the caller.
    if (data != NULL)
    {
        lcopy(0xFFD6E00L, (unsigned long)data, 512);
    }
}

char hw_assisted_verify_512(unsigned long address, const unsigned char * data)
{
    // SPI command byte 0x6C.
    lcopy((unsigned long)data, 0XFFD6E00L, 512);
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x5f); // Set number of dummy cycles
    POKE(0xD680, 0x56); // QSPI Flash Sector verify command

    // Wait for hardware assisted verify operation to finish.
    while (PEEK(0xD680) & 1);

    return (PEEK(0xD689) & 0x40) ? -1 : 0;
}

void hw_assisted_erase_parameter_sector(unsigned long address)
{
    // SPI command byte 0x21.
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xd680, 0x59);

    // Wait for hardware assisted erase operation to finish. Hardware assisted
    // erase operations finish as soon as the corresponding SPI command has
    // been transmitted to the flash device. The caller is responsible for
    // waiting until the flash device has finished the erase command by polling
    // the status register.
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

    // Wait for hardware assisted erase operation to finish. Hardware assisted
    // erase operations finish as soon as the corresponding SPI command has
    // been transmitted to the flash device. The caller is responsible for
    // waiting until the flash device has finished the erase command by polling
    // the status register.
    while (PEEK(0xD680) & 1);
}

void hw_assisted_program_page_256(unsigned long address, const unsigned char * data)
{
    // SPI command byte 0x34.
    // NB. Command 0x55 (U) writes the *last* 256 bytes of the SD card buffer to
    // flash!
    lcopy((unsigned long)data, 0XFFD6F00L, 256);
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x55);

    // Wait for hardware assisted program page operation to finish. Hardware
    // assisted program page operations finish as soon as the corresponding SPI
    // command has been transmitted to the flash device. The caller is
    // responsible for waiting until the flash device has finished the program
    // page command by polling the status register.
    while (PEEK(0xD680) & 1);
}

void hw_assisted_program_page_512(unsigned long address, const unsigned char * data)
{
    // SPI command byte 0x34.
    lcopy((unsigned long)data, 0XFFD6E00L, 512);
    POKE(0xD681, address >> 0);
    POKE(0xD682, address >> 8);
    POKE(0xD683, address >> 16);
    POKE(0xD684, address >> 24);
    POKE(0xD680, 0x54);

    // Wait for hardware assisted program page operation to finish. Hardware
    // assisted program page operations finish as soon as the corresponding SPI
    // command has been transmitted to the flash device. The caller is
    // responsible for waiting until the flash device has finished the program
    // page command by polling the status register.
    while (PEEK(0xD680) & 1);
}

// TODO: Function to read CFI block using SPI command 0x9B; POKE 0x6B to $D680.
//
// void hw_assisted_cfi_block_read(unsigned char *data)
// {
//     unsigned int i;
//     // SPI command byte 0x9B.
//     // Hardware acclerated CFI block read
//     POKE(0xD6CD, 0x02);
//     // spi_cs_high();
//     POKE(0xD680, 0x6B);
//     // Give time to complete
//     for (i = 0; i < 512; i++)
//     {
//         continue;
//     }
//     // spi_cs_high();
//
//     lcopy(0XFFD6E00L, (unsigned long)data, 512);
// }

// TODO: Function to set number of dummy cycles; POKE 0x5a .. 0x5f to $D680.
//
// when x"5a" => qspi_command_len <= 90;
// when x"5b" => qspi_command_len <= 92;
// when x"5c" => qspi_command_len <= 94;
// when x"5d" => qspi_command_len <= 96;
// when x"5e" => qspi_command_len <= 98;
// when x"5f" => qspi_command_len <= 100;

// TODO: Function to set write enable using SPI command 0x06; POKE 0x66 to $D680.

// TODO: Function to clear status register using SPI command 0x30; POKE 0x6a to $D680.
