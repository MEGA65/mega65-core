#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "mf_buffers.h"
#include "mhexes.h"
#include "nohysdc.h"
#include "mf_progress.h"
#include "mf_selectcore.h"
#include "mf_hlflash.h"
#include "qspiflash.h"
#include "mf_utility.h"
//#include "qspiflash.h"
#include "../version.h"

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

unsigned char joy_x = 100;
unsigned char joy_y = 100;

uint8_t booted_via_jtag = 0;
uint8_t old_flash_chip = 0;

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

#define SLOT_EMPTY    0x00
#define SLOT_INVALID  0x01
#define SLOT_QSPIFAIL 0x02
#define SLOT_VALID    0x80

typedef struct {
  char name[17];
  char short_name[6];
  char help[5];
  uint8_t bits;
  uint8_t slot;
} corecap_def_t;

#define CORECAP_DEF_MAX 4
#define CORECAP_ALL 0
#define CORECAP_M65 1
#define CORECAP_C64 2
#define CORECAP_C128 3
corecap_def_t corecap_def[CORECAP_DEF_MAX] = {
  {"Default Core",     "[ALL]", "none", CORECAP_SLOT_DEFAULT, 0xff},
  {"MEGA65 Cartridge", "[M65]", "M65",  CORECAP_CART_M65,     0xff},
  {"C64 Cartridge",    "[C64]", "C64",  CORECAP_CART_C64,     0xff},
  {"C128 Cartridge",   "[128]", "C128", CORECAP_CART_C128,    0xff},
};

#include <cbm_petscii_charmap.h>
#define CART_C64_MAGIC_LENGTH 5
char cart_c64_magic[5] = "CBM80";
#define CART_C128_MAGIC_LENGTH 3
char cart_c128_magic[3] = "cbm";
#define CART_M65_MAGIC_LENGTH 3
char cart_m65_magic[3] = "m65";

#ifndef STANDALONE
#include <ascii_charmap.h>
static const char BRINGUP_CORE[13] = "BRINGUP.COR";
#endif

#include <cbm_screen_charmap.h>

typedef struct {
  char name[33];
  char version[33];
  uint8_t capabilities;
  uint8_t flags;
  uint8_t real_flags;
  uint8_t valid;
  uint32_t length;
} slot_core_t;

slot_core_t slot_core[MAX_SLOTS] = {
  // this is needed for BRINGUP.COR, as draw_editslot will display it
  {"FACTORY CORE AUTO UPDATE", "", 0x00, 0x00, SLOT_VALID, 0x800000UL},
};

uint8_t exrom_game = 0xff;
// #if !defined(FIRMWARE_UPGRADE) || !defined(STANDALONE)
uint8_t selected_reflash_slot, selected_file;
// #endif
#ifdef LAZY_ATTICRAM_CHECK
uint8_t atticram_bad = 0;
#endif

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
  uint8_t search_cart = 0, selected = -1, cc = 0;

#ifndef STANDALONE
  // if this is the core megaflash, display boot slot selection information
  search_cart = check_cartridge();
  selected = scan_core_information(search_cart);
  if (selected == 0xff)
    selected = 1 + ((PEEK(0xD69D) >> 3) & 1);
  for (; cc < CORECAP_DEF_MAX; cc++)
    if (corecap_def[cc].bits == search_cart)
      break;
  if (cc == CORECAP_DEF_MAX)
    cc = 0;
#endif

  mhx_writef(mhx_screen_get_format(&mf_screens_format_help, 0, MF_SCREEN_FMTHELP_CRTDBG, (char *)&buffer),
         PEEK(0xD635), PEEK(0xD634), PEEK(0xD633), PEEK(0xD632), booted_via_jtag ? " (booted via JTAG)" : "",
         utilVersion,
         slot_core[0].valid == SLOT_EMPTY ? "empty factory slot!" : slot_core[0].version,
         hw_model_id, hw_model_name, slot_count, mfu_slot_mb, (long)mfu_slot_size, mfu_slot_pagemask,
         corecap_def[cc].help, selected);

