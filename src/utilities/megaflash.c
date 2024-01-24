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
#include "mf_progress.h"
#include "mf_selectcore.h"
#include "mf_hlflash.h"

#ifdef STANDALONE
#include "mf_screens_solo.h"

// OPENROM Palette for STANDALONE MODE
// make sure to also load openrom font for perfect testing!
struct rgb {
  uint8_t r, g, b;
};

struct rgb openrom_palette[] = {
  {0, 0, 0},
  {0xff, 0xff, 0xff},
  {0xba, 0x13, 0x62},
  {0x66, 0xad, 0xff},
  {0xbb, 0xf3, 0x8b},
  {0x55, 0xec, 0x85},
  {0xd1, 0xe0, 0x79},
  {0xae, 0x5f, 0xc7},
  {0x9b, 0x47, 0x81},
  {0x87, 0x37, 0x00},
  {0xdd, 0x39, 0x78},
  {0xb5, 0xb5, 0xb5},
  {0xb8, 0xb8, 0xb8},
  {0x0b, 0x4f, 0xca},
  {0xaa, 0xd9, 0xfe},
  {0x8b, 0x8b, 0x8b},
};
#else
#include "mf_screens.h"
#endif

#include "version.h"

unsigned char joy_x = 100;
unsigned char joy_y = 100;

uint8_t booted_via_jtag = 0;

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
} corecap_def_t;

#define CORECAP_DEF_MAX 4
#define CORECAP_ALL 0
#define CORECAP_M65 1
#define CORECAP_C64 2
#define CORECAP_C128 3
corecap_def_t corecap_def[CORECAP_DEF_MAX] = {
  {"Default Core",     "[ALL]", CORECAP_SLOT_DEFAULT, 0xff},
  {"MEGA65 Cartridge", "[M65]", CORECAP_CART_M65,     0xff},
  {"C64 Cartridge",    "[C64]", CORECAP_CART_C64,     0xff},
  {"C128 Cartridge",   "[128]", CORECAP_CART_C128,    0xff},
};

#include <cbm_petscii_charmap.h>
#define CART_C64_MAGIC_LENGTH 5
char cart_c64_magic[5] = "CBM80";
#define CART_C128_MAGIC_LENGTH 3
char cart_c128_magic[3] = "cbm";
#define CART_M65_MAGIC_LENGTH 3
char cart_m65_magic[3] = "m65";
#include <cbm_screen_charmap.h>

typedef struct {
  char name[33];
  char version[33];
  uint8_t capabilities;
  uint8_t flags;
  uint8_t valid;
  uint32_t length;
} slot_core_t;

slot_core_t slot_core[MAX_SLOTS];

uint8_t exrom_game = 0xff;
// #if !defined(FIRMWARE_UPGRADE) || !defined(STANDALONE)
uint8_t selected_reflash_slot, selected_file;
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

unsigned char scan_core_information(unsigned char search_flags);

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
         PEEK(0xD635), PEEK(0xD634), PEEK(0xD633), PEEK(0xD632), booted_via_jtag ? " (booted via JTAG)" : "",
         utilVersion,
         slot_core[0].valid == SLOT_EMPTY ? "empty factory slot!" : slot_core[0].version,
         hw_model_id, hw_model_name, slot_count, SLOT_MB);
#ifdef QSPI_VERBOSE
  mhx_writef("    Slot Size:  %ld (%ld pages)\n", (long)SLOT_SIZE, (long)SLOT_SIZE_PAGES);
#endif

#ifndef STANDALONE
  // if this is the core megaflash, display boot slot selection information
  search_cart = check_cartridge();
  selected = scan_core_information(search_cart);
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
    mhx_getkeycode(0);
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
  // Work around weird flash thing where first read of a sector reads rubbish
  // TODO: is this really required?
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
 * uchar scan_core_information(search_flags)
 *
 * gathers core slot information from flash and looks
 * for a slot to boot.
 *
 * if search_flags is not 0, then it is matched against the core flags
 * to determine the first slot that has one of the flags. The slot number
 * is returned. 0xff means not found. Searching for a slot will *not*
 * copy any slot information, to be fast!
 *
 */
