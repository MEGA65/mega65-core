#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include <memory.h>

#include "mhexes.h"
#include "mf_hlflash.h"
#include "mf_progress.h"
#include "nohysdc.h"
#include "mf_selectcore.h"
#include "crc32accl.h"
#include "qspicommon.h"

#ifdef STANDALONE
#include "mf_screens_solo.h"
#else
#include "mf_screens.h"
#endif

#define MFHF_FLASH_MAX_RETRY 10

uint8_t mfhf_slot_mb = 1;
uint32_t mfhf_slot_size = 1L << 20;
uint32_t mfhf_curaddr = 0UL;

uint8_t mfhf_core_file_state = MFHF_LC_NOTLOADED;

/*
 * mfhf_erase_some(uint32_t end_addr, uint8_t flag)
 *
 * parameters:
 *   erases 
 */
/*
void mfhf_erase_some(uint32_t end_addr, uint8_t flag)
{
  uint32_t size;

  while (addr < end_addr) {
    if (addr < (unsigned long)num_4k_sectors << 12)
      size = 4096;
    else
      size = 1L << ((long)flash_sector_bits);

    mhx_writef("%c    Erasing sector at $%08lX", 0x13, addr);
    if (flag & MFHF_FLAG_VISUAL)
      POKE(0xD020, 2);
    erase_sector(addr);
    read_data(0xffffffff);
    if (flag & MFHF_FLAG_VISUAL)
      POKE(0xD020, 0);

    addr += size;
    if (flag & MFHF_FLAG_PROGRESS)
      mfp_set_area(end_addr, num, 'E', MHX_A_RED | MHX_A_INVERT);
  }
}
*/

void mfhf_display_sderror(char *error, uint8_t error_code) {
  mhx_draw_rect(3, 12, 32, 2, "Load Error", MHX_A_ORANGE, 1);
  mhx_write_xy(20 - (mhx_strlen(error) >> 1), 13, error, MHX_A_ORANGE);
  if (error_code != NHSD_ERR_NOERROR) {
    mhx_set_xy(9, 14);
    mhx_writef(MHX_W_ORANGE "SD Card Error Code $%02X", error_code);
  }
  mhx_press_any_key(MHX_AK_NOMESSAGE|MHX_AK_ATTENTION, MHX_A_NOCOLOR);
}

void mfhf_display_message(char *title, char *text, uint8_t attr);

int8_t mfhf_load_core() {
  uint8_t err;
  uint16_t length;
  uint32_t addr, addr_len, core_crc;

  mfhf_core_file_state = MFHF_LC_NOTLOADED;

  // cover menu bar keys except STOP
  lfill(mhx_base_scr + 23*40, 0xa0, 60);

  // setup progress bar
  mfp_init_progress(8, 17, '-', " Load Core ", MHX_A_WHITE);
  if (mfsc_corehdr_length < SLOT_SIZE) {
    // fill unused slot area grey
    length = mfsc_corehdr_length >> 16;
    if (mfsc_corehdr_length & 0xffff)
      length++;
    mfp_set_area(length, 255, 0x69, MHX_A_LGREY);
  }
  else
    length = 128;
  addr_len = mfsc_corehdr_length;

  // open file
  if ((err = nhsd_open(mfsc_corefile_inode))) {
    // Couldn't open the file.
    mfhf_display_sderror("Could not open core file!", err);
    return 0;
  }

  // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

  // load file to attic ram
  mfp_start(0, MFP_DIR_UP, 0x5f, MHX_A_WHITE, " Load Core ", MHX_A_WHITE);
  for (addr = 0; addr < mfsc_corehdr_length; addr += 512) {
    if ((err = nhsd_read()))
      break;
    lcopy(QSPI_FLASH_BUFFER, 0x8000000L + addr, 512);
    mfp_progress(addr);
    // let user abort load
    mhx_getkeycode(MHX_GK_PEEK);
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return 0;
  }
  if (err != NHSD_ERR_NOERROR) {
    mfhf_display_sderror("Error while loading core file!", err);
    return 0;
  }
  nhsd_close();

  if (addr & 0xffff)
    mfp_set_area(addr >> 16, 1, 0x5f, MHX_A_WHITE);

  // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

  // check crc32 of file
  mfp_start(0, MFP_DIR_UP, 0xa0, MHX_A_WHITE, " Checking CRC32 ", MHX_A_WHITE);
  make_crc32_tables(data_buffer, buffer);
  init_crc32();
#define first err
  for (first = 1, addr = 0; addr < mfsc_corehdr_length; addr += 256) {
    // we don't need the part string anymore, so we reuse this buffer
    // note: part is only used in probe_qspi_flash
    lcopy(0x8000000L + addr, (long)part, 256);
    if (first) {
      // the first sector has the real length and the CRC32
      addr_len = *(uint32_t *)(part + MFSC_COREHDR_LENGTH);
      core_crc = *(uint32_t *)(part + MFSC_COREHDR_CRC32);
      // set CRC bytes to pre-calculation value
      *(uint32_t *)(part + MFSC_COREHDR_CRC32) = 0xf0f0f0f0UL;
      if (addr_len != mfsc_corehdr_length)
        break;
      first = 0;
    }
    update_crc32(addr_len - addr > 255 ? 0 : addr_len - addr, part);
    mfp_progress(addr);
    // let user abort load
    mhx_getkeycode(MHX_GK_PEEK);
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return 0;
  }
  if (core_crc == get_crc32() && !first)
    mfhf_core_file_state = MFHF_LC_ATTICOK;
#undef first
  mfp_set_area(0, length, mfhf_core_file_state != MFHF_LC_ATTICOK ? 'E' : ' ', MHX_A_INVERT|(mfhf_core_file_state != MFHF_LC_ATTICOK ? MHX_A_RED : MHX_A_GREEN));

  if (mfhf_core_file_state != MFHF_LC_ATTICOK) {
    mfhf_display_sderror("CRC32 Checksum Error!", NHSD_ERR_NOERROR);
    return MFHF_LC_NOTLOADED;
  }

  // set potentially changed flags after load & crc check
  lpoke(0x8000000L + MFSC_COREHDR_BOOTFLAGS, mfsc_corehdr_bootflags);

  // mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

  return mfhf_core_file_state;
}

