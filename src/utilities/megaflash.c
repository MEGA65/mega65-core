#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspicommon.h"
#include "qspireconfig.h"
#include "mhexes.h"
#include "nohysdc.h"

#ifdef STANDALONE
#include "megaflash_screens_scr.h"
#else
#include "megaflash_screens.h"
#endif

#include "version.h"

unsigned char joy_x = 100;
unsigned char joy_y = 100;

uint8_t reconfig_disabled = 0;
unsigned int base_addr;

// mega65r3 QSPI has the most space currently with 8x8MB
// this is to much for r3 or r2, but we can handle...
#define MAX_SLOTS 8

// core flags/caps
#define CORECAP_USED         0b10000111
#define CORECAP_CART         0b00000111
#define CORECAP_CART_C64     0b00000001
#define CORECAP_CART_C128    0b00000010
#define CORECAP_CART_M65     0b00000100
#define CORECAP_UNDEFINED    0b01111000 // free for further expansion
#define CORECAP_SLOT_DEFAULT 0b10000000

#define SLOT_EMPTY   0x00
#define SLOT_INVALID 0x01
#define SLOT_VALID   0x80

typedef struct {
  char name[17];
  char short_name[6];
  uint8_t bits;
  uint8_t slot;
} corecap_def_type;

#define CORECAP_DEF_MAX 4
#define CORECAP_ALL 0
#define CORECAP_M65 1
#define CORECAP_C64 2
#define CORECAP_C128 3
corecap_def_type corecap_def[CORECAP_DEF_MAX] = {
  {"Default Core",     "[ALL]", CORECAP_SLOT_DEFAULT, 0xff},
  {"MEGA65 Cartridge", "[M65]", CORECAP_CART_M65,     0xff},
  {"C64 Cartridge",    "[C64]", CORECAP_CART_C64,     0xff},
  {"C128 Cartridge",   "[128]", CORECAP_CART_C128,    0xff},
};

char main_menu_bar[] = "  <0>-<7> Launch   <CTRL>+<1>-<7> Edit  ";

#include <cbm_petscii_charmap.h>
#define CART_C64_MAGIC_LENGTH 5
unsigned char cart_c64_magic[5] = "CBM80";
#define CART_C128_MAGIC_LENGTH 3
unsigned char cart_c128_magic[3] = "cbm";
#define CART_M65_MAGIC_LENGTH 3
unsigned char cart_m65_magic[3] = "m65";
#include <cbm_screen_charmap.h>

typedef struct {
  char name[33];
  char version[33];
  unsigned char capabilities;
  unsigned char flags;
  unsigned char valid;
} slot_core_type;

slot_core_type slot_core[MAX_SLOTS];

unsigned char exrom_game = 0xff;
// #if !defined(FIRMWARE_UPGRADE) || !defined(STANDALONE)
unsigned char selected_reflash_slot, selected_file;
// #endif
#ifndef STANDALONE
char cart_id[9];

unsigned char check_cartridge(void)
{
  // copy cartridge magics out of cartridge ROM space
  lcopy(0x4008004UL, (long)cart_id, 6);
  lcopy(0x400C007UL, (long)cart_id + 6, 3);

  // first we always look for a M65 style cart, regardless what EXROM/GAME says
  if (!memcmp(cart_id + 3, cart_m65_magic, CART_M65_MAGIC_LENGTH))
    return CORECAP_CART_M65;

  // there might be C64 cartridges that do some "magic", so we can't depend on
  // EXROM/GAME. If CBM80 magic can be seem, assume C64 cartridge.
  if (!memcmp(cart_id, cart_c64_magic, CART_C64_MAGIC_LENGTH))
    return CORECAP_CART_C64;

  // check for /EXROM and/or /GAME is low, we have a C64 or M65 cart
  if ((exrom_game & 0x60) != 0x60)
    return CORECAP_CART_C64;

  // check for C128/M65 style cart by looking at signature at 8007 or C007
  if (!memcmp(cart_id + 3, cart_c128_magic, CART_C128_MAGIC_LENGTH) || !memcmp(cart_id + 6, cart_c128_magic, CART_C128_MAGIC_LENGTH))
    return CORECAP_CART_C128;

  return CORECAP_SLOT_DEFAULT;
}
#endif

unsigned char scan_bitstream_information(unsigned char search_flags, unsigned char update_slot);

