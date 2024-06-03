#include <string.h>
#include <memory.h>

#include "mhexes.h"
// #include <cbm_screen_charmap.h>

#include "qspiflash.h"
#include "s25flxxxl.h"
#include "s25flxxxs.h"

#include "mf_flash.h"
#include "mf_buffers.h"
#include "mf_utility.h"

unsigned char slot_count = 0;
unsigned int num_4k_sectors = 0;
unsigned char flash_sector_bits = 0;

void * qspi_flash_device = NULL;

unsigned char probe_qspi_flash(void)
{
  uint8_t i;
  // const char * manufacturer = NULL;
  unsigned int size;
  enum qspi_flash_page_size page_size;
  unsigned int page_size_bytes;
  BOOL erase_block_sizes[qspi_flash_erase_block_size_last];

  mhx_writef("\nHardware model = %s\n\n", hw_model_name);

  // Return an error for hardware models that do not have a flash chip.
  if (hw_model_id == 0x00 || hw_model_id == 0xFE) {
    return -1;
  }

  // Select the flash chip driver based on the hardware model ID.
#if defined(QSPI_STANDALONE)
  if (hw_model_id == 0x60 || hw_model_id == 0x61 || hw_model_id == 0x62 || hw_model_id == 0xFD) {
    qspi_flash_device = s25flxxxl;
  }
  else {
    qspi_flash_device = s25flxxxs;
  }
#elif defined(QSPI_S25FLXXXL)
  qspi_flash_device = s25flxxxl;
#elif defined(QSPI_S25FLXXXS)
  qspi_flash_device = s25flxxxs;
#else
#error "failed to select low level flash device"
#endif

  mhx_writef("Probing flash...");

  if (qspi_flash_init(qspi_flash_device))
  {
    mhx_writef(MHX_W_RED " ERROR" MHX_W_WHITE "\n\n");
    return -1;
  }
  mhx_writef(" OK\n\n");

  // if (qspi_flash_get_manufacturer(qspi_flash_device, &manufacturer) != 0)
  // {
  //   return -1;
  // }

  if (qspi_flash_get_size(qspi_flash_device, &size) != 0)
  {
    return -1;
  }

  if (qspi_flash_get_page_size(qspi_flash_device, &page_size) != 0)
  {
    return -1;
  }

  if (get_page_size_in_bytes(page_size, &page_size_bytes) != 0)
  {
    return -1;
  }

  for (i = 0; i < qspi_flash_erase_block_size_last; ++i)
  {
    if (qspi_flash_get_erase_block_size_support(qspi_flash_device, (enum qspi_flash_erase_block_size) i, &erase_block_sizes[i]) != 0)
    {
      return -1;
    }
  }

  slot_count = size / SLOT_MB;

  num_4k_sectors = 0;

  if (erase_block_sizes[qspi_flash_erase_block_size_4k])
    flash_sector_bits = 12;
  if (erase_block_sizes[qspi_flash_erase_block_size_32k])
    flash_sector_bits = 15;
  if (erase_block_sizes[qspi_flash_erase_block_size_64k])
    flash_sector_bits = 16;
  if (erase_block_sizes[qspi_flash_erase_block_size_256k])
    flash_sector_bits = 18;

#ifdef QSPI_VERBOSE
  mhx_writef(// "Manufacturer = %s\n"
             "Flash size   = %u MB\n"
             "Flash slots  = %u x %u MB\n",
             // manufacturer,
             size, (unsigned int) slot_count, (unsigned int) SLOT_MB);
  mhx_writef("Erase sizes  =");
  if (erase_block_sizes[qspi_flash_erase_block_size_4k])
    mhx_writef(" 4K");
  if (erase_block_sizes[qspi_flash_erase_block_size_32k])
    mhx_writef(" 32K");
  if (erase_block_sizes[qspi_flash_erase_block_size_64k])
    mhx_writef(" 64K");
  if (erase_block_sizes[qspi_flash_erase_block_size_256k])
    mhx_writef(" 256K");
  mhx_writef("\n");
  mhx_writef("Page size    = %u\n", page_size_bytes);
  mhx_writef("\n");
  mhx_press_any_key(0, MHX_A_NOCOLOR);
#endif

  return 0;
}

void read_data(unsigned long start_address)
{
    qspi_flash_read(qspi_flash_device, start_address, data_buffer, 512);
}

unsigned char verify_data_in_place(unsigned long start_address)
{
    return (qspi_flash_verify(qspi_flash_device, start_address, data_buffer, 512) == 0) ? 1 : 0;
}

void program_page(unsigned long start_address, unsigned int page_size)
{
    (void) page_size;
    qspi_flash_program(qspi_flash_device, qspi_flash_page_size_256, start_address, data_buffer);
}

void erase_sector(unsigned long address_in_sector)
{
    enum qspi_flash_erase_block_size erase_block_size;

    if ( flash_sector_bits == 12 )
        erase_block_size = qspi_flash_erase_block_size_4k;
    else if ( flash_sector_bits == 15 )
        erase_block_size = qspi_flash_erase_block_size_32k;
    else if ( flash_sector_bits == 16 )
        erase_block_size = qspi_flash_erase_block_size_64k;
    else if ( flash_sector_bits == 18 )
        erase_block_size = qspi_flash_erase_block_size_256k;
    else
        return;

    qspi_flash_erase(qspi_flash_device, erase_block_size, address_in_sector);
}
