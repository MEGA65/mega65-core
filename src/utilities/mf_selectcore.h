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

extern uint8_t mfsc_corehdr_model_id;
extern uint8_t mfsc_corehdr_bootcaps;
extern uint8_t mfsc_corehdr_bootflags;
extern uint8_t mfsc_corehdr_instflags;
extern uint32_t mfsc_corehdr_length;
extern char mfsc_corehdr_name[33];
extern char mfsc_corehdr_version[33];
extern char mfsc_corehdr_error[33];

#define MFSC_FILE_INVALID 0
#define MFSC_FILE_VALID 1
#define MFSC_FILE_ERASE 2

#define MFSC_COREHDR_MAGIC 0x00
#define MFSC_COREHDR_NAME 0x10
#define MFSC_COREHDR_VERSION 0x30
#define MFSC_COREHDR_MODELID 0x70
#define MFSC_COREHDR_BOOTCAPS 0x7b
#define MFSC_COREHDR_BOOTFLAGS 0x7c
#define MFSC_COREHDR_INSTFLAGS 0x7d
#define MFSC_COREHDR_LENGTH 0x80
#define MFSC_COREHDR_CRC32 0x84

/*
 * mfsc_selectcore(slot)
 *
 * Reads COR files headers from either SD cards either from
 * root or "CORE" directory. The SD card and directory is
 * switchable.
 * Staying on a COR file will display information about it
 * and the user can select one of the files, but only if
 * readings it's header does not result in errors.
 *
 * returns: MFSC_FILE_VALID or _INVALID
 *
 */
uint8_t mfsc_selectcore(uint8_t slot);

/*
 * int8_t mfsc_checkcore(require_mega)
 *
 * reads the header from the file in mfsc_corefile_inode
 * (set by select_bitstream_file), stores header information
 * in gobal variables and does sanity checks.
 *
 * returns 0 on no errors, <0 on failure. stores failure
 * reason in global variables mfsc_corefile_* (screencoded)
 *
 */
int8_t mfsc_checkcore(uint8_t require_mega);

#endif /* MF_SELECTCORE_H */
