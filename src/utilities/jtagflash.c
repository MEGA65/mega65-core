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
  POKE(0xD020,0); POKE(0xD021,0);
  
  // White text
  POKE(0x286,1);

  SEI();

  // Probe flash with verbose output
  probe_qpsi_flash(1);
  
  // flash_inspector();
   reflash_slot(0);
  
}

