#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspijoy.h"

struct m65_tm tm_start;
struct m65_tm tm_now;

void wait_for_fire(void);

unsigned char slot_count = 0;

short i, x, y, z;

unsigned long addr, vaddr;
unsigned char progress = 0;
unsigned long progress_acc = 0;
unsigned char tries = 0;

unsigned int num_4k_sectors = 0;

unsigned char first, last, verboseProgram = 0;

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

unsigned char reconfig_disabled = 0;

unsigned char data_buffer[512];
// Magic string for identifying properly loaded bitstream
unsigned char bitstream_magic[16] =
    // "MEGA65BITSTREAM0";
    { 0x4d, 0x45, 0x47, 0x41, 0x36, 0x35, 0x42, 0x49, 0x54, 0x53, 0x54, 0x52, 0x45, 0x41, 0x4d, 0x30 };
unsigned char mega65core_magic[7] = { 0x4d, 0x45, 0x47, 0x41, 0x36, 0x35, 0x00 };

unsigned short mb = 0;

unsigned char buffer[512];

const unsigned long sd_timeout_value = 100000;

/***************************************************************************

 General utility functions

 ***************************************************************************/

unsigned char progress_chars[4] = { 32, 101, 97, 231 };

void progress_bar(unsigned char onesixtieths)
{
  unsigned char fulls = onesixtieths >> 2;

  /* Draw a progress bar several chars high */
  for (i = 0; i < fulls; i++) {
    POKE(0x0400 + (4 * 40) + i, 160);
    POKE(0x0400 + (5 * 40) + i, 160);
    POKE(0x0400 + (6 * 40) + i, 160);
  }
  if (i < 40) {
    POKE(0x0400 + (4 * 40) + i, progress_chars[onesixtieths & 3]);
    POKE(0x0400 + (5 * 40) + i, progress_chars[onesixtieths & 3]);
    POKE(0x0400 + (6 * 40) + i, progress_chars[onesixtieths & 3]);
    for (i++; i < 40; i++) {
      POKE(0x400 + (4 * 40) + i, 0x20);
      POKE(0x400 + (5 * 40) + i, 0x20);
      POKE(0x400 + (6 * 40) + i, 0x20);
    }
  }

  return;
}

static unsigned char input_key;

unsigned char check_input(char *m, uint8_t case_sensitive)
{
  return 0;
}

unsigned char debcd(unsigned char c)
{
  return (c & 0xf) + (c >> 4) * 10;
}

void getciartc(struct m65_tm *a)
{
  a->tm_hour = debcd(PEEK(0xDC0B));
  a->tm_min = debcd(PEEK(0xDC0A));
  a->tm_sec = debcd(PEEK(0xDC09));
  a->tm_wday = PEEK(0xDC08); // to remove read latch, wday is not used here
}

// assumes that b is greater equal a!
unsigned long seconds_between(struct m65_tm *a, struct m65_tm *b)
{
  unsigned long d = 0;

  d += 3600L * b->tm_hour;
  d += 60L * b->tm_min;
  d += b->tm_sec;

  d -= 3600L * a->tm_hour;
  d -= 60L * a->tm_min;
  d -= a->tm_sec;

  return d;
}

void wait_10ms(void)
{
  // 16 x ~64usec raster lines = ~1ms
  int c = 160;
  unsigned char b;
  while (c--) {
    b = PEEK(0xD012U);
    while (b == PEEK(0xD012U))
      continue;
  }
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
    POKE(0xd020, (PEEK(0xd020) + 1) & 15);
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

    POKE(0xd020, (PEEK(0xd020) + 1) & 0xf);

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
}

struct m65_dirent hy_dirent;

struct m65_dirent *hy_readdir(void)
{
  unsigned char *dirent;
  unsigned char j;
  unsigned char found = 0;