void display_version(void)
{
#ifndef STANDALONE
  unsigned char search_cart, selected;
#endif

/*
  mhx_writef(MHX_W_WHITE MHX_W_CLRHOME MHX_W_YELLOW
             "Test: " MHX_W_BLACK MHX_W_REVON "$%03X" MHX_W_REVOFF MHX_W_BROWN " $%4x" MHX_W_WHITE "\n"
             "%s\n"
             "dec($f1ae)=%07d oct($4711)=%7o\n", 0xa, 0x9f, "abcDEF123", 0xf1ae, 0x4711);
*/

  mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "\n"
         "  Core hash:\n    %02x%02x%02x%02x%s\n"
         "  MEGAFLASH version:\n    %s\n"
         "  Slot 0 Version:\n    %s\n\n"
         "  Hardware information\n"
         "    Model ID:   $%02X\n"
         "    Model name: %s\n"
         "    Slots:      %d (each %d MB)\n",
         PEEK(0xD635), PEEK(0xD634), PEEK(0xD633), PEEK(0xD632), reconfig_disabled ? " (booted via JTAG)" : "",
         utilVersion, slot_core[0].version,
         hw_model_id, hw_model_name, slot_count, SLOT_MB);
#ifdef QSPI_VERBOSE
  mhx_writef("    Slot Size:  %ld (%ld pages)\n", (long)SLOT_SIZE, (long)SLOT_SIZE_PAGES);
#endif

#ifndef STANDALONE
  // if this is the core megaflash, display boot slot selection information
  search_cart = check_cartridge();
  selected = scan_bitstream_information(search_cart, 0);
  if (selected == 0xff)
    selected = 1 + ((PEEK(0xD69D) >> 3) & 1);

  mhx_writef("\n  Cartridge: ");
  switch (search_cart) {
  case CORECAP_CART_C64:
    mhx_writef(corecap_def[CORECAP_C64].short_name);
    break;
  case CORECAP_CART_C128:
    mhx_writef(corecap_def[CORECAP_C128].short_name);
    break;
  case CORECAP_CART_M65:
    mhx_writef(corecap_def[CORECAP_M65].short_name);
    break;
  default:
    mhx_writef("none");
    break;
  }
  mhx_writef("\n  Boot Slot: %d\n", selected);
  selected = 0;
#endif

  // wait for ESC or RUN/STOP
  do {
    mhx_getkeycode();
#ifndef STANDALONE
    // extra boot/cart debug information on F1, so we don't confuse the user
    if (mhx_lastkey.code.key == 0xf1 && !selected) {
      mhx_writef(MHX_W_LGREY "\n   DIP4: %d\n  $D67E: $%02X (now $%02X)\n", 1 + ((PEEK(0xD69D) >> 3) & 1), exrom_game, PEEK(0xD67EU));
      mhx_writef("  $8004: %02X %02X %02X %02X %02X %02X\n", cart_id[0], cart_id[1], cart_id[2], cart_id[3], cart_id[4],
          cart_id[5]);
      mhx_writef("  $C007:          %02X %02X %02X\n" MHX_W_WHITE, cart_id[0], cart_id[1], cart_id[2]);
      selected = 1;
    }
#endif
  } while (mhx_lastkey.code.key != 0x1b && mhx_lastkey.code.key != 0x03);
}

uint8_t first_flash_read = 1;
void do_first_flash_read(unsigned long addr)
{
  // XXX Work around weird flash thing where first read of a sector reads rubbish
  read_data(addr);
  for (x = 0; x < 256; x++) {
    if (data_buffer[0] != 0xee)
      break;
    usleep(50000L);
    read_data(addr);
    read_data(addr);
  }
  first_flash_read = 0;
}

/*
 * uchar scan_bitstream_information(search_flags, slot)
 *
 * gathers core slot information from flash and looks
 * for a slot to boot.
 *
 * if search_flags is not 0, then it is matched against the core flags
 * to determine the first slot that has one of the flags. The slot number
 * is returned. 0xff means not found. Searching for a slot will *not*
 * copy any slot information, to be fast!
 *
 * if slot is non zero, only the slot with the specified slot number & 0xf
 * is updated, otherwise all slots are updated (used after flash). Set high
 * bit to only update one slot.
 *
 */
