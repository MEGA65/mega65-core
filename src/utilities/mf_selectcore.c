#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>

#include "mhexes.h"
#include "nohysdc.h"
#include "mf_selectcore.h"

// from qspicommon
extern short i, x, y, z;
extern unsigned char buffer[512];
extern uint8_t hw_model_id;

/*
 * MEGAFLASH - Core file chooser
 *
 * This is written for 40x25 screen mode using upper/lowercase
 * charset.
 *
 * The directory entries are stored in bank 4. Starting from
 * $40000 the starting inode and the file size (4+4 bytes) are
 * stored, for a maximum of 1024 entries. Starting at $42000
 * the filenames, shortened to 40 chars, are stored in a format
 * that can be copied directly to the screen. The memory used
 * ends at $4C000.
 */

// information from the core files header
uint8_t corefile_model_id = 0;
uint8_t corefile_caps = 0, corefile_flags = 0;
char corefile_name[33];
char corefile_version[33];
char corefile_error[33];

uint16_t sbs_file_count = 0;
uint32_t sbs_coredir_inode = 0;
int16_t selection_number = 0;
int16_t display_offset = 0;

// Magic string for identifying properly loaded bitstream
#include <ascii_charmap.h>
unsigned char bitstream_magic[] = "MEGA65BITSTREAM0";
// it's the same, MEGA65, but only 6 chars, followed by 0 bytes
#define mega65core_magic bitstream_magic
#include <cbm_screen_charmap.h>

char *diskchooser_footer = " <F9> Internal SD <F11> Directory: ROOT "
                           " <RETURN> Select file      <STOP> Abort ";
char *diskchooser_header = "      Select core file for slot X       ";
#define erase_message "- Erase Slot -"

#define SCREEN_ADDRESS 0x0400UL
#define COLOUR_RAM_ADDRESS 0xff80000UL
#define HIGHLIGHT_ATTR 0x21
#define NORMAL_ATTR 0x01

#define FILELIST_MAX 1024
#define FILEINODE_ADDRESS 0x40000UL
#define FILESCREEN_ADDRESS 0x42000UL