  while (!found) {
    // Chain through directory as required
    if (hy_opendir_offset_in_sector == 512) {
      hy_opendir_offset_in_sector = 0;
      hy_opendir_sector_in_cluster++;
      hy_opendir_sector++;
    }
    if (hy_opendir_sector_in_cluster >= fat32_sectors_per_cluster) {
      hy_opendir_sector_in_cluster = 0;
      hy_opendir_cluster = fat32_nextclusterinchain(hy_opendir_cluster);
      if (hy_opendir_cluster >= 0x0ffffff0)
        return NULL;
      hy_opendir_sector = (hy_opendir_cluster - 2) * fat32_sectors_per_cluster + fat32_cluster2_sector;
    }
    if (!hy_opendir_cluster)
      return NULL;

    sdcard_readsector(hy_opendir_sector);

    // Get DOS directory entry and populate
    dirent = &buffer[hy_opendir_offset_in_sector];
    ((unsigned char *)&hy_dirent.d_ino)[0] = dirent[0x1a];
    ((unsigned char *)&hy_dirent.d_ino)[1] = dirent[0x1b];
    ((unsigned char *)&hy_dirent.d_ino)[2] = dirent[0x14];
    ((unsigned char *)&hy_dirent.d_ino)[3] = dirent[0x15];
    for (j = 0; j < 8; j++)
      hy_dirent.d_name[j] = dirent[0 + j];
    hy_dirent.d_name[8] = '.';
    for (j = 0; j < 8; j++)
      hy_dirent.d_name[9 + j] = dirent[8 + j];
    hy_dirent.d_name[12] = 0;

    if (hy_dirent.d_name[0] && hy_dirent.d_name[0] != 0xe5)
      found = 1;

    hy_opendir_offset_in_sector += 0x20;
  }