unsigned char scan_bitstream_information(unsigned char search_flags, unsigned char update_slot)
{
  short slot, j;
  unsigned char found = 0xff, default_slot = 0xff, flagmask = CORECAP_USED;

  if (first_flash_read)
    do_first_flash_read(0);

  for (slot = update_slot & 0x0f; slot < slot_count; slot++) {
    // read first sector from flash slot
    read_data(slot * SLOT_SIZE);

    // check for bitstream magic
    slot_core[slot].valid = SLOT_VALID;
    for (j = 0; j < 16; j++)
      if (data_buffer[j] != bitstream_magic[j]) {
        slot_core[slot].valid = SLOT_INVALID;
        break;
      }

    if (slot_core[slot].valid == SLOT_VALID) {
      slot_core[slot].capabilities = data_buffer[0x7b] & CORECAP_USED;
      // mask out flags from prior slots, slot 0 never has flags enabled!
      slot_core[slot].flags = data_buffer[0x7c] & flagmask;
      // remove flags from flagmask (we only find the first flag of a kind)
      flagmask ^= slot_core[slot].flags;
      if (search_flags && found == 0xff && (slot_core[slot].flags & search_flags))
        found = slot;
      if (default_slot == 0xff && (slot_core[slot].flags & CORECAP_SLOT_DEFAULT))
        default_slot = slot;
    }
    else {
      slot_core[slot].capabilities = slot_core[slot].flags = 0;
      // check if slot is empty (all FF)
      for (j = 0; j < 512 && data_buffer[j] == 0xff; j++)
        ;
      if (j == 512)
        slot_core[slot].valid = SLOT_EMPTY;
    }

    // if we are searching for a slot, we can cut the process short...
    if (search_flags)
      continue;

#include <cbm_screen_charmap.h>
    lfill((long)slot_core[slot].name, ' ', 66);
    // extract names
    if (slot_core[slot].valid == SLOT_VALID) {
      for (j = 0; j < 32; j++) {
        slot_core[slot].name[j] = mhx_ascii2screen(data_buffer[16 + j], ' ');
        slot_core[slot].version[j] = mhx_ascii2screen(data_buffer[48 + j], ' ');
      }
    }
    if (slot == 0) {
      // slot 0 is always displayed as FACTORY CORE
      memcpy(slot_core[slot].name, "MEGA65 FACTORY CORE", 19);
    }
    else if (slot_core[slot].valid == SLOT_EMPTY) {
      // 0xff in the first 512 bytes, this is empty
      memcpy(slot_core[slot].name, "EMPTY SLOT", 10);
    }
    else if (slot_core[slot].valid == SLOT_INVALID) {
      // no bitstream magic at the start of the slot
      memcpy(slot_core[slot].name, "UNKNOWN CONTENT", 15);
    }
    slot_core[slot].name[32] = '\x0';
    slot_core[slot].version[32] = '\x0';

    if (slot_core[slot].flags)
      for (j = 0; j < CORECAP_DEF_MAX; j++)
        if (corecap_def[j].slot == 0xff && slot_core[slot].flags & corecap_def[j].bits)
          corecap_def[j].slot = slot;

    if (update_slot & 0x80)
      break;
  }

  return found != 0xff ? found : default_slot;
}

unsigned char confirm_slot0_flash()
{
  char slot_magic[] = "MEGA65   ";
#include <ascii_charmap.h>
  if (strncmp(slot_core[1].name, slot_magic, 9)) {
    mhx_copyscreen(&slot1_not_m65);
    if (!mhx_check_input("CONFIRM\r", MHX_CI_CHECKCASE|MHX_CI_PRINT, MHX_A_YELLOW))
      return 0;
  }
  mhx_copyscreen(&slot0_warning);
  return mhx_check_input("CONFIRM\r", MHX_CI_CHECKCASE|MHX_CI_PRINT, MHX_A_YELLOW);
}

