#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include <memory.h>
#include <dirent.h>

#include "nohysdc.h"

/***************************************************************************

 SDcard and FAT32 file system routines

 ***************************************************************************/

#define NHSD_SBUF 0xffd6e00L
#define NHSD_CTRL 0xd680L
#define NHSD_ADDR 0xd681L

uint8_t *nhsd_buffer = NULL;
uint8_t nhsd_init_state = 0;

uint32_t nhsd_part_start = 0;
uint32_t nhsd_part_end = 0; // TODO: OPT unused
uint8_t  nhsd_fat32_sectors_per_cluster = 0;
uint32_t nhsd_fat32_reserved_sectors = 0;
uint32_t nhsd_fat32_data_sectors = 0; // TODO: OPT unused
uint32_t nhsd_fat32_sectors_per_fat = 0; // TODO: OPT only used one time in init
uint32_t nhsd_fat32_cluster2_sector = 0;

uint32_t nhsd_open_cluster = 0;
uint32_t nhsd_open_sector = 0;
uint8_t nhsd_open_sector_in_cluster = 0;
uint16_t nhsd_open_offset_in_sector = 0;

struct m65_dirent nhsd_dirent;

uint8_t nhsd_reset(uint8_t bus)
{
  uint32_t timeout = 100000UL;

  // Reset and release reset
  // Check for external SD card, then internal SD card.
  // Select external SD card slot
  POKE(NHSD_CTRL, 0xc0 | bus);

  // Clear SDHC flag
  POKE(NHSD_CTRL, 0x40);

  POKE(NHSD_CTRL, 0);
  POKE(NHSD_CTRL, 1);

  // Now wait for SD card reset to complete
  while (PEEK(NHSD_CTRL) & 3) {
    // POKE(0xD020, (PEEK(0xD020) + 1) & 0x0F);
    timeout--;
    if (!timeout)
      return NHSD_ERR_TIMEOUT;
  }

  // Reassert SDHC flag
  POKE(NHSD_CTRL, 0x41);

  return NHSD_ERR_NOERROR;
}

uint8_t nhsd_readsector(const uint32_t sector_address)
{
  uint8_t tries = 0;
  uint16_t timeout;

  // set read address
  POKE(NHSD_ADDR + 0, (sector_address >> 0) & 0xff);
  POKE(NHSD_ADDR + 1, (sector_address >> 8) & 0xff);
  POKE(NHSD_ADDR + 2, (sector_address >> 16) & 0xff);
  POKE(NHSD_ADDR + 3, (sector_address >> 24) & 0xff);

  while (tries < 10) {

    // Wait for SD card to be ready
    timeout = 50000U;
    while (PEEK(NHSD_CTRL) & 0x3) {
      timeout--;
      if (!timeout || // timed out
          PEEK(NHSD_CTRL) & 0x40 || // SDIO Error flag
          PEEK(NHSD_CTRL) == 0x01) // mysterious busy error
        goto retry;
    }

    // Command read
    POKE(NHSD_CTRL, 2);

    // Wait for read to complete
    timeout = 50000U;
    while (PEEK(NHSD_CTRL) & 0x3) {
      timeout--;
      if (!timeout || // timed out
          PEEK(NHSD_CTRL) & 0x40 || // SDIO Error flag
          PEEK(NHSD_CTRL) == 0x01) // mysterious busy error
        goto retry;
    }

    // Note result
    // result=PEEK(NHSD_CTRL);

    if (!(PEEK(NHSD_CTRL) & 0x67)) {
      // Copy data from hardware sector buffer via DMA
      lcopy(NHSD_SBUF, (long)nhsd_buffer, 512);

      return NHSD_ERR_NOERROR;
    }

retry:
    // Reset SD card current bus
    POKE(0xD020, 7);
    if (nhsd_reset(nhsd_init_state & NHSD_INIT_BUSMASK))
      return NHSD_ERR_TIMEOUT;
    POKE(0xD020, 0);

    tries++;
  }

  return NHSD_ERR_READERROR;
}

