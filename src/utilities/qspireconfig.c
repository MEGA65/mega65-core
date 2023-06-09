#include <stdio.h>

#include <hal.h>
#include <memory.h>
#include "qspireconfig.h"

unsigned char reconfig_disabled = 0;
unsigned char input_key;

#include <cbm_petscii_charmap.h>

unsigned char press_any_key(unsigned char attention, unsigned char nomessage)
{
  if (!nomessage)
    printf("\nPress any key to continue.\n");

  // clear key buffer
  POKE(0xD020, 0);
  while (PEEK(0xD610))
    POKE(0xD610, 0);
  while (!(input_key = PEEK(0xD610)))
    if (attention) // attention lets the border flash
      POKE(0xD020, PEEK(0xD020) + 1);
  POKE(0xD020, 0);

  POKE(0xD610, 0);
  return input_key;
}

void reconfig_fpga(unsigned long addr)
{
  short i;

  if (reconfig_disabled) {
    printf("%c%cERROR:%c Remember that warning about\n"
           "having started from JTAG?\n"
           "You %ccan't%c start a core from flash after\n"
           "having started the system via JTAG.\n",
        0x93, 158, 5, 158, 5);
    press_any_key(0, 0);
    printf("%c", 0x93);
    return;
  }

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
    POKE(0xD020, PEEK(0xD012) & 0x0F);
  }
  // reconfig failed!
  POKE(0xD020, 0x0C);
  while (1);
}