#include <cbm_screen_charmap.h>
void display_cartridge(short slot)
{
  unsigned char offset = 1;
  // TODO: if we get more than 3 cartridge types, we need to change this!

  // if all three bits are 1, write ALL... is that even possible?
  if ((slot_core[slot].flags & CORECAP_CART) == CORECAP_CART) {
    mhx_write_xy(35, slot * 3 + offset, corecap_def[CORECAP_ALL].short_name, MHX_A_NOCOLOR);
    return;
  }

  if (slot_core[slot].flags & CORECAP_CART_C64) {
    mhx_write_xy(35, slot * 3 + offset++, corecap_def[CORECAP_C64].short_name, MHX_A_NOCOLOR);
  }
  if (slot_core[slot].flags & CORECAP_CART_C128) {
    mhx_write_xy(35, slot * 3 + offset++, corecap_def[CORECAP_C128].short_name, MHX_A_NOCOLOR);
  }
  if (slot_core[slot].flags & CORECAP_CART_M65) {
    mhx_write_xy(35, slot * 3 + offset++, corecap_def[CORECAP_M65].short_name, MHX_A_NOCOLOR);
  }
}

void draw_edit_slot(unsigned char selected_slot)
{
  mhx_clearscreen(0x20, MHX_A_WHITE);
  memset((void *)0x400, 0x40, 40);
  memcpy((void *)(0x400 + 13), " Edit Slot #  ", 14);
  POKE(0x400 + 13 + 12, 0x30 + selected_slot);

  mhx_draw_rect(0, 2, 32, 2, " Current ", MHX_A_NOCOLOR);
  mhx_write_xy(1, 3, slot_core[selected_slot].name, MHX_A_NOCOLOR);
  mhx_write_xy(1, 4, slot_core[selected_slot].version, MHX_A_NOCOLOR);
  mhx_draw_rect(0, 6, 38, 3, " Replace ", MHX_A_NOCOLOR);
  mhx_hl_lines(6, 10, MHX_A_MGREY);
  mhx_write_xy(5, 8, "Press <F3> to load a core file", MHX_A_NOCOLOR);
  mhx_draw_rect(0, 12, 28, 4, " Flags ", MHX_A_NOCOLOR);
  for (i = 0; i < CORECAP_DEF_MAX; i++) {
    if (slot_core[selected_slot].capabilities & corecap_def[i].bits) {
      mhx_write_xy(1, 13 + i, "< > [ ]", MHX_A_NOCOLOR);
      mhx_putch_offset(-6, 0x31 + i, MHX_A_NOCOLOR);
      mhx_putch_offset(-2, (slot_core[selected_slot].flags & corecap_def[i].bits)?'*':' ', MHX_A_NOCOLOR);
    }
    mhx_write_xy(9, 13 + i, corecap_def[i].name, MHX_A_NOCOLOR);
    if (corecap_def[i].slot != 0xff) {
      mhx_write_xy(26, 13 + i, "( )",
        (!(slot_core[selected_slot].capabilities & corecap_def[i].bits) ? MHX_A_NOCOLOR :
          (corecap_def[i].slot < selected_slot ? MHX_A_YELLOW :
            (corecap_def[i].slot == selected_slot ? MHX_A_GREEN : MHX_A_NOCOLOR))));
      mhx_putch_offset(-2, 0x30 + corecap_def[i].slot, MHX_A_NOCOLOR);
    }
  }

  mhx_write_xy(0, 19, "Press <ESC> or <STOP> to abort.", MHX_A_WHITE);
  mhx_write_xy(0, 20, "Press <F10> to flash slot flags.", MHX_A_MGREY);
  mhx_write_xy(0, 24, "Note: the lowest flagged slot wins!", MHX_A_YELLOW);
}