int8_t mfhf_load_core_from_flash(uint8_t slot, uint32_t addr_len) {
  uint32_t addr, flash_addr;

  mfhf_core_file_state = MFHF_LC_NOTLOADED;

  // cover menu bar keys except STOP
  lfill(mhx_base_scr + 23*40, 0xa0, 60);

  // setup progress bar
  mfp_init_progress(8, 17, '-', " Read Core Header ", MHX_A_WHITE);

  // load core from qspi to attic ram
  mfp_start(0, MFP_DIR_UP, 0xa0, MHX_A_WHITE, " Read Core Header ", MHX_A_WHITE);
  for (flash_addr = SLOT_SIZE * slot, addr = 0; addr < addr_len; flash_addr += 512, addr += 512) {
    read_data(flash_addr);
    lcopy((long)&data_buffer, 0x8000000L + addr, 512);
    mfp_progress(addr);
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return mfhf_core_file_state;
  }

  // set potentially changed flags after load & crc check
  lpoke(0x8000000L + MFSC_COREHDR_BOOTFLAGS, mfsc_corehdr_bootflags);

  mfsc_corehdr_length = addr_len;
  mfhf_core_file_state = MFHF_LC_ATTICOK;

  // do a dummy sdcard action in hope that this resets the bus
  // TODO: solve underlaying problem!
  nhsd_init(NHSD_INIT_BUS0_FB1, buffer);

  return mfhf_core_file_state;
}

int8_t mfhf_sectors_differ(uint32_t attic_addr, uint32_t flash_addr, uint32_t size)
{
  while (size > 0) {

    lcopy(0x8000000L + attic_addr, QSPI_FLASH_BUFFER, 512);
    if (!verify_data_in_place(flash_addr)) {
#if 0
//#ifdef SHOW_FLASH_DIFF
      mhx_writef("\nVerify error  ");
      mhx_press_any_key(0, MHX_A_NOCOLOR);
      mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "attic_addr=$%08lX, flash_addr=$%08lX\n", attic_addr, flash_addr);
      read_data(flash_addr);
      lcopy(0x8000000L + attic_addr, (long)buffer, 512);
      debug_memory_block(0, flash_addr);
      debug_memory_block(256, flash_addr);
      mhx_writef("comparing read data against reread yields %d\n", verify_data_in_place(flash_addr));
      mhx_press_any_key(0, MHX_A_NOCLOR);
      mhx_clearscreen(' ', MHX_A_WHITE);
      mhx_set_xy(0, 0);
#endif
      return 1;
    }
    attic_addr += 512;
    flash_addr += 512;
    size -= 512;
  }
  return 0;
}