uint8_t nhsd_init(uint8_t bus, uint8_t *buffer)
{
  uint8_t p;
  uint8_t part_id;
  uint16_t offset;

  // start unitialised
  nhsd_init_state = 0;

  // try reset bus requested
  if (!nhsd_reset(bus & 0x1)) {
    nhsd_init_state = (bus & 0x1) | NHSD_INIT_SDBUS;
  } // if init failed, try other bus if fallback is allowed
  else if (bus & 0x80 && !nhsd_reset((bus & 0x1) ^ 0x1)) {
    nhsd_init_state = ((bus & 0x1) ^ 0x1) | NHSD_INIT_SDBUS;
  }
  else
    return NHSD_ERR_TIMEOUT;

  // set buffer so we can read data
  nhsd_buffer = buffer;

  // Get MBR to find FAT32 partition
  p = nhsd_readsector(0);
  if (p) {
    nhsd_buffer = NULL;
    nhsd_init_state = 0;
    return p;
  }

  if ((nhsd_buffer[0x1fe] != 0x55) || (nhsd_buffer[0x1ff] != 0xAA)) {
    nhsd_buffer = NULL;
    nhsd_init_state = 0;
    return NHSD_ERR_INVALID_MBR;
  }
  nhsd_init_state |= NHSD_INIT_MBR;

  // find the FAT partition
  for (p = 0; p < 4; p++) {
    offset = 0x1be + (p << 4);
    part_id = nhsd_buffer[offset + 4];
    if (part_id == 0x0c || part_id == 0x0b)
      break;
  }
  if (p == 4) {
    nhsd_buffer = NULL;
    nhsd_init_state = 0;
    return NHSD_ERR_PART_NOT_FOUND;
  }
  for (p = 0; p < 4; p++) {
    ((char *)&nhsd_part_start)[p] = nhsd_buffer[offset + 8 + p];
    ((char *)&nhsd_part_end)[p] = nhsd_buffer[offset + 12 + p];
  }
  nhsd_init_state |= NHSD_INIT_PART;

  // Ok, we have the partition, now work out where the FAT is etc
  if ((p = nhsd_readsector(nhsd_part_start))) {
    nhsd_buffer = NULL;
    nhsd_init_state = 0;
    return p;
  }

  nhsd_fat32_sectors_per_cluster = nhsd_buffer[0x0d];
  for (p = 0; p < 2; p++)
    ((char *)&nhsd_fat32_reserved_sectors)[p] = nhsd_buffer[0x0e + p];
  for (p = 0; p < 4; p++)
    ((char *)&nhsd_fat32_data_sectors)[p] = nhsd_buffer[0x20 + p];
  for (p = 0; p < 4; p++)
    ((char *)&nhsd_fat32_sectors_per_fat)[p] = nhsd_buffer[0x24 + p];

  nhsd_fat32_cluster2_sector = nhsd_part_start + nhsd_fat32_reserved_sectors + nhsd_fat32_sectors_per_fat + nhsd_fat32_sectors_per_fat;

  nhsd_init_state |= NHSD_INIT_FAT;

  return NHSD_ERR_NOERROR;
}

uint32_t nhsd_fat32_nextcluster(uint32_t cluster)
{
  uint16_t offset_in_sector = (cluster & 0x7f) << 2;

  if (!nhsd_readsector(nhsd_part_start + nhsd_fat32_reserved_sectors + (cluster >> 7)))
    return *(uint32_t *)(&nhsd_buffer[offset_in_sector]);
  
  return 0xfffffffful;
}

uint8_t nhsd_opendir()
{
  if ((nhsd_init_state & NHSD_INIT_INITMASK) != NHSD_INIT_INITMASK)
    return NHSD_ERR_NOINIT;

  if (nhsd_init_state & NHSD_INIT_OPENFILE)
    return NHSD_ERR_ALREADY_OPEN;

  nhsd_open_cluster = 2;
  nhsd_open_sector = nhsd_fat32_cluster2_sector;
  nhsd_open_sector_in_cluster = 0;
  nhsd_open_offset_in_sector = 0xffe0u; // one direntry back, so the first advance gets us to 0

  nhsd_init_state |= NHSD_INIT_OPENDIR;

  return NHSD_ERR_NOERROR;
}

// TODO: can be possibly also used with files??
uint8_t nhsd_dir_next_entry()
{
  nhsd_open_offset_in_sector += 0x20;
  if (nhsd_open_offset_in_sector < 512)
    return NHSD_ERR_NOERROR;
  
  // Chain through directory as required
  nhsd_open_offset_in_sector = 0;
  nhsd_open_sector_in_cluster++;
  nhsd_open_sector++;
  if (nhsd_open_sector_in_cluster >= nhsd_fat32_sectors_per_cluster) {
    nhsd_open_sector_in_cluster = 0;
    nhsd_open_cluster = nhsd_fat32_nextcluster(nhsd_open_cluster);
    if (nhsd_open_cluster >= 0x0ffffff0) {
      // end of directory reached
      return NHSD_ERR_EOF;
    }
    nhsd_open_sector = (nhsd_open_cluster - 2) * nhsd_fat32_sectors_per_cluster + nhsd_fat32_cluster2_sector;
  }
  if (!nhsd_open_cluster)
    return NHSD_ERR_EOF;

  if (nhsd_readsector(nhsd_open_sector))
    return NHSD_ERR_TIMEOUT;

  return NHSD_ERR_NOERROR;
}

