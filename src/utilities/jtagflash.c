#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspicommon.h"
#include "version.h"

void main(void)
{
  unsigned char atticram_bad = 0;
  mega65_io_enable();

  // Black screen for middle-of-the-night development
  POKE(0xD020, 0);
  POKE(0xD021, 0);

  // White text
  POKE(0x286, 1);

  // clear screen
  printf("%c", 147);

  SEI();

  // quick and dirty attic ram check
  lpoke(0x8000000l, 0x55);
  if (lpeek(0x8000000l) != 0x55)
    atticram_bad = 1;
  else {
    lpoke(0x8000000l, 0xaa);
    if (lpeek(0x8000000l) != 0xaa)
      atticram_bad = 1;
    else {
      lpoke(0x8000000l, 0xff);
      if (lpeek(0x8000000l) != 0xff)
        atticram_bad = 1;
      else {
        lpoke(0x8000000l, 0x00);
        if (lpeek(0x8000000l) != 0x00)
          atticram_bad = 1;
      }
    }
  }
  if (atticram_bad) {
    printf("\nWARNING: could not detect working attic\n"
           "RAM, which is required by this flasher.\n"
           "\n"
           "ABORT\n");
    return;
  }

  // check if the bitstream was loaded via JTAG
  // this does NOT work if the PRG was pushed by JTAG!
  // reason is currently unknown
  if (PEEK(0xD6C7) != 0xFF) {
    printf("\nWARNING: You appear to have not started\n"
           "this bitstream via JTAG!\n"
           "\n"
           "Without JTAG to rescue your system, it\n"
           "is not recommended to flash slot 0!\n"
           "\n");
    press_any_key(1,0);
  }

  printf("%c\njtagflash Version\n  %s\n", 0x93, utilVersion);

  // Probe flash with verbose output
  probe_qspi_flash();

  verboseProgram = 1;
  reflash_slot(0l);

  printf("%c", 0x93);
  POKE(0xD020, 0);
}
