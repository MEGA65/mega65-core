#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>

#include "qspicommon.h"
#include "qspireconfig.h"
#include "mhexes.h"
#include "crc32accl.h"
#include "nohysdc.h"
#include "mf_selectcore.h"

#include <cbm_screen_charmap.h>

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

// used by QSPI routines
unsigned char data_buffer[512];
// used by SD card routines
unsigned char buffer[512];

uint8_t hw_model_id = 0;
char *hw_model_name = "?unknown?";

unsigned short mb = 0;

/***************************************************************************

 FPGA / Core file / Hardware platform routines

 ***************************************************************************/

// clang-format off
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
  mhx_writef("Flash @ $%08x:\n", addr);
  for (i = 0; i < 256; i++) {
    if (!(i & 15))
      mhx_writef("+%03x : ", i);
    mhx_writef("%02x", data_buffer[i]);
    if ((i & 15) == 15)
      mhx_writef("\n");
  }

  mhx_writef("page_size=%d\n", page_size);

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
        mhx_press_any_key(0, MHX_A_NOCOLOR);
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
        mhx_writef("E: %02x %02x %02x\n", lpeek(0xffd6e00), lpeek(0xffd6e01), lpeek(0xffd6e02));
        mhx_writef("F: %02x %02x %02x\n", lpeek(0xffd6f00), lpeek(0xffd6f01), lpeek(0xffd6f02));
        mhx_writef("P: %02x %02x %02x\n", data_buffer[0], data_buffer[1], data_buffer[2]);
        // Now program it
        unprotect_flash(addr);
        query_flash_protection(addr);
        mhx_writef("About to call program_page()\n");
        //        program_page(addr,page_size);
        program_page(addr, 256);
        mhx_press_any_key(0, MHX_A_NOCOLOR);
      }

      read_data(addr);
      mhx_writef("%cFlash @ $%08lx:\n", 0x93, addr);
      for (i = 0; i < 256; i++) {
        if (!(i & 15))
          mhx_writef("+%03x : ", i);
        mhx_writef("%02x", data_buffer[i]);
        if ((i & 15) == 15)
          mhx_writef("\n");
      }
      mhx_writef("Bytes differ? %s\n", PEEK(0xD689) & 0x40 ? "Yes" : "No");
      mhx_writef("page_size=%d\n", page_size);
    }
  }
#endif
}

#ifdef SHOW_FLASH_DIFF
void debug_memory_block(int offset, unsigned long dbg_addr)
{
  for (i = 0; i < 256; i++) {
    if (!(i & 15))
      mhx_writef(MHX_W_WHITE "%07lx:", dbg_addr + i);
    if (data_buffer[offset + i] != buffer[offset + i])
      mhx_setattr(MHX_A_RED);
    else
      mhx_setattr(MHX_A_LGREEN);
    mhx_writef("%02x", data_buffer[offset + i]);
  }
  mhx_press_any_key(0, MHX_A_WHITE);
}
#endif