void nhsd_copy_to_dnamechunk_from_offset(unsigned char* dirent_data, char* dnamechunk, int offset, int numuc2chars)
{
  int k;
  for (k = 0; k < numuc2chars; k++, offset += 2) {
    dnamechunk[k] = dirent_data[offset];
  }
}

void nhsd_copy_vfat_chars_into_dname(unsigned char* dirent_data, char* dname, int seqnumber)
{
  // increment char-pointer to the seqnumber string chunk we'll copy across
  dname = dname + 13 * (seqnumber - 1);
  nhsd_copy_to_dnamechunk_from_offset(dirent_data, dname, 0x01, 5);
  dname += 5;
  nhsd_copy_to_dnamechunk_from_offset(dirent_data, dname, 0x0e, 6);
  dname += 6;
  nhsd_copy_to_dnamechunk_from_offset(dirent_data, dname, 0x1c, 2);
}

uint8_t nhsd_readdir()
{
  unsigned char vfatEntry = 0, firstTime, deletedEntry = 0;
  uint8_t seqnumber, err;
  uint8_t *dirent_data;

  if ((nhsd_init_state & NHSD_INIT_OPENMASK) != NHSD_INIT_OPENDIR)
    return NHSD_ERR_DIR_NOT_OPEN;

  while (1) {
    // Get DOS directory entry and populate
    if ((err = nhsd_dir_next_entry()))
      return err;

    dirent_data = (uint8_t *)&nhsd_buffer[nhsd_open_offset_in_sector];

    // Check if this is a VFAT entry
    if (dirent_data[0x0b] == 0x0f) {
      // Read in all FAT32-VFAT entries to extract out long filenames
      // first byte is sequence (1-19) plus end marker 0x40, but end can come
      // first and name might be in reverse order! (or is this always the case?)
      vfatEntry = 1;
      firstTime = 1;
      do {
        if (dirent_data[0x00] == 0xe5) { // if deleted-entry, then ignore
          deletedEntry = 1;
        }
        if (!deletedEntry) {
          // we only copy filename if entry is not deleted
          seqnumber = dirent_data[0x00] & 0x1f;

          // assure there is a null-terminator
          if (firstTime) {
            nhsd_dirent.d_name[seqnumber * 13] = 0;
            firstTime = 0;
          }

          // vfat seqnumbers will be parsed from high to low, each containing up to 13 UCS-2 characters
          nhsd_copy_vfat_chars_into_dname(dirent_data, nhsd_dirent.d_name, seqnumber);
        }

        // Get next FAT directory entry and populate
        if ((err = nhsd_dir_next_entry()))
          return err;

        dirent_data = (uint8_t *)&nhsd_buffer[nhsd_open_offset_in_sector];

        // if next dirent is not a vfat entry, break out
      } while (dirent_data[0x0b] == 0x0f && seqnumber > 1);
      // printf("vfat = '%s'\n", nhsd_dirent.d_name);
      // press_any_key(0,0);
    }

    // ignore deleted vfat entries and deleted entries
    // ignore everything with underscore or tilde as first character (MacOS)
    // ignore any vfat files starting with '.' (such as mac osx '._*' metadata files)
    // if the DOS 8.3 entry is a deleted-entry, then ignore
    if (deletedEntry || dirent_data[0x00] == 0xe5
        || dirent_data[0x00] == 0x7e || dirent_data[0x00] == 0x5f
        || (vfatEntry && nhsd_dirent.d_name[0] == '.')) {
      nhsd_dirent.d_name[0] = 0;
      vfatEntry = 0;
      deletedEntry = 0;
      continue;
    }

    // OPT: loops?

    // copy start of file inode
    ((unsigned char *)&nhsd_dirent.d_ino)[0] = dirent_data[0x1a];
    ((unsigned char *)&nhsd_dirent.d_ino)[1] = dirent_data[0x1b];
    ((unsigned char *)&nhsd_dirent.d_ino)[2] = dirent_data[0x14];
    ((unsigned char *)&nhsd_dirent.d_ino)[3] = dirent_data[0x15];

    // copy size of file in bytes
    ((unsigned char *)&nhsd_dirent.d_reclen)[0] = dirent_data[0x1c];
    ((unsigned char *)&nhsd_dirent.d_reclen)[1] = dirent_data[0x1d];
    ((unsigned char *)&nhsd_dirent.d_reclen)[2] = dirent_data[0x1e];
    ((unsigned char *)&nhsd_dirent.d_reclen)[3] = dirent_data[0x1f];

    // if not vfat-longname, then extract out old 8.3 name
    if (!vfatEntry) {
      memcpy(nhsd_dirent.d_name, dirent_data, 8);
      nhsd_dirent.d_name[8] = '.';
      memcpy(nhsd_dirent.d_name + 9, dirent_data + 8, 4);
      nhsd_dirent.d_name[12] = 0;
    }

    if (nhsd_dirent.d_name[0]) // sanity check, deleted check is done further up
      return NHSD_ERR_NOERROR;

    // for (k = 0; k < 16; k++)
    //   printf("%02x ", dirent[k]);
    // printf("\n\n");
  }

  // won't be reached
  return NHSD_ERR_EOF;
}