unsigned char scan_core_information(unsigned char search_flags)
{
  short slot, j;
  unsigned char found = 0xff, default_slot = 0xff, flagmask = CORECAP_USED;

  if (first_flash_read)
    do_first_flash_read(0);

  for (j = 0; j < CORECAP_DEF_MAX; j++)
    corecap_def[j].slot = 0xff;

  for (slot = 0; slot < slot_count; slot++) {
    // read first sector from flash slot
    read_data(slot * SLOT_SIZE);

    // check for bitstream magic
    slot_core[slot].valid = SLOT_VALID;
    for (j = 0; j < 16; j++)
      if (data_buffer[MFSC_COREHDR_MAGIC + j] != mfsc_bitstream_magic[j]) {
        slot_core[slot].valid = SLOT_INVALID;
        break;
      }

    if (slot_core[slot].valid == SLOT_VALID) {
      slot_core[slot].capabilities = data_buffer[MFSC_COREHDR_BOOTCAPS] & CORECAP_USED;
      // mask out flags from prior slots, slot 0 never has flags enabled!
      slot_core[slot].flags = data_buffer[MFSC_COREHDR_BOOTFLAGS] & flagmask;
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
        slot_core[slot].name[j] = mhx_ascii2screen(data_buffer[MFSC_COREHDR_NAME + j], ' ');
        slot_core[slot].version[j] = mhx_ascii2screen(data_buffer[MFSC_COREHDR_VERSION + j], ' ');
      }
      slot_core[slot].length = *(uint32_t *)(data_buffer + MFSC_COREHDR_LENGTH);
    }
    if (slot == 0) {
      // slot 0 is always displayed as FACTORY CORE
      memcpy(slot_core[slot].name, "MEGA65 FACTORY CORE", 19);
    }
    else if (slot_core[slot].valid == SLOT_EMPTY) {
      // 0xff in the first 512 bytes, this is empty
      memcpy(slot_core[slot].name, "EMPTY SLOT", 10);
      slot_core[slot].length = 0;
    }
    else if (slot_core[slot].valid == SLOT_INVALID) {
      // no bitstream magic at the start of the slot
      memcpy(slot_core[slot].name, "UNKNOWN CONTENT", 15);
      slot_core[slot].length = 0;
    }
    slot_core[slot].name[32] = '\x0';
    slot_core[slot].version[32] = '\x0';

    if (slot_core[slot].flags)
      for (j = 0; j < CORECAP_DEF_MAX; j++)
        if (corecap_def[j].slot == 0xff && slot_core[slot].flags & corecap_def[j].bits)
          corecap_def[j].slot = slot;
  }

  // if we don't have a slot, then we use slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
  if (default_slot == 0xff) {
    default_slot = 1 + ((PEEK(0xD69D) >> 3) & 1);
    corecap_def[0].slot = default_slot;
  }

  return found != 0xff ? found : default_slot;
}

