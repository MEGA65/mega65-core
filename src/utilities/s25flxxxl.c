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

static unsigned char read_configuration_register_2(void)
{
    return spi_transaction_tx8rx8(0x15);
}

static unsigned char read_configuration_register_3(void)
{
    return spi_transaction_tx8rx8(0x33);
}

static void write_enable(void)
{
    spi_transaction_tx8(0x06);
}

static void clear_status_register(void)
{
    spi_transaction_tx8(0x30);
}

struct s25flxxxl_status
{
    unsigned char sr1;
    unsigned char sr2;
};

static struct s25flxxxl_status read_status(void)
{
    struct s25flxxxl_status status;
    status.sr1 = read_status_register_1();
    status.sr2 = read_status_register_2();
    return status;
}

#define erase_error_occurred(status) (status.sr2 & 0x40 ? TRUE : FALSE)

#define program_error_occurred(status) (status.sr2 & 0x20 ? TRUE : FALSE)

#define write_enabled(status) (status.sr1 & 0x02 ? TRUE : FALSE)

#define write_in_progress(status) (status.sr1 & 0x01 ? TRUE : FALSE)

#define busy(status) (status.sr1 & 0x03 ? TRUE : FALSE)

#define error_occurred(status) (status.sr2 & 0x60 ? TRUE : FALSE)

static void clear_status(void)
{
    struct s25flxxxl_status status;
    for (;;)
    {
        status = read_status();
        if (!busy(status) && !error_occurred(status))
        {
            break;
        }
        clear_status_register();
    }
}

static char wait_status(void)
{
    struct s25flxxxl_status status;
    for (;;)
    {
        status = read_status();
        if (!busy(status))
        {
            break;
        }
    }

    return (error_occurred(status) ? 1 : 0);
}

struct s25flxxxl
{
    // Interface.
    const struct qspi_flash_interface interface;
    // Attributes.
    unsigned int size;
    unsigned char read_latency_cycles;
};

static char s25flxxxl_reset(void * qspi_flash_device)
{
    (void) qspi_flash_device;

    // Ensure SPI bus is in idle state.
    spi_cs_high();
    spi_clock_high();

    // Wait a while.
    usleep(10000);

    // Transmit idle clock pulses to get the attention of the flash chip.
    spi_idle_clocks(255);

    // Reset enable.
    spi_transaction_tx8(0x66);

    // Reset.
    spi_transaction_tx8(0x99);

    // Wait a while.
    usleep(10000);

    return 0;
}

static void volatile_write_enable(void)
{
    spi_transaction_tx8(0x50);
}

static char enable_quad_mode(void)
{
    unsigned char spi_tx[] = {0x01, 0x00, 0x00};

    spi_tx[1] = read_status_register_1();
    spi_tx[2] = read_configuration_register_1();
    spi_tx[2] |= 0x02;

    volatile_write_enable();
    spi_transaction(spi_tx, 3, NULL, 0);

    return wait_status();
}

static char s25flxxxl_init(void * qspi_flash_device)
{
    struct s25flxxxl * self = (struct s25flxxxl *) qspi_flash_device;
    const uint8_t spi_tx[] = {0x9f};
    uint8_t spi_rx[] = {0x00, 0x00, 0x00};
    unsigned char cr1, cr3;
    BOOL quad_mode_enabled;

    if (s25flxxxl_reset(qspi_flash_device) != 0)
    {
        return 1;
    }

#ifdef QSPI_VERBOSE
    mhx_writef("Registers = %02X %02X %02X %02X %02X\n", read_status_register_1(), read_status_register_2(), read_configuration_register_1(),
        read_configuration_register_2(), read_configuration_register_3());
#endif

    // Read RDID to confirm model and get density.
    spi_transaction(spi_tx, 1, spi_rx, 3);

#ifdef QSPI_VERBOSE
    mhx_writef("CFI = %02X %02X %02X\n", spi_rx[0], spi_rx[1], spi_rx[2]);
#endif

    if (spi_rx[0] != 0x01 || spi_rx[1] != 0x60)
    {
        return 1;
    }

    if (spi_rx[2] == 0x18)
    {
        // 128 Mb == 16 MB.
        self->size = 16;
    }
    else if (spi_rx[2] == 0x19)
    {
        // 256 Mb == 32 MB.
        self->size = 32;
    }
    else
    {
        return 1;
    }

    cr3 = read_configuration_register_3();
    self->read_latency_cycles = cr3 & 0x0f;

    cr1 = read_configuration_register_1();
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
    mhx_writef("Quad mode = %d\n", quad_mode_enabled ? 1 : 0);
    mhx_writef("Registers = %02X %02X %02X %02X %02X\n", read_status_register_1(), read_status_register_2(), read_configuration_register_1(),
        read_configuration_register_2(), read_configuration_register_3());
#endif

    return 0;
}

