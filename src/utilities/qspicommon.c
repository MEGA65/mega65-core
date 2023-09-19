#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>

#include "qspicommon.h"
#include "qspireconfig.h"
#include "mhexes.h"
#include "crc32accl.h"

#ifndef STANDALONE
void nope(char *format, ...) { *format |= 0; }
#endif

typedef struct {
  uint8_t tm_sec, tm_min, tm_hour;
} time_t;

time_t tm_start;
time_t tm_now;

uint8_t hw_model_id = 0;
char *hw_model_name = "?unknown?";
unsigned char slot_count = 0;

#ifdef STANDALONE
uint8_t SLOT_MB = 1;
unsigned long SLOT_SIZE = 1L << 20;
unsigned long SLOT_SIZE_PAGES = 1L << 12;
#endif

short i, x, y, z;

unsigned long addr, addr_len;
unsigned char tries = 0;

unsigned int num_4k_sectors = 0;

unsigned char verboseProgram = 0;

unsigned char part[256];

unsigned int page_size = 0;
unsigned char latency_code = 0xff;
unsigned char reg_cr1 = 0x00;
unsigned char reg_sr1 = 0x00;

unsigned char manufacturer;
unsigned short device_id;
unsigned char cfi_data[512];
unsigned short cfi_length = 0;
unsigned char flash_sector_bits = 0;
unsigned char last_sector_num = 0xff;
unsigned char sector_num = 0xff;

unsigned char corefile_model_id = 0;
char corefile_name[32];
char corefile_version[32];
char corefile_error[32];

// used by QSPI routines
unsigned char data_buffer[512];
// Magic string for identifying properly loaded bitstream
#include <ascii_charmap.h>
unsigned char bitstream_magic[] = "MEGA65BITSTREAM0";
// it's the same, MEGA65, but only 6 chars, followed by 0 bytes
#define mega65core_magic bitstream_magic
#include <cbm_petscii_charmap.h>

unsigned short mb = 0;

// used by SD card routines
unsigned char buffer[512];

const unsigned long sd_timeout_value = 100000;

/***************************************************************************

 General utility functions

 ***************************************************************************/

unsigned char debcd(unsigned char c)
{
  return (c & 0xf) + (c >> 4) * 10;
}

uint8_t tm_last_sec;
uint16_t tm_elapsed;
/*
 * this counts elapsed seconds and needs to be called at least
 * once per minute to work! better call it every few seconds!
 * 
 * returns 1 if tm_elapsed has changed since the last call
 */
uint8_t elapsed_sec(uint8_t start)
{
  uint8_t tm_sec;

#ifdef MODE_INTEGRATED
  // in HYPPO the CIA does not work, so we need to rely on RTC
  tm_sec = debcd(lpeek(0xFFD7110L));
  lpeek(0xFFD7116L); // to remove read latch, wday is not used here
#else
  tm_sec = debcd(PEEK(0xDC09));
  lpeek(0xDC08L); // read tenth of sec to remove read latch
#endif

  if (start) {
    tm_last_sec = tm_sec;
    tm_elapsed = 0;
  }
  if (tm_last_sec == tm_sec)
    return 0;

  if (tm_last_sec > tm_sec)
    tm_sec += 60;
  tm_elapsed += tm_sec - tm_last_sec;
  tm_last_sec = tm_sec;

  return 1;
}

unsigned char progress_chars[4] = { 32, 101, 97, 231 };
unsigned char progress = 0, progress_last = 0;
unsigned int progress_total = 0, progress_goal = 0;

#ifdef STANDALONE
#define progress_start(PAGES, LABEL) \
  elapsed_sec(1); \
  progress = progress_last = 0; \
  progress_total = 0; \
  progress_goal = PAGES; \
  printf("%c%c%c%c%c%c%c%c%c%s ?KB/sec, done in ? sec.     \n", 0x13, 0x11, 0x11, 0x11, 0x11, \
            0x11, 0x11, 0x11, 0x11, LABEL)
#else
#define progress_start(PAGES, LABEL) \
  elapsed_sec(1); \
  progress = progress_last = 0; \
  progress_total = 0; \
  progress_goal = PAGES; \
  printf("%c%c%c%c%c%c%c%c%c%s ?KB/sec, done in ? sec.     \n", 0x13, 0x11, 0x11, 0x11, 0x11, \
            0x11, 0x11, 0x11, 0x11, LABEL)
#endif
#define progress_time(VAR) VAR = tm_elapsed

#define EIGHT_FROM_TOP printf("\x13""\n\n\n\n\n\n\n\n");

// this count 256 byte blocks and draws a 32 char wide progress bar with 128 divisions
void progress_bar(unsigned int add_pages, char *action)
{
  unsigned char progress_small, bar;

  progress_total += add_pages;
  progress = progress_total >> 8;
  if (progress != progress_last) {
    progress_last = progress;

    if (elapsed_sec(0)) {
      unsigned int speed;
      unsigned int eta;

      speed = (unsigned int)((progress_total / tm_elapsed) >> 2);
      if (speed > 0)
        eta = ((progress_goal - progress_total) / speed) >> 2;
        EIGHT_FROM_TOP;
        printf("%s %uKB/sec, done in %u sec.     ", action, speed, eta);
    }
  }

  /* Draw a progress bar several chars high */
  POKE(0x0403 + (4 * 40), 93);
  POKE(0x0403 + (5 * 40), 93);
  POKE(0x0403 + (6 * 40), 93);
  progress_small = progress >> 2;
  for (i = 0; i < 32; i++) {
    if (i < progress_small || i >= progress_goal >> 10)
      bar = 160;
    else if (i == progress_small)
      bar = progress_chars[progress & 3];
    else
      bar = 32;
    POKE(0x0404 + (4 * 40) + i, bar);
    POKE(0x0404 + (5 * 40) + i, bar);
    POKE(0x0404 + (6 * 40) + i, bar);
  }
  POKE(0x0424 + (4 * 40), 93);
  POKE(0x0424 + (5 * 40), 93);
  POKE(0x0424 + (6 * 40), 93);

  return;
}

/***************************************************************************

 SDcard and FAT32 file system routines

 ***************************************************************************/

unsigned long sdcard_timeout;
unsigned char sdbus = 0;

unsigned long fat32_partition_start = 0;
unsigned long fat32_partition_end = 0;
unsigned char fat32_sectors_per_cluster = 0;
unsigned long fat32_reserved_sectors = 0;
unsigned long fat32_data_sectors = 0;
unsigned long fat32_sectors_per_fat = 0;
unsigned long fat32_cluster2_sector = 0;

void sdcard_reset(void)
{
  // Reset and release reset

  // Check for external SD card, then internal SD card.

  // Select external SD card slot
  POKE(sd_ctl, 0xc1);

  // Clear SDHC flag
  POKE(sd_ctl, 0x40);

  POKE(sd_ctl, 0);
  POKE(sd_ctl, 1);

  sdcard_timeout = sd_timeout_value;

  // Now wait for SD card reset to complete
  while (PEEK(sd_ctl) & 3) {
    POKE(0xD020, (PEEK(0xD020) + 1) & 0x0F);
    sdcard_timeout--;
    if (!sdcard_timeout) {
      if (sdbus == 0) {
        POKE(sd_ctl, 0xc0);
        POKE(sd_ctl, 0);
        POKE(sd_ctl, 1);
        sdcard_timeout = sd_timeout_value;
        sdbus = 1;
      }
    }
  }

  if (!sdcard_timeout) {
    printf("Could not reset SD card\n");
    while (1)
      continue;
  }

  // Reassert SDHC flag
  POKE(sd_ctl, 0x41);
}

void sdcard_readsector(const uint32_t sector_number)
{
  char tries = 0;

  uint32_t sector_address = sector_number * 512;
  sector_address = sector_number;

  POKE(sd_addr + 0, (sector_address >> 0) & 0xff);
  POKE(sd_addr + 1, (sector_address >> 8) & 0xff);
  POKE(sd_addr + 2, ((uint32_t)sector_address >> 16) & 0xff);
  POKE(sd_addr + 3, ((uint32_t)sector_address >> 24) & 0xff);

  //  write_line("Reading sector @ $",0);
  //  screen_hex(screen_line_address-80+18,sector_address);

  while (tries < 10) {

    // Wait for SD card to be ready
    sdcard_timeout = 50000U;
    while (PEEK(sd_ctl) & 0x3) {
      sdcard_timeout--;
      if (!sdcard_timeout)
        return;
      if (PEEK(sd_ctl) & 0x40) {
        return;
      }
      // Sometimes we see this result, i.e., sdcard.vhdl thinks it is done,
      // but sdcardio.vhdl thinks not. This means a read error
      if (PEEK(sd_ctl) == 0x01)
        return;
    }

    // Command read
    POKE(sd_ctl, 2);

    // Wait for read to complete
    sdcard_timeout = 50000U;
    while (PEEK(sd_ctl) & 0x3) {
      sdcard_timeout--;
      if (!sdcard_timeout)
        return;
      //      write_line("Waiting for read to complete",0);
      if (PEEK(sd_ctl) & 0x40) {
        return;
      }
      // Sometimes we see this result, i.e., sdcard.vhdl thinks it is done,
      // but sdcardio.vhdl thinks not. This means a read error
      if (PEEK(sd_ctl) == 0x01)
        return;
    }

    // Note result
    // result=PEEK(sd_ctl);

    if (!(PEEK(sd_ctl) & 0x67)) {
      // Copy data from hardware sector buffer via DMA
      lcopy(sd_sectorbuffer, (long)buffer, 512);

      return;
    }

    POKE(0xD020, (PEEK(0xd020) + 1) & 0x0F);

    // Reset SD card
    sdcard_reset();

    tries++;
  }
}

