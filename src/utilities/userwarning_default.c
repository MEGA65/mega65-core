#include "qspicommon.h"

unsigned char user_has_been_warned(void)
{
  printf("%c"
         "An error while replacing slot 0 can\n"
         "brick your MEGA65, which can ONLY be\n"
         "reverted using a JTAG adapter. If you\n"
         "own a JTAG, and are confident that you\n"
         "can start you MEGA65 using it, you can\n"
         "proceed by typing:\n"
         "THIS VOIDS MY WARRANTY\n",
      0x93);
  if (!check_input("THIS VOIDS MY WARRANTY\r", CASE_SENSITIVE))
    return 0;
  return 1;
}