unsigned char confirm_slot0_flash()
{
  char slot_magic[] = "MEGA65   ";
#include <ascii_charmap.h>
  if (strncmp(slot_core[1].name, slot_magic, 9)) {
    mhx_copyscreen(&mf_screens_slot1_not_m65);
    if (!mhx_check_input("CONFIRM\r", MHX_CI_CHECKCASE|MHX_CI_PRINT, MHX_A_YELLOW))
      return 0;
  }
  mhx_copyscreen(&mf_screens_slot0_warning);
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

uint8_t mfde_replace_attr[3] = { MHX_A_MGREY, MHX_A_YELLOW, MHX_A_LRED };

void draw_edit_slot(uint8_t selected_slot, uint8_t loaded)
{
  mhx_clearscreen(0x20, MHX_A_WHITE | MHX_A_FLIP);
  mhx_set_xy(14, 0);
  mhx_writef("Edit Slot #%d", selected_slot);
  mhx_hl_lines(0, 0, MHX_A_INVERT | MHX_A_LGREY);

  mhx_draw_rect(0, 2, 38, 2, " Current ", MHX_A_NOCOLOR, 0);
  mhx_set_xy(1,3);
  mhx_writef(MHX_W_LGREY "Name: " MHX_W_WHITE "%s", slot_core[selected_slot].name);
  mhx_set_xy(1,4);
  mhx_writef(MHX_W_LGREY "Ver.: " MHX_W_WHITE "%s", slot_core[selected_slot].version);
  mhx_draw_rect(0, 6, 38, 3, " Replace ", mfde_replace_attr[selected_file], 1);
  if (selected_file == MFSC_FILE_ERASE) {
    mhx_write_xy(15, 8, "Erase slot", MHX_A_LRED);
  }
  else if (selected_file == MFSC_FILE_VALID) {
    mhx_write_xy(1, 7, mfsc_corefile_displayname, MHX_A_WHITE);
    mhx_set_xy(1, 8);
    mhx_writef(MHX_W_LGREY "Name: " MHX_W_WHITE "%s", mfsc_corehdr_name);
    mhx_set_xy(1, 9);
    mhx_writef(MHX_W_LGREY "Ver.: " MHX_W_WHITE "%s", mfsc_corehdr_version);
  }
  if (selected_slot > 0) {
    mhx_draw_rect(0, 11, 28, 4, " Flags ", MHX_A_NOCOLOR, 0);
    for (i = 0; i < CORECAP_DEF_MAX; i++) {
      if (mfsc_corehdr_bootcaps & corecap_def[i].bits) {
        mhx_write_xy(1, 12 + i, "< > [ ]", MHX_A_NOCOLOR);
        mhx_putch_offset(-6, 0x31 + i, MHX_A_NOCOLOR);

        if (loaded || (slot_core[selected_slot].flags & corecap_def[i].bits) == (mfsc_corehdr_bootflags & corecap_def[i].bits)) {
          mhx_putch_offset(-2, (mfsc_corehdr_bootflags & corecap_def[i].bits) ? '*' : ' ', MHX_A_WHITE);
        }
        else {
          mhx_putch_offset(-2, (mfsc_corehdr_bootflags & corecap_def[i].bits) ? '+' : '-', MHX_A_YELLOW);
        }
      }
      mhx_write_xy(9, 12 + i, corecap_def[i].name, MHX_A_NOCOLOR);
      if (mfsc_corehdr_length && corecap_def[i].slot != 0xff) {
        mhx_write_xy(26, 12 + i, "( )",
          (!(mfsc_corehdr_bootcaps & corecap_def[i].bits) ? MHX_A_NOCOLOR :
            (corecap_def[i].slot < selected_slot ? MHX_A_YELLOW :
              (corecap_def[i].slot == selected_slot ? MHX_A_GREEN : MHX_A_NOCOLOR))));
        mhx_putch_offset(-2, 0x30 + corecap_def[i].slot, MHX_A_NOCOLOR);
      }
    }
  }
  if (!mfsc_corehdr_length) {
    mhx_hl_lines(11, 16, MHX_A_MGREY);
  }

  mfp_init_progress(8, 17, '-', " Slot Contents ", MHX_A_WHITE);
  mfp_set_area(0, slot_core[selected_slot].length >> 16, '*', MHX_A_WHITE);

  // copy footer from upper memory
  //lcopy(mf_screens_menu.screen_start + 40*10 + ((selected_file != MFSC_FILE_INVALID || slot_core[selected_slot].flags != mfsc_corehdr_bootflags) ? 80 : 0), mhx_base_scr + 23*40, 80);
  // no flags only flashing yet...
  lcopy(mf_screens_menu.screen_start + 40*10 + ((selected_file != MFSC_FILE_INVALID) ? 80 : 0), mhx_base_scr + 23*40, 80);
  // color and invert lines
  mhx_hl_lines(23, 24, MHX_A_INVERT | MHX_A_LGREY);
}

uint8_t edit_slot(uint8_t selected_slot)
{
  // display screen with current slot information
  // plus menu with flags and the option to flash a new core
  // new core must load header, then display information
  // and allow for flag manipulation
  // so this will also to mfsc_selectcore, and part of
  // the header check?
  uint8_t selbit, loaded = 0;

  // setup mfsc_selectcore flags with slot flags, so that
  // they can be replace by caps and flags of a core file selected
  mfsc_corehdr_bootflags = slot_core[selected_slot].flags;
  mfsc_corehdr_bootcaps = slot_core[selected_slot].capabilities;
  mfsc_corehdr_length = slot_core[selected_slot].length;

  selected_file = MFSC_FILE_INVALID;
  draw_edit_slot(selected_slot, loaded);
  while (1) {
    // get a key
    mhx_getkeycode(MHX_GK_WAIT);

    // ESC or STOP exist without changes
    if (mhx_lastkey.code.key == 0x03 || mhx_lastkey.code.key == 0x1b)
      return 0;

    // check if a number is pressed which toggles a flag
    if (selected_slot > 0 && mhx_lastkey.code.key > 0x30 && mhx_lastkey.code.key < 0x31 + CORECAP_DEF_MAX) {
      selbit = mhx_lastkey.code.key - 0x31;
      if (mfsc_corehdr_bootcaps & corecap_def[selbit].bits)
        mfsc_corehdr_bootflags ^= corecap_def[selbit].bits;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }

    // F3 loads a core
    if (mhx_lastkey.code.key == 0xf3) {
      selected_file = mfsc_selectcore(selected_reflash_slot);
      if (selected_file == MFSC_FILE_VALID)
        loaded = 1;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }
    
    if (selected_slot > 0 && mhx_lastkey.code.key == 0xf4) {
      selected_file = MFSC_FILE_ERASE;
      loaded = 0;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }

    if (selected_file != MFSC_FILE_INVALID && mhx_lastkey.code.key == 0xf8) {
      if (selected_file == MFSC_FILE_ERASE || mfhf_load_core()) {
        // patch flags into loaded core, but no flags for slot 0
        mfhf_flash_core(selected_file, selected_slot);
        scan_core_information(0);
      }
      return 0;
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
  uint8_t selected = 0xff, search_cart = CORECAP_SLOT_DEFAULT, last_selected = 0xff;
  uint8_t redraw_menu = REDRAW_CLEAR;
#ifdef LAZY_ATTICRAM_CHECK
  uint8_t atticram_bad = 0;
#endif

  mega65_io_enable();

  SEI();

  // we want to read this first!
  exrom_game = PEEK(0xD67EU);

  // white text, blue screen, black border, clear screen
  POKE(0xD018, 23);
  MF_SCREENS_INIT;
  mhx_screencolor(MHX_A_BLUE, MHX_A_BLACK);
  mhx_clearscreen(' ', MHX_A_WHITE);

#ifdef STANDALONE
  // setup OPENROM palette in standalone mode
  for (i = 0; i < 16; i++) {
    POKE(0xd100 + i, openrom_palette[i].r);
    POKE(0xd200 + i, openrom_palette[i].g);
    POKE(0xd300 + i, openrom_palette[i].b);
  }
#endif

  // we need to probe the hardware now, as we are going into the menu
  if (probe_hardware_version())
    hard_exit();

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
      selected = scan_core_information(search_cart);

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
    mhx_writef(MHX_W_YELLOW "WARNING:" MHX_W_WHITE " You have started this bitstream"
               "via JTAG, launching other cores has been" MHX_W_LRED "disabled" MHX_W_WHITE "!\n\n");
    booted_via_jtag = 1;
    // wait for key see below
#ifndef LAZY_ATTICRAM_CHECK
    mhx_press_any_key(MHX_AK_IGNORETAB, MHX_A_WHITE);
#endif
  }

#ifdef LAZY_ATTICRAM_CHECK
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
    mhx_writef(MHX_W_YELLOW "WARNING:" MHX_W_WHITE " Your system does not support\n"
           "attic ram, flashing has been " MHX_W_LRED "disabled" MHX_W_WHITE "!\n\n");

  // if we gave some warning, wait for a keypress before continuing
  if (booted_via_jtag || atticram_bad)
    mhx_press_any_key(MHX_AK_IGNORETAB, MHX_A_WHITE);
#endif

  // Scan for existing bitstreams and locate first default slot
  scan_core_information(0);

#if !defined(FIRMWARE_UPGRADE) || !defined(STANDALONE)

#include <cbm_screen_charmap.h>

  selected = 0;
  while (1) {
    // draw menu (TODO: no need to redraw constantly!)
    if (redraw_menu) {
      if (redraw_menu == REDRAW_CLEAR) {
        mhx_clearscreen(0x20, MHX_A_WHITE);
        mhx_setattr(MHX_A_WHITE);
        last_selected = MAX_SLOTS;
      }
      for (i = 0; i < slot_count; i++) {
        // Display slot information
        mhx_set_xy(1, i*3 + 1);
        mhx_writef("%c%d%c  %s", ((i == corecap_def[0].slot) ? '>' : '('), i, ((i == corecap_def[0].slot) ? '<' : ')'), slot_core[i].name);
        if (i > 0 && slot_core[i].valid == SLOT_VALID) {
          mhx_write_xy(6, i*3 + 2, slot_core[i].version, MHX_A_NOCOLOR);
          display_cartridge(i);
        }
      }
      // Draw footer line with instructions
      lcopy(mf_screens_menu.screen_start, mhx_base_scr + 24*40, 40);
      // set slot number
      mhx_putch_xy(7, 24, 0x30 + MAX_SLOTS - 1, MHX_A_NOCOLOR);
      mhx_putch_xy(31, 24, 0x30 + MAX_SLOTS - 1, MHX_A_NOCOLOR);
      // color and invert
      mhx_hl_lines(24, 24, MHX_A_INVERT|MHX_A_WHITE);
      redraw_menu = REDRAW_DONE;
    }

    // highlight slot
    if (last_selected < MAX_SLOTS)
      mhx_hl_lines(last_selected*3, last_selected*3 + 2, MHX_A_REVERT|MHX_A_WHITE);
    mhx_hl_lines(selected*3, selected*3 + 2, MHX_A_INVERT|(slot_core[selected].valid == SLOT_VALID ? MHX_A_WHITE : (slot_core[selected].valid == SLOT_INVALID ? MHX_A_RED : MHX_A_YELLOW)));
    last_selected = selected;

    mhx_getkeycode(0);

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
      if (selected > 0) // the entry above is the only way to flash slot 0
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
#ifdef LAZY_ATTICRAM_CHECK

      if (atticram_bad) {
        mhx_flashscreen(MHX_A_RED, 150);
        continue;
      }
#endif
      edit_slot(selected_reflash_slot);
#if 0
#ifdef FIRMWARE_UPGRADE
      selected_file = MFSC_FILE_INVALID;
      if (selected_reflash_slot == 0) {
#include <ascii_charmap.h>
        strncpy(disk_name_return, "UPGRADE0.COR", 32);
#include <cbm_screen_charmap.h>
        memcpy(mfsc_corefile_displayname, "UPGRADE0.COR", 12);
        memset(mfsc_corefile_displayname + 12, 0x20, 28);
        selected_file = MFSC_FILE_VALID;
      }
      else
#endif
        selected_file = mfsc_selectcore(selected_reflash_slot);
      if (selected_file != MFSC_FILE_INVALID) {
        reflash_slot(selected_reflash_slot, selected_file, slot_core[0].version);
        scan_core_information(0);
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
  memcpy(mfsc_corefile_displayname, "UPGRADE0.COR", 12);
  memset(mfsc_corefile_displayname + 12, 0x20, 28);
  mfsc_corefile_displayname[39] = MHX_C_EOS;
  reflash_slot(0, MFSC_FILE_VALID, slot_core[0].version);
#endif

  hard_exit();
}
