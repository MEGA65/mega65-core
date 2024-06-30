#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>

#include "mhexes.h"
#include "nohysdc.h"
#include "mf_utility.h"
#include "mf_selectcore.h"
#include "mf_buffers.h"

#ifdef STANDALONE
#include "mf_screens_solo.h"
#else
#include "mf_screens.h"
#endif

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

// Release 0.95 cores in the Batch2 machines do not have a erase list
// to get rid of the extra sync words. We provide them statically,
// so the list can be set in scan_core_information
const char R095_VER_STUB[] = "Release 0.95";
const uint8_t R095_ERASE_LIST[] = { 0x36, 0x41 };

// information from the core files header
uint8_t mfsc_corehdr_model_id = 0;
uint8_t mfsc_corehdr_bootcaps = 0;
uint8_t mfsc_corehdr_bootflags = 0;
uint8_t mfsc_corehdr_instflags = 0;
uint8_t mfsc_corehdr_erase_list[16];
uint32_t mfsc_corehdr_length = 0UL;
char mfsc_corehdr_name[33];
char mfsc_corehdr_version[33];
char mfsc_corehdr_error[33];

uint16_t mfsc_filecount = 0;
uint32_t mfsc_coredir_inode = 0;
int16_t mfsc_selection = 0;
int16_t mfsc_offset = 0;

// Magic string for identifying properly loaded bitstream
#include <ascii_charmap.h>
unsigned char mfsc_bitstream_magic[] = "MEGA65BITSTREAM0";
// it's the same, MEGA65, but only 6 chars, followed by 0 bytes
#define mega65core_magic mfsc_bitstream_magic
#include <cbm_screen_charmap.h>

#define FILELIST_MAX 1024
#define FILEINODE_ADDRESS 0x40000UL
#define FILESCREEN_ADDRESS 0x42000UL

uint32_t mfsc_corefile_inode;
uint32_t mfsc_corefile_size;
char mfsc_corefile_displayname[40];

/*
 * int8_t mfsc_checkcore(require_mega)
 *
 * reads the header from the file in mfsc_corefile_inode
 * (set by mfsc_selectcore), stores header information
 * in gobal variables and does sanity checks.
 *
 * returns 0 on no errors, <0 on failure. stores failure
 * reason in global variable (screencodes)
 *
 */
int8_t mfsc_checkcore(uint8_t require_mega)
{
  uint8_t x, err;

  // initialize fields
  mfsc_corehdr_model_id = 0;
  memset(mfsc_corehdr_name, ' ', 32);
  memset(mfsc_corehdr_version, ' ', 32);
  memcpy(mfsc_corehdr_name, "UNKNOWN CORE TYPE", 18);
  memcpy(mfsc_corehdr_version, "UNKNOWN VERSION", 16);
  mfsc_corehdr_name[32] = mfsc_corehdr_version[32] = mfsc_corehdr_error[32] = MHX_C_EOS;

  if ((err = nhsd_open(mfsc_corefile_inode))) {
    return MFSC_CF_ERROR_OPEN;
  }

  err = nhsd_read();
  nhsd_close(); // only need the first sector
  if (err) {
    return MFSC_CF_ERROR_READ;
  }

  // check for core bitstream signature
  for (x = 0; x < 16; x++)
    if (buffer[MFSC_COREHDR_MAGIC + x] != mfsc_bitstream_magic[x])
      break;
  if (x < 16) {
    return MFSC_CF_ERROR_SIG;
  }

  // copy and convert name and version to screencode
  for (x = 0; x < 32; x++) {
    mfsc_corehdr_name[x] = mhx_ascii2screen(buffer[MFSC_COREHDR_NAME + x], ' ');
    mfsc_corehdr_version[x] = mhx_ascii2screen(buffer[MFSC_COREHDR_VERSION + x], ' ');
  }

  // check core file size
  mfsc_corehdr_length = *(uint32_t *)(buffer + MFSC_COREHDR_LENGTH);
  if (mfsc_corehdr_length > mfu_slot_size) {
    return MFSC_CF_ERROR_SIZE;
  }

  // check hardware model compability
  mfsc_corehdr_model_id = buffer[MFSC_COREHDR_MODELID];
  if (mfsc_corehdr_model_id != hw_model_id) {
    return MFSC_CF_ERROR_HWMODEL;
  }

  // allow only marked cores for slot 0
  if (require_mega) {
    // check install_flags bit 0 == FACTORY
    if (!(buffer[MFSC_COREHDR_INSTFLAGS] & MFSC_COREINST_FACTORY))
      return MFSC_CF_ERROR_FACTORY;
    // check CORE name, which needs to be MEGA65 only
    for (x = 0; x < 6; x++)
      if (buffer[MFSC_COREHDR_NAME + x] != mega65core_magic[x])
        break;
    for (err = ((x < 6) ? 0xff : 0); !err && x < 32; x++)
      err |= buffer[MFSC_COREHDR_NAME + x];
    if (err)
      return MFSC_CF_ERROR_FACTORY;
  }

  // if all is good, we copy over the flags
  mfsc_corehdr_bootcaps = buffer[MFSC_COREHDR_BOOTCAPS];
  mfsc_corehdr_bootflags = buffer[MFSC_COREHDR_BOOTFLAGS];
  mfsc_corehdr_instflags = buffer[MFSC_COREHDR_INSTFLAGS];
  memset(mfsc_corehdr_erase_list, 0xff, 16);
  if (mfsc_corehdr_instflags & MFSC_COREINST_ERASELIST)
    memcpy(mfsc_corehdr_erase_list, buffer + MFSC_COREHDR_ERASELIST, 16);
  else if (!memcmp(mfsc_corehdr_version, R095_VER_STUB, R095_VER_STUB_SIZE)) {
    mfsc_corehdr_erase_list[0] = R095_ERASE_LIST[0];
    mfsc_corehdr_erase_list[1] = R095_ERASE_LIST[1];
  }

  return MFSC_CF_NO_ERROR;
}