uint32_t disk_file_inode;
uint32_t disk_file_size;
char disk_display_return[40];

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
int8_t read_and_check_core(uint8_t require_mega)
{
  uint8_t err;

  // initialize fields
  corefile_model_id = 0;
  memset(corefile_error, ' ', 32);
  memset(corefile_name, ' ', 32);
  memset(corefile_version, ' ', 32);
  memcpy(corefile_name, "UNKNOWN CORE TYPE", 17);
  memcpy(corefile_version, "UNKNOWN VERSION", 15);
  corefile_name[32] = corefile_version[32] = corefile_error[32] = MHX_C_EOS;

  if ((err = nhsd_open(disk_file_inode))) {
    memcpy(corefile_error, "Could not open core file!", 25);
    return -1;
  }

  err = nhsd_read();
  nhsd_close(); // only need the first sector
  if (err) {
    memcpy(corefile_error, "Failed to read core file header!", 32);
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
    corefile_name[x] = mhx_ascii2screen(buffer[0x10 + x], ' ');
    corefile_version[x] = mhx_ascii2screen(buffer[0x30 + x], ' ');
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

void select_bs_draw_list(void)
{
  // wait for raster leaving screen
  while (!(PEEK(0xD011)&0x80));

  // set colour
  lfill(COLOUR_RAM_ADDRESS + 40, NORMAL_ATTR, 40 * 22);

  // copy pregenerated screen
  lcopy(FILESCREEN_ADDRESS + display_offset * 40, SCREEN_ADDRESS + 40, 22 * 40);
  // highlight selected line
  lfill(COLOUR_RAM_ADDRESS + (selection_number - display_offset + 1) * 40, HIGHLIGHT_ATTR, 40);
}

/*
 * uint8_t select_bs_load_dir(uint8_t new_dir)
 *
 * loads all the .COR files from either ROOT or CORE diretory
 * of the selected disk. new_disk bit 0 selects disk, bit 1
 * selects directory (0 = ROOT, 1 = CORE).
 *
 * returns:
 *   byte describing which dir was loaded, bit 7 set means error
 *
 * parameters:
 *   new_dir: which disk and dir should be loaded.
 *            bit 0 = disk (0 int, 1 ext)
 *            bit 1 = dir (0 root, 1 core)
 *            bit 7 = force init
 *
 */
uint8_t select_bs_load_dir(uint8_t new_dir)
{
  uint8_t fnlen, i, j, isroot = 0;

  // clear screen and display scanning message
  mhx_draw_rect(6, 11, 26, 1, "Scanning directoy", MHX_A_WHITE|MHX_A_INVERT, 1);
  mhx_set_xy(7, 12);

  // check if sd card is either not initialised or the wrong bus is selected
  if ((new_dir & 0x80) || (nhsd_init_state & NHSD_INIT_INITMASK) != NHSD_INIT_INITMASK || (nhsd_init_state & NHSD_INIT_BUSMASK) != (new_dir & 1)) {
    if ((i = nhsd_init((new_dir & 1) | NHSD_INIT_FALLBACK, buffer))) {
      mhx_writef(MHX_W_WHITE MHX_W_REVON "SD Card init error $%02X" MHX_W_REVOFF, i);
      mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
      return 0x80;
    }
    // after init we need to forget the CORE dirs inode
    sbs_coredir_inode = 0;
  }
  
restart_dirload:
  if (sbs_coredir_inode != 0 && (new_dir & 2)) {
    nhsd_current_dir = sbs_coredir_inode;
    isroot = 0;
  }
  else {
    nhsd_current_dir = NHSD_ROOT_INODE;
    isroot = 1;
  }
  if ((i = nhsd_opendir())) {
    mhx_writef(MHX_W_WHITE MHX_W_REVON "SD Card opendir error $%02X" MHX_W_REVOFF, i);
    mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
    return 0x80;
  }

  // fill temp memory with space
  lfill(FILEINODE_ADDRESS, 0, 8L * FILELIST_MAX);
  lfill(FILESCREEN_ADDRESS, ' ', 40L * FILELIST_MAX);
  // Add dummy entry for erasing the slot
  lcopy((long)erase_message, FILESCREEN_ADDRESS, 14);
  sbs_file_count = 1;

  while (sbs_file_count < FILELIST_MAX && !nhsd_readdir()) {
    fnlen = strlen(nhsd_dirent.d_name);
#include <ascii_charmap.h>
    // check if we have a CORE subdir, but only if in root and not already discovered
    if (!sbs_coredir_inode && isroot && !strcmp(nhsd_dirent.d_name, "CORE")) {
      sbs_coredir_inode = nhsd_dirent.d_ino;
      // check if we wanted to go to the CORE dir and restart scanning
      if (new_dir & 2) {
        nhsd_closedir();
        goto restart_dirload;
      }
    }
    if ((!strncmp(&nhsd_dirent.d_name[fnlen - 4], ".COR", 4))
        || (!strncmp(&nhsd_dirent.d_name[fnlen - 4], ".cor", 4))) {
#include <cbm_screen_charmap.h>
      // File is a core, store start inode, size and name to temp area
      // inode and reclen are two 32 bit numbers directly following each other, so we copy both here
      lcopy((long)&nhsd_dirent.d_ino, FILEINODE_ADDRESS + (sbs_file_count * 8), 8);

      // We need to convert the up to 247 char long ASCII filename to a
      // maximum 38 character screencode name for displaying. We do this
      // by adding a '...' ellipse between the start and the last 7 characters
      // of the string.
      // This needs to be 38 to be able to place it into a rectangle on
      //  the 40 wide screen
      // we do this directly in the dirent d_name to safe space
      for (j = 0; j < 28 && j < fnlen; j++)
        nhsd_dirent.d_name[j] = mhx_ascii2screen(nhsd_dirent.d_name[j], MHX_C_DEFAULT);

      // filename is longer than 38 chars, so we need to place the ellipse now
      if (fnlen > 38) {
        for (; j < 31; j++)
          nhsd_dirent.d_name[j] = 0x2e;
        // place postion to 7 chars from the end of the string
        i = fnlen - 7;
      }
      else // filename not to long, so just do inline replace
        i = j;
      for (; j < 38 && i < fnlen; j++, i++)
        nhsd_dirent.d_name[j] = mhx_ascii2screen(nhsd_dirent.d_name[i], MHX_C_DEFAULT);

      lcopy((long)nhsd_dirent.d_name, FILESCREEN_ADDRESS + (sbs_file_count * 40) + 1, j);
      sbs_file_count++;
/*
      disk_name_return[25] = 0x80;
      mhx_writef("--%08lx--%s--\n", nhsd_dirent.d_reclen, disk_name_return);
      mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
*/
    }
  }
  nhsd_closedir();

  // mhx_writef(MHX_W_WHITE MHX_W_REVON "%X Loaded %d files" MHX_W_REVOFF, sbs_file_count);
  // mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

  // return on which sd card and in which directory we are (fallback may have happened!)
  return (nhsd_init_state & NHSD_INIT_BUSMASK) | (isroot ? 0 : 2);
}

void select_bs_draw_header(uint8_t selected_dir)
{
  if (selected_dir & 1) {
    diskchooser_footer[6] = 'E';
    diskchooser_footer[7] = 'x';
  }
  else {
    diskchooser_footer[6] = 'I';
    diskchooser_footer[7] = 'n';
  }
  if (selected_dir & 2)
    memcpy(diskchooser_footer + 35, "CORE", 4);
  else
    memcpy(diskchooser_footer + 35, "ROOT", 4);

  // Draw instructions to FOOTER
  lcopy((long)diskchooser_header, SCREEN_ADDRESS, 40);
  lcopy((long)diskchooser_footer, SCREEN_ADDRESS + 23*40, 80);
  mhx_hl_lines(0, 0, MHX_A_LGREY|MHX_A_INVERT);
  mhx_hl_lines(23, 24, MHX_A_LGREY|MHX_A_INVERT);
}

/*
 * uchar select_bitstream_file(uchar slot)
 *
 * displays a file selector with core files on SD
 *
 * returns
 *   0 - nothing was selected, abort
 *   1 - special erase entry was selected
 *   2 - file was selected, filename in disk_file_inode
 *
 * side-effects:
 *  disk_file_inode may be changed
 */
uint8_t select_bitstream_file(uint8_t slot)
{
  uint8_t idle_time = 0;
  uint8_t selected_dir = 0x83; // force init, external disk, core dir

  selection_number = 0;
  display_offset = 0;

  // Okay, we have some disk images, now get the user to pick one!
  diskchooser_header[32] = 0x30 + slot;

  mhx_clearscreen(' ', MHX_A_WHITE);
  if ((selected_dir = select_bs_load_dir(selected_dir)) & 0x80)
    return MFS_FILE_INVALID;

  select_bs_draw_header(selected_dir);
  select_bs_draw_list();
  while (1) {

    mhx_getkeycode(1);

    if (!mhx_lastkey.code.key) {
      if (idle_time < 150)
        idle_time++;

      if (selection_number && idle_time == 150) {
        idle_time++;
        lcopy(FILEINODE_ADDRESS + (selection_number * 8), (long)&disk_file_inode, 4);
        read_and_check_core(0);

        if (selection_number - display_offset < 12) {
          mhx_draw_rect(3, 15, 32, 3, " Corefile ", MHX_A_WHITE|MHX_A_INVERT, 1);
          mhx_write_xy(4, 16, corefile_name, MHX_A_WHITE);
          mhx_write_xy(4, 17, corefile_version, MHX_A_WHITE);
          mhx_write_xy(4, 18, corefile_error, MHX_A_WHITE);
        }
        else {
          mhx_draw_rect(3, 5, 32, 3, " Corefile ", MHX_A_WHITE|MHX_A_INVERT, 1);
          mhx_write_xy(4, 6, corefile_name, MHX_A_WHITE);
          mhx_write_xy(4, 7, corefile_version, MHX_A_WHITE);
          mhx_write_xy(4, 8, corefile_error, MHX_A_WHITE);
        }
      }
      usleep(10000);
      continue;
    }
    idle_time = 0;

    switch (mhx_lastkey.code.key) {
    case 0x03: // RUN-STOP = make no change
    case 0x1b: // ESC
      return MFS_FILE_INVALID;
    case 0x0d: // Return = select this disk.
      // was erase (first entry) selected?
      if (selection_number == 0) {
        disk_file_inode = 0xfffffffful;
        disk_display_return[0] = MHX_C_EOS;
        return MFS_FILE_ERASE;
      }

      // Copy name out
      lcopy(FILEINODE_ADDRESS + (selection_number * 8), (long)&disk_file_inode, 4);
      lcopy(FILEINODE_ADDRESS + (selection_number * 8) + 4, (long)&disk_file_size, 4);
      lcopy(FILESCREEN_ADDRESS + (selection_number * 40) + 1, (long)&disk_display_return, 38);
      disk_display_return[38] = MHX_C_EOS;

      if (!disk_file_inode) {
        disk_file_inode = 0xfffffffful;
        disk_display_return[0] = MHX_C_EOS;
        return MFS_FILE_ERASE;
      }

      read_and_check_core(0);
      return MFS_FILE_VALID;

    case 0xf9: // F9 - switch disk
      if ((selected_dir = select_bs_load_dir((selected_dir ^ 1) | 0x2)) & 0x80)
        return MFS_FILE_INVALID;
      select_bs_draw_header(selected_dir);
      selection_number = 0;
      break;
    case 0xfb: // F11 - switch dir (root / CORE)
      if ((selected_dir = select_bs_load_dir(selected_dir ^ 2)) & 0x80)
        return MFS_FILE_INVALID;
      select_bs_draw_header(selected_dir);
      selection_number = 0;
      break;

    case 0x13: // HOME
      selection_number = 0;
      break;
    case 0x93: // Shift-HOME
      selection_number = sbs_file_count - 1;
      break;
    case 0x1d: // Cursor right is a page
      selection_number += 21;
    case 0x11: // Cursor down
      selection_number++;
      if (selection_number >= sbs_file_count)
        selection_number = sbs_file_count - 1;
      break;
    case 0x9d: // Cursor left is a page
      selection_number -= 21;
    case 0x91: // Cursor up or left
      selection_number--;
      if (selection_number < 0)
        selection_number = 0;
      break;
    }

    // Adjust display position
    if (selection_number < display_offset)
      display_offset = selection_number;
    if (selection_number > (display_offset + 21))
      display_offset = selection_number - 21;
    if (display_offset > (sbs_file_count - 21))
      display_offset = sbs_file_count - 21;
    if (display_offset < 0)
      display_offset = 0;

    select_bs_draw_list();
  }

  return MFS_FILE_INVALID;
}