unsigned char flash_region_differs(unsigned long attic_addr, unsigned long flash_addr, long size)
{
  while (size > 0) {

    lcopy(0x8000000 + attic_addr, 0xffd6e00L, 512);
    if (!verify_data_in_place(flash_addr)) {
#ifdef SHOW_FLASH_DIFF
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

void reflash_slot(unsigned char the_slot, unsigned char selected_file, char *slot0version)
{
  unsigned long size, waddr, end_addr;
  uint8_t err;
  unsigned char tries;
  unsigned char erase_mode = 0;
  unsigned char slot = the_slot;
  uint32_t core_crc;

  mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "REFLASH SLOT %d %d\n", the_slot, selected_file);
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

  if (selected_file == MFS_FILE_INVALID)
    return;

  mhx_writef("is valid\n");
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

#ifndef QSPI_ERASE_ZERO
  if (selected_file == MFS_FILE_ERASE && slot == 0) {
    // we refuse to erase slot 0
    mhx_writef(MHX_W_WHITE MHX_W_CLRHOME MHX_W_RED "\nRefusing to erase slot 0!\n\n" MHX_W_WHITE);
    mhx_press_any_key(0, MHX_A_NOCOLOR);
    return;
  }
#endif

  mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "Preparing to reflash slot %d...\n\n", slot);
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

  // Read a few times to make sure transient initial read problems disappear
  read_data(0);
  read_data(0);
  read_data(0);

  mhx_writef("dummy read done\n");
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

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

  mhx_writef("buffer cleared %d\n", selected_file);
  mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

  // return code of select_bitstream_file > 1 means a file was selected
  if (selected_file == MFS_FILE_VALID) {
    mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "Checking core file...\n %s\n", disk_display_return);
    mhx_press_any_key(MHX_AK_NOMESSAGE, 0);

    if ((err = nhsd_open(disk_file_inode))) {
      // Couldn't open the file.
      mhx_writef(MHX_W_RED "\nERROR: Could not open core file (%d)!\n" MHX_W_WHITE, err);
      mhx_press_any_key(0, MHX_A_WHITE);
      return;
    }

    mhx_move_xy(0, 1);

    // TODO: also check NAME "MEGA65" for slot 0 flash!
    //if (!check_model_id_field(slot == 0 ? 1 : 0, slot0version))
    //  return;

#if defined(STANDALONE) && defined(QSPI_DEBUG)
    make_crc32_tables(data_buffer, buffer);
    init_crc32();
    update_crc32(11, "hello world");
    mhx_writef(MHX_W_CLRHOME "\n\nhello world CRC32 = %08lX\n", get_crc32());
    mhx_press_any_key(0, MHX_A_WHITE);
#endif

#if 0
    // start reading file from beginning again
    // (as the model_id checking read the first 512 bytes already)
    if ((err = nhsd_open(disk_file_inode))) {
      mhx_writef("error %d while loading COR file\n", err);
      mhx_press_any_key(MHX_AK_NOMESSAGE, 0);
      return;
    }
#endif

    mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "%cLoading COR file into Attic RAM...\n");
    // progress_start(SLOT_SIZE_PAGES, "Loading");

    for (addr = 0; addr < SLOT_SIZE; addr += 512) {
      if ((err = nhsd_read()))
        break;
      lcopy(0xffd6e00L, 0x8000000L + addr, 512);
      // progress_bar(2, "Loading");
    }
    addr_len = addr; // save last sector
    // fill rest of attic ram with emptiness
    for (; addr < SLOT_SIZE; addr += 512) {
      lfill(addr, 0xff, 512);
      // progress_bar(2, "Filling");
    }
    // progress_time(load_time);
    nhsd_close();

    // mhx_writef("\n\nLoaded COR file in %u seconds.\n", load_time);

    // always do a CRC32 check!
    mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "Generating CRC32 checksum...\n");
    // progress_start(addr_len >> 8, "Checksum");
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
        // progress_goal = addr_len >> 8;
        core_crc = *(uint32_t *)(part + 0x84);
        // set CRC bytes to pre-calculation value
        *(uint32_t *)(part + 0x84) = 0xf0f0f0f0UL;

        // EIGHT_FROM_TOP;
        mhx_writef("\n\nCORE Length = %08lx\nCORE CRC32  = %08lx", addr_len, core_crc);

        y = 0;
      }
      update_crc32(addr_len - addr > 255 ? 0 : addr_len - addr, part);
      // progress_bar(1, "Checksum");
    }
    // progress_time(crc_time);
    // EIGHT_FROM_TOP;
    mhx_writef("\n\n\nCALC CRC32  = %08lx\n", get_crc32());

    if (addr_len < 4096 || core_crc != get_crc32()) {
      mhx_writef("\n" MHX_W_RED "CHECKSUM MISMATCH" MHX_W_WHITE " %ds %ds\n", load_time, crc_time);
      if (slot == 0) {
        mhx_writef("\nRefusing to flash slot 0!\n");
        mhx_press_any_key(0, MHX_A_NOCOLOR);
        return;
      }
      else {
        mhx_writef("\nPress F10 to flash anyway, or any other key to abort.\n");
        mhx_press_any_key(MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
        if (mhx_lastkey.code.key != 0xfa)
          return;
      }
    }
    else {
      mhx_writef("\n" MHX_W_GREEN "Checksum matches, good to flash." MHX_W_WHITE "\n");
      mhx_press_any_key(0, MHX_A_NOCOLOR);
      if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
        return;
    }

    // start flashing
    mhx_clearscreen(' ', MHX_A_WHITE);
    mhx_set_xy(0, 0);
    // progress_start(SLOT_SIZE_PAGES, "Flashing");
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
      mhx_writef("\n%d %08lX %08lX\nsize = %ld", num_4k_sectors, (unsigned long)num_4k_sectors << 12, addr, size);
      mhx_press_any_key(0, 0);
#endif

      // Do a dummy read to clear any pending stuck QSPI commands
      // (else we get incorrect return value from QSPI verify command)
      while (!verify_data_in_place(0L))
        read_data(0);

      // try 10 times to erase/write the sector
      tries = 0;
      do {
        // Verify the sector to see if it is already correct
        mhx_writef(MHX_W_HOME "  Verifying sector at $%08lX/%07lX", addr, addr - SLOT_SIZE * slot);
        if (!flash_region_differs(addr - SLOT_SIZE * slot, addr, size))
          break;

        // if we failed 10 times, we abort with the option for the flash inspector
        if (tries == 10) {
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
          return;
        }

        // next try to erase/program the sector
        tries++;

        // Erase Sector
        mhx_writef(MHX_W_HOME "    Erasing sector at $%08lX", addr);
        POKE(0xD020, 2);
        erase_sector(addr);
        read_data(0xffffffff);
        POKE(0xD020, 0);

        // Program sector
        mhx_writef(MHX_W_HOME "Programming sector at $%08lX", addr);
        for (waddr = addr + size; waddr > addr; waddr -= 256) {
          lcopy(0x8000000L + waddr - 256 - SLOT_SIZE * slot, (unsigned long)data_buffer, 256);
          // display sector on screen
          // lcopy(0x8000000L+waddr-SLOT_SIZE*slot,0x0400+17*40,256);
          POKE(0xD020, 3);
          program_page(waddr - 256, 256);
          POKE(0xD020, 0);
        }
      } while (tries < 11);

      // progress_bar(size >> 8, "Flashing");
    }
    // progress_time(flash_time);

    // Undraw the sector display before showing results
    lfill(0x0400 + 12 * 40, 0x20, 512);
  }
  else if (selected_file == MFS_FILE_ERASE) {
    // extra question before erasing a slot
    mhx_writef(MHX_W_ORANGE "\nYou are about to erase slot %d!\n"
           "Are you sure you want to proceed? (y/n)" MHX_W_WHITE "\n\n", slot);
    if (!mhx_check_input("y", 0, MHX_A_NOCOLOR))
      return;
    mhx_clearscreen(' ', MHX_A_WHITE);
    mhx_set_xy(0, 0);

    // Erase mode
    // progress_start(SLOT_SIZE_PAGES, "Erasing");
    addr = SLOT_SIZE * slot;
    erase_some_sectors(addr + SLOT_SIZE, 1);
    // progress_time(flash_time);
  }

  // EIGHT_FROM_TOP;
  mhx_writef("Flash slot successfully updated.      \n\n");
  if (selected_file == MFS_FILE_ERASE && flash_time > 0)
    mhx_writef("   Erase: %d sec \n\n", flash_time);
  else if (load_time + crc_time + flash_time > 0)
    mhx_writef("    Load: %d sec \n"
               "     CRC: %d sec \n"
               "   Flash: %d sec \n"
               "\n", load_time, crc_time, flash_time);

  mhx_press_any_key(MHX_AK_ATTENTION, MHX_A_NOCOLOR);

  return;
}