void mfsc_draw_list(void)
{
  uint8_t y;

  // wait for raster leaving screen
  while (!(PEEK(0xD011)&0x80));

  // set colour
  mhx_hl_lines(1, 22, MHX_A_WHITE);

  // copy pregenerated screen
  lcopy(FILESCREEN_ADDRESS + mfsc_offset * 40, mhx_base_scr + 40, 22 * 40);
  for (y = 0; y < 22; y++) {
    lcopy(FILEINODE_ADDRESS + ((mfsc_offset + y) * 8) + 4, (long)&mfsc_corefile_size, 4);
    mhx_hl_lines(y + 1, y + 1, (!mfsc_corefile_size ? MHX_A_DGREY : MHX_A_WHITE) | (mfsc_selection - mfsc_offset == y ? MHX_A_INVERT : 0));
  }
}

/*
 * uint8_t mfsc_load_dir(uint8_t new_dir)
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
uint8_t mfsc_load_dir(uint8_t new_dir)
{
  uint8_t fnlen, i, j, isroot = 0;

  // clear screen and display scanning message
  mhx_draw_rect(6, 11, 26, 1, "Scanning directoy", MHX_A_WHITE|MHX_A_INVERT, 1);
  mhx_set_xy(7, 12);

  // check if sd card is either not initialised or the wrong bus is selected
  if ((new_dir & 0x80) || (nhsd_init_state & NHSD_INIT_INITMASK) != NHSD_INIT_INITMASK || (nhsd_init_state & NHSD_INIT_BUSMASK) != (new_dir & NHSD_INIT_BUSMASK)) {
    if ((i = nhsd_init((new_dir & 1) | NHSD_INIT_FALLBACK, buffer))) {
      mhx_writef(MHX_W_WHITE MHX_W_REVON "SD Card init error $%02X" MHX_W_REVOFF, i);
      mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
      return 0x80;
    }
    // after init we need to forget the CORE dirs inode
    mfsc_coredir_inode = 0;
  }

  if (!(new_dir & 0x80) && (new_dir & NHSD_INIT_BUSMASK) != (nhsd_init_state & NHSD_INIT_BUSMASK)) {
    mhx_flashscreen(MHX_A_ORANGE, 50);
  }

restart_dirload:
  if (mfsc_coredir_inode != 0 && (new_dir & 2)) {
    nhsd_current_dir = mfsc_coredir_inode;
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
  mfsc_filecount = 0;

  while (mfsc_filecount < FILELIST_MAX && !nhsd_readdir()) {
    fnlen = strlen(nhsd_dirent.d_name);
#include <ascii_charmap.h>
    // check if we have a CORE subdir, but only if in root and not already discovered
    if (!mfsc_coredir_inode && isroot && !strcmp(nhsd_dirent.d_name, "CORE")) {
      mfsc_coredir_inode = nhsd_dirent.d_ino;
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
      lcopy((long)&nhsd_dirent.d_ino, FILEINODE_ADDRESS + (mfsc_filecount * 8), 8);

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

      lcopy((long)nhsd_dirent.d_name, FILESCREEN_ADDRESS + (mfsc_filecount * 40) + 1, j);
      mfsc_filecount++;
/*
      disk_name_return[25] = 0x80;
      mhx_writef("--%08lx--%s--\n", nhsd_dirent.d_reclen, disk_name_return);
      mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
*/
    }
  }
  nhsd_closedir();

  // mhx_writef(MHX_W_WHITE MHX_W_REVON "%X Loaded %d files" MHX_W_REVOFF, mfsc_filecount);
  // mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

  // return on which sd card and in which directory we are (fallback may have happened!)
  return (nhsd_init_state & NHSD_INIT_BUSMASK) | (isroot ? 0 : 2);
}

