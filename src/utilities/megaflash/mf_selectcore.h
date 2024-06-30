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

#define R095_VER_STUB_SIZE 12
extern const char R095_VER_STUB[];
extern const uint8_t R095_ERASE_LIST[];

extern unsigned char mfsc_bitstream_magic[];

extern char mfsc_corefile_displayname[40];
extern uint32_t mfsc_corefile_inode;
extern uint32_t mfsc_corefile_size;

extern uint8_t mfsc_corehdr_model_id;
extern uint8_t mfsc_corehdr_bootcaps;
extern uint8_t mfsc_corehdr_bootflags;
extern uint8_t mfsc_corehdr_instflags;
extern uint8_t mfsc_corehdr_erase_list[16];
extern uint32_t mfsc_corehdr_length;

extern char mfsc_corehdr_name[33];
extern char mfsc_corehdr_version[33];
extern char mfsc_corehdr_error[33];

// clang-format off
#define MFSC_FILE_INVALID 0
#define MFSC_FILE_VALID   1
#define MFSC_FILE_ERASE   2

#define MFSC_COREHDR_MAGIC     0x00
#define MFSC_COREHDR_NAME      0x10
#define MFSC_COREHDR_VERSION   0x30
#define MFSC_COREHDR_MODELID   0x70
#define MFSC_COREHDR_BOOTCAPS  0x7b
#define MFSC_COREHDR_BOOTFLAGS 0x7c
#define MFSC_COREHDR_INSTFLAGS 0x7d
#define MFSC_COREHDR_LENGTH    0x80
#define MFSC_COREHDR_CRC32     0x84
#define MFSC_COREHDR_ERASELIST 0xf0

#define MFSC_COREINST_FACTORY   0b00000001
#define MFSC_COREINST_AUTO      0b00000010
#define MFSC_COREINST_ERASELIST 0b01000000
#define MFSC_COREINST_FORCE     0b10000000
// clang-format on

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

/*
 * int8_t mfsc_findcorefile(filename, require_mega65)
 *
 * parameters:
 *   filename: fat filename
 *   require_mega65: bool, should core be checked for slot 0 compability?
 *
 * search for filename in the root of the internal SD card.
 * 
 * returns 0 if it was found and is a valid MEGA65 FACTORY core.
 *
 */
int8_t mfsc_findcorefile(const char *filename, uint8_t require_mega65);

#endif /* MF_SELECTCORE_H */