uint8_t edit_slot(unsigned char selected_slot)
{
  // display screen with current slot information
  // plus menu with flags and the option to flash a new core
  // new core must load header, then display information
  // and allow for flag manipulation
  // so this will also to select_bitstream_file, and part of
  // the header check?
  uint8_t cur_flags = slot_core[selected_slot].flags, core_loaded = 0, selbit;
  mhx_keycode_t key;

  draw_edit_slot(selected_slot);
  while (1) {
    if (core_loaded) {
      mhx_write_xy(12, 20, "to flash slot.      ", MHX_A_WHITE);
    }
    else {
      mhx_write_xy(12, 20, "to flash slot flags.", MHX_A_WHITE);
    }
    if (slot_core[selected_slot].flags != cur_flags || core_loaded)
      mhx_hl_lines(20, 20, MHX_A_WHITE);
    else
      mhx_hl_lines(20, 20, MHX_A_MGREY);

    key = mhx_getkeycode();

    if (key.code.key > 0x30 && key.code.key < 0x31 + CORECAP_DEF_MAX) {
      selbit = key.code.key - 0x31;
      if (slot_core[selected_slot].capabilities & corecap_def[selbit].bits) {
        cur_flags ^= corecap_def[selbit].bits;
        if ((slot_core[selected_slot].flags & corecap_def[selbit].bits) == (cur_flags & corecap_def[selbit].bits)) {
          mhx_putch_xy(6, 13 + selbit, (cur_flags & corecap_def[selbit].bits) ? '*' : ' ', MHX_A_WHITE);
        }
        else {
          mhx_putch_xy(6, 13 + selbit, (cur_flags & corecap_def[selbit].bits) ? '+' : '-', MHX_A_YELLOW);
        }
      }
      continue;
    }

    // ESC or STOP exists without changes
    if (key.code.key == 0x03 || key.code.key == 0x1b)
      return 0;
    
    if (core_loaded && key.code.key == 0xfa) {
      reflash_slot(selected_slot, selected_file, NULL);
      return 0;
    }

    // F3 loads a core
    if (key.code.key == 0xf3) {
      selected_file = select_bitstream_file(selected_reflash_slot);
      draw_edit_slot(selected_slot);
      if (selected_file != SELECTED_FILE_INVALID) {
        core_loaded = 1;
        memcpy((void *)(0x400 + 7*40 + 1), disk_display_return, 38);
        mhx_hl_lines(6, 10, MHX_A_YELLOW);
      }
    }
  }

  return 0;
}

void hard_exit(void)
{
  // clear keybuffer
  *(unsigned char *)0xc6 = 0;

  // Switch back to normal speed control before exiting
  POKE(0, 64);
#ifdef STANDALONE
  mhx_screencolor(MHX_A_BLUE, MHX_A_LBLUE);
  mhx_clearscreen(' ', MHX_A_WHITE);
  // call NMI vector
  asm(" jmp ($fffa) ");
#else
  // back to HYPPO
  POKE(0xCF7f, 0x4C);
  asm(" jmp $cf7f ");
#endif
}

#define REDRAW_DONE    0
#define REDRAW_CHANGED 1
#define REDRAW_CLEAR   2