unsigned char sdcard_setup = 0;

void scan_partition_entry(const char i)
{
  char j;

  int offset = 0x1be + (i << 4);

  char id = buffer[offset + 4];
  uint32_t lba_start, lba_end;

  for (j = 0; j < 4; j++)
    ((char *)&lba_start)[j] = buffer[offset + 8 + j];
  for (j = 0; j < 4; j++)
    ((char *)&lba_end)[j] = buffer[offset + 12 + j];

  if (id == 0x0c || id == 0x0b) {
    // Found FAT partition
    fat32_partition_start = lba_start;
    fat32_partition_end = lba_end;
#if 0
    printf("Partition type $%02x spans sectors $%lx -- $%lx\n",
        id,fat32_partition_start,fat32_partition_end);
#endif
  }
}

void setup_sdcard(void)
{
  unsigned char j;

  sdcard_reset();

  // Get MBR to find FAT32 partition
  sdcard_readsector(0);

  if ((buffer[0x1fe] != 0x55) || (buffer[0x1ff] != 0xAA)) {
    printf("Current partition table is invalid.\n");
    while (1)
      continue;
  }
  else {
    for (i = 0; i < 4; i++) {
      scan_partition_entry(i);
    }
  }
  if (!fat32_partition_start) {
    printf("Could not find a valid FAT partition\n");
    while (1)
      continue;
  }

  // Ok, we have the partition, now work out where the FAT is etc
  sdcard_readsector(fat32_partition_start);

#if 0
  for(j=0;j<64;j++) {
    if (!(j&7)) printf("\n %02x :",j);
    printf(" %02x",buffer[j]);
  }
  printf("\n");
#endif

  fat32_sectors_per_cluster = buffer[0x0d];
  for (j = 0; j < 2; j++)
    ((char *)&fat32_reserved_sectors)[j] = buffer[0x0e + j];
  for (j = 0; j < 4; j++)
    ((char *)&fat32_data_sectors)[j] = buffer[0x20 + j];
  for (j = 0; j < 4; j++)
    ((char *)&fat32_sectors_per_fat)[j] = buffer[0x24 + j];

  fat32_cluster2_sector = fat32_partition_start + fat32_reserved_sectors + fat32_sectors_per_fat + fat32_sectors_per_fat;

#if 0
  printf("%ld sectors per fat, %ld reserved sectors, %d sectors per cluster.\n",
      fat32_sectors_per_fat,fat32_reserved_sectors,fat32_sectors_per_cluster);
  printf("Cluster 2 begins at sector $%08lx\n",fat32_cluster2_sector);
#endif

  sdcard_setup = 1;
}

unsigned long fat32_nextclusterinchain(unsigned long cluster)
{
  unsigned short offset_in_sector = (cluster & 0x7f) << 2;
  unsigned long fat_sector = fat32_partition_start + fat32_reserved_sectors;
  fat_sector += (cluster >> 7);

  sdcard_readsector(fat_sector);
  return *(unsigned long *)(&buffer[offset_in_sector]);
}

void hy_close(void)
{
}

unsigned long hy_opendir_cluster = 0;
unsigned long hy_opendir_sector = 0;
unsigned char hy_opendir_sector_in_cluster = 0;
unsigned int hy_opendir_offset_in_sector = 0;

void hy_opendir(void)
{
  if (!sdcard_setup)
    setup_sdcard();

  hy_opendir_cluster = 2;
  hy_opendir_sector = fat32_cluster2_sector;
  hy_opendir_sector_in_cluster = 0;
  hy_opendir_offset_in_sector = 0;

  // bring it back by one direntry, so that first advance will increment to correct location
  hy_opendir_offset_in_sector -= 0x20;

}

struct m65_dirent hy_dirent;

int8_t advance_to_next_entry(void)
{
  hy_opendir_offset_in_sector += 0x20;
  if (hy_opendir_offset_in_sector < 512)
    return 0;
  
  // Chain through directory as required
  hy_opendir_offset_in_sector = 0;
  hy_opendir_sector_in_cluster++;
  hy_opendir_sector++;
  if (hy_opendir_sector_in_cluster >= fat32_sectors_per_cluster) {
    hy_opendir_sector_in_cluster = 0;
    hy_opendir_cluster = fat32_nextclusterinchain(hy_opendir_cluster);
    if (hy_opendir_cluster >= 0x0ffffff0) {
      // end of directory reached
      return -2;
    }
    hy_opendir_sector = (hy_opendir_cluster - 2) * fat32_sectors_per_cluster + fat32_cluster2_sector;
  }
  if (!hy_opendir_cluster)
    return -2;

  sdcard_readsector(hy_opendir_sector);
  return 0;
}

void copy_to_dnamechunk_from_offset(unsigned char* dirent, char* dnamechunk, int offset, int numuc2chars)
{
  int k;
  for (k = 0; k < numuc2chars; k++) {
    dnamechunk[k] = dirent[offset + k * 2];
  }
}

void copy_vfat_chars_into_dname(unsigned char* dirent, char* dname, int seqnumber)
{
  // increment char-pointer to the seqnumber string chunk we'll copy across
  dname = dname + 13 * (seqnumber - 1);
  copy_to_dnamechunk_from_offset(dirent, dname, 0x01, 5);
  dname += 5;
  copy_to_dnamechunk_from_offset(dirent, dname, 0x0e, 6);
  dname += 6;
  copy_to_dnamechunk_from_offset(dirent, dname, 0x1c, 2);
}

struct m65_dirent *hy_readdir(void)
{
  unsigned char vfatEntry = 0, firstTime, deletedEntry = 0;
  uint8_t seqnumber;
  unsigned char *dirent;

  while (1) {
    // Get DOS directory entry and populate
    if (advance_to_next_entry() == -2) // exiting due to end-of-directory
      return NULL;
    dirent = &buffer[hy_opendir_offset_in_sector];

    // Check if this is a VFAT entry
    if (dirent[0x0b] == 0x0f) {
      // Read in all FAT32-VFAT entries to extract out long filenames
      // first byte is sequence (1-19) plus end marker 0x40, but end can come
      // first and name might be in reverse order! (or is this always the case?)
      vfatEntry = 1;
      firstTime = 1;
      do {
        if (dirent[0x00] == 0xe5) { // if deleted-entry, then ignore
          deletedEntry = 1;
        }
        if (!deletedEntry) {
          // we only copy filename if entry is not deleted
          seqnumber = dirent[0x00] & 0x1f;

          // assure there is a null-terminator
          if (firstTime) {
            hy_dirent.d_name[seqnumber * 13] = 0;
            firstTime = 0;
          }

          // vfat seqnumbers will be parsed from high to low, each containing up to 13 UCS-2 characters
          copy_vfat_chars_into_dname(dirent, hy_dirent.d_name, seqnumber);
        }

        // Get next FAT directory entry and populate
        if (advance_to_next_entry() == -2)
          return NULL;
        dirent = &buffer[hy_opendir_offset_in_sector];

        // if next dirent is not a vfat entry, break out
      } while (dirent[0x0b] == 0x0f && seqnumber > 1);
      // printf("vfat = '%s'\n", hy_dirent.d_name);
      // press_any_key(0,0);
    }

    // ignore deleted vfat entries and deleted entries
    // ignore everything with underscore or tilde as first character (MacOS)
    // ignore any vfat files starting with '.' (such as mac osx '._*' metadata files)
    // if the DOS 8.3 entry is a deleted-entry, then ignore
    if (deletedEntry || dirent[0x00] == 0xe5
        || dirent[0x00] == 0x7e || dirent[0x00] == 0x5f
        || (vfatEntry && hy_dirent.d_name[0] == '.')) {
      hy_dirent.d_name[0] = 0;
      vfatEntry = 0;
      deletedEntry = 0;
      continue;
    }

    // copy start of file inode
    ((unsigned char *)&hy_dirent.d_ino)[0] = dirent[0x1a];
    ((unsigned char *)&hy_dirent.d_ino)[1] = dirent[0x1b];
    ((unsigned char *)&hy_dirent.d_ino)[2] = dirent[0x14];
    ((unsigned char *)&hy_dirent.d_ino)[3] = dirent[0x15];

    // copy size of file in bytes
    ((unsigned char *)&hy_dirent.d_reclen)[0] = dirent[0x1c];
    ((unsigned char *)&hy_dirent.d_reclen)[1] = dirent[0x1d];
    ((unsigned char *)&hy_dirent.d_reclen)[2] = dirent[0x1e];
    ((unsigned char *)&hy_dirent.d_reclen)[3] = dirent[0x1f];

    // if not vfat-longname, then extract out old 8.3 name
    if (!vfatEntry) {
      memcpy(hy_dirent.d_name, dirent, 8);
      hy_dirent.d_name[8] = '.';
      memcpy(hy_dirent.d_name+9, dirent+8, 4);
      hy_dirent.d_name[12] = 0;
    }

    if (hy_dirent.d_name[0]) // sanity check, deleted check is done further up
      return &hy_dirent;

    // for (k = 0; k < 16; k++)
    //   printf("%02x ", dirent[k]);
    // printf("\n\n");
  }

  // won't be reached
  return NULL;
}

void hy_closedir(void)
{
}

