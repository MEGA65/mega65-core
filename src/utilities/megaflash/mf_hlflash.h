#ifndef MF_HLFLASH_H
#define MF_HLFLASH_H 1

#include <stdint.h>

/*
 * MEGAFLASH High level flash routines
 */

#define MFHF_FLAG_VISUAL   0b00000001
#define MFHF_FLAG_PROGRESS 0b00000010

extern uint8_t mfhf_slot0_erase_list[];

extern unsigned char slot_count;

#ifdef STANDALONE
extern uint8_t mfhf_attic_disabled;
#endif

#define MFHF_LC_NOTLOADED 0
#define MFHF_LC_ATTICOK   1
#define MFHF_LC_FROMDISK  2

#ifdef FLASH_INSPECT
/*
 * mfhl_flash_inspector
 *
 * for debugging, gives a view into flash
 *
 */
void mfhl_flash_inspector(void);
#endif /* FLASH_INSPECT */

/*
 * int8_t mfhf_init()
 *
 * side effects:
 *   slot_count: set to the number of flash slots available
 *
 * returns:
 *   int8_t(bool): 0 - success
 *                 1 - initialization failed
 *
 * Initialize the high level flash routines. This function
 * should be called before calling any of the other high
 * level flash routines.
 */
int8_t mfhf_init();

/*
 * int8_t mfhf_read_core_header_from_flash()
 *
 * parameters:
 *   slot: slot to load header from
 *
 * side effects:
 *   data_buffer: contains the header contents
 *
 * returns:
 *   int8_t(bool): 0 - success
 *                 1 - invalid slot specified
 *
 * Read the first 512 bytes of the specified slot form flash
 * into data_buffer.
 *
 */
int8_t mfhf_read_core_header_from_flash(uint8_t slot);

/*
 * int8_t mfhf_load_core()
 *
 * Returns:
 *   int8_t: one of MFHF_LC_* constants (see above)
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
 * Returns:
 *   int8_t: one of MFHF_LC_* constants (see above)
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
