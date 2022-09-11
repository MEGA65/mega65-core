#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspicommon.h"

void main(void)
{
  mega65_io_enable();

  // Black screen for middle-of-the-night development
  POKE(0xD020, 0);
  POKE(0xD021, 0);

  // White text
  POKE(0x286, 1);

  // clear screen
  printf("%c", 147);

  SEI();

  // check if the bitstream was loaded via JTAG
  // this does NOT work if the PRG was pushed by JTAG!
  // reason is currently unknown
  if (PEEK(0xD6C7) != 0xFF) {
    printf("\nWARNING: You appear to have not started\n"
           "this bitstream via JTAG!\n"
           "\n"
           "Without JTAG to rescue your system, it\n"
           "is not recommended to flash slot 0!\n"
           "\n"
           "ABORT\n");
  }
  else {
    // Probe flash with verbose output
    probe_qpsi_flash(1);

    // flash_inspector();
    reflash_slot(0);
  }
}
