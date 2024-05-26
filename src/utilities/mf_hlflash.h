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
extern uint8_t mfhf_slot0_erase_list[];

#define MFHF_LC_NOTLOADED 0
#define MFHF_LC_ATTICOK   1
#define MFHF_LC_FROMDISK  2

#ifdef QSPI_FLASH_INSPECT
/*
 * mfhl_flash_inspector
 *
 * for debugging, gives a view into flash
 *
 */
void mfhl_flash_inspector(void);
#endif /* QSPI_FLASH_INSPECT */

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
 * This will replace the core flags field by the value of
 * mfsc_corefile_bootflags.
 *
 */
int8_t mfhf_load_core();

/*
 * int8_t mfhf_load_core_from_flash(slot, addr_len)
 *
 * parameters:
 *   slot: flash slot to load from
 *   addr_len: how many bytes should be loaded
 *
 * side effects:
 *   mfhf_core_file_state
 *   mfsc_corehdr_length: set to addr_len after success
 *
 * loads data from a flash slot into attic ram.
 *
 */
int8_t mfhf_load_core_from_flash(uint8_t slot, uint32_t addr_len);

/*
 * int8_t mfhf_flash_core(selected_file, slot)
 *
 * parameters:
 *   selected_file: selects between flashing and erasing
 *   slot: flash slot that should be flashed
 *
 * flashes data from attic ram into a core slot. if 
 * selected_file is MFSC_FILE_ERASE, the routine will
 * erase all sectors without writing anything.
 *
 */
int8_t mfhf_flash_core(uint8_t selected_file, uint8_t slot);

#endif /* MF_HLFLASH_H */