unsigned long file_cluster = 0;
unsigned long file_sector = 0;
unsigned char file_sector_in_cluster = 0;

unsigned char hy_open(char *filename)
{
  struct m65_dirent *de;
  if (!sdcard_setup)
    setup_sdcard();
  hy_opendir();
  while (de = hy_readdir()) {
    // printf("file '%s' at cluster $%lx\n", de->d_name, de->d_ino);
    if (!strcmp(de->d_name, filename)) {
      file_cluster = de->d_ino;
      file_sector_in_cluster = 0;
      file_sector = (file_cluster - 2) * fat32_sectors_per_cluster + fat32_cluster2_sector;
      return 0;
    }
  }
  return 0xff;
}

unsigned short hy_read512(void)
{
  unsigned long the_sector = file_sector;
  if (!sdcard_setup)
    setup_sdcard();

  if (!file_cluster)
    return 0;

  file_sector_in_cluster++;
  file_sector++;
  if (file_sector_in_cluster >= fat32_sectors_per_cluster) {
    file_sector_in_cluster = 0;
    file_cluster = fat32_nextclusterinchain(file_cluster);
    if (file_cluster >= 0x0ffffff0 || (!file_cluster)) {
      file_cluster = 0;
    }
    file_sector = (file_cluster - 2) * fat32_sectors_per_cluster + fat32_cluster2_sector;
  }

  sdcard_readsector(the_sector);

  return 512;
}

void hy_closeall(void)
{
}

/***************************************************************************

 FPGA / Core file / Hardware platform routines

 ***************************************************************************/

/*
  Bitstream file chooser. Adapted from Freeze Menu disk
  image chooser.

  It is displayed over the top of the normal freeze menu,
  and so we use that screen mode.

  We get our list of disknames and put them at $40000.
  As we only care about their names, and file names are
  limited to 64 characters, we can fit ~1000.
  In fact, we can only safely mount images with names <32
  characters.

  We return the disk image name or a NULL pointer if the
  selection has failed and $FFFF if the user cancels selection
  of a disk.
 */

short file_count = 0;
short selection_number = 0;
short display_offset = 0;

#include <cbm_screen_charmap.h>
char *diskchooser_instructions = " Select file for slot X, press <RETURN> "
                                 "   to accept or press <STOP> to abort   ";
#include <cbm_petscii_charmap.h>
#define erase_message "- Erase Slot -"

#define SCREEN_ADDRESS 0x0400L
#define COLOUR_RAM_ADDRESS 0xff80000L
#define HIGHLIGHT_ATTR 0x21
#define NORMAL_ATTR 0x01

#define FILELIST_MAX 512
#define FILELIST_ADDRESS 0x40000L
#define FILESCREEN_ADDRESS 0x48000L

char disk_name_return[65];
char disk_display_return[40];

#ifdef WITH_JOYSTICK
unsigned char read_joystick_input(void)
{
  unsigned char x = 0, v;

  if ((v = PEEK(0xDC00) & 0x1f) == 0x1f)
    v = PEEK(0xDC01) & 0x1f;

/*
 * This is a disaster recovery function that uses
 * an adapter to wire an joystick to the floppy disk
 * interface!
 */
#ifdef WITH_FLOPPYJOYSTICK
  if (!v) // all is zero, not possible!
    v = (PEEK(0xD6A0) >> 3) & 0x1f; // use floppy adapter for joystick input
#endif /* WITH_FLOPPYJOYSTICK */

  if (!(v & 16))
    x = 0x0d; // FIRE/F_INDEX = return
  else if (!(v & 1))
    x = 0x91; // UP/F_DISKCHANGED = CRSR-UP
  else if (!(v & 8))
    x = 0x1d; // RIGHT/F_TRACK0 = CRSR-RIGHT
  else if (!(v & 4))
    x = 0x9d; // LEFT/F_WRITEPROTECT = CRSR-LEFT
  else if (!(v & 2))
    x = 0x11; // DOWN/F_RDATA = CRSR-DOWN

  // wait for release of joystick
  while (v != 0x1f) {
    v = PEEK(0xDC00) & PEEK(0xDC01) & 0x1f;

#ifdef WITH_FLOPPYJOYSTICK
    if (!v) // all is zero, not possible!
      v = (PEEK(0xD6A0) >> 3) & 0x1f; // use floppy adapter for joystick input
#endif /* WITH_FLOPPYJOYSTICK */

  }

  return x;
}
#endif

/*
 * int8_t read_and_check_core()
 *
 * reads the header from the file in disk_name_return
 * (set by select_bitstream_file), stores header information
 * in gobal variables and does sanity checks.
 *
 * returns 0 on no errors, <0 on failure. stores failure
 * reason in global variable (screencodes)
 *
 */
#include <cbm_screen_charmap.h>
int8_t read_and_check_core(uint8_t require_mega)
{
  unsigned char fd;

  // initialize fields
  corefile_model_id = 0;
  memset(corefile_error, ' ', 32);
  memset(corefile_name, ' ', 32);
  memset(corefile_version, ' ', 32);
  memcpy(corefile_name, "UNKNOWN CORE TYPE", 17);
  memcpy(corefile_version, "UNKNOWN VERSION", 15);

  fd = hy_open(disk_name_return);
  if (fd == 0xff) {
    // Couldn't open the file.
    memcpy(corefile_error, "Could not open core file!", 25);
    return -1;
  }

  y = hy_read512();
  if (!y) {
    memcpy(corefile_error, "Failed to read core file!", 25);
    return -2;
  }

  // check for core bitstream signature
  for (x = 0; x < 16; x++)
    if (buffer[x] != bitstream_magic[x])
      break;
  if (x < 16) {
    memcpy(corefile_error, "Core signature not found!", 25);
    return -3;
  }

  // copy and convert name and version to screencode
  for (x = 0; x < 32; x++) {
    corefile_name[x] = ascii2screen(buffer[0x10 + x], ' ');
    corefile_version[x] = ascii2screen(buffer[0x30 + x], ' ');
  }

  // check hardware model compability
  corefile_model_id = buffer[0x70];
  if (corefile_model_id != hw_model_id) {
    memcpy(corefile_error, "Core hardware model mismatch!", 29);
    return -4;
  }

  // only allow valid cores with MEGA65 as core name
  if (require_mega) {
    for (x = 0; x < 7; x++)
      if (buffer[0x10 + x] != mega65core_magic[x])
        break;
    for (y = ((x < 7) ? 0xff : 0); x < 32; x++)
      y |= buffer[0x10 + x];
    if (y) {
      memcpy(corefile_error, "Not a MEGA65 core!", 18);
      return -5;
    }
  }

  return 0;
}
#include <cbm_petscii_charmap.h>

void select_bs_copy_name()
{
  lcopy(FILELIST_ADDRESS + (selection_number * 64), (long)disk_name_return, 64);
  for (x = 63; x && disk_name_return[x] == ' '; x--)
    disk_name_return[x] = 0;
  disk_name_return[64] = 0;
}

void select_bs_draw_list(void)
{
  unsigned addr = SCREEN_ADDRESS;
  // unsigned char i, x;
  // unsigned char name[40];

  // wait for raster leaving screen
  while (!(PEEK(0xD011)&0x80));

  // set colour
  lfill(COLOUR_RAM_ADDRESS, NORMAL_ATTR, 40 * 23);

  // copy pregenerated screen
  lcopy(FILESCREEN_ADDRESS + display_offset * 40, SCREEN_ADDRESS, 23 * 40);
  // highlight selected line
  lfill(COLOUR_RAM_ADDRESS + (selection_number - display_offset) * 40, HIGHLIGHT_ATTR, 40);
}

/*
 * uchar select_bitstream_file(uchar slot)
 *
 * displays a file selector with core files on SD
 *
 * returns
 *   0 - nothing was selected, abort
 *   1 - special erase entry was selected
 *   2 - file was selected, filename in disk_name_return
 *
 * side-effects:
 *  disk_name_return may be changed
 */