static char s25flxxxl_read(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
#ifdef QSPI_HW_ASSIST
    if (size == 512)
    {
        // Use hardware acceleration if possible.
        hw_assisted_read_512(address, data);
    }
    else
#endif
    {
        const struct s25flxxxl * self = (const struct s25flxxxl *) qspi_flash_device;

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
        if (data == NULL)
        {
            unsigned int i;

            for (i = 0; i < size; ++i)
            {
                qspi_rx_byte();
            }
        }
        else
        {
            unsigned int i;

            for (i = 0; i < size; ++i)
            {
                data[i] = qspi_rx_byte();
            }
        }
        spi_cs_high();
        spi_clock_high();
    }

    return 0;
}

static char s25flxxxl_verify(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    char result = 0;

    if (data == NULL)
    {
        // Invalid data pointer.
        return 1;
    }

#ifdef QSPI_HW_ASSIST
    if (size == 512)
    {
        // Use hardware acceleration if possible.
        result = hw_assisted_verify_512(address, data);
    }
    else
#endif
    {
        const struct s25flxxxl * self = (const struct s25flxxxl *) qspi_flash_device;
        unsigned int i;

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
                result = 1;
                break;
            }
        }
        spi_cs_high();
        spi_clock_high();
    }

    return result;
}

static char s25flxxxl_erase(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, unsigned long address)
{
    (void) qspi_flash_device;

#ifdef QSPI_HW_ASSIST
    // Use hardware acceleration if possible (4K and 64K sectors).
    if (erase_block_size == qspi_flash_erase_block_size_4k || erase_block_size == qspi_flash_erase_block_size_64k)
    {
        clear_status();
        write_enable();
        if (erase_block_size == qspi_flash_erase_block_size_4k)
        {
            hw_assisted_erase_parameter_sector(address);
        }
        else
        {
            hw_assisted_erase_sector(address);
        }
        return wait_status();
    }
#else
    if (erase_block_size == qspi_flash_erase_block_size_4k)
    {
        unsigned char spi_tx[5];

        spi_tx[0] = 0x21;
        spi_tx[1] = address >> 24;
        spi_tx[2] = address >> 16;
        spi_tx[3] = address >> 8;
        spi_tx[4] = address >> 0;

        clear_status();
        write_enable();
        spi_transaction(spi_tx, 5, NULL, 0);
        return wait_status();
    }

    if (erase_block_size == qspi_flash_erase_block_size_64k)
    {
        unsigned char spi_tx[5];

        spi_tx[0] = 0xDC;
        spi_tx[1] = address >> 24;
        spi_tx[2] = address >> 16;
        spi_tx[3] = address >> 8;
        spi_tx[4] = address >> 0;

        clear_status();
        write_enable();
        spi_transaction(spi_tx, 5, NULL, 0);
        return wait_status();
    }
#endif

    // Use a software implementation for 32K sectors.
    if (erase_block_size == qspi_flash_erase_block_size_32k)
    {
        unsigned char spi_tx[5];

        spi_tx[0] = 0x53;
        spi_tx[1] = address >> 24;
        spi_tx[2] = address >> 16;
        spi_tx[3] = address >> 8;
        spi_tx[4] = address >> 0;

        clear_status();
        write_enable();
        spi_transaction(spi_tx, 5, NULL, 0);
        return wait_status();
    }

    return 1;
}

static char s25flxxxl_program(void * qspi_flash_device, enum qspi_flash_page_size page_size, unsigned long address, const unsigned char * data)
{
    unsigned int i = 0;

    (void) qspi_flash_device;

    if (page_size != qspi_flash_page_size_256)
    {
        return 1;
    }

    if (data == NULL)
    {
        return 1;
    }

    clear_status();
    write_enable();
#ifdef QSPI_HW_ASSIST
    hw_assisted_program_page_256(address, data);
#else
    spi_clock_high();
    spi_cs_low();
    spi_output_enable();
    spi_tx_byte(0x34);
    spi_tx_byte(address >> 24);
    spi_tx_byte(address >> 16);
    spi_tx_byte(address >> 8);
    spi_tx_byte(address >> 0);
    for (i = 0; i < 256; ++i)
    {
        qspi_tx_byte(data[i]);
    }
    spi_output_disable();
    spi_cs_high();
    spi_clock_high();
#endif
    return wait_status();
}

/*
static char s25flxxxl_get_manufacturer(void * qspi_flash_device, const char ** manufacturer)
{
    (void) qspi_flash_device;
    *manufacturer = "Infineon";
    return 0;
}
*/

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
    // s25flxxxl_get_manufacturer,
    s25flxxxl_get_size,
    s25flxxxl_get_page_size,
    s25flxxxl_get_erase_block_size_support
}};

void * s25flxxxl = & _s25flxxxl;
