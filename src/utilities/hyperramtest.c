#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <fileio.h>

/*
  Bit bash interface for Hyperram:

  $BFFFFF0 = read debug mode ($FF = debug mode, $00 = normal mode)  (write $DE to enable, or $1d to disable)
  $BFFFFF1 = Read hr_d, and if hr_ddr bit set, write it
  $BFFFFF2.0 = hr_rwds
  $BFFFFF2.1 = hr_reset_int
  $BFFFFF2.2 = hr_clk_n_int
  $BFFFFF2.3 = hr_clk_p_int
  $BFFFFF2.4 = hr_cs0_int
  $BFFFFF2.5 = hr_cs1_int
  $BFFFFF2.6 = hr_ddr (data direction for hr_d)
  $BFFFFF2.7 = cache_enable
  $BFFFFF3 = write_latency
  $BFFFFF4 = read hyperram state machine value
*/

void main(void)
{
}