unsigned char select_bitstream_file(unsigned char slot)
{
  signed char fnlen, j;
  struct m65_dirent *dirent;
  int idle_time = 0;

  selection_number = 0;
  display_offset = 0;

  // fill temp memory with space
  lfill(FILELIST_ADDRESS, ' ', 64L * FILELIST_MAX);
  lfill(FILESCREEN_ADDRESS, ' ', 40L * FILELIST_MAX + 1024L);

#include <cbm_screen_charmap.h>
  // clear screen and display scanning message
  lfill(SCREEN_ADDRESS, 0x20, 40 * 25);
  lcopy((long)"Scanning directory...", SCREEN_ADDRESS, 21);

  // Add dummy entry for erasing the slot
  lcopy((long)erase_message, FILESCREEN_ADDRESS, 14);
#include <ascii_charmap.h>
  lcopy((long)erase_message, FILELIST_ADDRESS, 14);

  hy_closeall();
  hy_opendir();
  file_count = 1;
  while (file_count < FILELIST_MAX && (dirent = hy_readdir()) != NULL) {
    fnlen = strlen(dirent->d_name);
#include <ascii_charmap.h>
    if (fnlen <= 64
        && ((!strncmp(&dirent->d_name[fnlen - 4], ".COR", 4)) || (!strncmp(&dirent->d_name[fnlen - 4], ".cor", 4)))) {
      // File is a core, store name to temp area
      lcopy((long)&dirent->d_name[0], FILELIST_ADDRESS + (file_count * 64), fnlen);

      // Also convert filename to screencode and copy to screen temp area
      for (j = 0; j < 40; j++)
        disk_name_return[j] = ascii2screen(dirent->d_name[j], 0x66);
      if (fnlen > 40) {
        // filename is longer than 40 chars, so we make a small ellipse using checkerboard
        for (j--, fnlen--; j > 33; j--, fnlen--)
          disk_name_return[j] = ascii2screen(dirent->d_name[fnlen], 0x66);
        disk_name_return[j--] = 0x66;
        disk_name_return[j--] = 0x66;
        disk_name_return[j--] = 0x66;

      }
#include <cbm_petscii_charmap.h>
      lcopy((long)disk_name_return, FILESCREEN_ADDRESS + (file_count * 40), fnlen);
      file_count++;
/*
#include <cbm_screen_charmap.h>
      disk_name_return[25] = 0x80;
      mhx_writef("--%08lx--%s--\n", dirent->d_reclen, disk_name_return);
#include <cbm_petscii_charmap.h>
      mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
*/
    }
  }
  hy_closedir();

  // Okay, we have some disk images, now get the user to pick one!
  diskchooser_instructions[22] = 0x30 + slot;
  // Draw instructions to FOOTER
  lcopy((long)diskchooser_instructions, SCREEN_ADDRESS + 23 * 40, 80);
  lfill(COLOUR_RAM_ADDRESS + 23 * 40, HIGHLIGHT_ATTR, 80);

  select_bs_draw_list();
  while (1) {

    if ((x = PEEK(0xD610U)))
      POKE(0xD610U, 0);
#ifdef WITH_JOYSTICK
    else
      x = read_joystick_input();
#endif /* WITH_JOYSTICK */

#include <cbm_screen_charmap.h>
    if (!x) {
      idle_time++;

      if (selection_number && idle_time == 150) {
        select_bs_copy_name();
        read_and_check_core(0);

        if (selection_number - display_offset < 12) {
          mhx_draw_rect(2, 17, 32, 3, " Corefile ", MHX_A_NOCOLOR);
          memcpy((void *)(0x400 + 3 + 18*40), corefile_name, 32);
          memcpy((void *)(0x400 + 3 + 19*40), corefile_version, 32);
          memcpy((void *)(0x400 + 3 + 20*40), corefile_error, 32);
        }
        else {
          mhx_draw_rect(2, 1, 32, 3, " Corefile ", MHX_A_NOCOLOR);
          memcpy((void *)(0x400 + 3 + 2*40), corefile_name, 32);
          memcpy((void *)(0x400 + 3 + 3*40), corefile_version, 32);
          memcpy((void *)(0x400 + 3 + 4*40), corefile_error, 32);
        }
      }

      usleep(10000);
      continue;
    }
    else
      idle_time = 0;
#include <cbm_petscii_charmap.h>

    switch (x) {
    case 0x03: // RUN-STOP = make no change
    case 0x1b: // ESC
      return SELECTED_FILE_INVALID;
    case 0x0d: // Return = select this disk.
      // was erase (first entry) selected?
      if (selection_number == 0) {
        disk_name_return[0] = 0;
        disk_display_return[0] = 0;
        return SELECTED_FILE_ERASE;
      }

      // Copy name out
      lcopy(FILESCREEN_ADDRESS + (selection_number * 40), (long)disk_display_return, 40);
      select_bs_copy_name();
      return SELECTED_FILE_VALID;

    case 0x11:
    case 0x1d: // Cursor down or right
      selection_number++;
      if (selection_number >= file_count)
        selection_number = 0;
      break;
    case 0x91:
    case 0x9d: // Cursor up or left
      selection_number--;
      if (selection_number < 0)
        selection_number = file_count - 1;
      break;
    }

    // Adjust display position
    if (selection_number < display_offset)
      display_offset = selection_number;
    if (selection_number > (display_offset + 22))
      display_offset = selection_number - 22;
    if (display_offset > (file_count - 22))
      display_offset = file_count - 22;
    if (display_offset < 0)
      display_offset = 0;

    select_bs_draw_list();
  }

  return SELECTED_FILE_INVALID;
}

// clang-format off
#include <cbm_screen_charmap.h>
models_type mega_models[] = {
  { 0x01, 8, "MEGA65 R1" },
  { 0x02, 4, "MEGA65 R2" },
  { 0x03, 8, "MEGA65 R3" },
  { 0x04, 8, "MEGA65 R4" },
  { 0x05, 8, "MEGA65 R5" },
  { 0x21, 4, "MEGAphone R1" },
  { 0x22, 4, "MEGAphone R4" },
  { 0x40, 4, "Nexys4" },
  { 0x41, 4, "Nexys4DDR" },
  { 0x42, 4, "Nexys4DDR-widget" },
  { 0x60, 4, "QMTECH A100T"},
  { 0x61, 8, "QMTECH A200T"},
  { 0x62, 8, "QMTECH A325T"},
  { 0xFD, 4, "Wukong A100T" },
  { 0xFE, 8, "Simulation" },
  { 0x00, 0, NULL }
};
// clang-format on

int8_t probe_hardware_version(void)
{
  uint8_t k;

  hw_model_id = PEEK(0xD629);
  for (k = 0; mega_models[k].name; k++)
    if (hw_model_id == mega_models[k].model_id)
      break;

  if (!mega_models[k].name)
    return -1;

  hw_model_name = mega_models[k].name;

  // we need to set those according to the hardware found
#ifdef STANDALONE
  SLOT_MB = mega_models[k].slot_mb;
  SLOT_SIZE_PAGES = SLOT_MB;
  SLOT_SIZE_PAGES <<= 12;
  SLOT_SIZE = SLOT_SIZE_PAGES;
  SLOT_SIZE <<= 8;
#endif

  return 0;
}

char *get_model_name(uint8_t model_id)
{
  static char *model_unknown = "?unknown?";
  uint8_t k;

  for (k = 0; mega_models[k].name; k++)
    if (model_id == mega_models[k].model_id)
      return mega_models[k].name;

  return model_unknown;
}
#include <cbm_petscii_charmap.h>

/***************************************************************************

 High-level flashing routines

 ***************************************************************************/

unsigned char j, k;
unsigned short flash_time = 0, crc_time = 0, load_time = 0;

void flash_inspector(void)
{
#ifdef QSPI_FLASH_INSPECT
  addr = 0;
  read_data(addr);
  printf("Flash @ $%08x:\n", addr);
  for (i = 0; i < 256; i++) {
    if (!(i & 15))
      printf("+%03x : ", i);
    printf("%02x", data_buffer[i]);
    if ((i & 15) == 15)
      printf("\n");
  }

  printf("page_size=%d\n", page_size);

  while (1) {
    x = 0;
    while (!x) {
      x = PEEK(0xd610);
    }

    if (x) {
      POKE(0xd610, 0);
      switch (x) {
      case 0x51:
      case 0x71:
        addr -= 0x10000;
        break;
      case 0x41:
      case 0x61:
        addr += 0x10000;
        break;
      case 0x11:
      case 0x44:
      case 0x64:
        addr += 256;
        break;
      case 0x91:
      case 0x55:
      case 0x75:
        addr -= 256;
        break;
      case 0x1d:
      case 0x52:
      case 0x72:
        addr += 0x400000;
        break;
      case 0x9d:
      case 0x4c:
      case 0x6c:
        addr -= 0x400000;
        break;
      case 0x03:
        return;
      case 0x50:
      case 0x70:
        query_flash_protection(addr);
        press_any_key(0, 0);
        break;
      case 0x54:
      case 0x74:
        // T = Test
        // Erase page, write page, read it back
        erase_sector(addr);
        // Some known data
        for (i = 0; i < 256; i++) {
          data_buffer[i] = i;
          data_buffer[0x1ff - i] = i;
        }
        data_buffer[0] = addr >> 24L;
        data_buffer[1] = addr >> 16L;
        data_buffer[2] = addr >> 8L;
        data_buffer[3] = addr >> 0L;
        addr += 256;
        data_buffer[0x100] = addr >> 24L;
        data_buffer[0x101] = addr >> 16L;
        data_buffer[0x102] = addr >> 8L;
        data_buffer[0x103] = addr >> 0L;
        addr -= 256;
        //        lfill(0xFFD6E00,0xFF,0x200);
        printf("E: %02x %02x %02x\n", lpeek(0xffd6e00), lpeek(0xffd6e01), lpeek(0xffd6e02));
        printf("F: %02x %02x %02x\n", lpeek(0xffd6f00), lpeek(0xffd6f01), lpeek(0xffd6f02));
        printf("P: %02x %02x %02x\n", data_buffer[0], data_buffer[1], data_buffer[2]);
        // Now program it
        unprotect_flash(addr);
        query_flash_protection(addr);
        printf("About to call program_page()\n");
        //        program_page(addr,page_size);
        program_page(addr, 256);
        press_any_key(0, 0);
      }

      read_data(addr);
      printf("%cFlash @ $%08lx:\n", 0x93, addr);
      for (i = 0; i < 256; i++) {
        if (!(i & 15))
          printf("+%03x : ", i);
        printf("%02x", data_buffer[i]);
        if ((i & 15) == 15)
          printf("\n");
      }
      printf("Bytes differ? %s\n", PEEK(0xD689) & 0x40 ? "Yes" : "No");
      printf("page_size=%d\n", page_size);
    }
  }
#endif
}

