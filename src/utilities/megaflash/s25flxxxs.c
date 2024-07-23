#include <hal.h>
#include <memory.h>
#include <stdio.h>

#include "qspiflash.h"
#include "qspihwassist.h"
#include "qspibitbash.h"

#include "mhexes.h"

static unsigned char read_status_register_1(void)
{
    return spi_transaction_tx8rx8(0x05);
}

static unsigned char read_status_register_2(void)
{
    return spi_transaction_tx8rx8(0x07);
}

static unsigned char read_configuration_register_1(void)
{
    return spi_transaction_tx8rx8(0x35);
}

static void write_enable(void)
{
    spi_transaction_tx8(0x06);
}

static void write_disable(void)
{
    spi_transaction_tx8(0x04);
}

static void clear_status_register(void)
{
    spi_transaction_tx8(0x30);
}

struct s25flxxxs_status
{
    unsigned char sr1;
    unsigned char sr2;
};

static struct s25flxxxs_status read_status(void)
{
    struct s25flxxxs_status status;
    status.sr1 = read_status_register_1();
    status.sr2 = read_status_register_2();
    return status;
}

#define erase_error_occurred(status) (status->sr1 & 0x20 ? TRUE : FALSE)

#define program_error_occurred(status) (status->sr1 & 0x40 ? TRUE : FALSE)

#define write_enabled(status) (status.sr1 & 0x02 ? TRUE : FALSE)

#define write_in_progress(status) (status.sr1 & 0x01 ? TRUE : FALSE)

#define error_occurred(status) (status.sr1 & 0x60 ? TRUE : FALSE)

#define dyb_lock_boot_enabled(aspr) (aspr & 0x10 ? FALSE : TRUE)

static void clear_status(void)
{
    struct s25flxxxs_status status;

    // In the event of an error, the flash chip remains busy. That is, the Write
    // In Progress (WIP) bit in the status register remains set while the
    // Program Error (P_ERR) bit and/or the Erase Error (E_ERR) bit in the
    // status register is set. The Clear Status Register command resets both
    // error bits, which in turn allows the WIP bit to clear.
    //
    // However, the Clear Status Register command does *not* affect the Write
    // Enable Latch (WEL) bit. This bit needs to be cleared using the Write
    // Disable command, which is ignored while the WIP bit is set.
    //
    // Therefore, the proper sequence is to issue the Clear Status Register to
    // clear the error bits, allowing the WIP bit to clear, and then issue the
    // Write Disable command to clear the WEL bit.

    for (status = read_status(); error_occurred(status) || write_in_progress(status); status = read_status())
    {
        clear_status_register();
    }

    for (status = read_status(); write_enabled(status); status = read_status())
    {
        write_disable();
    }
}

static char wait_status(void)
{
    struct s25flxxxs_status status;

    for (status = read_status(); write_enabled(status) || write_in_progress(status); status = read_status())
    {
        if (error_occurred(status))
        {
            clear_status();
            return 1;
        }
    }

    return 0;
}

static char enable_quad_mode(void)
{
    unsigned char spi_tx[] = {0x01, 0x00, 0x00};

    spi_tx[1] = read_status_register_1();
    spi_tx[2] = read_configuration_register_1();
    spi_tx[2] |= 0x02;

    clear_status();
    write_enable();
    spi_transaction(spi_tx, 3, NULL, 0);

    return wait_status();
}

static uint16_t read_asp_register()
{
    unsigned char spi_tx[] = {0x2b};
    unsigned char spi_rx[] = {0x00, 0x00};
    spi_transaction(spi_tx, 1, spi_rx, 2);
    return (((uint16_t) spi_rx[1]) << 8) + spi_rx[0];
}

