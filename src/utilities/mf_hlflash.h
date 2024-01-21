#ifndef MF_HLFLASH_H
#define MF_HLFLASH_H 1

#include <stdint.h>

/*
 * MEGAFLASH High level flash routines
 */

#define MFHF_FLAG_VISUAL   0b00000001
#define MFHF_FLAG_PROGRESS 0b00000010

extern uint8_t mfhf_slot_mb;
extern uint32_t mfhf_slot_size;

#define MFHF_LC_NOTLOADED 0
#define MFHF_LC_ATTICOK   1
#define MFHF_LC_FROMDISK  2

/*
 * int8_t mfhf_load_core()
 *
 * Returns:
 *   int8_t(bool): 0 - load succeeded
 *                 1 - load failed / abort
 *
 * Loads the selected core into attic ram and does a crc32
 * check. Will ask for confirmation if crc32 check fails.
 *
 */
int8_t mfhf_load_core();

int8_t mfhf_flash_core(uint8_t selected_file, uint8_t slot);

#endif /* MF_HLFLASH_H */