#ifdef SHOW_FLASH_DIFF
void debug_memory_block(int offset, unsigned long dbg_addr)
{
  for (i = 0; i < 256; i++) {
    if (!(i & 15))
      printf("%c%07lx:", 5, dbg_addr + i);
    if (data_buffer[offset + i] != buffer[offset + i])
      printf("%c", 28);
    else
      printf("%c", 153);
    printf("%02x", data_buffer[offset + i]);
  }
  printf("%c", 5);
  press_any_key(0, 0);
}
#endif

unsigned char flash_region_differs(unsigned long attic_addr, unsigned long flash_addr, long size)
{
  while (size > 0) {

    lcopy(0x8000000 + attic_addr, 0xffd6e00L, 512);
    if (!verify_data_in_place(flash_addr)) {
#ifdef SHOW_FLASH_DIFF
      printf("\nVerify error  ");
      press_any_key(0, 0);
      printf("%cattic_addr=$%08lX, flash_addr=$%08lX\n", 0x93, attic_addr, flash_addr);
      read_data(flash_addr);
      lcopy(0x8000000L + attic_addr, (long)buffer, 512);
      debug_memory_block(0, flash_addr);
      debug_memory_block(256, flash_addr);
      printf("comparing read data against reread yields %d\n", verify_data_in_place(flash_addr));
      press_any_key(0, 0);
      printf("%c", 0x93);
#endif
      return 1;
    }
    attic_addr += 512;
    flash_addr += 512;
    size -= 512;
  }
  return 0;
}

void reflash_slot(unsigned char the_slot, unsigned char selected_file, char *slot0version)
{
  unsigned long size, waddr, end_addr;
  unsigned short bytes_returned;
  unsigned char fd, tries;
  unsigned char erase_mode = 0;
  unsigned char slot = the_slot;
  uint32_t core_crc;

  if (selected_file == SELECTED_FILE_INVALID)
    return;

#ifndef QSPI_ERASE_ZERO
  if (selected_file == 1 && slot == 0) {
    // we refuse to erase slot 0
    printf("%c%c\nRefusing to erase slot 0!%c\n\n", 0x93, 0x1c, 0x5);
    press_any_key(0, 0);
    return;
  }
#endif

  printf("%cPreparing to reflash slot %d...\n\n", 0x93, slot);

  hy_closeall();

  // Read a few times to make sure transient initial read problems disappear
  read_data(0);
  read_data(0);
  read_data(0);

  /*
    The 512S QSPI on the R3A boards _sometimes_ suffer high write error rates
    that can often be worked around by processing flash sector at a time, so
    that if such an error occurs that requires rewriting a sector*, we can do just
    that sector. It also has the nice side-effect that if only part of a bitstream
    (or the embedded files in a COR file) change, then only that part will need to
    be modified.

    The trick is that we will have to refactor the code here quite a bit, because
    we can't seek backwards through an SD card file here, and the hardware verification
    support requires that the data be in the SD card buffer, so we will have to buffer
    a sector's worth of data in HyperRAM (non-MEGA65R3 targets are assumed to have JTAG
    and Vivado as the main flashing solution for now. We can resolve this post-release),
    and then copying those sectors of data back into the SD card sector buffer for
    hardware verification.

    This might end up being a bit slower or a bit faster, its hard to predict right now.
    The extra copying will slow things down, but not having to read the file from SD card
    twice will potentially speed things up.  Overall, performance should be quite acceptable,
    however.

    It's probably easiest in fact to simply read the whole <= 8MB COR file into HyperRAM,
    and then just work from that.

    * This only occurs if a byte gets bits cleared that shouldn't have been cleared.
    This happens only when the QSPI chip misses clock edges or detects extra ones,
    both of which we have seen happen.
  */

  lfill((unsigned long)buffer, 0, 512);

  // return code of select_bitstream_file > 1 means a file was selected
  if (selected_file == SELECTED_FILE_VALID) {
    printf("%cChecking core file...\n\n", 0x93);
    lcopy((long)disk_display_return, SCREEN_ADDRESS + 40, 40);

    fd = hy_open(disk_name_return);
    if (fd == 0xff) {
      // Couldn't open the file.
      printf("\n%cERROR: Could not open core file!%c\n", 25, 3);
      press_any_key(0, 0);
      return;
    }

    printf("\n");

    // TODO: also check NAME "MEGA65" for slot 0 flash!
    //if (!check_model_id_field(slot == 0 ? 1 : 0, slot0version))
    //  return;

#if defined(STANDALONE) && defined(QSPI_DEBUG)
    printf("%c", 0x93);
    make_crc32_tables(data_buffer, buffer);
    init_crc32();
    update_crc32(11, "hello world");
    printf("\n\nhello world CRC32 = %08lX\n", get_crc32());
    press_any_key(0, 0);
#endif

    // start reading file from beginning again
    // (as the model_id checking read the first 512 bytes already)
    fd = hy_open(disk_name_return);

    printf("%cLoading COR file into Attic RAM...\n", 0x93);
    progress_start(SLOT_SIZE_PAGES, "Loading");

    for (addr = 0; addr < SLOT_SIZE; addr += 512) {
      bytes_returned = hy_read512();
      if (!bytes_returned)
        break;
      lcopy(0xffd6e00L, 0x8000000L + addr, 512);
      progress_bar(2, "Loading");
    }
    addr_len = addr; // save last sector
    // fill rest of attic ram with emptiness
    for (; addr < SLOT_SIZE; addr += 512) {
      lfill(addr, 0xff, 512);
      progress_bar(2, "Filling");
    }
    progress_time(load_time);
    hy_close();
    //printf("%c%cLoaded COR file in %u seconds.\n", 0x11, 0x11, load_time);

    // always do a CRC32 check!
    printf("%cGenerating CRC32 checksum...\n", 0x93);
    progress_start(addr_len >> 8, "Checksum");
    // lets use two 512 byte buffers for our 1024 byte crc32 lookup table
    make_crc32_tables(data_buffer, buffer);
    init_crc32();
    for (y = 1, addr = 0; addr < addr_len; addr += 256) {
      // we don't need the part string anymore, so we reuse this buffer
      // note: part is only used in probe_qspi_flash
      lcopy(0x8000000L + addr, (unsigned long)part, 256);
      if (y) {
        // the first sector has the real length and the CRC32
        addr_len = *(uint32_t *)(part + 0x80);
        progress_goal = addr_len >> 8;
        core_crc = *(uint32_t *)(part + 0x84);
        // set CRC bytes to pre-calculation value
        *(uint32_t *)(part + 0x84) = 0xf0f0f0f0UL;

        EIGHT_FROM_TOP;
        printf("\n\nCORE Length = %08lx\n", addr_len);
        printf("CORE CRC32  = %08lx", core_crc);

        y = 0;
      }
      update_crc32(addr_len - addr > 255 ? 0 : addr_len - addr, part);
      progress_bar(1, "Checksum");
    }
    progress_time(crc_time);
    EIGHT_FROM_TOP;
    printf("\n\n\nCALC CRC32  = %08lx\n", get_crc32());

    if (addr_len < 4096 || core_crc != get_crc32()) {
      printf("\n%cCHECKSUM MISMATCH%c %ds %ds\n", 28, 5, load_time, crc_time);
      if (slot == 0) {
        printf("\nRefusing to flash slot 0!\n");
        press_any_key(0, 0);
        return;
      }
      else {
        printf("\nPress F10 to flash anyway, or any other key to abort.\n", 28, 5);
        bytes_returned = press_any_key(0, 1);
        if (bytes_returned != 0xfa)
          return;
      }
    }
    else {
      printf("\n%cChecksum matches, good to flash.%c\n", 30, 5);
      bytes_returned = press_any_key(0, 0);
      if (bytes_returned == 0x03 || bytes_returned == 0x1b)
        return;
    }

    // start flashing
    printf("%c", 0x93);
    progress_start(SLOT_SIZE_PAGES, "Flashing");
    // erase first 256k first
    end_addr = addr = SLOT_SIZE * slot;
    // tests with Senfsosse showed that 256k or 512k were not enough to ensure slot 1 boot
    erase_some_sectors(addr + 1024L * 1024L, 0);
    // start at the end...
    addr = end_addr + SLOT_SIZE;
    while (addr > end_addr) {
      if (addr <= (unsigned long)num_4k_sectors << 12)
        size = 4096;
      else
        size = 1L << ((long)flash_sector_bits);
      addr -= size;
#if 0
      printf("\n%d %08lX %08lX", num_4k_sectors, (unsigned long)num_4k_sectors << 12, addr);
      printf("\nsize = %ld", size);
      press_any_key(0, 0);
#endif

      // Do a dummy read to clear any pending stuck QSPI commands
      // (else we get incorrect return value from QSPI verify command)
      while (!verify_data_in_place(0L))
        read_data(0);

      // try 10 times to erase/write the sector
      tries = 0;
      do {
        // Verify the sector to see if it is already correct
        printf("%c  Verifying sector at $%08lX/%07lX", 0x13, addr, addr - SLOT_SIZE * slot);
        if (!flash_region_differs(addr - SLOT_SIZE * slot, addr, size))
          break;

        // if we failed 10 times, we abort with the option for the flash inspector
        if (tries == 10) {
          printf("\n\n\n\n\n\n\n\n\n\nERROR: Could not write to flash after\n%d tries.\n", tries);

          // secret Ctrl-F (keycode 0x06) will launch flash inspector,
          // but only if QSPI_FLASH_INSPECTOR is defined!
          // otherwise: endless loop!
#ifdef QSPI_FLASH_INSPECTOR
          printf("Press Ctrl-F for Flash Inspector.\n");

          while (PEEK(0xD610))
            POKE(0xD610, 0);
          while (PEEK(0xD610) != 0x06)
            POKE(0xD610, 0);
          while (PEEK(0xD610))
            POKE(0xD610, 0);
          flash_inspector();
#else
          // TODO: re-erase start of slot 0, reprogram flash to start slot 1
          printf("\nPlease turn the system off!\n");
          // don't let the user do anything else
          while (1)
            POKE(0xD020, PEEK(0xD020) & 0xf);
#endif
          // don't do anything else, as this will result in slot 0 corruption
          // as global addr gets changed by flash_inspector
          return;
        }

        // next try to erase/program the sector
        tries++;

        // Erase Sector
        printf("%c    Erasing sector at $%08lX", 0x13, addr);
        POKE(0xD020, 2);
        erase_sector(addr);
        read_data(0xffffffff);
        POKE(0xD020, 0);

        // Program sector
        printf("%cProgramming sector at $%08lX", 0x13, addr);
        for (waddr = addr + size; waddr > addr; waddr -= 256) {
          lcopy(0x8000000L + waddr - 256 - SLOT_SIZE * slot, (unsigned long)data_buffer, 256);
          // display sector on screen
          // lcopy(0x8000000L+waddr-SLOT_SIZE*slot,0x0400+17*40,256);
          POKE(0xD020, 3);
          program_page(waddr - 256, 256);
          POKE(0xD020, 0);
        }
      } while (tries < 11);

      progress_bar(size >> 8, "Flashing");
    }
    progress_time(flash_time);

    // Undraw the sector display before showing results
    lfill(0x0400 + 12 * 40, 0x20, 512);
  }
  else if (selected_file == SELECTED_FILE_ERASE) {
    // extra question before erasing a slot
    printf("%c\nYou are about to erase slot %d!\n"
           "Are you sure you want to proceed? (y/n)%c\n\n",
        0x81, slot, 0x05);
    if (!mhx_check_input("y", 0, MHX_A_NOCOLOR))
      return;
    printf("%c", 0x93);

    // Erase mode
    progress_start(SLOT_SIZE_PAGES, "Erasing");
    addr = SLOT_SIZE * slot;
    erase_some_sectors(addr + SLOT_SIZE, 1);
    progress_time(flash_time);
  }

  EIGHT_FROM_TOP;
  printf("Flash slot successfully updated.      \n\n");
  if (selected_file == SELECTED_FILE_ERASE && flash_time > 0)
    printf("   Erase: %d sec \n\n", flash_time);
  else if (load_time + crc_time + flash_time > 0)
    printf("    Load: %d sec \n"
           "     CRC: %d sec \n"
           "   Flash: %d sec \n"
           "\n",
        load_time, crc_time, flash_time);

  press_any_key(1, 0);

  return;
}

