#include <stdint.h>

#include <hal.h>
#include <memory.h>

#include <cbm_petscii_charmap.h>

void reconfig_fpga(unsigned long addr)
{
  uint8_t i;

  // Black screen when reconfiguring
  POKE(0xD020, 0);
  POKE(0xD011, 0);

  mega65_io_enable();

  // Addresses for WBSTAR are shifted by 8 bits
  POKE(0xD6C8U, (addr >> 8) & 0xff);
  POKE(0xD6C9U, (addr >> 16) & 0xff);
  POKE(0xD6CAU, (addr >> 24) & 0xff);
  POKE(0xD6CBU, 0x00);

  // Try to reconfigure for some time
  for (i = 0; i < 200; i++) {
    // Wait a little while, to make sure that the WBSTAR slot in
    // the reconfig sequence gets set before we instruct the FPGA
    // to reconfigure.
    usleep(255);

    // Trigger reconfigure
    POKE(0xD6CFU, 0x42);
    // visual feedback
    POKE(0xD020, PEEK(0xD020) & 0x0F);
  }
  // reconfig failed!
  POKE(0xD020, 0x0C);
  while (1);
}