  if (found)
    return &hy_dirent;
  else
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
    if (!strcmp(de->d_name, filename)) {
      //      printf("Found file '%s' at cluster $%08lx\n",
      //             filename,de->d_ino);
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

  Disk chooser for freeze menu.

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

char *diskchooser_instructions = "  SELECT FLASH FILE, THEN PRESS RETURN  "
                                 "       OR PRESS RUN/STOP TO ABORT       ";

#define HIGHLIGHT_ATTR 0x21
#define NORMAL_ATTR 0x01

char disk_name_return[32];

unsigned char joy_to_key_disk[32] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x0d,         // With fire pressed
  0, 0, 0, 0, 0, 0, 0, 0x9d, 0, 0, 0, 0x1d, 0, 0x11, 0x91, 0 // without fire
};

#define SCREEN_ADDRESS 0x0400
#define COLOUR_RAM_ADDRESS 0x1f800

void draw_file_list(void)
{
  unsigned addr = SCREEN_ADDRESS;
  unsigned char i, x;
  unsigned char name[64];
  // First, clear the screen
  lfill(SCREEN_ADDRESS, ' ', 40 * 23);
  lfill(COLOUR_RAM_ADDRESS, NORMAL_ATTR, 40 * 23);

  // Draw instructions to FOOTER
  for (i = 0; i < 80; i++) {
    if (diskchooser_instructions[i] >= 'A' && diskchooser_instructions[i] <= 'Z')
      POKE(SCREEN_ADDRESS + 23 * 40 + i + 0, diskchooser_instructions[i] & 0x1f);
    else
      POKE(SCREEN_ADDRESS + 23 * 40 + i + 0, diskchooser_instructions[i]);
  }
  lfill(COLOUR_RAM_ADDRESS + (23 * 40) + 0, HIGHLIGHT_ATTR, 80);

  for (i = 0; i < 23; i++) {
    if ((display_offset + i) < file_count) {
      // Real line
      lcopy(0x40000U + ((display_offset + i) << 6), (unsigned long)name, 64);

      for (x = 0; x < 20; x++) {
        if ((name[x] >= 'A' && name[x] <= 'Z') || (name[x] >= 'a' && name[x] <= 'z'))
          POKE(addr + x, name[x] & 0x1f);
        else
          POKE(addr + x, name[x]);
      }
    }
    else {
      // Blank dummy entry
      for (x = 0; x < 20; x++)
        POKE(addr + x, ' ');
    }
    if ((display_offset + i) == selection_number) {
      // Highlight the row
      lfill(COLOUR_RAM_ADDRESS + (i * 40), HIGHLIGHT_ATTR, 20);
    }
    addr += (40 * 1);
  }
}

/*
 * uchar select_bitstream_file()
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
unsigned char select_bitstream_file(void)
{
  unsigned char x;
  signed char j;
  struct m65_dirent *dirent;
  int idle_time = 0;

  file_count = 0;
  selection_number = 0;
  display_offset = 0;

  // First, clear the screen
  POKE(SCREEN_ADDRESS + 0, ' ');
  POKE(SCREEN_ADDRESS + 1, ' ');
  lcopy(SCREEN_ADDRESS, SCREEN_ADDRESS + 2, 40 * 25 - 2);

  // Add dummy entry for erasing the slot
  lfill(0x40000L + (file_count * 64), ' ', 64);
  lcopy((long)"-erase slot-", 0x40000L + (file_count * 64), 12);
  file_count++;

  // ARGH!!! We are running from in hypervisor mode, so we can't use hypervisor
  // traps to get the directory listing!
  hy_closeall();
  hy_opendir();
  printf("%cScanning directory...\n", 0x93);
  dirent = hy_readdir();
  while (dirent && ((unsigned short)dirent != 0xffffU)) {
    j = strlen(dirent->d_name) - 4;
    if (j >= 0) {
      // don't show filenames with _ or ~ as first char
      // only select files ending in .COR
      if ((dirent->d_name[0] != 0x7e) && (dirent->d_name[0] != 0x5f) &&
          ((!strncmp(&dirent->d_name[j], ".COR", 4)) ||
           (!strncmp(&dirent->d_name[j], ".cor", 4)))) {
        // File is a core
        lfill(0x40000L + (file_count * 64), ' ', 64);
        lcopy((long)&dirent->d_name[0], 0x40000L + (file_count * 64), j + 4);
        file_count++;
      }
    }

    dirent = hy_readdir();
  }

  hy_closedir();

  // Okay, we have some disk images, now get the user to pick one!
  draw_file_list();
  while (1) {

    unsigned char v;
    v=PEEK(0xDC00)&0x1f;
    x = joy_to_key_disk[PEEK(0xDC00) & PEEK(0xDC01) & 0x1f];
    //
    if (!v) {
      v=PEEK(0xD6A0)>>3;    
      if (!(v&16)) x=0x0d; // FIRE/F_INDEX = return
      if (!(v&1)) x=0x91;  // UP/F_DISKCHANGED = CRSR-UP
      if (!(v&8)) x=0x1d;  // RIGHT/F_TRACK0 = CRSR-RIGHT
      if (!(v&4)) x=0x9d;  // LEFT/F_WRITEPROTECT = CRSR-LEFT
      if (!(v&2)) x=0x11;  // DOWN/F_RDATA = CRSR-DOWN
      // Wait for joystick presses to be released before continuing
    }
    while (v!=0x1f) {
      v=PEEK(0xDC00)&0x1f;
      if (!v) v=PEEK(0xD6A0)>>3;
    }            
    
    if (!x) {
      idle_time++;
      
      usleep(10000);
      continue;
    }
    else
      idle_time = 0;

    switch (x) {
    case 0x03: // RUN-STOP = make no change
      return 0;
    case 0x0d: // Return = select this disk.
      // was erase (first entry) selected?
      if (selection_number == 0) {
        disk_name_return[0] = 0;
        return 1;
      }

      // Copy name out
      lcopy(0x40000L + (selection_number * 64), (unsigned long)disk_name_return, 32);
      // Then null terminate it
      for (x = 31; x && disk_name_return[x] == ' '; x--)
        disk_name_return[x] = 0;
      return 2;

    case 0x11:
    case 0x9d: // Cursor down or left
      selection_number++;
      if (selection_number >= file_count)
        selection_number = 0;
      break;
    case 0x91:
    case 0x1d: // Cursor up or right
      selection_number--;
      if (selection_number < 0)
        selection_number = file_count - 1;
      break;
    }

    // Adjust display position
    if (selection_number < display_offset)
      display_offset = selection_number;
    if (selection_number > (display_offset + 23))
      display_offset = selection_number - 22;
    if (display_offset > (file_count - 22))
      display_offset = file_count - 22;
    if (display_offset < 0)
      display_offset = 0;

    draw_file_list();
  }

  return 0;
}

void reconfig_fpga(unsigned long addr)
{

  if (reconfig_disabled) {
    printf("%c%cERROR:%c Remember that warning about\n"
           "having started from JTAG?\n"
           "You %ccan't%c start a core from flash after\n"
           "having started the system via JTAG.\n",
        0x93, 158, 5, 158, 5);
    wait_for_fire();
    printf("%c", 0x93);
    return;
  }

  // Black screen when reconfiguring
  POKE(0xd020, 0);
  POKE(0xd011, 0);

  mega65_io_enable();

  // Addresses for WBSTAR are shifted by 8 bits
  POKE(0xD6C8U, (addr >> 8) & 0xff);
  POKE(0xD6C9U, (addr >> 16) & 0xff);
  POKE(0xD6CAU, (addr >> 24) & 0xff);
  POKE(0xD6CBU, 0x00);

  // Wait a little while, to make sure that the WBSTAR slot in
  // the reconfig sequence gets set before we instruct the FPGA
  // to reconfigure.
  usleep(255);

  // Try to reconfigure
  POKE(0xD6CFU, 0x42);
  while (1) {
    POKE(0xD020, PEEK(0xD012));
    POKE(0xD6CFU, 0x42);

    // Grey screen if reconfig failing
    POKE(0xd020, 0x0d);
  }
}

typedef struct {
  int model_id;
  char *name;
} models_type;

// clang-format off
models_type models[] = {
  { 0x01, "MEGA65 R1" },
  { 0x02, "MEGA65 R2" },
  { 0x03, "MEGA65 R3" },
  { 0x21, "MEGAphone R1" },
  { 0x22, "MEGAphone R4" },
  { 0x40, "Nexys4" },
  { 0x41, "Nexys4DDR" },
  { 0x42, "Nexys4DDR-widget" },
  { 0xFD, "QMTECH Wukong A100T" },
  { 0xFE, "Simulation" } };
// clang-format on

char *get_model_name(uint8_t model_id)
{
  static char *model_unknown = "?unknown?";
  uint8_t k;
  uint8_t l = sizeof(models) / sizeof(models_type);

  for (k = 0; k < l; k++) {
    if (model_id == models[k].model_id) {
      return models[k].name;
    }
  }

  return model_unknown;
}

int check_model_id_field(unsigned char megaonly)
{
  unsigned char x;
  unsigned short bytes_returned;
  uint8_t hardware_model_id = PEEK(0xD629);
  uint8_t core_model_id = 0;

  bytes_returned = hy_read512();

  if (!bytes_returned) {
    printf("Failed to read .cor file.\n");
    wait_for_fire();
    return 0;
  }

  // check for core bitstream signature
  for (x = 0; x < 16; x++)
    if (buffer[x] != bitstream_magic[x])
      break;
  if (x < 16) {
    printf("\n%c.COR file has no COR signature!%c\n", 0x1c, 0x05);
    wait_for_fire();
    return 0;
  }

  // only allow valid cores with MEGA65 as core name
  if (megaonly) {
    for (x = 0; x < 7; x++)
      if (buffer[0x10 + x] != mega65core_magic[x])
        break;
    if (x < 7) {
      printf("\n%cThis is no valid MEGA65 .COR file!\n\n"
             "Refusing to flash!%c\n",
          0x1c, 0x05);
      wait_for_fire();
      return 0;
    }
  }

  core_model_id = buffer[0x70];
  printf(".COR file model id: $%02X - %s\n", core_model_id, get_model_name(core_model_id));
  printf(" Hardware model id: $%02X - %s\n\n", hardware_model_id, get_model_name(hardware_model_id));

  if (hardware_model_id == core_model_id) {
    printf("%cVerified .COR file matches hardware.\n"
           "Safe to flash.%c\n\n"
           "Press FIRE to continue, or turn off computer to abort.\n",
        0x1e, 0x05);
    wait_for_fire();
    return 1;
  }

  if (core_model_id == 0x00) {
    printf("\x1c.COR file is missing model-id field.\n"
           "Cannot confirm if .COR matches hardware.\n"
           "%cAre you sure you want to flash? (y/n)\n\n",
        0x05);
    if (!check_input("y", CASE_INSENSITIVE))
      return 0;

    printf("Press FIRE to proceed to flash\n");
    wait_for_fire();
    return 1;
  }

  printf("%cVerification error!\n"
         "This .COR file is not intended for this hardware.%c\n",
      0x1c, 0x05);
  wait_for_fire();
  return 0;
}

/***************************************************************************

 High-level flashing routines

 ***************************************************************************/

unsigned char j, k;
unsigned short erase_time = 0, flash_time = 0, verify_time = 0, load_time = 0;

unsigned char slot_empty_check(unsigned short mb_num)
{
  unsigned long addr;
  for (addr = (mb_num * 1048576L); addr < ((mb_num * 1048576L) + SLOT_SIZE); addr += 512) {
    read_data(addr);
    y = 0xff;
    for (x = 0; x < 512; x++)
      y &= data_buffer[x];
    if (y != 0xff)
      return -1;

    *(unsigned long *)(0x0400) = addr;
  }
  return 0;
}

void flash_inspector(void)
{
}

unsigned char flash_region_differs(unsigned long attic_addr, unsigned long flash_addr, long size)
{
  while (size > 0) {

    lcopy(0x8000000 + attic_addr, 0xffd6e00L, 512);
    if (!verify_data_in_place(flash_addr)) {
      //#define SHOW_FLASH_DIFF
#ifdef SHOW_FLASH_DIFF
      printf("attic_addr=$%08lX, flash_addr=$%08lX\n", attic_addr, flash_addr);
      read_data(flash_addr);
      printf("repeated verify yields %d\n", verify_data_in_place(flash_addr));
      for (i = 0; i < 256; i++) {
        if (!(i & 15))
          printf("%c%07lx:", 5, flash_addr + i);
        if (data_buffer[i] != lpeek(0x8000000L + attic_addr + i))
          printf("%c", 28);
        else
          printf("%c", 153);
        printf("%02x", data_buffer[i]);
        //          if ((i&15)==15) printf("\n");
      }
      printf("%c", 5);
      wait_for_fire();
      for (i = 256; i < 512; i++) {
        if (!(i & 15))
          printf("%c%07lx:", 5, flash_addr + i);
        if (data_buffer[i] != lpeek(0x8000000L + attic_addr + i))
          printf("%c", 28);
        else
          printf("%c", 153);
        printf("%02x", data_buffer[i]);
        //          if ((i&15)==15) printf("\n");
      }
      printf("%c", 5);
      printf("repeated verify yields %d\n", verify_data_in_place(flash_addr));
      wait_for_fire();
#endif
      return 1;
    }
    attic_addr += 512;
    flash_addr += 512;
    size -= 512;
  }
  return 0;
}

void reflash_slot(unsigned char slot, unsigned char selected_file)
{
  unsigned long d, d_last, size, waddr;
  unsigned short bytes_returned;
  unsigned char fd, tries;
  unsigned char erase_mode = 0;

  if (selected_file == 0)
    return;

#ifndef QSPI_ERASE_ZERO
  if (selected_file == 1 && slot == 0) {
    // we refuse to erase slot 0
    printf("%c%c\nRefusing to erase slot 0!%c\n\n", 0x93, 0x1c, 0x5);
    wait_for_fire();
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

  printf("%cChecking COR file...\n", 0x93);

  lfill((unsigned long)buffer, 0, 512);

  // return code of select_bitstream_file > 1 means a file was selected
  if (selected_file > 1) {

    fd = hy_open(disk_name_return);
    if (fd == 0xff) {
      // Couldn't open the file.
      printf("ERROR: Could not open flash file '%s'\n", disk_name_return);

      wait_for_fire();
      return;
    }

    if (!check_model_id_field(slot == 0 ? 1 : 0))
      return;

    // start reading file from beginning again
    // (as the model_id checking read the first 512 bytes already)
    fd = hy_open(disk_name_return);

    progress_acc = 0;
    progress = 0;
    printf("%cLoading COR file into Attic RAM...\n", 0x93);

    d_last = 0;
    getciartc(&tm_start);
    for (addr = 0; addr < SLOT_SIZE; addr += 512) {
      progress_acc += 512;
#ifdef A100T
      if (progress_acc > 26214) {
        progress_acc -= 26214;
        progress++;
        progress_bar(progress);
      }
#else
      if (progress_acc > 52428UL) {
        progress_acc -= 52428UL;
        progress++;
        progress_bar(progress);
      }
#endif

      if (!(addr & 0xffff)) {
        getciartc(&tm_now);
        d = seconds_between(&tm_start, &tm_now);
        // This division is _really_ slow, which is why we do it only
        // once per second.
        if (d != d_last) {
          unsigned int speed = (unsigned int)(((addr - (SLOT_SIZE * slot)) / d) >> 10);
          unsigned long eta = (((SLOT_SIZE) * (slot + 1) - addr) / speed) >> 10;
          d_last = d;
          if (speed > 0)
            printf("%c%c%c%c%c%c%c%c%c%cLoading %dKB/sec, done in %ld sec.          \n", 0x13, 0x11, 0x11, 0x11, 0x11, 0x11,
                0x11, 0x11, 0x11, 0x11, speed, eta);
        }
      }

      bytes_returned = hy_read512();

      if (!bytes_returned)
        break;
      lcopy(0xffd6e00L, 0x8000000L + addr, 512);
    }
    getciartc(&tm_now);
    load_time = seconds_between(&tm_start, &tm_now);
    printf("%cLoaded COR file in %d seconds.\n", 0x93, load_time);

    // start flashing
    progress_acc = 0;
    progress = 0;
    d_last = 0;
    getciartc(&tm_start);

    addr = SLOT_SIZE * slot;
    while (addr < (SLOT_SIZE * (slot + 1))) {
      if (num_4k_sectors * 4096 > addr)
        size = 4096;
      else
        size = 1L << ((long)flash_sector_bits);

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
          printf("%c%c\nERROR: Could not write to flash after %d tries.\n", 0x11, 0x11, tries);

          // secret Ctrl-F (keycode 0x06) will launch flash inspector,
          // but only if QSPI_FLASH_INSPECTOR is defined!
          // otherwise: endless loop!
          printf("Please turn the system off!\n");
          // don't let the user do anything else
          while (1)
            POKE(0xD020, PEEK(0xD020) & 0xf);

          hy_close();
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
        for (waddr = addr; waddr < (addr + size); waddr += 256) {
          lcopy(0x8000000L + waddr - SLOT_SIZE * slot, (unsigned long)data_buffer, 256);
          // display sector on screen
          //        lcopy(0x8000000L+waddr-SLOT_SIZE*slot,0x0400+17*40,256);
          POKE(0xD020, 3);
          program_page(waddr, 256);
          POKE(0xD020, 0);
        }
      } while (tries < 11);

      progress_acc += size;
#ifdef A100T
      while (progress_acc > 26214UL) {
        progress_acc -= 26214UL;
        progress++;
        progress_bar(progress);
      }
#else
      while (progress_acc > 52428UL) {
        progress_acc -= 52428UL;
        progress++;
        progress_bar(progress);
      }
#endif

      addr += size;

      getciartc(&tm_now);
      d = seconds_between(&tm_start, &tm_now);
      // This division is _really_ slow, which is why we do it only
      // once per second.
      if (d != d_last) {
        unsigned int speed = (unsigned int)(((addr - (SLOT_SIZE * slot)) / d) >> 10);
        unsigned long eta = (((SLOT_SIZE) * (slot + 1) - addr) / speed) >> 10;
        d_last = d;
        if (speed > 0)
          printf("%c%c%c%c%c%c%c%c%c\nFlashing at %dKB/sec, done in %ld sec.          \n", 0x13, 0x11, 0x11, 0x11, 0x11,
              0x11, 0x11, 0x11, 0x11, speed, eta);
      }
    }
    flash_time = seconds_between(&tm_start, &tm_now);

    // Undraw the sector display before showing results
    lfill(0x0400 + 12 * 40, 0x20, 512);
  }
  else {
    // extra question before erasing a slot
    printf("%c\nYou are about to erase slot %d!\n"
           "Are you sure you want to proceed? (y/n)%c\n\n",
           0x81, slot, 0x05);
    if (!check_input("y", CASE_INSENSITIVE))
      return;
    printf("%c", 0x93);

    // Erase mode
    d_last = 0;
    getciartc(&tm_start);
    progress_acc = 0;
    progress = 0;
    addr = SLOT_SIZE * slot;
    while (addr < (SLOT_SIZE * (slot + 1))) {
      if (num_4k_sectors * 4096 > addr)
        size = 4096;
      else
        size = 1L << ((long)flash_sector_bits);

      printf("%c    Erasing sector at $%08lX", 0x13, addr);
      POKE(0xD020, 2);
      erase_sector(addr);
      read_data(0xffffffff);
      POKE(0xD020, 0);

      progress_acc += size;
#ifdef A100T
      while (progress_acc > 26214UL) {
        progress_acc -= 26214UL;
        progress++;
        progress_bar(progress);
      }
#else
      while (progress_acc > 52428UL) {
        progress_acc -= 52428UL;
        progress++;
        progress_bar(progress);
      }
#endif

      addr += size;

      getciartc(&tm_now);
      d = seconds_between(&tm_start, &tm_now);
      // This division is _really_ slow, which is why we do it only
      // once per second.
      if (d != d_last) {
        unsigned int speed = (unsigned int)(((addr - (SLOT_SIZE * slot)) / d) >> 10);
        unsigned long eta = (((SLOT_SIZE) * (slot + 1) - addr) / speed) >> 10;
        d_last = d;
        if (speed > 0)
          printf("%c%c%c%c%c%c%c%c%c\nErasing at %dKB/sec, done in %ld sec.          \n", 0x13, 0x11, 0x11, 0x11, 0x11, 0x11,
              0x11, 0x11, 0x11, speed, eta);
      }
    }
    flash_time = seconds_between(&tm_start, &tm_now);
  }

  printf("%c%c%c%c%c%c%c%c%c\n"
         "Flash slot successfully updated.      \n\n", 0x13, 0x11, 0x11, 0x11, 0x11,
              0x11, 0x11, 0x11, 0x11);
  if (selected_file == 1 && flash_time > 0)
    printf("   Erase: %d sec \n\n", flash_time);
  else if (load_time + flash_time > 0)
    printf("    Load: %d sec \n"
           "   Flash: %d sec \n"
           "\n", load_time, flash_time);

  wait_for_fire();

  hy_close(); // there was once an intent to pass (fd), but it wasn't getting used

  return;
}

/***************************************************************************

 Mid-level SPI flash routines

 ***************************************************************************/

void probe_qspi_flash(void)
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
  

#ifdef QSPI_VERBOSE
  for (i = 0; i < 0x80; i++) {
    if (!(i & 15))
      printf("+%03x : ", i);
    printf("%02x", (unsigned char)cfi_data[i]);
    if ((i & 15) == 15)
      printf("\n");
  }
  wait_for_fire();
  printf("\nQSPI Information\n\n");
#endif