#ifndef STANDALONE
  selected = 0;
#endif
  // wait for ESC or RUN/STOP
  do {
    mhx_getkeycode(0);
#ifndef STANDALONE
    // extra boot/cart debug information on F1, so we don't confuse the user
    if (mhx_lastkey.code.key == 0xf1 && !selected) {
      mhx_writef(mhx_screen_get_format(&mf_screens_format_help, MF_SCREEN_FMTHELP_CRTDBG, mf_screens_format_help.screen_size - MF_SCREEN_FMTHELP_CRTDBG, (char *)&buffer),
                 1 + ((PEEK(0xD69D) >> 3) & 1), search_cart, exrom_game, PEEK(0xD67EU),
                 cart_id[0], cart_id[1], cart_id[2], cart_id[3], cart_id[4], cart_id[5], cart_id[6], cart_id[7], cart_id[8]);
      selected = 1;
    }
#endif
  } while (mhx_lastkey.code.key != 0x1b && mhx_lastkey.code.key != 0x03);

#ifndef STANDALONE
  // rescan real core information for menu
  scan_core_information(0);
#endif
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

  for (j = 0; j < CORECAP_DEF_MAX; j++)
    corecap_def[j].slot = 0xff;

  for (slot = 0; slot < slot_count; slot++) {
    // read first sector from flash slot
    if (mfhf_read_core_header_from_flash(slot)) {
      slot_core[slot].valid = SLOT_QSPIFAIL;
    }
    else {
      // check for bitstream magic
      slot_core[slot].valid = SLOT_VALID;
      for (j = 0; j < 16; j++)
        if (data_buffer[MFSC_COREHDR_MAGIC + j] != mfsc_bitstream_magic[j]) {
          slot_core[slot].valid = SLOT_INVALID;
          break;
        }

      if (slot_core[slot].valid == SLOT_VALID) {
        slot_core[slot].capabilities = data_buffer[MFSC_COREHDR_BOOTCAPS] & CORECAP_USED;
        // needed for flag editing
        slot_core[slot].real_flags = data_buffer[MFSC_COREHDR_BOOTFLAGS];
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
      if (slot == 0) {
        // slot 0 is always displayed as FACTORY CORE
        memcpy(slot_core[slot].name, "MEGA65 FACTORY CORE", 19);
        // copy erase list from header or set r0.95 default
        memset(mfhf_slot0_erase_list, 0xff, 16);
        if (data_buffer[MFSC_COREHDR_INSTFLAGS] & MFSC_COREINST_ERASELIST)
          memcpy(mfhf_slot0_erase_list, data_buffer + MFSC_COREHDR_ERASELIST, 16);
        else if (!memcmp(slot_core[slot].version, R095_VER_STUB, R095_VER_STUB_SIZE)) {
          mfhf_slot0_erase_list[0] = R095_ERASE_LIST[0];
          mfhf_slot0_erase_list[1] = R095_ERASE_LIST[1];
        }
      }
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
    else if (slot_core[slot].valid == SLOT_QSPIFAIL) {
      // no bitstream magic at the start of the slot
      memcpy(slot_core[slot].name, "QSPI READ FAILURE", 17);
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
    mhx_screen_display(&mf_screens_slot1_not_m65);
    if (!mhx_check_input("CONFIRM\r", MHX_CI_CHECKCASE|MHX_CI_PRINT, MHX_A_YELLOW))
      return 0;
  }
  mhx_screen_display(&mf_screens_slot0_warning);
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
  uint8_t i;

  mhx_clearscreen(0x20, MHX_A_WHITE | MHX_A_FLIP);
  mhx_set_xy(14, 0);
  mhx_writef("Edit Slot #%d", selected_slot);
  mhx_hl_lines(0, 0, MHX_A_INVERT | MHX_A_LGREY);

#ifdef STANDALONE
  // make attic ram selection switchable
  mhx_write_xy(0, 1, "<M-A> ATTICRAM", mfhf_attic_disabled?MHX_A_MGREY:MHX_A_YELLOW);
  mhx_write_xy(15, 1, mfhf_attic_disabled?"OFF":" ON", mfhf_attic_disabled?MHX_A_MGREY:MHX_A_YELLOW);
  mhx_write_xy(22, 1, "<M-B> HWACCCEL", qspi_force_bitbash?MHX_A_MGREY:MHX_A_YELLOW);
  mhx_write_xy(37, 1, qspi_force_bitbash?"OFF":" ON", qspi_force_bitbash?MHX_A_MGREY:MHX_A_YELLOW);
#endif

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

        if (loaded || (slot_core[selected_slot].real_flags & corecap_def[i].bits) == (mfsc_corehdr_bootflags & corecap_def[i].bits)) {
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

  mfp_init_progress(mfu_slot_mb, 17, '-', " Slot Contents ", MHX_A_WHITE);
  if (slot_core[selected_slot].valid != SLOT_EMPTY)
    mfp_set_area(0, slot_core[selected_slot].length ? slot_core[selected_slot].length >> 16 : mfu_slot_pagemask + 1,
                 slot_core[selected_slot].length && slot_core[selected_slot].valid == SLOT_VALID ? '*' : '?', MHX_A_WHITE);

  // copy footer from upper memory
  lcopy(mf_screens_menu.screen_start + MFMENU_EDIT_FOOTER * 40 +
        ((selected_slot | booted_via_jtag) ? 160 : 0) +
        ((selected_file != MFSC_FILE_INVALID
#if defined(STANDALONE)
          || (!mfhf_attic_disabled && slot_core[selected_slot].real_flags != mfsc_corehdr_bootflags)
#elif !defined(NO_ATTIC)
          || slot_core[selected_slot].real_flags != mfsc_corehdr_bootflags
#endif
         ) ? 80 : 0),
        mhx_base_scr + 23*40, 80);
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
  mfsc_corehdr_bootflags = slot_core[selected_slot].real_flags;
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

#ifdef STANDALONE
    // M-A toggles ATTIC RAM
    if (mhx_lastkey.code.key == 0xc1 && !atticram_bad) {
      mfhf_attic_disabled ^= 1;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }

    // M-B toggles BITBASH
    if (mhx_lastkey.code.key == 0xc2) {
      qspi_force_bitbash ^= 1;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }
#endif

    // F3 loads a core
    if (mhx_lastkey.code.key == 0xf3) {
      selected_file = mfsc_selectcore(selected_reflash_slot);
      if (selected_file == MFSC_FILE_VALID)
        loaded = 1;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }

    if (mhx_lastkey.code.key == 0xf4) {
#ifndef STANDALONE
      // main flasher only allows erasing slot 0 if booted from jtag
      if (selected_slot == 0 && !booted_via_jtag) {
        mhx_flashscreen(MHX_A_LRED, 150);
        continue;
      }
#endif
      selected_file = MFSC_FILE_ERASE;
      loaded = 0;
      draw_edit_slot(selected_slot, loaded);
      continue;
    }

    if (mhx_lastkey.code.key == 0xf8) {
      // first check if file or erase was selected
      if (selected_file != MFSC_FILE_INVALID) {
        // mfhf_load_core patches flags into loaded core
        if (selected_file == MFSC_FILE_ERASE || mfhf_load_core()) {
          mfhf_flash_core(selected_file, selected_slot);
          scan_core_information(0);
        }
        return 0;
      // otherwise perhaps only flags have changed?
      } else if (slot_core[selected_slot].real_flags != mfsc_corehdr_bootflags) {
        // TODO: this requires ATTIC RAM!!!
#ifdef NO_ATTIC
        mhx_flashscreen(MHX_A_RED, 150);
        continue;
#else
#ifdef STANDALONE
        if (mfhf_attic_disabled) {
          mhx_flashscreen(MHX_A_RED, 150);
          continue;
        }
#endif
        // we default to loading 256k (this is the sector size on r3a+)
        // TODO: make this independet of flash chip geometry
        if (mfhf_load_core_from_flash(selected_slot, 0x40000L)) {
          selected_file = MFSC_FILE_VALID; // mfhf_flash_core needs to know what to do
          mfhf_flash_core(selected_file, selected_slot);
          scan_core_information(0);
        }
#endif /* !NO_ATTIC */
        // TODO: display failure
        return 0;
      }
    }
  }

  return 0;
}

void perhaps_reconfig(uint8_t slot)
{
  if (!booted_via_jtag) {
    mhx_clear_keybuffer();
    mhx_until_keys_released();
    if (!slot || slot_core[slot].valid != SLOT_EMPTY)
      mfut_reconfig_fpga(slot * mfu_slot_size + 4096);
  }
  mhx_flashscreen(MHX_A_RED, 150);
}

void hard_exit(void)
{
  // clear keybuffer
  mhx_clear_keybuffer();
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
  uint8_t i;
#ifndef STANDALONE
  uint8_t r;
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
  mhx_setattr(MHX_A_WHITE);

#ifdef STANDALONE
  // setup OPENROM palette in standalone mode
  POKE(0xd030U, PEEK(0xd030U) | 0x04); // switch to RAM palette
  for (i = 0; i < 16; i++) {
    POKE(0xd100U + i, openrom_palette[i].r);
    POKE(0xd200U + i, openrom_palette[i].g);
    POKE(0xd300U + i, openrom_palette[i].b);
  }
#endif

  // we need to probe the hardware now, as we are going into the menu
  if (mfut_probe_hardware_version())
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

  if (mfhf_init()) {
    mhx_writef("\n" MHX_W_ORANGE "Failed to init QSPI flash!" MHX_W_WHITE "\n\njtagflash Version\n  %s\n", utilVersion);
    mhx_press_any_key(MHX_AK_ATTENTION|MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
    hard_exit();
  }

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
    usleep(20);
    // Allow a little while for it to be fetched.
    // (about 70 cycles should be long enough) - raised to 70 based on test

    // check if BOOTSTS is not reading properly, because we started from
    // a bitstream pushed via JTAG
    // check if we automatically flash slot 0 with BRINGUP.COR
    if (PEEK(0xD6C7) == 0xFF && !mfsc_findcorefile(BRINGUP_CORE, 1)) {
      if ((mfsc_corehdr_instflags & (MFSC_COREINST_FACTORY | MFSC_COREINST_AUTO | MFSC_COREINST_FORCE)) == (MFSC_COREINST_FACTORY | MFSC_COREINST_AUTO | MFSC_COREINST_FORCE)) {
        selected_file = MFSC_FILE_VALID;
        draw_edit_slot(0, 1);
        if (mfhf_load_core()) {
          mfhf_flash_core(selected_file, 0);
        }
        mhx_clearscreen(' ', MHX_A_WHITE);
        mhx_set_xy(5, 12);
        mhx_writef("Please power cycle your MEGA65");
        while (1)
          POKE(0xD020, PEEK(0xD020) & 0x0f);
      }
    }

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

#if 0
      // DEBUG: interrupt boot and first display what slot we will boot
      mhx_writef("Selected Slot: %08x (V:%02x)\n\n", selected, slot_core[selected].valid);
      mhx_press_any_key(0,0);
#endif

      if (slot_core[selected].valid == SLOT_VALID) {
        // extra delay: wait two frames so the QSPI has time to settle
        r = PEEK(0xD7FA);
        while (r == PEEK(0xD7FA));
        r = PEEK(0xD7FA);
        while (r == PEEK(0xD7FA));
        mfut_reconfig_fpga(mfu_slot_size * selected + 4096);
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

  if (mfut_probe_hardware_version()) {
    mhx_writef("\nUnknown hardware model id $%02X\n", hw_model_id);
    mhx_press_any_key(MHX_AK_ATTENTION|MHX_AK_NOMESSAGE, MHX_A_NOCOLOR);
    hard_exit();
  }
  if (mfhf_init()) {
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

#if 0
  // currently flashing is only possible on r3a or later
  if (hw_model_id < 3 || hw_model_id > 9 || num_4k_sectors || flash_sector_bits != 18) {
    mhx_writef(MHX_W_YELLOW "WARNING:" MHX_W_WHITE " Flashing is currently not\n"
               "supported on your platform, please use\n"
               "alternative ways.\n\n");
    old_flash_chip = 1;
    mhx_press_any_key(MHX_AK_IGNORETAB, MHX_A_WHITE);
  }
#endif

#ifdef LAZY_ATTICRAM_CHECK
  // quick and dirty attic ram check
  lpoke(0x8000000l, 0x55);
  if (lpeek(0x8000000l) != 0x55)
    atticram_bad = 1;
  else {
    lpoke(0x8000000l, 0xaa);
    if (lpeek(0x8000000l) != 0xaa)
      atticram_bad = 1;
    else {
      lpoke(0x8000000l, 0xff);
      if (lpeek(0x8000000l) != 0xff)
        atticram_bad = 1;
      else {
        lpoke(0x8000000l, 0x00);
        if (lpeek(0x8000000l) != 0x00)
          atticram_bad = 1;
      }
    }
  }
  if (atticram_bad) {
    mhx_writef(MHX_W_YELLOW "WARNING:" MHX_W_WHITE " Your system does not support\n"
           "attic ram! Flashing will be slower!\n\n");
    mfhf_attic_disabled = 1;
  }

  // if we gave some warning, wait for a keypress before continuing
  if (booted_via_jtag || atticram_bad)
    mhx_press_any_key(MHX_AK_IGNORETAB, MHX_A_WHITE);
#endif

  // Scan for existing bitstreams and locate first default slot
  scan_core_information(0);

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
      lcopy(mf_screens_menu.screen_start + MFMENU_MAIN_FOOTER * 40, mhx_base_scr + 24*40, 40);
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
    mhx_hl_lines(selected*3, selected*3 + 2, MHX_A_INVERT|(slot_core[selected].valid == SLOT_VALID ? MHX_A_WHITE : (slot_core[selected].valid == SLOT_EMPTY ? MHX_A_YELLOW : MHX_A_RED)));
    last_selected = selected;

    mhx_getkeycode(0);

    // check for number key pressed
    if (mhx_lastkey.code.key >= 0x30 && mhx_lastkey.code.key < 0x30 + slot_count)
      perhaps_reconfig(mhx_lastkey.code.key - 0x30);

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
      perhaps_reconfig(selected);
      break;
#ifdef FLASH_INSPECT
    case 0x06: // CTRL-F
      // Flash memory monitor
      mfhl_flash_inspector();
      redraw_menu = REDRAW_CLEAR;
      break;
#endif
// slot 0 flashing is only done with PRG and DIP 3!
#if FIRMWARE_UPGRADE
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
#ifdef FIRMWARE_UPGRADE
    if (selected_reflash_slot < slot_count) {
#else
    if (selected_reflash_slot > 0 && selected_reflash_slot < slot_count) {
#endif
      // TODO: put in again
      // if (old_flash_chip) {
      //   mhx_flashscreen(MHX_A_YELLOW, 150);
      //   continue;
      // }

#ifdef LAZY_ATTICRAM_CHECK

      // TODO: put in again
      // if (atticram_bad) {
      //   mhx_flashscreen(MHX_A_RED, 150);
      //   continue;
      // }
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

  hard_exit();
}
