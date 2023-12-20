#ifndef MF_SELECTCORE_H
#define MF_SELECTCORE_H 1

/*
 * MEGAFLASH Select Core Helper
 *
 * Load core files from the sd card and extract the header
 * information needed.
 *
 */

extern unsigned char bitstream_magic[];
extern unsigned char mega65core_magic[];

extern char disk_display_return[40];
extern uint32_t disk_file_inode;
extern uint32_t disk_file_size;

extern uint8_t corefile_model_id;
extern char corefile_name[33];
extern char corefile_version[33];
extern char corefile_error[33];

#define MFS_FILE_INVALID 0
#define MFS_FILE_ERASE 1
#define MFS_FILE_VALID 2

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
 * returns: MFS_FILE_* constant
 *
 */
uint8_t select_bitstream_file(uint8_t slot);

/*
 * int8_t read_and_check_core(require_mega)
 *
 * reads the header from the file in disk_file_inode
 * (set by select_bitstream_file), stores header information
 * in gobal variables and does sanity checks.
 *
 * returns 0 on no errors, <0 on failure. stores failure
 * reason in global variable (screencodes)
 *
 */
int8_t read_and_check_core(uint8_t require_mega);

#endif /* MF_SELECTCORE_H */