  // this looks for ALT?\00 at cfi_data pos 0x51
  if (cfi_data[0x51] == 0x41 && cfi_data[0x52] == 0x4c && cfi_data[0x53] == 0x54 && cfi_data[0x56] == 0x00) {
    for (i = 0; i < cfi_data[0x57]; i++)
      part[i] = cfi_data[0x58 + i];
    part[i] = 0;
#ifdef QSPI_VERBOSE
    printf("Part         = %s\n"
           "Part Family  = %02x-%c%c\n", part, cfi_data[5], cfi_data[6], cfi_data[7]);
#endif
  }
  else {
    part[0] = 0;
#ifdef QSPI_VERBOSE
    printf("%cPart         = unknown %02x %02x %02x\n"
           "Part Family  = unknown%c\n", 28, cfi_data[0x51], cfi_data[0x52], cfi_data[0x53], 5);
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
         "Page size    = 2^%d bytes\n", cfi_data[0x20], cfi_data[0x2a]);
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
  wait_for_fire();  
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
  // latency_code=3;
  latency_code = reg_cr1 >> 6;

#ifdef QSPI_VERBOSE
  printf("\n"
          "Flash size   = %dMB\n"
          "Flash slots  = %d slots of %dMB\n"
          "Register SR1 = $%02x\n", mb, slot_count, SLOT_MB, reg_sr1);
  printf("  latency code %d\n", latency_code);
  if (reg_sr1 & 0x80)
    printf("  flash is write protected.\n");
  if (reg_sr1 & 0x40)
    printf("  programming error occurred.\n");
  if (reg_sr1 & 0x20)
    printf("  erase error occurred.\n");
  if (reg_sr1 & 0x02)
    printf("  write latch enabled.\n");
  else
    printf("  write latch not (yet) enabled.\n");
  if (reg_sr1 & 0x01)
    printf("  device busy.\n");
  printf("Register CR1 = $%02x\n"
          "", reg_cr1);
#endif