static char write_dynamic_protection_bits(unsigned long address, BOOL protect)
{
    unsigned char spi_tx[6];

    spi_tx[0] = 0xe1;
    spi_tx[1] = address >> 24;
    spi_tx[2] = address >> 16;
    spi_tx[3] = address >> 8;
    spi_tx[4] = address >> 0;
    spi_tx[5] = protect ? 0 : 255;

    clear_status();
    write_enable();
    spi_transaction(spi_tx, 6, NULL, 0);

    return wait_status();
}

struct s25flxxxs
{
    // Interface.
    const struct qspi_flash_interface interface;
    // Attributes.
    unsigned int size;
    unsigned char read_latency_cycles;
    enum qspi_flash_erase_block_size erase_block_size;
    enum qspi_flash_page_size page_size;
    BOOL dyb_lock_boot_enabled;
};

static char s25flxxxs_reset(void * qspi_flash_device)
{
    (void) qspi_flash_device;

    spi_cs_high();
    spi_clock_high();

    usleep(10000);

    // Allow lots of clock ticks to get attention of SPI
    spi_idle_clocks(255);

    // Reset.
    spi_transaction_tx8(0xf0);

    usleep(10000);

    return 0;
}

static char s25flxxxs_init(void * qspi_flash_device)
{
    struct s25flxxxs * self = (struct s25flxxxs *) qspi_flash_device;
    const uint8_t spi_tx[] = {0x9f};
    uint8_t spi_rx[5] = {0x00};
    unsigned char cr1;
    uint16_t aspr;
    BOOL quad_mode_enabled;

    // Software reset.
    if (s25flxxxs_reset(qspi_flash_device) != 0)
    {
        return 1;
    }

#ifdef QSPI_VERBOSE
    mhx_writef("Registers = %02X %02X %02X\n", read_status_register_1(), read_status_register_2(), read_configuration_register_1());
#endif

    // Read RDID to confirm manufacturer and model, and get density.
    spi_transaction(spi_tx, 1, spi_rx, 5);

#ifdef QSPI_VERBOSE
    mhx_writef("CFI = %02X %02X %02X %02X %02X\n", spi_rx[0], spi_rx[1], spi_rx[2], spi_rx[3], spi_rx[4]);
#endif

    if (spi_rx[0] != 0x01)
    {
        return 1;
    }

    if (spi_rx[1] == 0x20 && spi_rx[2] == 0x18)
    {
        // 128 Mb == 16 MB.
        self->size = 16;
    }
    else if (spi_rx[1] == 0x02 && spi_rx[2] == 0x19)
    {
        // 256 Mb == 32 MB.
        self->size = 32;
    }
    else if (spi_rx[1] == 0x02 && spi_rx[2] == 0x20)
    {
        // 512 Mb == 64 MB.
        self->size = 64;
    }
    else
    {
        return 1;
    }

    // Determine sector architecture and page buffer size.
    if (spi_rx[4] == 0x00)
    {
        // Uniform 256K sectors, 512 byte page buffer.
        self->erase_block_size = qspi_flash_erase_block_size_256k;
        self->page_size = qspi_flash_page_size_512;
    }
    else if (spi_rx[4] == 0x01)
    {
        // Mixed 4K / 64K sectors, 256 byte page buffer.
        self->erase_block_size = qspi_flash_erase_block_size_64k;
        self->page_size = qspi_flash_page_size_256;
    }
    else
    {
        return 1;
    }

    // Determine latency cycle count.
    cr1 = read_configuration_register_1();
    self->read_latency_cycles = ((cr1 >> 6) == 3) ? 0 : 8;

    // Determine if DYB lock boot is enabled.
    aspr = read_asp_register();
#ifdef QSPI_VERBOSE
    mhx_writef("ASPR = %04X\n", aspr);
#endif
    self->dyb_lock_boot_enabled = dyb_lock_boot_enabled(aspr);

    // Enable quad mode if it is not enabled, and verify.
    quad_mode_enabled = cr1 & 0x02;
    if (!quad_mode_enabled)
    {
        if (enable_quad_mode() != 0)
        {
            return 1;
        }
        cr1 = read_configuration_register_1();
        quad_mode_enabled = cr1 & 0x02;
        if (!quad_mode_enabled)
        {
            return 1;
        }
    }

#ifdef QSPI_VERBOSE
    mhx_writef("Flash size = %d MB\n", self->size);
    mhx_writef("Latency cycles = %d\n", self->read_latency_cycles);
    mhx_writef("Sector size (K) = %d\n", (self->erase_block_size == qspi_flash_erase_block_size_256k) ? 256 : 64);
    mhx_writef("Page size = %d\n", (self->page_size == qspi_flash_page_size_256) ? 256 : 512);
    mhx_writef("DYB lock boot = %d\n", self->dyb_lock_boot_enabled ? 1 : 0);
    mhx_writef("Quad mode = %d\n", quad_mode_enabled ? 1 : 0);
    mhx_writef("Registers = %02X %02X %02X\n", read_status_register_1(), read_status_register_2(), read_configuration_register_1());
#endif

    return 0;
}