void mfsc_draw_header(uint8_t selected_dir, uint8_t slot)
{
  // copy header and footer from upper memory
  lcopy((long)mf_screens_menu.screen_start + MFMENU_SELECT_HEADER * 40, mhx_base_scr, 40);
  lcopy((long)mf_screens_menu.screen_start + (MFMENU_SELECT_FOOTER * 40) + ((selected_dir & 0x3) * 80), mhx_base_scr + 23*40, 80);
  // set slot number in header
  mhx_putch_xy(32, 0, 0x30 + slot, MHX_A_NOCOLOR);
  // invert and color header and footer
  mhx_hl_lines(0, 0, MHX_A_LGREY|MHX_A_INVERT);
  mhx_hl_lines(23, 24, MHX_A_LGREY|MHX_A_INVERT);
}

/*
 * uchar mfsc_selectcore(uchar slot)
 *
 * displays a file selector with core files on SD
 *
 * returns
 *   0 - nothing was selected, abort
 *   1 - special erase entry was selected
 *   2 - file was selected, filename in mfsc_corefile_inode
 *
 * side-effects:
 *  mfsc_corefile_inode may be changed
 */
uint8_t mfsc_selectcore(uint8_t slot)
{
  uint8_t idle_time = 0, core_check;
  uint8_t selected_dir = 0x83; // force init, external disk, core dir

  mfsc_selection = 0;
  mfsc_offset = 0;

  // Okay, we have some disk images, now get the user to pick one!
  //diskchooser_header[32] = 0x30 + slot;

  mhx_clearscreen(' ', MHX_A_WHITE);
  if ((selected_dir = mfsc_load_dir(selected_dir)) & 0x80)
    return MFSC_FILE_INVALID;

  mfsc_draw_header(selected_dir, slot);
  mfsc_draw_list();
  while (1) {

    mhx_getkeycode(1);

    if (!mhx_lastkey.code.key) {
      if (idle_time < 150)
        idle_time++;

      if (idle_time == 150) {
        idle_time++;
        lcopy(FILEINODE_ADDRESS + (mfsc_selection * 8), (long)&mfsc_corefile_inode, 4);
        core_check = mfsc_checkcore(slot ? 0 : 1);

        if (core_check) {
          lfill(FILEINODE_ADDRESS + (mfsc_selection * 8) + 4, 0, 4);
        }

        if (mfsc_selection - mfsc_offset < 12) {
          mhx_draw_rect(3, 15, 32, 3, " Corefile ", MHX_A_WHITE|MHX_A_INVERT, 1);
          mhx_write_xy(4, 16, mfsc_corehdr_name, MHX_A_WHITE|MHX_A_INVERT);
          mhx_write_xy(4, 17, mfsc_corehdr_version, MHX_A_WHITE|MHX_A_INVERT);
          mhx_write_xy(4, 18, mhx_screen_get_line(&mf_screens_core_error, core_check, (char *)&buffer), MHX_A_WHITE|MHX_A_INVERT);
        }
        else {
          mhx_draw_rect(3, 5, 32, 3, " Corefile ", MHX_A_WHITE|MHX_A_INVERT, 1);
          mhx_write_xy(4, 6, mfsc_corehdr_name, MHX_A_WHITE|MHX_A_INVERT);
          mhx_write_xy(4, 7, mfsc_corehdr_version, MHX_A_WHITE|MHX_A_INVERT);
          mhx_write_xy(4, 8, mhx_screen_get_line(&mf_screens_core_error, core_check, (char *)&buffer), MHX_A_WHITE|MHX_A_INVERT);
        }
      }
      usleep(10000);
      continue;
    }
    idle_time = 0;

    switch (mhx_lastkey.code.key) {
    case 0x03: // RUN-STOP = make no change
    case 0x1b: // ESC
      return MFSC_FILE_INVALID;
    case 0x0d: // Return = select this disk.
      // Copy name out
      lcopy(FILEINODE_ADDRESS + (mfsc_selection * 8), (long)&mfsc_corefile_inode, 4);
      lcopy(FILEINODE_ADDRESS + (mfsc_selection * 8) + 4, (long)&mfsc_corefile_size, 4);
      lcopy(FILESCREEN_ADDRESS + (mfsc_selection * 40) + 1, (long)&mfsc_corefile_displayname, 38);
      mfsc_corefile_displayname[38] = MHX_C_EOS;

      if ((core_check = mfsc_checkcore(slot ? 0 : 1)) || !mfsc_corefile_inode) {
        mhx_flashscreen(MHX_A_RED, 150);
        if (mfsc_corefile_size)
          lfill(FILEINODE_ADDRESS + (mfsc_selection * 8) + 4, 0, 4);
        // let the main loop display info popup directly
        idle_time = 149;
        continue;
      }

      return MFSC_FILE_VALID;

    case 0xf5: // F5 - switch disk
      if ((selected_dir = mfsc_load_dir((selected_dir ^ 1) | 0x2)) & 0x80)
        return MFSC_FILE_INVALID;
      mfsc_draw_header(selected_dir, slot);
      mfsc_selection = 0;
      break;
    case 0xf7: // F7 - switch dir (root / CORE)
      if ((selected_dir = mfsc_load_dir(selected_dir ^ 2)) & 0x80)
        return MFSC_FILE_INVALID;
      mfsc_draw_header(selected_dir, slot);
      mfsc_selection = 0;
      break;

    case 0x13: // HOME
      mfsc_selection = 0;
      break;
    case 0x93: // Shift-HOME
      mfsc_selection = mfsc_filecount - 1;
      break;
    case 0x1d: // Cursor right is a page
      mfsc_selection += 21;
    case 0x11: // Cursor down
      mfsc_selection++;
      if (mfsc_selection >= mfsc_filecount)
        mfsc_selection = mfsc_filecount - 1;
      break;
    case 0x9d: // Cursor left is a page
      mfsc_selection -= 21;
    case 0x91: // Cursor up or left
      mfsc_selection--;
      if (mfsc_selection < 0)
        mfsc_selection = 0;
      break;
    }

    // Adjust display position
    if (mfsc_selection < mfsc_offset)
      mfsc_offset = mfsc_selection;
    if (mfsc_selection > (mfsc_offset + 21))
      mfsc_offset = mfsc_selection - 21;
    if (mfsc_offset > (mfsc_filecount - 21))
      mfsc_offset = mfsc_filecount - 21;
    if (mfsc_offset < 0)
      mfsc_offset = 0;

    mfsc_draw_list();
  }

  return MFSC_FILE_INVALID;
}

int8_t mfsc_findcorefile(const char *filename, uint8_t require_mega65)
{
  uint8_t err;

  if ((err = nhsd_init(NHSD_INIT_BUS0, buffer)))
    return err;

  if ((err = nhsd_findfile(filename)))
    return err;

  mfsc_corefile_inode = nhsd_dirent.d_ino;
  mfsc_corefile_size = nhsd_dirent.d_reclen;
  memcpy(mfsc_corefile_displayname, "BRINGUP.COR", 12);

  if (mfsc_checkcore(require_mega65))
    return err;

  return 0;
}