uint8_t nhsd_closedir()
{
  if ((nhsd_init_state & NHSD_INIT_OPENMASK) != NHSD_INIT_OPENDIR)
    return NHSD_ERR_DIR_NOT_OPEN;

  nhsd_init_state &= 0xff ^ NHSD_INIT_OPENDIR;
  
  return NHSD_ERR_NOERROR;
}

uint8_t nhsd_findfile(char *filename)
{
  uint8_t err;

  if ((nhsd_init_state & NHSD_INIT_INITMASK) != NHSD_INIT_INITMASK)
    return NHSD_ERR_NOINIT;

  if ((err = nhsd_opendir()))
    return err;

  while (!(err = nhsd_readdir()))
    if (!strcmp(nhsd_dirent.d_name, filename))
      break;
  // not catching any errors here, but we are also not expecting any...
  nhsd_closedir();

  if (!err) // nhsd_dirent.d_ino contains first cluster
    return NHSD_ERR_NOERROR;

  return err;
}

uint8_t nhsd_open(uint32_t inode)
{
  if ((nhsd_init_state & NHSD_INIT_INITMASK) != NHSD_INIT_INITMASK)
    return NHSD_ERR_NOINIT;

  if (nhsd_init_state & NHSD_INIT_OPENMASK)
    return NHSD_ERR_ALREADY_OPEN;

  nhsd_open_cluster = inode;
  nhsd_open_sector_in_cluster = 0;
  nhsd_open_sector = (nhsd_open_cluster - 2) * nhsd_fat32_sectors_per_cluster + nhsd_fat32_cluster2_sector;

  nhsd_init_state |= NHSD_INIT_OPENFILE;

  return NHSD_ERR_NOERROR;
}

uint8_t nhsd_read()
{
  uint8_t err;
  uint32_t the_sector = nhsd_open_sector;

  if (!(nhsd_init_state & NHSD_INIT_OPENFILE))
    return NHSD_ERR_FILE_NOT_OPEN;

  if (!nhsd_open_cluster)
    return NHSD_ERR_EOF;

  nhsd_open_sector_in_cluster++;
  nhsd_open_sector++;
  if (nhsd_open_sector_in_cluster >= nhsd_fat32_sectors_per_cluster) {
    nhsd_open_sector_in_cluster = 0;
    nhsd_open_cluster = nhsd_fat32_nextcluster(nhsd_open_cluster);
    if (nhsd_open_cluster >= 0x0ffffff0 || (!nhsd_open_cluster)) {
      nhsd_open_cluster = 0;
    }
    nhsd_open_sector = (nhsd_open_cluster - 2) * nhsd_fat32_sectors_per_cluster + nhsd_fat32_cluster2_sector;
  }

  if ((err = nhsd_readsector(the_sector)))
    return err;

  return NHSD_ERR_NOERROR;
}

uint8_t nhsd_close()
{
  if ((nhsd_init_state & NHSD_INIT_INITMASK) != NHSD_INIT_INITMASK)
    return NHSD_ERR_NOINIT;

  if (nhsd_init_state & NHSD_INIT_OPENFILE)
    nhsd_init_state &= 0xff ^ NHSD_INIT_OPENFILE;
  
  return NHSD_ERR_NOERROR;
}
