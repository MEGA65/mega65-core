#ifndef MF_SELECTCORE_H
#define MF_SELECTCORE_H 1

#include <stdint.h>

/*
 * MEGAFLASH Select Core Helper
 *
 * Load core files from the sd card and extract the header
 * information needed.
 *
 */

extern unsigned char mfsc_bitstream_magic[];

extern char mfsc_corefile_displayname[40];
extern uint32_t mfsc_corefile_inode;
extern uint32_t mfsc_corefile_size;

extern uint8_t mfsc_corefile_model_id;
extern char mfsc_corefile_name[33];
extern char mfsc_corefile_version[33];
extern char mfsc_corefile_error[33];

#define MFS_FILE_INVALID 0
#define MFS_FILE_VALID 1
#define MFS_FILE_ERASE 2

/*
 * mfs_selectcore(slot)
 *
 * Reads COR files headers from either SD cards either from
 * root or "CORE" directory. The SD card and directory is
 * switchable.
 * Staying on a COR file will display information about it
 * and the user can select one of the files, but only if
 * readings it's header does not result in errors.
 *
 * returns: MFS_FILE_VALID or _INVALID
 *
 */
uint8_t select_bitstream_file(uint8_t slot);

/*
 * int8_t read_and_check_core(require_mega)
 *
 * reads the header from the file in mfsc_corefile_inode
 * (set by select_bitstream_file), stores header information
 * in gobal variables and does sanity checks.
 *
 * returns 0 on no errors, <0 on failure. stores failure
 * reason in global variables mfsc_corefile_* (screencoded)
 *
 */
int8_t read_and_check_core(uint8_t require_mega);

#endif /* MF_SELECTCORE_H */