/***************************************************************************

 Mid-level SPI flash routines

 ***************************************************************************/

unsigned char probe_qspi_flash(void)
{
  spi_cs_high();
  usleep(50000L);

#ifdef QSPI_VERBOSE
  printf("\nProbing flash...\n");
#endif

  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT, 0x02);

  //  flash_reset();

  // Disable OSK
  lpoke(0xFFD3615L, 0x7F);

  // Enable VIC-III attributes
  POKE(0xD031, 0x20);

  // Start by resetting to CS high etc
  bash_bits = 0xff;
  POKE(BITBASH_PORT, bash_bits);
  POKE(CLOCKCTL_PORT, 0x02);
  DEBUG_BITBASH(bash_bits);

  usleep(10000);

  fetch_rdid();
  read_registers();
  while ((manufacturer == 0xff) && (device_id == 0xffff)) {
    printf("%cERROR: Cannot communicate with QSPI\nflash device. Retry...%c\n\n", 28, 5);

    flash_reset();
    fetch_rdid();
    read_registers();
  }

#ifdef QSPI_DEBUG
  // hexdump info block
  for (i = 0; i < 0x80; i++) {
    if (!(i & 15))
      printf("+%03x : ", i);
    printf("%02x", (unsigned char)cfi_data[i]);
    if ((i & 15) == 15)
      printf("\n");
  }
  press_any_key(0, 0);
#endif
#ifdef QSPI_VERBOSE
  printf("\nQSPI Information\n\n");
#endif

  // this looks for ALT?\00 at cfi_data pos 0x51
  if (cfi_data[0x51] == 0x41 && cfi_data[0x52] == 0x4c && cfi_data[0x53] == 0x54 && cfi_data[0x56] == 0x00) {
    for (i = 0; i < cfi_data[0x57]; i++)
      part[i] = cfi_data[0x58 + i];
    part[i] = 0;
#ifdef QSPI_VERBOSE
    printf("Part         = %s\n"
           "Part Family  = %02x-%c%c\n",
        part, cfi_data[5], cfi_data[6], cfi_data[7]);
#endif
  }
  else {
    part[0] = 0;
#ifdef QSPI_VERBOSE
    printf("%cPart         = unknown %02x %02x %02x\n"
           "Part Family  = unknown%c\n",
        28, cfi_data[0x51], cfi_data[0x52], cfi_data[0x53], 5);
#endif
  }

#ifdef QSPI_VERBOSE
  printf("Manufacturer = $%02x\n", manufacturer);
  printf("Device ID    = $%04x\n", device_id);
  printf("RDID count   = %d\n", cfi_length);
  printf("Sector Arch  = ");
#endif

  if (cfi_data[4] == 0x00) {
#ifdef QSPI_VERBOSE
    printf("uniform 256kb\n");
#endif
    num_4k_sectors = 0;
    flash_sector_bits = 18;
  }
  else if (cfi_data[4] == 0x01) {
    num_4k_sectors = 1 + cfi_data[0x2d];
    flash_sector_bits = 16;
#ifdef QSPI_VERBOSE
    printf("%dx4kb param/64kb data\n", num_4k_sectors);
#endif
  }
  else {
#ifdef QSPI_VERBOSE
    printf("%cunknown ($%02x)%c\n", 28, cfi_data[4], 5);
#endif
    flash_sector_bits = 0;
  }
#ifdef QSPI_VERBOSE
  printf("Prgtime      = 2^%d us\n"
         "Page size    = 2^%d bytes\n",
      cfi_data[0x20], cfi_data[0x2a]);
#endif

  if (cfi_data[0x2a] == 8)
    page_size = 256;
  if (cfi_data[0x2a] == 9)
    page_size = 512;
  if (!page_size) {
    printf("%cWARNING: Unsupported page size%c\n", 28, 5);
    page_size = 0;
  }
#ifdef QSPI_VERBOSE
  printf("Est. prgtime = %d us/byte.\n", cfi_data[0x20] / cfi_data[0x2a]);
  printf("Est. erasetm = 2^%d ms/sector.\n", cfi_data[0x21]);
#endif

  // Work out size of flash in MB
  {
    unsigned char n = cfi_data[0x27];
    mb = 1;
    n -= 20;
    while (n) {
      mb = mb << 1;
      n--;
    }
  }

  slot_count = mb / SLOT_MB;
  // sanity check for slot count
  if (slot_count == 0 || slot_count > 8)
    slot_count = 8;

  // latency_code=3;
  latency_code = reg_cr1 >> 6;

#ifdef QSPI_VERBOSE
  printf("Flash size   = %d MB\n"
         "Flash slots  = %d slots of %d MB\n"
         "Register SR1 = %c$%02x%c\n",
      mb, slot_count, SLOT_MB, reg_sr1 == 0xff ? 28 : 5, reg_sr1, 5);
  // show flags
  if (reg_sr1 & 0x80)
    printf(" WRPROT");
  if (reg_sr1 & 0x40)
    printf(" PRGERR");
  if (reg_sr1 & 0x20)
    printf(" ERAERR");
  if (reg_sr1 & 0x02)
    printf(" WRLENA");
  if (reg_sr1 & 0x01)
    printf(" DEVBSY");
  if (reg_sr1 & 0xe3)
    printf("\n");
  printf("Register CR1 = %c$%02x%c (latency code %d)\n",
         reg_cr1 == 0xff ? 28 : 5, reg_cr1, 5, latency_code);
#endif

  // failed to detect, probably dip sw #3 = off
  if (mb == 0 || page_size == 0 || flash_sector_bits == 0 || part[0] == 0) {
    printf("\n%cERROR: Failed to probe flash\n       (dip #3 not on?)%c\n", 28, 5);
#ifndef STANDALONE
    // never return
    while (1)
      POKE(0xD020, PEEK(0xD020) + 1);
#endif
    return -1;
  }

#ifdef QSPI_VERBOSE
  press_any_key(0, 0);
#endif

  /* The 64MB = 512Mbit flash in the MEGA65 R3A comes write-protected, and with
     quad-SPI mode disabled. So we have to fix both of those (which then persists),
     and then flash the bitstream.
  */
  enable_quad_mode();

  read_registers();

  if (reg_sr1 & 0x80) {
    printf("\n%cERROR: Could not clear whole-of-flash write-protect flag.%c\n", 28, 5);
    while (1)
      POKE(0xD020, PEEK(0xD020) + 1);
  }

  printf("\nQuad-mode enabled,\nflash is write-enabled.\n\n");

  // Finally make sure that there is no half-finished QSPI commands that will cause erroneous
  // reads of sectors.
  read_data(0);
  read_data(0);
  read_data(0);

  printf("Done probing flash.\n\n");

  return 0;
}