  // failed to detect, probably dip sw #3 = off
  if (mb == 0 || page_size == 0 || flash_sector_bits == 0 || part[0] == 0) {
    printf("\n%cERROR: Failed to probe flash\n       (dip #3 not on?)%c\n", 28, 5);
    while (1)
      POKE(0xD020, PEEK(0xD020) + 1);
  }

#ifdef QSPI_VERBOSE
  wait_for_fire();
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

#if 0
  if (reg_sr1&0x20) printf("error erasing sector @ $%08x\n",address_in_sector);
  else {
    printf("sector at $%08llx erased.\n%c",address_in_sector,0x91);
  }
#endif
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

  first = 0;
  last = 0xff;

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
    //
    // ERROR: this should be 0xffd6e00L, 512
    // but as it is never used... and it also does not work lydon@20220912
    lcopy((unsigned long)data_buffer, 0xffd6f00L, 256);
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

  // this can't happen, can it? the loop in front of this will catch the 0x01
  //if (reg_sr1 & 0x03)
  //  printf("error writing data @$%08llx\n", start_address);
  //else
  //  printf("data at $%08llx written.\n",start_address);

}

void read_data(unsigned long start_address)
{
  unsigned char b;

  // Full hardware-acceleration of reading, which is both faster
  // and more reliable.
  POKE(0xd020, 1);
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
  POKE(0xd020, 0);
  //  while(PEEK(0xD680)&3) POKE(0xD020,PEEK(0xD020)+1);

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
  spi_tx_byte(sector_start>>24);
  spi_tx_byte(sector_start>>16);
  spi_tx_byte(sector_start>> 8);
  spi_tx_byte(sector_start>> 0);
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