void erase_some_sectors(unsigned long end_addr, unsigned char progress)
{
  unsigned long size;

  while (addr < end_addr) {
    if (addr < (unsigned long)num_4k_sectors << 12)
      size = 4096;
    else
      size = 1L << ((long)flash_sector_bits);

    mhx_writef("%c    Erasing sector at $%08lX", 0x13, addr);
    POKE(0xD020, 2);
    erase_sector(addr);
    read_data(0xffffffff);
    POKE(0xD020, 0);

    addr += size;
    if (progress) ;
      // progress_bar(size >> 8, "Erasing");
  }
}

/***************************************************************************

 Mid-level SPI flash routines

 ***************************************************************************/

unsigned char probe_qspi_flash(void)
{
  spi_cs_high();
  usleep(50000L);

#ifdef QSPI_VERBOSE
  mhx_writef("\nProbing flash...\n");
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
    mhx_writef(MHX_W_RED "ERROR: Cannot communicate with QSPI\nflash device. Retry..." MHX_W_WHITE "\n\n");
    flash_reset();
    fetch_rdid();
    read_registers();
  }

#ifdef QSPI_DEBUG
  // hexdump info block
  for (i = 0; i < 0x80; i++) {
    if (!(i & 15))
      mhx_writef("+%03x : ", i);
    mhx_writef("%02x", (unsigned char)cfi_data[i]);
    if ((i & 15) == 15)
      mhx_writef("\n");
  }
  mhx_press_any_key(0, MHX_A_NOCOLOR);
