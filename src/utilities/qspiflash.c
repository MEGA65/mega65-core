#include <stddef.h>

#include "qspiflash.h"
#include "s25flxxxl.h"
#include "s25flxxxs.h"

char qspi_flash_init(void * qspi_flash_device)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->init == NULL)
    {
        return -1;
    }
    return interface->init(qspi_flash_device);
}

char qspi_flash_read(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->read == NULL)
    {
        return -1;
    }
    return interface->read(qspi_flash_device, address, data, size);
}

char qspi_flash_verify(void * qspi_flash_device, unsigned long address, unsigned char * data, unsigned int size)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->verify == NULL)
    {
        return -1;
    }
    return interface->verify(qspi_flash_device, address, data, size);
}

char qspi_flash_erase(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, unsigned long address)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->erase == NULL)
    {
        return -1;
    }
    return interface->erase(qspi_flash_device, erase_block_size, address);
}

char qspi_flash_program(void * qspi_flash_device, enum qspi_flash_page_size page_size, unsigned long address, const unsigned char * data)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->program == NULL)
    {
        return -1;
    }
    return interface->program(qspi_flash_device, page_size, address, data);
}

char qspi_flash_get_manufacturer(void * qspi_flash_device, const char ** manufacturer)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->get_manufacturer == NULL)
    {
        return -1;
    }
    return interface->get_manufacturer(qspi_flash_device, manufacturer);
}

char qspi_flash_get_size(void * qspi_flash_device, unsigned int * size)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->get_size == NULL)
    {
        return -1;
    }
    return interface->get_size(qspi_flash_device, size);
}

char qspi_flash_get_page_size(void * qspi_flash_device, enum qspi_flash_page_size * page_size)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->get_page_size == NULL)
    {
        return -1;
    }
    return interface->get_page_size(qspi_flash_device, page_size);
}

char qspi_flash_get_erase_block_size_support(void * qspi_flash_device, enum qspi_flash_erase_block_size erase_block_size, BOOL * is_supported)
{
    const struct qspi_flash_interface * interface = qspi_flash_device;
    if (interface == NULL || interface->get_erase_block_size_support == NULL)
    {
        return -1;
    }
    return interface->get_erase_block_size_support(qspi_flash_device, erase_block_size, is_supported);
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

char get_page_size_in_bytes(enum qspi_flash_page_size page_size, unsigned int * size)
{
    if (size == NULL)
    {
        return -1;
    }

    switch (page_size)
    {
    case qspi_flash_page_size_256:
        *size = 256;
        return 0;
    case qspi_flash_page_size_512:
        *size = 512;
        return 0;
    default:
        return -1;
    }
}

char get_max_erase_block_size(void * qspi_flash_device, enum qspi_flash_erase_block_size * max_erase_block_size)
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

        if (qspi_flash_get_erase_block_size_support(qspi_flash_device, (enum qspi_flash_erase_block_size) i, &is_supported) != 0)
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
