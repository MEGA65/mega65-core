#ifndef MF_FLASH_H
#define MF_FLASH_H 1

#include <stdint.h>

/*
 * QSPI Flash Buffer Address
 */
#define QSPI_FLASH_BUFFER 0xFFD6E00L

extern void * qspi_flash_device;

extern unsigned char slot_count;
extern unsigned char flash_sector_bits;
extern unsigned int num_4k_sectors;

unsigned char probe_qspi_flash(void);

void read_data(unsigned long start_address);
unsigned char verify_data_in_place(unsigned long start_address);

void program_page(unsigned long start_address, unsigned int page_size);
void erase_sector(unsigned long address_in_sector);

#endif /* MF_FLASH_H */