#endif
#ifdef QSPI_VERBOSE
  mhx_writef("\nQSPI Information\n\n");
#endif

  // this looks for ALT?\00 at cfi_data pos 0x51
  if (cfi_data[0x51] == 0x41 && cfi_data[0x52] == 0x4c && cfi_data[0x53] == 0x54 && cfi_data[0x56] == 0x00) {
    for (i = 0; i < cfi_data[0x57]; i++)
      part[i] = cfi_data[0x58 + i];
    part[i] = MHX_C_EOS;
#ifdef QSPI_VERBOSE
    mhx_writef("Part         = %s\n"
               "Part Family  = %02x-%c%c\n",
        part, cfi_data[5], cfi_data[6], cfi_data[7]);
#endif
  }
  else {
    part[0] = 0;
#ifdef QSPI_VERBOSE
    mhx_writef(MHX_W_RED "Part         = unknown %02x %02x %02x\n"
               "Part Family  = unknown" MHX_W_WHITE "\n",
               cfi_data[0x51], cfi_data[0x52], cfi_data[0x53]);
#endif
  }

#ifdef QSPI_VERBOSE
  mhx_writef("Manufacturer = $%02x\n"
             "Device ID    = $%04x\n"
             "RDID count   = %d\n"
             "Sector Arch  = ", manufacturer, device_id, cfi_length);
#endif

  if (cfi_data[4] == 0x00) {
#ifdef QSPI_VERBOSE
    mhx_writef("uniform 256kb\n");
#endif
    num_4k_sectors = 0;
    flash_sector_bits = 18;
  }
  else if (cfi_data[4] == 0x01) {
    num_4k_sectors = 1 + cfi_data[0x2d];
    flash_sector_bits = 16;
#ifdef QSPI_VERBOSE
    mhx_writef("%dx4kb param/64kb data\n", num_4k_sectors);
#endif
  }
  else {
#ifdef QSPI_VERBOSE
    mhx_writef("%cunknown ($%02x)%c\n", 28, cfi_data[4], 5);
#endif
    flash_sector_bits = 0;
  }
#ifdef QSPI_VERBOSE
  mhx_writef("Prgtime      = 2^%d us\n"
             "Page size    = 2^%d bytes\n",
             cfi_data[0x20], cfi_data[0x2a]);
#endif

  if (cfi_data[0x2a] == 8)
    page_size = 256;
  if (cfi_data[0x2a] == 9)
    page_size = 512;
  if (!page_size) {
    mhx_writef(MHX_W_RED "WARNING: Unsupported page size" MHX_W_WHITE "\n");
    page_size = 0;
  }