int8_t mfhf_erase_some_sectors(uint32_t start_addr, uint32_t end_addr)
{
  uint32_t size;

  while (start_addr < end_addr) {
    if (start_addr < (uint32_t)num_4k_sectors << 12)
      size = 4096UL;
    else
      size = 1UL << ((uint32_t)flash_sector_bits);

#if 0
    mhx_set_xy(0, 4);
    mhx_writef(MHX_W_WHITE
               "start_addr  = %08lx  \n"
               "start_block = %08lx  \n"
               "size        = %08lx  \n"
               "size_blocks = %08lx  \n", start_addr, start_addr >> 16, size, size >> 16);
    mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
#endif

    POKE(0xD020, 2);
    erase_sector(start_addr); // qspi lowlevel, needs returncode! erase could fail!
    read_data(0xffffffff); // needed?
    POKE(0xD020, 0);

    mfp_set_area(start_addr >> 16, size >> 16, '0', MHX_A_INVERT|MHX_A_LRED);

    start_addr += size;
  }

  return 0;
}

int8_t mfhf_flash_core(uint8_t selected_file, uint8_t slot) {
  uint32_t addr, end_addr, size, waddr;
  uint8_t tries;

  /*
   * Flow of high level flashing progress:
   *
   * - erase first 1M of flash
   * - for each sector starting from top of flash slot going down:
   *   - verify sector with data, if equal: mark as done and got to next sector
   *   - otherwise:
   *     - check if we flashed this sector MFHF_FLASH_MAX_RETRY times, and abort if exceeded
   *     - erase sector (256k, 64k, or even 4k)
   *     - write sector data in 256 byte chunks reading data either from attic or from disk
   *     - start over with verification of sector
   * 
   * How does flashing differ from erasing? Just cut out verfiy and write steps and you have
   * erasing.
   * 
   */

  // cover STOP menubar option with warning
  lcopy((long)mf_screens_menu.screen_start + 7 * 80, mhx_base_scr + 23*40, 80);
  mhx_hl_lines(23, 24, MHX_A_LGREY|MHX_A_INVERT);

  // Read a few times to make sure transient initial read problems disappear
  // TODO: get rid of this by fixing underlaying problem!
  read_data(0);
  read_data(0);
  read_data(0);

  /*
   * Special handling for 0.95 in slot 0
   *
   * we specifically erase the three sectors that contain a sync word
   * to make sure recovery by slot 1 core works
   *
   */
  if (slot == 0x80) {
    mfhf_erase_some_sectors(0x000000UL, 0x040000UL);
    mfhf_erase_some_sectors(0x340000UL, 0x380000UL);
    mfhf_erase_some_sectors(0x400000UL, 0x440000UL);
  }
  slot &= 0x7f;
  /*
   * end of special handling for 0.95 in slot 0
   */

  // set end_addr to the START OF THE SLOT (flashing downwards!)
  end_addr = SLOT_SIZE * slot;

  /*
  mhx_set_xy(0, 1);
  mhx_writef(MHX_W_WHITE "SLOT_SIZE = %08lx  \nSLOT      = %d\nend_addr  = %08lx  \n", SLOT_SIZE, slot, end_addr);
  */

  // Setup progress bar
  mfp_start(0, MFP_DIR_DOWN, '*', MHX_A_INVERT|MHX_A_WHITE, " Erasing Slot ", MHX_A_WHITE);

  if (!slot || selected_file == MFSC_FILE_ERASE)
    // if we are flashing slot 0 or erasing a slot, we
    // erase the full slot first
    size = SLOT_SIZE;
  else {
    // if we are not flashing factory slot, just erase the first sector
    // to get rid of the core header -- header is 4k!
    if (end_addr <= (uint32_t)num_4k_sectors << 12)
      size = 4096;
    else
      size = 1L << ((uint32_t)flash_sector_bits);
  }

  // now erase what is needed
  mfhf_erase_some_sectors(end_addr, end_addr + size);

  // if it was erase only, we jump to the end!
  if (selected_file == MFSC_FILE_ERASE)
    goto mfhf_flash_finish;

  mfp_start(0, MFP_DIR_DOWN, '*', MHX_A_INVERT|MHX_A_WHITE, " Flash Core to Slot ", MHX_A_WHITE);

  // only flash up to the files length
  addr = end_addr + SLOT_SIZE;

#undef SHORTFLASHDEBUG

#ifdef SHORTFLASHDEBUG
  mhx_set_xy(0,0);
  mhx_writef(MHX_W_WHITE "end  = %08lx\naddr = %08lx\n", end_addr, addr);
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
#endif
  while (addr > end_addr) {
    if (addr <= (uint32_t)num_4k_sectors << 12)
      size = 4096;
    else
      size = 1L << ((uint32_t)flash_sector_bits);
    addr -= size;

#ifdef SHORTFLASHDEBUG
    mhx_writef(MHX_W_WHITE MHX_W_HOME "addr = %08lx\nsize = %08lx\n                  \n                  \n                     \n", addr, size);
#endif
#if 0
    mhx_writef("\n%d %08lX %08lX\nsize = %ld", num_4k_sectors, (unsigned long)num_4k_sectors << 12, addr, size);
    mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
#endif

    // if we are flashing a file, skip over sectors without data
    // this works because at this point addr points at the start of the sector that is being flashed
    if ((addr - end_addr) >= mfsc_corehdr_length) {
#ifdef SHORTFLASHDEBUG
      mhx_writef("skip\n");
#endif
      continue;
    }

#ifdef SHORTFLASHDEBUG
    mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
#endif
    // Do a dummy read to clear any pending stuck QSPI commands
    // (else we get incorrect return value from QSPI verify command)
    // TODO: get rid of this
    while (!verify_data_in_place(0UL))
      read_data(0UL);

    // try 10 times to erase/write the sector
    for (tries = 0; tries < MFHF_FLASH_MAX_RETRY; tries++) {
      if (selected_file == MFSC_FILE_VALID) {
        // Verify the sector to see if it is already correct
        if (!mfhf_sectors_differ(addr - end_addr, addr, size)) {
          mfp_set_area(addr >> 16, size >> 16, '*', MHX_A_INVERT|MHX_A_WHITE);
          break;
        }
      }
#ifdef SHORTFLASHDEBUG
      mhx_writef("verify..");
#endif
      // Erase Sector
      mfhf_erase_some_sectors(addr, addr + size);
      if (selected_file == MFSC_FILE_ERASE)
        break;

#ifdef SHORTFLASHDEBUG
      mhx_writef("erase..");
#endif
      // Program sector
      if (selected_file == MFSC_FILE_VALID) {
        for (waddr = addr + size; waddr > addr; waddr -= 256) {
#ifdef SHORTFLASHDEBUG
          mhx_writef("%08lx..", waddr);
          mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
#endif
          lcopy(0x8000000L + waddr - 256 - end_addr, (unsigned long)data_buffer, 256);
          // display sector on screen
          // lcopy(0x8000000L+waddr-SLOT_SIZE*slot,0x0400+17*40,256);
          POKE(0xD020, 3);
          program_page(waddr - 256, 256);
          POKE(0xD020, 0);
          mfp_progress(waddr - 256);
        }
      }
    }

    // if we failed 10 times, we abort with the option for the flash inspector
    if (tries == MFHF_FLASH_MAX_RETRY) {
      mhx_move_xy(0, 10);
      mhx_writef("ERROR: Could not write to flash after\n%d tries.\n", tries);

      // secret Ctrl-F (keycode 0x06) will launch flash inspector,
      // but only if QSPI_FLASH_INSPECTOR is defined!
      // otherwise: endless loop!
#ifdef QSPI_FLASH_INSPECTOR
      mhx_writef("Press Ctrl-F for Flash Inspector.\n");

      while (PEEK(0xD610))
        POKE(0xD610, 0);
      while (PEEK(0xD610) != 0x06)
        POKE(0xD610, 0);
      while (PEEK(0xD610))
        POKE(0xD610, 0);
      flash_inspector();
#else
      // TODO: re-erase start of slot 0, reprogram flash to start slot 1
      mhx_writef("\nPlease turn the system off!\n");
      // don't let the user do anything else
      while (1)
        POKE(0xD020, PEEK(0xD020) & 0xf);
#endif
      // don't do anything else, as this will result in slot 0 corruption
      // as global addr gets changed by flash_inspector
      return 0;
    }
  }

#if 0
  mhx_writef("Flash slot successfully updated.      \n\n");
  if (selected_file == MFSC_FILE_ERASE && flash_time > 0)
    mhx_writef("   Erase: %d sec \n\n", flash_time);
  else if (load_time + crc_time + flash_time > 0)
    mhx_writef("    Load: %d sec \n"
               "     CRC: %d sec \n"
               "   Flash: %d sec \n"
               "\n", load_time, crc_time, flash_time);
#endif

mfhf_flash_finish:
  mhx_draw_rect(4, 12, 30, 1, "Finished Flashing", MHX_A_GREEN, 1);
  mhx_write_xy(5, 13, (selected_file == MFSC_FILE_VALID) ? "Core was successfully flashed" : "Slot was successfully erased", MHX_A_GREEN);

  mhx_press_any_key(MHX_AK_ATTENTION|MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);

  return 0;
}
