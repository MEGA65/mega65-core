#ifndef NOHYSDC_H
#define NOHYSDC_H

/*
 * NO HYPPO SDCARD
 *
 * SDcard and FAT access routines, which don't rely on HYPPO traps
 * used by hyppo mode tools like MEGAFLASH
 *
 * Warning! This is very minimalistic to save precious space!
 *
 * Limitations:
 *  - can only work with internal or external card (core limitation)
 *  - can only have one directory OR one file open!
 *  - can only read full 512 byte sectors, will not truncate the last sector!
 *  - has limited error handling
 *
 */

#define NHSD_INIT_BUS0     0
#define NHSD_INIT_BUS1     1
#define NHSD_INIT_SDBUS    0x02
#define NHSD_INIT_MBR      0x04
#define NHSD_INIT_PART     0x08
#define NHSD_INIT_FAT      0x10
#define NHSD_INIT_OPENDIR  0x20
#define NHSD_INIT_OPENFILE 0x40

#define NHSD_INIT_BUSMASK  0b00000001
#define NHSD_INIT_INITMASK 0b00011110
#define NHSD_INIT_OPENMASK 0b01100000

/*
 * nhsd_init_state
 * .0 sd bus 0 (internal) or 1 (external)
 * .1 sd card init done
 * .2 mbr ok
 * .3 part ok
 * .4 fat read
 * .5 dir open
 * .6 file open
 * .7 t.b.d.
 */
extern uint8_t nhsd_init_state;

/*
 * current directory entry read by nhsd_readdir
 */
extern struct m65_dirent nhsd_dirent;

/*
 * return codes used by nearly all functions
 */
#define NHSD_ERR_NOERROR 0
#define NHSD_ERR_NOINIT 1
#define NHSD_ERR_TIMEOUT 2
#define NHSD_ERR_INVALID_MBR 3
#define NHSD_ERR_PART_NOT_FOUND 4
#define NHSD_ERR_READERROR 5
#define NHSD_ERR_DIR_NOT_OPEN 6
#define NHSD_ERR_FILE_NOT_OPEN 7
#define NHSD_ERR_ALREADY_OPEN 8
#define NHSD_ERR_EOF 0x80

/*
 * uint8_t nhsd_init(uint8_t bus, char *buffer)
 *
 * setup sdcard access within hyppo context (i.e. without using hyppo traps)
 * the parameter bus selects either the internal or external sd card.
 * this will read the MBR, search for a FAT partition and initialise fat
 * pointers for reading directory and files.
 * 
 * parameters:
 *   bus: bit 0 selects either internal(0) or external (1) sd card slot. if bit
 *        7 is set (0x80), then failure to init the requested slot will try to select
 *        the other (so 0x81 will try external then internal slot)
 *   buffer: memory buffer of at least 512 bytes (not checked, so don't mess up)
 *
 * returns:
 *   uint8_t NHSD_ERR_* error code
 */
uint8_t nhsd_init(uint8_t bus, uint8_t *buffer);

/*
 * uint8_t nhsd_opendir()
 *
 * prepears no-hyppo sd for reading directory entries.
 *
 */
uint8_t nhsd_opendir();

/*
 * uint8_t nhsd_readdir(struct m65dirent *dirent)
 *
 * reads the next directory entry. returns NHSD_ERR_EOF when no more entries are
 * found. stores the directory entry data in global nhsd_dirent.
 * entry names are in ASCII encoding (or whatever was used on the SD...)
 * 
 */
uint8_t nhsd_readdir();

/*
 * uint8_t nhsd_closedir()
 *
 * tells no-hyppo sd that directory reading is finished.
 * note: you can only have opened directory or file, not both!
 *
 */
uint8_t nhsd_closedir();

/*
 * uint8_t nhsd_findfile(char *filename)
 *
 * search for filename in the current directory of the initialised sd card
 * returns NOERROR on success, nhsd_dirent containing the found entry
 * EOF means file not found, anything else is an error.
 *
 * parameters:
 *   filename: filename to be searched in the fat, needs to have the right encoding (ASCII)
 */
uint8_t nhsd_findfile(char *filename);

/*
 * uint8_t nhsd_open(uint32_t inode)
 *
 * opens the file starting at inode, which is the d_ino from a found
 * directory entry.
 * Only one file or directory can be open at a time!
 *
 * parameters:
 *   inode: starting inode of the file to be opened
 */
uint8_t nhsd_open(uint32_t inode);

/*
 * uint8_t nhsf_read()
 *
 * reads the next 512 byte sector from the open file. read data can
 * be found in the buffer used in nhsd_init.
 * NOERROR means data was read, EOF means end of file reached, anything
 * else is an error.
 * 
 */
uint8_t nhsd_read();

/*
 * uint8_t nhsd_close()
 *
 * closes the currently open file.
 * 
 */
uint8_t nhsd_close();

#endif /* NOHYSDC_H */