void main(void)
{
  uint8_t selected = 0xff, atticram_bad = 0, search_cart = CORECAP_SLOT_DEFAULT, default_slot = 0xff, last_selected = 0xff;
  uint8_t redraw_menu = REDRAW_CLEAR;

  mega65_io_enable();

  SEI();

  // we want to read this first!
  exrom_game = PEEK(0xD67EU);

  // white text, blue screen, black border, clear screen
  POKE(0xD018, 23);
  MEGAFLASH_SCREENS_INIT;
  mhx_screencolor(MHX_A_BLUE, MHX_A_BLACK);
  mhx_clearscreen(' ', MHX_A_WHITE);

#ifndef STANDALONE
  /*
   * This part is the *Startup Process* of the core,
   * so we don't need this if we are in standalone mode.
   *
   * It determines if the user wants to see the flash menu,
   * otherwise it will try to find out what core to start
   * and fallback to the default 1/2 via DIPSW 4.
   *
   * If it can't find anything, it will return control to
   * Hyppo without loading a different core.
   */

  // We care about whether the IPROG bit is set.
  // If the IPROG bit is set, then we are post-config, and we
  // don't want to automatically change config. Rather, we just
  // exit to allow the Hypervisor to boot normally.  The exception
  // is if the fire button on either joystick is held, or the TAB
  // key is being pressed.  In that case, we show the menu of
  // flash slots, and allow the user to select which core to load.

  // Holding ESC on boot will prevent flash menu starting
  if (PEEK(0xD610) == 0x1b) {
    hard_exit();
  }

  probe_qspi_flash(); // sets slot_count

  // The following section starts a core, but only if certain keys
  // are NOT pressed, depending on the system
  // this is the non-interactive part, where megaflash just
  // starts a core from slot 1 or 2
  // if this failes, got to GUI anyway
#ifdef TAB_FOR_MENU
  // TAB or NO-SCROLL on nexys and semilar
  if ((PEEK(0xD610) != 0x09) && (!(PEEK(0xD611) & 0x20))) {
#else
  // only NO-SCROLL on mega65r2/r3
  if (!(PEEK(0xD611) & 0x20)) {
#endif
    // Select BOOTSTS register
    POKE(0xD6C4, 0x16);
    usleep(10);
    // Allow a little while for it to be fetched.
    // (about 40 cycles should be long enough)
    if (PEEK(0xD6C5) & 0x01) {
      // FPGA has been reconfigured, so assume that we should boot
      // normally, unless magic keys are being pressed.

      // We should actually jump ($CF80) to resume hypervisor booting
      // (see src/hyppo/main.asm launch_flash_menu routine for more info)

      // Switch back to normal speed control before exiting
      hard_exit();
    }
    else { // FPGA has NOT been reconfigured
      /*
       * Determine which core should be started
       */
      search_cart = check_cartridge();

      // determine boot slot by flags (default search is for default slot)
      selected = scan_bitstream_information(search_cart, 0);

      // if we don't have a cart slot, then we use slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
      if (selected == 0xff)
        selected = 1 + ((PEEK(0xD69D) >> 3) & 1);

      if (slot_core[selected].valid == SLOT_VALID) {
        // Valid bitstream -- so start it
        reconfig_fpga(SLOT_SIZE * selected + 4096);
      }
      else if (slot_core[selected].valid == SLOT_EMPTY) {
        // Empty slot -- ignore and resume
        // Switch back to normal speed control before exiting
        hard_exit();
      }
      else {
        mhx_writef(MHX_W_YELLOW "WARNING:" MHX_W_WHITE " Flash slot %d seems to be\n"
               "messed up.\n"
               "To avoid seeing this message every time,"
               "either erase or re-flash the slot.\n\n", selected);
        mhx_press_any_key(MHX_AK_IGNORETAB, MHX_A_WHITE);

        mhx_clearscreen(0x20, MHX_A_WHITE);
      }
    }
  }

  // we need to probe the hardware now, as we are going into the menu
  if (probe_hardware_version())
    hard_exit();

#else /* STANDALONE */
#include <cbm_screen_charmap.h>
  mhx_writef(MHX_W_WHITE MHX_W_CLRHOME "\njtagflash Version\n  %s\n", utilVersion);

  if (probe_hardware_version()) {
    mhx_writef("\nUnknown hardware model id $%02X\n", hw_model_id);
    mhx_press_any_key(MHX_AK_ATTENTION|MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
    hard_exit();
  }
  if (probe_qspi_flash()) {
    // print it a second time, screen has scrolled!
    mhx_writef("\njtagflash Version\n  %s\n", utilVersion);
    mhx_press_any_key(MHX_AK_ATTENTION|MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
    hard_exit();
  }

#endif

  // We are now in interactive mode, do some tests,
  // then start the GUI

  if (PEEK(0xD6C7) == 0xFF) {
    // BOOTSTS not reading properly.  This usually means we have
    // started from a bitstream via JTAG, and the ECAPE2 thingy
    // isn't working. This means we can't successfully reconfigure
    // so we should probably display a warning.
    mhx_writef(MHX_W_YELLOW "WARNING:" MHX_W_WHITE " You appear to have started this"
               "bitstream via JTAG.  This means that you"
               MHX_W_YELLOW "can't" MHX_W_WHITE " use this menu to launch other\n"
               "cores.\n"
               "You will still be able to flash new\n"
               "bitstreams, though.\n\n");
    reconfig_disabled = 1;
    // wait for key see below
  }

  // quick and dirty attic ram check
  dma_poke(0x8000000l, 0x55);
  if (dma_peek(0x8000000l) != 0x55)
    atticram_bad = 1;
  else {
    dma_poke(0x8000000l, 0xaa);
    if (dma_peek(0x8000000l) != 0xaa)
      atticram_bad = 1;
    else {
      dma_poke(0x8000000l, 0xff);
      if (dma_peek(0x8000000l) != 0xff)
        atticram_bad = 1;
      else {
        dma_poke(0x8000000l, 0x00);
        if (dma_peek(0x8000000l) != 0x00)
          atticram_bad = 1;
      }
    }
  }
  if (atticram_bad)
    mhx_writef(MHX_W_LRED "WARNING:" MHX_W_WHITE " Your system does not support\n"
           "attic ram. Because the flasher in this\n"
           "core does not support flashing without\n"
           "attic ram, flashing has been " MHX_W_LRED "disabled" MHX_W_WHITE ".\n\n");
/* TODO:
  if (reconfig_disabled) {
    mhx_writef(MHX_W_WHITE MHX_W_CLRHOME MHX_W_YELLOW "ERROR:" MHX_W_WHITE " Remember that warning about\n"
               "having started from JTAG?\n"
               "You " MHX_W_YELLOW "can't" MHX_W_WHITE " start a core from flash after\n"
               "having started the system via JTAG.\n");
    mhx_press_any_key(0, MHX_A_NOCOLOR);
    mhx_clearscreen(' ', MHX_A_WHITE);
    mhx_set_xy(0, 0);
    return;
  }
*/

  // if we gave some warning, wait for a keypress before continuing
  if (reconfig_disabled || atticram_bad)
    mhx_press_any_key(MHX_AK_IGNORETAB, MHX_A_WHITE);

  // Scan for existing bitstreams and locate first default slot
  scan_bitstream_information(0, 0);

#if !defined(FIRMWARE_UPGRADE) || !defined(STANDALONE)
  // prepare menu
  for (default_slot = 1; default_slot < MAX_SLOTS; default_slot++)
    if (slot_core[default_slot].flags & CORECAP_SLOT_DEFAULT)
      break;

  // if we don't have a default slot, then we use slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
  if (default_slot == MAX_SLOTS)
    default_slot = 1 + ((PEEK(0xD69D) >> 3) & 1);

  // set max slot in menu bar
  main_menu_bar[7] = main_menu_bar[31] = 0x30 + MAX_SLOTS - 1;

#include <cbm_screen_charmap.h>
  // clear screen
  selected = 0;
  while (1) {
    // draw menu (TODO: no need to redraw constantly!)
    if (redraw_menu) {
      if (redraw_menu == REDRAW_CLEAR) {
        mhx_clearscreen(0x20, MHX_A_WHITE);
        last_selected = MAX_SLOTS;
      }
      for (i = 0; i < slot_count; i++) {
        // Display slot information
        base_addr = 0x0400 + i*(3*40);
        memcpy((void *)(base_addr + 46), slot_core[i].name, 32);
        POKE(base_addr + 41, ((i == default_slot) ? '>' : '('));
        POKE(base_addr + 42, 0x30 + i);
        POKE(base_addr + 43, ((i == default_slot) ? '<' : ')'));
        if (i > 0 && slot_core[i].valid == SLOT_VALID) {
          memcpy((void *)(base_addr + 86), slot_core[i].version, 32);
          display_cartridge(i);
        }
      }
      // Draw footer line with instructions
      memcpy((void *)(0x400 + 24*40), main_menu_bar, 40);
      mhx_hl_lines(24, 24, MHX_A_INVERT|MHX_A_WHITE);
      redraw_menu = REDRAW_DONE;
    }

    // highlight slot
    if (last_selected < MAX_SLOTS)
      mhx_hl_lines(last_selected*3, last_selected*3 + 2, MHX_A_REVERT|MHX_A_WHITE);
    mhx_hl_lines(selected*3, selected*3 + 2, MHX_A_INVERT|(slot_core[selected].valid == SLOT_VALID ? MHX_A_WHITE : (slot_core[selected].valid == SLOT_INVALID ? MHX_A_RED : MHX_A_YELLOW)));
    last_selected = selected;

    mhx_getkeycode();

    // check for number key pressed
    if (mhx_lastkey.code.key >= 0x30 && mhx_lastkey.code.key < 0x30 + slot_count) {
      if (mhx_lastkey.code.key == 0x30) {
        reconfig_fpga(0 + 4096);
      }
      else if (slot_core[mhx_lastkey.code.key - 0x30].valid != 0) // only boot slot if not empty
        reconfig_fpga((mhx_lastkey.code.key - 0x30) * SLOT_SIZE + 4096);
      else
        mhx_flashscreen(MHX_A_RED, 150);
    }

    selected_reflash_slot = 0xff;

    switch (mhx_lastkey.code.key) {
    case 0x03: // RUN-STOP
    case 0x1b: // ESC
      // Simply exit flash menu without doing anything.

      // Switch back to normal speed control before exiting
      hard_exit();
      return;

    case 0x1d: // CRSR-RIGHT
    case 0x11: // CRSR-DOWN
      selected++;
      if (selected >= slot_count)
        selected = 0;
      break;
    case 0x9d: // CRSR-LEFT
    case 0x91: // CRSR-UP
      if (selected == 0)
        selected = slot_count - 1;
      else
        selected--;
      break;
    case 0x0d: // RET
      // Launch selected slot
      if (slot_core[selected].valid != SLOT_EMPTY)
        reconfig_fpga(selected * SLOT_SIZE + 4096);
      else
        mhx_flashscreen(MHX_A_RED, 150);
      break;
#ifdef QSPI_FLASH_INSPECT
    case 0x06: // CTRL-F
      // Flash memory monitor
      mhx_clearscreen(0x20, MHX_A_WHITE);
      flash_inspector();
      mhx_clearscreen(0x20, MHX_A_WHITE);
      break;
#endif
// slot 0 flashing is only done with PRG and DIP 3!
#if QSPI_FLASH_SLOT0
    case 0x7e: // TILDE (MEGA-LT)
      // ask for confirmation
      if (confirm_slot0_flash()) {
        selected_reflash_slot = 0;
      }
      redraw_menu = REDRAW_CLEAR;
      break;
#endif
    case 0x09: // TAB
      // Edit selected slot
      if (selected > 0)
        selected_reflash_slot = selected;
      break;
    case 144: // CTRL-1
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 1;
      break;
    case 5: // CTRL-2
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 2;
      break;
    case 28: // CTRL-3
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 3;
      break;
    case 159: // CTRL-4
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 4;
      break;
    case 156: // CTRL-5
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 5;
      break;
    case 30: // CTRL-6
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 6;
      break;
    case 31: // CTRL-7 && HELP
      if (mhx_lastkey.code.mod & MHX_KEYMOD_CTRL)
        selected_reflash_slot = 7;
      else {
        display_version();
        redraw_menu = REDRAW_CLEAR;
      }
      break;
    }

    // extra security against slot 0 flashing
#ifdef QSPI_FLASH_SLOT0
    if (selected_reflash_slot < slot_count) {
#else
    if (selected_reflash_slot > 0 && selected_reflash_slot < slot_count) {
#endif
      if (atticram_bad) {
        mhx_flashscreen(MHX_A_RED, 150);
        continue;
      }
      if (selected_reflash_slot > 0)
        edit_slot(selected_reflash_slot);
#if 0
#ifdef FIRMWARE_UPGRADE
      selected_file = SELECTED_FILE_INVALID;
      if (selected_reflash_slot == 0) {
#include <ascii_charmap.h>
        strncpy(disk_name_return, "UPGRADE0.COR", 32);
#include <cbm_screen_charmap.h>
        memcpy(disk_display_return, "UPGRADE0.COR", 12);
        memset(disk_display_return + 12, 0x20, 28);
        selected_file = SELECTED_FILE_VALID;
      }
      else
#endif
        selected_file = select_bitstream_file(selected_reflash_slot);
      if (selected_file != SELECTED_FILE_INVALID) {
        reflash_slot(selected_reflash_slot, selected_file, slot_core[0].version);
        scan_bitstream_information(0, selected_reflash_slot | 0x80);
      }
#endif
      redraw_menu = REDRAW_CLEAR;
    }

    // restore black border
    POKE(0xD020, 0);
  }
#else /* FIRMWARE_UPGRADE && STANDALONE */
  if (!confirm_slot0_flash()) {
    mhx_writef("\n\nABORTED!\n");
    mhx_press_any_key(MHX_AK_ATTENTION, MHX_A_RED);
    hard_exit();
  }

#include <ascii_charmap.h>
// misappropiate variable
#define err selected
  // only use internal slot
  if ((err = nhsd_init(0, buffer))) {
    mhx_writef(MHX_W_RED "ERROR: failed to init internal SD card (%x)" MHX_W_WHITE "\n", err);
    hard_exit();
  }
  if ((err = nhsd_findfile("UPGRADE0.COR"))) {
    mhx_writef(MHX_W_RED "ERROR: failed to find UPGRADE0.COR on\ninternal SD card (%d)" MHX_W_WHITE "\n", err);
    hard_exit();
  }
#include <cbm_screen_charmap.h>
  memcpy(disk_display_return, "UPGRADE0.COR", 12);
  memset(disk_display_return + 12, 0x20, 28);
  disk_display_return[39] = MHX_C_EOS;
  reflash_slot(0, SELECTED_FILE_VALID, slot_core[0].version);
#endif

  hard_exit();
}