void enable_quad_mode(void)
{
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x06); // WREN
  spi_cs_high();
  delay();

  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x01);
  spi_tx_byte(0x00);
  // Latency code = 01, quad mode=1
  spi_tx_byte(0x42);
  spi_cs_high();
  delay();

  // Wait for busy flag to clear
  // This can take ~200ms according to the data sheet!
  reg_sr1 = 0x01;
  while (reg_sr1 & 0x01) {
    read_sr1();
  }

#if 0
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x35); // RDCR
  c=spi_rx_byte();
  spi_cs_high();
  delay();
  printf("CR1=$%02x\n",c);
  press_any_key(0, 0);
#endif
}

void unprotect_flash(unsigned long addr)
{
  unsigned char c;

  //  printf("unprotecting sector.\n");

  i = addr >> flash_sector_bits;

  c = 0;
  while (c != 0xff) {

    // Wait for busy flag to clear
    reg_sr1 = 0x03;
    while (reg_sr1 & 0x03) {
      read_sr1();
    }

    spi_write_enable();

    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0xe1);
    spi_tx_byte(i >> 6);
    spi_tx_byte(i << 2);
    spi_tx_byte(0);
    spi_tx_byte(0);

    spi_tx_byte(0xff);
    spi_clock_low();

    spi_cs_high();
    delay();

    // Wait for busy flag to clear
    reg_sr1 = 0x03;
    while (reg_sr1 & 0x03) {
      read_sr1();
    }

    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0xe0);
    spi_tx_byte(i >> 6);
    spi_tx_byte(i << 2);
    spi_tx_byte(0);
    spi_tx_byte(0);
    c = spi_rx_byte();

    spi_cs_high();
    delay();
  }
  //   printf("done unprotecting.\n");
}

void query_flash_protection(unsigned long addr)
{
  unsigned long address_in_sector = 0;
  unsigned char c;

  i = addr >> flash_sector_bits;

  printf("DYB Protection flag: ");

  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xe0);
  spi_tx_byte(i >> 6);
  spi_tx_byte(i << 2);
  spi_tx_byte(0);
  spi_tx_byte(0);
  c = spi_rx_byte();
  printf("$%02x ", c);

  spi_cs_high();
  delay();
  printf("\n");

  printf("PPB Protection flags: ");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xe2);
  spi_tx_byte(i >> 6);
  spi_tx_byte(i << 2);
  spi_tx_byte(0);
  spi_tx_byte(0);
  c = spi_rx_byte();
  printf("$%02x ", c);

  spi_cs_high();
  delay();
  printf("\n");
}

void erase_some_sectors(unsigned long end_addr, unsigned char progress)
{
  unsigned long size;

  while (addr < end_addr) {
    if (addr < (unsigned long)num_4k_sectors << 12)
      size = 4096;
    else
      size = 1L << ((long)flash_sector_bits);

    printf("%c    Erasing sector at $%08lX", 0x13, addr);
    POKE(0xD020, 2);
    erase_sector(addr);
    read_data(0xffffffff);
    POKE(0xD020, 0);

    addr += size;
    if (progress)
      progress_bar(size >> 8, "Erasing");
  }
}

void erase_sector(unsigned long address_in_sector)
{

  unprotect_flash(address_in_sector);
  //  query_flash_protection(address_in_sector);

  // XXX Send Write Enable command (0x06 ?)
  //  printf("activating write enable...\n");
  spi_write_enable();

  // XXX Clear status register (0x30)
  //  printf("clearing status register...\n");
  while (reg_sr1 & 0x61) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x30);
    spi_cs_high();

    read_sr1();
  }

  // XXX Erase 64/256kb (0xdc ?)
  // XXX Erase 4kb sector (0x21 ?)
  //  printf("erasing sector...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  if ((addr >> 12) >= num_4k_sectors) {
    // Do 64KB/256KB sector erase
    //    printf("erasing large sector.\n");
    POKE(0xD681, address_in_sector >> 0);
    POKE(0xD682, address_in_sector >> 8);
    POKE(0xD683, address_in_sector >> 16);
    POKE(0xD684, address_in_sector >> 24);
    // Erase large page
    POKE(0xd680, 0x58);
  }
  else {
    // Do fast 4KB sector erase
    //    printf("erasing small sector.\n");
    spi_tx_byte(0x21);
    spi_tx_byte(address_in_sector >> 24);
    spi_tx_byte(address_in_sector >> 16);
    spi_tx_byte(address_in_sector >> 8);
    spi_tx_byte(address_in_sector >> 0);
  }

  // CLK must be set low before releasing CS according
  // to the S25F512 datasheet.
  // spi_clock_low();
  //  POKE(CLOCKCTL_PORT,0x00);

  // spi_cs_high();

  {
    // Give command time to be sent before we do anything else
    unsigned char b;
    for (b = 0; b < 200; b++)
      continue;
  }

  reg_sr1 = 0x03;
  while (reg_sr1 & 0x03) {
    read_registers();
  }

#ifndef QSPI_VERBOSE
  if (reg_sr1&0x20) {
    printf("error erasing sector @ $%08x\n",address_in_sector);
    press_any_key(0, 0);
  }
#ifdef QSPI_DEBUG
  else
    printf("sector at $%08llx erased.\n%c",address_in_sector,0x91);
#endif /* QSPI_DEBUG */
#endif /* QSPI_VERBOSE */
}

unsigned char verify_data_in_place(unsigned long start_address)
{
  unsigned char b;
  POKE(0xd020, 1);
  POKE(0xD681, start_address >> 0);
  POKE(0xD682, start_address >> 8);
  POKE(0xD683, start_address >> 16);
  POKE(0xD684, start_address >> 24);
  POKE(0xD680, 0x5f); // Set number of dummy cycles
  POKE(0xD680, 0x56); // QSPI Flash Sector verify command
  // XXX For some reason the busy flag is broken here.
  // So just wait a little while, but only a little while
  for (b = 0; b < 180; b++)
    continue;
  POKE(0xd020, 0);

  // 1 = verify success, 0 = verify failure
  if (PEEK(0xD689) & 0x40)
    return 0;
  else
    return 1;
}

unsigned char verify_data(unsigned long start_address)
{
  // Copy data to buffer for hardware compare/verify
  lcopy((unsigned long)data_buffer, 0xffd6e00L, 512);

  return verify_data_in_place(start_address);
}

void program_page(unsigned long start_address, unsigned int page_size)
{
  unsigned char b, pass = 0;
  unsigned char errs = 0;

top:
  pass++;
  //  printf("About to clear SR1\n");

  spi_clear_sr1();
  //  printf("About to clear WREN\n");
  spi_write_disable();

  //  printf("Waiting for flash to go non-busy\n");
  while (reg_sr1 & 0x03) {
    //    printf("flash busy. ");
    read_sr1();
  }

  // XXX Send Write Enable command (0x06 ?)
  //  printf("activating write enable...\n");
  spi_write_enable();

  // XXX Clear status register (0x30)
  //  printf("clearing status register...\n");
  while (reg_sr1 & 0x61) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x30);
    spi_cs_high();

    // We have to read registers here to clear error flags?
    // i.e. not just read SR1?
    read_registers();
  }

  // We shouldn't need free-running clock, and it may in fact cause problems.
  POKE(0xd6cd, 0x02); // do we need to do this every block?

  spi_write_enable();
  spi_clock_high();
  spi_cs_high();

  POKE(0xD020, 2);
  //  printf("Writing with page_size=%d\n",page_size);
  // printf("Data = $%02x, $%02x, $%02x, $%02x ... $%02x, $%02x, $%02x, $%02x ...\n",
  //         data_buffer[0],data_buffer[1],data_buffer[2],data_buffer[3],
  //         data_buffer[0x100],data_buffer[0x101],data_buffer[0x102],data_buffer[0x103]);
  if (page_size == 256) {
    // Write 256 bytes
    //    printf("256 byte program\n");
    lcopy((unsigned long)data_buffer, 0xffd6f00L, 256);

    POKE(0xD681, start_address >> 0);
    POKE(0xD682, start_address >> 8);
    POKE(0xD683, start_address >> 16);
    POKE(0xD684, start_address >> 24);
    POKE(0xD680, 0x55);
    while (PEEK(0xD680) & 3)
      POKE(0xD020, PEEK(0xD020) + 1);

    //    printf("Hardware SPI write 256\n");
  }
  else if (page_size == 512) {
    // Write 512 bytes
    //    printf("Hardware SPI write 512 (a)\n");

    // is this broken? at least it is not used
    lcopy((unsigned long)data_buffer, 0xffd6e00L, 512);
    POKE(0xD681, start_address >> 0);
    POKE(0xD682, start_address >> 8);
    POKE(0xD683, start_address >> 16);
    POKE(0xD684, start_address >> 24);
    POKE(0xD680, 0x54);
    while (PEEK(0xD680) & 3)
      POKE(0xD020, PEEK(0xD020) + 1);
    //    press_any_key(0, 0);
    spi_clock_high();
    spi_cs_high();

    //    printf("Hardware SPI write 512 done\n");
    //    press_any_key(0, 0);
  }

  // XXX For some reason the busy flag is broken here.
  // So just wait a little while, but only a little while
  for (b = 0; b < 180; b++)
    continue;

  //  press_any_key(0, 0);

  // Revert lines to input after QSPI operation
  bash_bits |= 0x8f;
  POKE(BITBASH_PORT, bash_bits);
  DEBUG_BITBASH(bash_bits);
  POKE(0xD020, 1);

  reg_sr1 = 0x01;
  while (reg_sr1 & 0x01) {
    if (reg_sr1 & 0x40) {
      if (verboseProgram || pass > 2) {
        printf("%c%c%cwrite error occurred @$%08lx\n", 0x13, 0x11, 152, start_address);
        //      query_flash_protection(start_address);
        //      read_registers();
        printf("reg_sr1=$%02x, reg_cr1=$%02x, pass=%d%c\n", reg_sr1, reg_cr1, pass, 5);
        //      press_any_key(0, 0);
      }
      goto top;
    }
    read_registers();
  }
  POKE(0xD020, 0);