#ifdef QSPI_VERBOSE
  mhx_writef("Est. prgtime = %d us/byte.\n"
             "Est. erasetm = 2^%d ms/sector.\n",
             cfi_data[0x20] / cfi_data[0x2a], cfi_data[0x21]);
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
  mhx_writef("Flash size   = %d MB\n"
             "Flash slots  = %d slots of %d MB\n"
             "Register SR1 = %c$%02x" MHX_W_WHITE "\n",
             mb, slot_count, SLOT_MB, reg_sr1 == 0xff ? MHX_C_RED : MHX_C_WHITE, reg_sr1);
  // show flags
  if (reg_sr1 & 0x80)
    mhx_writef(" WRPROT");
  if (reg_sr1 & 0x40)
    mhx_writef(" PRGERR");
  if (reg_sr1 & 0x20)
    mhx_writef(" ERAERR");
  if (reg_sr1 & 0x02)
    mhx_writef(" WRLENA");
  if (reg_sr1 & 0x01)
    mhx_writef(" DEVBSY");
  if (reg_sr1 & 0xe3)
    mhx_writef("\n");
  mhx_writef("Register CR1 = %c$%02x" MHX_W_WHITE " (latency code %d)\n\n",
             reg_cr1 == 0xff ? MHX_C_RED : MHX_C_WHITE, reg_cr1, latency_code);
#endif

  // failed to detect, probably dip sw #3 = off
  if (mb == 0 || page_size == 0 || flash_sector_bits == 0 || part[0] == 0) {
    mhx_writef(MHX_W_RED "ERROR: Failed to probe flash\n       (dip #3 not on?)" MHX_W_WHITE "\n");
#ifndef STANDALONE
    // never return
    while (1)
      POKE(0xD020, PEEK(0xD020) + 1);
#endif
    return -1;
  }

#ifdef QSPI_VERBOSE
  mhx_press_any_key(0, MHX_A_NOCOLOR);
#endif

  /* The 64MB = 512Mbit flash in the MEGA65 R3A comes write-protected, and with
     quad-SPI mode disabled. So we have to fix both of those (which then persists),
     and then flash the bitstream.
  */
  enable_quad_mode();

  read_registers();

  if (reg_sr1 & 0x80) {
    mhx_writef("\n" MHX_W_RED "ERROR: Could not clear whole-of-flash write-protect flag." MHX_W_WHITE "\n");
    while (1)
      POKE(0xD020, PEEK(0xD020) + 1);
  }

  mhx_writef("\nQuad-mode enabled,\nflash is write-enabled.\n\n");

  // Finally make sure that there is no half-finished QSPI commands that will cause erroneous
  // reads of sectors.
  read_data(0);
  read_data(0);
  read_data(0);

  mhx_writef("Done probing flash.\n\n");

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
  mhx_writef()"CR1=$%02x\n",c);
  mhx_press_any_key(0, MHX_A_NOCOLOR);
#endif
}

void unprotect_flash(unsigned long addr)
{
  unsigned char c;

  //  mhx_writef("unprotecting sector.\n");

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
  //   mhx_writef("done unprotecting.\n");
}

void query_flash_protection(unsigned long addr)
{
  unsigned long address_in_sector = 0;
  unsigned char c;

  i = addr >> flash_sector_bits;

  mhx_writef("DYB Protection flag: ");

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
  mhx_writef("$%02x ", c);

  spi_cs_high();
  delay();
  mhx_writef("\n");

  mhx_writef("PPB Protection flags: ");
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
  mhx_writef("$%02x ", c);

  spi_cs_high();
  delay();
  mhx_writef("\n");
}

void erase_sector(unsigned long address_in_sector)
{

  unprotect_flash(address_in_sector);
  //  query_flash_protection(address_in_sector);

  // XXX Send Write Enable command (0x06 ?)
  //  mhx_writef("activating write enable...\n");
  spi_write_enable();

  // XXX Clear status register (0x30)
  //  mhx_writef("clearing status register...\n");
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
  //  mhx_writef("erasing sector...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  if ((addr >> 12) >= num_4k_sectors) {
    // Do 64KB/256KB sector erase
    //    mhx_writef("erasing large sector.\n");
    POKE(0xD681, address_in_sector >> 0);
    POKE(0xD682, address_in_sector >> 8);
    POKE(0xD683, address_in_sector >> 16);
    POKE(0xD684, address_in_sector >> 24);
    // Erase large page
    POKE(0xd680, 0x58);
  }
  else {
    // Do fast 4KB sector erase
    //    mhx_writef("erasing small sector.\n");
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
    mhx_writef("error erasing sector @ $%08x\n",address_in_sector);
    mhx_press_any_key(0, MHX_A_NOCOLOR);
  }
