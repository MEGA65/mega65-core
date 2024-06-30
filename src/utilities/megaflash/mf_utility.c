#include <stdint.h>

#include <hal.h>
#include <memory.h>
#include <string.h>
#include "mhexes.h"
#include "mf_buffers.h"

#ifdef STANDALONE
#include "mf_screens_solo.h"
#else
#include "mf_screens.h"
#endif

uint8_t mfu_slot_mb = 1;
uint8_t mfu_slot_pagemask = (1 << 4) - 1;
uint32_t mfu_slot_size = 1L << 20;

uint8_t hw_model_id = 0;
char hw_model_name[20] = "Unknown";

/***************************************************************************

 FPGA / Core file / Hardware platform routines

 ***************************************************************************/

typedef struct {
  uint8_t model_id;
  uint8_t slot_mb;
} mega_models_t;

int8_t mfut_probe_hardware_version(void)
{
  uint8_t k = 0;

  hw_model_id = PEEK(0xD629);

#define MFUT_BUF2MOD(A) (((mega_models_t *)buffer)->A)

  while (k < mf_screens_mega65_target.cursor_y) {
    mhx_screen_get_line(&mf_screens_mega65_target, k++, (char *)&buffer);
    if (MFUT_BUF2MOD(model_id) == 0)
      break;
    if (MFUT_BUF2MOD(model_id) == hw_model_id) {
      mfu_slot_pagemask = mfu_slot_mb = MFUT_BUF2MOD(slot_mb);
      mfu_slot_pagemask <<= 4;
      mfu_slot_size = ((uint32_t)mfu_slot_pagemask) << 16;
      mfu_slot_pagemask--;
      mhx_strncpy(hw_model_name, buffer + sizeof(mega_models_t), 20);
      return 0;
    }
  }

  mhx_strncpy(hw_model_name, buffer + sizeof(mega_models_t), 20);
  return -1;
}

void mfut_reconfig_fpga(uint32_t addr)
{
  uint8_t i;

  // Black screen when reconfiguring
  POKE(0xD020U, 0);
  POKE(0xD011U, 0);

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
    POKE(0xD020U, PEEK(0xD020U) & 0x0F);
  }
  // reconfig failed!
  POKE(0xD020U, 0x0C);
  while (1);
}