#ifdef QSPI_VERBOSE
  if (reg_sr1 & 0x03) {
    printf("error writing data @$%08llx\n", start_address);
  }
#ifdef QSPI_DEBUG
  else
    printf("data at $%08llx written.\n",start_address);
#endif /* QSPI_DEBUG */
#endif /* QSPI_VERBOSE */

}

void read_data(unsigned long start_address)
{
  unsigned char b;

  // Full hardware-acceleration of reading, which is both faster
  // and more reliable.
  POKE(0xD020, 1);
  POKE(0xD681, start_address >> 0);
  POKE(0xD682, start_address >> 8);
  POKE(0xD683, start_address >> 16);
  POKE(0xD684, start_address >> 24);
  POKE(0xD680, 0x5f); // Set number of dummy cycles
  POKE(0xD680, 0x53); // QSPI Flash Sector read command
  // XXX For some reason the busy flag is broken here.
  // So just wait a little while, but only a little while
  for (b = 0; b < 180; b++)
    continue;

  // Tristate and release CS at the end
  POKE(BITBASH_PORT, 0xff);

  lcopy(0xFFD6E00L, (unsigned long)data_buffer, 512);

  POKE(0xD020, 0);
}

void fetch_rdid(void)
{
  /* Run command 0x9F and fetch CFI etc data.
     (Section 9.2.2)
   */

  unsigned short i;

#if 1
  // Hardware acclerated CFI block read
  POKE(0xd6cd, 0x02);
  spi_cs_high();
  POKE(0xD680, 0x6B);
  // Give time to complete
  for (i = 0; i < 512; i++)
    continue;
  spi_cs_high();
  lcopy(0xffd6e00L, (unsigned long)cfi_data, 512);

#else
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();

  spi_tx_byte(0x9f);

  // Data format according to section 11.2

  // Start with 3 byte manufacturer + device ID
  // Now get the CFI data block
  for (i = 0; i < 512; i++)
    cfi_data[i] = 0x00;
  for (i = 0; i < 512; i++)
    cfi_data[i] = spi_rx_byte();
#endif

  manufacturer = cfi_data[0];
  device_id = cfi_data[1] << 8;
  device_id |= cfi_data[2];
  cfi_length = cfi_data[3];
  if (cfi_length == 0)
    cfi_length = 512;

  spi_cs_high();
  delay();
  spi_clock_high();
  delay();
}

void read_registers(void)
{

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x05);
  reg_sr1 = spi_rx_byte();
  spi_cs_high();
  delay();

  // Config Register 1 (CR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x35);
  reg_cr1 = spi_rx_byte();
  spi_cs_high();
  delay();
}

void read_sr1(void)
{
  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x05);
  reg_sr1 = spi_rx_byte();
  spi_cs_high();
  delay();
}

void read_ppbl(void)
{
  // PPB Lock Register
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xa7);
  spi_cs_high();
  delay();
}

void read_ppb_for_sector(unsigned long sector_start)
{
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xe2);
  spi_tx_byte(sector_start >> 24);
  spi_tx_byte(sector_start >> 16);
  spi_tx_byte(sector_start >> 8);
  spi_tx_byte(sector_start >> 0);
  spi_cs_high();
  delay();
}

void spi_write_enable(void)
{
  while (!(reg_sr1 & 0x02)) {
    POKE(0xD680, 0x66);

    read_sr1();
  }
}

void spi_write_disable(void)
{
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x04);
  spi_cs_high();
  delay();

  read_sr1();
  while (reg_sr1 & 0x02) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x04);
    spi_cs_high();
    delay();

    read_sr1();
  }
}

void spi_clear_sr1(void)
{
  while ((reg_sr1 & 0x60)) {
    POKE(0xD680, 0x6a);

    read_sr1();
    //    printf("reg_sr1=$%02x\n",reg_sr1);
    //    press_any_key(0, 0);
  }
}

/***************************************************************************

 Low-level SPI flash routines

 ***************************************************************************/

// TODO: replace this with a macro that calls usleep instead or does nothing
void delay(void)
{
  // Slow down signalling when debugging using JTAG monitoring.
  // Not needed for normal operation.

  // unsigned int di;
  //   for(di=0;di<1000;di++) continue;
}

unsigned char bash_bits = 0xFF;

void spi_tristate_si(void)
{
  POKE(BITBASH_PORT, 0x8f);
  bash_bits |= 0x8f;
}

void spi_tristate_si_and_so(void)
{
  POKE(BITBASH_PORT, 0x8f);
  bash_bits |= 0x8f;
}

unsigned char spi_sample_si(void)
{
  bash_bits |= 0x80;
  POKE(BITBASH_PORT, 0x80);
  if (PEEK(BITBASH_PORT) & 0x02)
    return 1;
  else
    return 0;
}

void spi_so_set(unsigned char b)
{
  // De-tri-state SO data line, and set value
  bash_bits &= (0x7f - 0x01);
  bash_bits |= (0x0F - 0x01);
  if (b)
    bash_bits |= 0x01;
  POKE(BITBASH_PORT, bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void qspi_nybl_set(unsigned char nybl)
{
  // De-tri-state SO data line, and set value
  bash_bits &= 0x60;
  bash_bits |= (nybl & 0xf);
  POKE(BITBASH_PORT, bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_clock_low(void)
{
  POKE(CLOCKCTL_PORT, 0x00);
  //  bash_bits&=(0xff-0x20);
  //  POKE(BITBASH_PORT,bash_bits);
  //  DEBUG_BITBASH(bash_bits);
}

void spi_clock_high(void)
{
  POKE(CLOCKCTL_PORT, 0x02);
  //  bash_bits|=0x20;
  //  POKE(BITBASH_PORT,bash_bits);
  //  DEBUG_BITBASH(bash_bits);
}

void spi_idle_clocks(unsigned int count)
{
  while (count--) {
    spi_clock_low();
    delay();
    spi_clock_high();
    delay();
  }
}

void spi_cs_low(void)
{
  bash_bits &= 0xff - 0x40;
  bash_bits |= 0xe;
  POKE(BITBASH_PORT, bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_cs_high(void)
{
  bash_bits |= 0x4f;
  POKE(BITBASH_PORT, bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_tx_bit(unsigned char bit)
{
  spi_clock_low();
  spi_so_set(bit);
  spi_clock_high();
}

void qspi_tx_nybl(unsigned char nybl)
{
  qspi_nybl_set(nybl);
  spi_clock_low();
  delay();
  spi_clock_high();
  delay();
}

void spi_tx_byte(unsigned char b)
{
  unsigned char i;

  // Disable tri-state of QSPIDB lines
  bash_bits |= (0x1F - 0x01);
  bash_bits &= 0x7f;
  POKE(BITBASH_PORT, bash_bits);

  for (i = 0; i < 8; i++) {

    //    spi_tx_bit(b&0x80);

    // spi_clock_low();
    POKE(CLOCKCTL_PORT, 0x00);
    //    bash_bits&=(0x7f-0x20);
    //    POKE(BITBASH_PORT,bash_bits);

    // spi_so_set(b&80);
    if (b & 0x80)
      POKE(BITBASH_PORT, 0x0f);
    else
      POKE(BITBASH_PORT, 0x0e);

    // spi_clock_high();
    POKE(CLOCKCTL_PORT, 0x02);

    b = b << 1;
  }
}

void qspi_tx_byte(unsigned char b)
{
  qspi_tx_nybl((b & 0xf0) >> 4);
  qspi_tx_nybl(b & 0xf);
}

unsigned char qspi_rx_byte(void)
{
  unsigned char b;

  spi_tristate_si_and_so();

  spi_clock_low();
  b = PEEK(BITBASH_PORT) & 0x0f;
  spi_clock_high();

  spi_clock_low();
  b = b << 4;
  b |= PEEK(BITBASH_PORT) & 0x0f;
  spi_clock_high();

  return b;
}

unsigned char spi_rx_byte(void)
{
  unsigned char b = 0;
  unsigned char i;

  b = 0;

  //  spi_tristate_si();
  POKE(BITBASH_PORT, 0x8f);
  for (i = 0; i < 8; i++) {
    // spi_clock_low();
    POKE(CLOCKCTL_PORT, 0x00);
    b = b << 1;
    delay();
    if (PEEK(BITBASH_PORT) & 0x02)
      b |= 0x01;
    // if (spi_sample_si()) b|=0x01;
    //    spi_clock_high();
    //    POKE(BITBASH_PORT,0xa0);
    POKE(CLOCKCTL_PORT, 0x02);
    delay();
  }

  return b;
}

void flash_reset(void)
{
  unsigned char i;

  spi_cs_high();
  usleep(10000);

  // Allow lots of clock ticks to get attention of SPI
  for (i = 0; i < 255; i++) {
    spi_clock_high();
    delay();
    spi_clock_low();
    delay();
  }

  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xf0);
  spi_cs_high();
  usleep(10000);
}