static char s25flxxxs_read(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
#ifndef QSPI_NO_BIT_BASH
    unsigned int i;
#endif

    if (data == NULL)
    {
        // Invalid data pointer.
        return 1;
    }

#ifdef QSPI_HW_ASSIST
#if defined(STANDALONE) && !defined(QSPI_NO_BIT_BASH)
    if (!qspi_force_bitbash && size == 512)
#else
    if (size == 512)
#endif
    {
        // Use hardware acceleration if possible.
        return hw_assisted_read_512(address, data, self->read_latency_cycles);
    }
#endif

#ifndef QSPI_NO_BIT_BASH
    spi_clock_high();
    spi_cs_low();
    spi_output_enable();
    spi_tx_byte(0x6c);
    spi_tx_byte(address >> 24);
    spi_tx_byte(address >> 16);
    spi_tx_byte(address >> 8);
    spi_tx_byte(address >> 0);
    spi_output_disable();
    spi_idle_clocks(self->read_latency_cycles);
    for (i = 0; i < size; ++i)
    {
        data[i] = qspi_rx_byte();
    }
    spi_cs_high();
    spi_clock_high();
    return 0;
#else
    return 1;
#endif
}

static char s25flxxxs_verify(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
#ifndef QSPI_NO_BIT_BASH
    unsigned int i;
#endif

    if (data == NULL)
    {
        // Invalid data pointer.
        return 1;
    }

#ifdef QSPI_HW_ASSIST
#if defined(STANDALONE) && !defined(QSPI_NO_BIT_BASH)
    if (!qspi_force_bitbash && size == 512)
#else
    if (size == 512)
#endif
    {
        // Use hardware acceleration if possible.
        return hw_assisted_verify_512(address, data, self->read_latency_cycles);
    }
#endif

#ifndef QSPI_NO_BIT_BASH
    spi_clock_high();
    spi_cs_low();
    spi_output_enable();
    spi_tx_byte(0x6c);
    spi_tx_byte(address >> 24);
    spi_tx_byte(address >> 16);
    spi_tx_byte(address >> 8);
    spi_tx_byte(address >> 0);
    spi_output_disable();
    spi_idle_clocks(self->read_latency_cycles);
    for (i = 0; i < size; ++i)
    {
        if (qspi_rx_byte() != data[i])
        {
            return 1;
        }
    }
    spi_cs_high();
    spi_clock_high();
    return 0;
#else
    return 1;
#endif
}

static char s25flxxxs_erase(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, unsigned long address)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
#ifndef QSPI_NO_BIT_BASH
    unsigned char spi_tx[5];