#ifdef QSPI_DEBUG
  else
    mhx_writef("sector at $%08llx erased.\n%c",address_in_sector,0x91);
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
  //  mhx_writef("About to clear SR1\n");

  spi_clear_sr1();
  //  mhx_writef("About to clear WREN\n");
  spi_write_disable();

  //  mhx_writef("Waiting for flash to go non-busy\n");
  while (reg_sr1 & 0x03) {
    //    mhx_writef("flash busy. ");
    read_sr1();
  }

  // XXX Send Write Enable command (0x06 ?)
  //  mhx_writef("activating write enable...\n");
  spi_write_enable();

  // XXX Clear status register (0x30)
  //  mhx_writef("clearing status register...\n");
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
  //  mhx_writef("Writing with page_size=%d\n",page_size);
  // mhx_writef("Data = $%02x, $%02x, $%02x, $%02x ... $%02x, $%02x, $%02x, $%02x ...\n",
  //         data_buffer[0],data_buffer[1],data_buffer[2],data_buffer[3],
  //         data_buffer[0x100],data_buffer[0x101],data_buffer[0x102],data_buffer[0x103]);
  if (page_size == 256) {
    // Write 256 bytes
    //    mhx_writef("256 byte program\n");
    lcopy((unsigned long)data_buffer, 0xffd6f00L, 256);

    POKE(0xD681, start_address >> 0);
    POKE(0xD682, start_address >> 8);
    POKE(0xD683, start_address >> 16);
    POKE(0xD684, start_address >> 24);
    POKE(0xD680, 0x55);
    while (PEEK(0xD680) & 3)
      POKE(0xD020, PEEK(0xD020) + 1);

    //    mhx_writef("Hardware SPI write 256\n");
  }
  else if (page_size == 512) {
    // Write 512 bytes
    //    mhx_writef("Hardware SPI write 512 (a)\n");

    // is this broken? at least it is not used
    lcopy((unsigned long)data_buffer, 0xffd6e00L, 512);
    POKE(0xD681, start_address >> 0);
    POKE(0xD682, start_address >> 8);
    POKE(0xD683, start_address >> 16);
    POKE(0xD684, start_address >> 24);
    POKE(0xD680, 0x54);
    while (PEEK(0xD680) & 3)
      POKE(0xD020, PEEK(0xD020) + 1);
    //    mhx_press_any_key(0, MHX_A_NOCOLOR);
    spi_clock_high();
    spi_cs_high();

    //    mhx_writef("Hardware SPI write 512 done\n");
    //    mhx_press_any_key(0, MHX_A_NOCOLOR);
  }

  // XXX For some reason the busy flag is broken here.
  // So just wait a little while, but only a little while
  for (b = 0; b < 180; b++)
    continue;

  //  mhx_press_any_key(0, MHX_A_NOCOLOR);

  // Revert lines to input after QSPI operation
  bash_bits |= 0x8f;
  POKE(BITBASH_PORT, bash_bits);
  DEBUG_BITBASH(bash_bits);
  POKE(0xD020, 1);

  reg_sr1 = 0x01;
  while (reg_sr1 & 0x01) {
    if (reg_sr1 & 0x40) {
      if (verboseProgram || pass > 2) {
        mhx_writef(MHX_W_HOME MHX_W_MGREY "\nwrite error occurred @$%08lx\n", start_address);
        //      query_flash_protection(start_address);
        //      read_registers();
        mhx_writef("reg_sr1=$%02x, reg_cr1=$%02x, pass=%d\n" MHX_W_WHITE, reg_sr1, reg_cr1, pass);
        //      press_any_key(0, 0);
      }
      goto top;
    }
    read_registers();
  }
  POKE(0xD020, 0);

#ifdef QSPI_VERBOSE
  if (reg_sr1 & 0x03) {
    mhx_writef("error writing data @$%08llx\n", start_address);
  }
#ifdef QSPI_DEBUG
  else
    mhx_writef("data at $%08llx written.\n",start_address);
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
    //    mhx_writef("reg_sr1=$%02x\n",reg_sr1);
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