#endif

    // Check pre-condition.
    if (erase_block_size != self->erase_block_size)
    {
        return 1;
    }

    // Disable dynamic sector protection for the sector.
    if (self->dyb_lock_boot_enabled)
    {
        if (erase_block_size == qspi_flash_erase_block_size_256k)
        {
            if (write_dynamic_protection_bits((address >> 18) << 18, FALSE) != 0)
            {
                return 1;
            }
        }
        else
        {
            // The combination of DYB lock boot and a 64K/4K mixed sector
            // architecture is currently not supported.
            return 1;
        }
    }

    clear_status();
    write_enable();

#ifdef QSPI_HW_ASSIST
#ifdef STANDALONE
    if (!qspi_force_bitbash) {
#else
    if (1) {
#endif
        hw_assisted_erase_sector(address);
    }
#endif

#ifndef QSPI_NO_BIT_BASH
#ifdef QSPI_HW_ASSIST
    else {
#else
    {
#endif
        spi_tx[0] = 0xdc;
        spi_tx[1] = address >> 24;
        spi_tx[2] = address >> 16;
        spi_tx[3] = address >> 8;
        spi_tx[4] = address >> 0;

        spi_transaction(spi_tx, 5, NULL, 0);
    }
#endif
    return wait_status();
}

static char s25flxxxs_program(void * qspi_flash_device, enum qspi_flash_page_size page_size, unsigned long address, const unsigned char * data)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
#ifndef QSPI_NO_BIT_BASH
    unsigned int page_size_bytes = (page_size == qspi_flash_page_size_256) ? 256 : 512;
    unsigned int i;
#endif

    if (page_size == qspi_flash_page_size_512 && self->page_size == qspi_flash_page_size_256)
    {
        // Unsupported page size.
        return 1;
    }

    if (data == NULL)
    {
        // Invalid data pointer.
        return 1;
    }

    if (address & 0xff)
    {
        // Address not aligned to page boundary.
        return 1;
    }

    if ((address & 0x1ff) && (page_size != qspi_flash_page_size_256))
    {
        // Address not aligned to page boundary.
        return 1;
    }

    clear_status();
    write_enable();

#ifdef QSPI_HW_ASSIST
#ifdef STANDALONE
    if (!qspi_force_bitbash) {
#else
    if (1) {
#endif
        if (page_size == qspi_flash_page_size_256)
        {
            hw_assisted_program_page_256(address, data);
        }
        else
        {
            hw_assisted_program_page_512(address, data);
        }
    }
#endif

#ifndef QSPI_NO_BIT_BASH
#ifdef QSPI_HW_ASSIST
    else {
#else
    {
#endif
        spi_clock_high();
        spi_cs_low();
        spi_output_enable();
        spi_tx_byte(0x34);
        spi_tx_byte(address >> 24);
        spi_tx_byte(address >> 16);
        spi_tx_byte(address >> 8);
        spi_tx_byte(address >> 0);
        for (i = 0; i < page_size_bytes; ++i)
        {
            qspi_tx_byte(data[i]);
        }
        spi_output_disable();
        spi_cs_high();
        spi_clock_high();
    }
#endif
    return wait_status();
}

static char s25flxxxs_get_size(void * qspi_flash_device, unsigned int * size)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
    *size = self->size;
    return 0;
}

static char s25flxxxs_get_page_size(void * qspi_flash_device, enum qspi_flash_page_size * page_size)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
    *page_size = self->page_size;
    return 0;
}

static char s25flxxxs_get_erase_block_size_support(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported)
{
    const struct s25flxxxs * self = (const struct s25flxxxs *) qspi_flash_device;
    *is_supported = (self->erase_block_size == erase_block_size);
    return 0;
}

static struct s25flxxxs _s25flxxxs = {{
    s25flxxxs_init,
    s25flxxxs_read,
    s25flxxxs_verify,
    s25flxxxs_erase,
    s25flxxxs_program,
    s25flxxxs_get_size,
    s25flxxxs_get_page_size,
    s25flxxxs_get_erase_block_size_support
}};

void * s25flxxxs = & _s25flxxxs;
