#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspicommon.h"
#include "qspireconfig.h"

#include "version.h"

unsigned char joy_x = 100;
unsigned char joy_y = 100;

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
#define CORECAP_SLOT_DEFAULT 0b10000000 // in capabilities 1 means: prohibited use as default

#define SLOT_EMPTY   0x00
#define SLOT_INVALID 0x01
#define SLOT_VALID   0x80

#define CARTCAP_NAME_MAX 3
char cartcap_names[CARTCAP_NAME_MAX][5] = {"C64 ", "C128", "M65"};
#include <ascii_charmap.h>
unsigned char cart_c128_magic[3] = "CBM";
unsigned char cart_m65_magic[3] = "M65";
#include <cbm_petscii_charmap.h>

typedef struct {
  char name[32];
  char version[32];
  unsigned char capabilities;
  unsigned char flags;
  unsigned char valid;
} slot_core_type;

slot_core_type slot_core[MAX_SLOTS];

void display_version(void)
{
  unsigned char key;
  uint8_t core_hash_1 = PEEK(0xD632);
  uint8_t core_hash_2 = PEEK(0xD633);
  uint8_t core_hash_3 = PEEK(0xD634);
  uint8_t core_hash_4 = PEEK(0xD635);

  printf("%c%c%c", 0x93, 0x11, 0x11);
  printf("  Core hash:\n    %02x%02x%02x%02x%s\n", core_hash_4, core_hash_3, core_hash_2, core_hash_1,
      reconfig_disabled ? " (booted via JTAG)" : "");
  printf("  MEGAFLASH version:\n    %s\n", utilVersion);
  printf("  Slot 0 Version:\n    %s\n\n", slot_core[0].version);
  printf("  Hardware information\n"
         "    Model ID:   $%02X\n"
         "    Model name: %s\n"
         "    Slots:      %d (each %dMB)\n"
         "    Slot Size:  %ld (%ld pages)\n",
         hw_model_id, hw_model_name, slot_count, SLOT_MB, SLOT_SIZE, SLOT_SIZE_PAGES);

#if 0
  {
    unsigned char cart_id[6];
    printf("  Cartridge debug:\n");
    key = PEEK(0xD67EU);
    printf("    $D67E: %02X ", key);
    switch (key & 0x60) {
    case 0x00:
      printf("ROML/ROMH");
      break;
    case 0x20:
      printf("ROML");
      break;
    case 0x40:
      printf("Ultimax");
      break;
    case 0x60:
      printf("no C64 cart");
      break;
    }
    lcopy(0x4008004, (long)cart_id, 6);
    printf("\n    $8004: %02X %02X %02X %02X %02X %02X\n", cart_id[0], cart_id[1], cart_id[2], cart_id[3], cart_id[4],
        cart_id[5]);
    lcopy(0x400C004, (long)cart_id, 6);
    printf(
        "    $C004: %02X %02X %02X %02X %02X %02X\n", cart_id[0], cart_id[1], cart_id[2], cart_id[3], cart_id[4], cart_id[5]);
  }
#endif

  // wait for ESC or RUN/STOP
  do {
    while (!(key = PEEK(0xD610)))
      ;
    POKE(0xD610, 0);
  } while (key != 0x1b && key != 0x03);

  // CLR screen for redraw
  printf("%c", 0x93);
}

unsigned char first_flash_read = 1;
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
 * bit to update slot 0.
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

#define FAST_PETSCII2ASCII(A) A == 0 ? 0x20 : (((A & 0b1000000) && ((A & 0b11111) != 0)) ? A^0x20 : A)

    lfill((long)slot_core[slot].name, ' ', 64);
    // extract names
    if (slot_core[slot].valid == SLOT_VALID) {
      for (j = 0; j < 31; j++) {
        slot_core[slot].name[j] = FAST_PETSCII2ASCII(data_buffer[16 + j]);
        slot_core[slot].version[j] = FAST_PETSCII2ASCII(data_buffer[48 + j]);
      }
    }

    if (slot == 0)
      // slot 0 is always displayed as FACTORY CORE
      memcpy(slot_core[slot].name, "MEGA65 FACTORY CORE", 19);
    else if (slot_core[slot].valid == SLOT_EMPTY)
      // 0xff in the first 512 bytes, this is empty
      memcpy(slot_core[slot].name, "EMPTY SLOT", 10);
    else if (slot_core[slot].valid == SLOT_INVALID)
      // no bitstream magic at the start of the slot
      memcpy(slot_core[slot].name, "UNKNOWN CONTENT", 15);
    slot_core[slot].name[31] = 0;
    slot_core[slot].version[31] = 0;

    if (update_slot & 0x80)
      break;
  }

  return found != 0xff ? found : default_slot;
}

void write_text(unsigned char x, unsigned char y, char *text, uint8_t length)
{
  while (length > 0) {
    POKE(0x400 + y*40 + x++, *text);
    text++;
    length--;
  }
}

unsigned char confirm_slot0_flash()
{
  printf("%c\n"
         " %c** You are about to replace slot 0! **%c\n\n"
         "If this process fails or is interrupted,"
         "slot 0 will fail to boot. Then you can\n"
         "either use a JTAG to boot again or wait "
         "30 sec until slot 1 hopefully starts.\n\n"
         "For this you need to make sure that your"
         "slot 1 MEGA65 core works correctly and\n"
         "that you can send the %cupgrade0.prg%c from\n"
         "your PC to your MEGA65!\n\n"
         "If you are unsure about any of this,\n"
         "please contact us first!\n\n%c"
         " * I confirm that I am aware of the\n"
         "   risks involved and like to proceed.\n\n"
         " * I confirm that I can start my MEGA65 "
         "   without the need of slot 0 and can\n"
         "   send the flasher to my MEGA65.%c\n\n"
         "Type CONFIRM to proceed, or press\n"
         "<RUN/STOP> to abort: ",
         0x93, 129, 5, 155, 5, 158, 5);
#if 0
  printf("%c\n"
         "An error while replacing slot 0 can\n"
         "temporary brick your MEGA65, which can\n"
         "ONLY be reverted using a JTAG adapter or"
         "a MEGA65 core in slot 1.\n\n"
         "Please confirm that you know the risks\n"
         "and the recovery procedure by typing\n"
         "CONFIRM: ", 0x93);
#endif
  return check_input("CONFIRM\r", CASE_SENSITIVE|CASE_PRINT);
}

#include <cbm_screen_charmap.h>
void display_cartridge(short slot)
{
  unsigned char offset = 1;
  // TODO: if we get more than 3 cartridge types, we need to change this!

  // if all three bits are 1, write ALL... is that even possible?
  if ((slot_core[slot].flags & CORECAP_CART) == CORECAP_CART) {
    write_text(35, slot * 3 + offset, "[ALL]", 5);
    return;
  }

  if (slot_core[slot].flags & CORECAP_CART_C64)
    write_text(35, slot * 3 + offset++, "[C64]", 5);
  if (slot_core[slot].flags & CORECAP_CART_C128)
    write_text(35, slot * 3 + offset++, "[128]", 5);
  if (slot_core[slot].flags & CORECAP_CART_M65)
    write_text(35, slot * 3 + offset++, "[M65]", 5);
}
#include <cbm_petscii_charmap.h>

void hard_exit(void)
{
  // clear keybuffer
  *(unsigned char *)0xc6 = 0;

  // Switch back to normal speed control before exiting
  POKE(0, 64);
#ifdef STANDALONE
  // NMI vector
  asm(" jmp $fffa ");
#else
  // back to HYPPO
  POKE(0xCF7f, 0x4C);
  asm(" jmp $cf7f ");
#endif
}

void main(void)
{
  unsigned char selected = 0xff, atticram_bad = 0, search_cart = CORECAP_SLOT_DEFAULT, i;
  unsigned char selected_reflash_slot;

  mega65_io_enable();

  SEI(); // this is useless, as the next printf a few lines down will do CLI

  // white text, blue screen, black border, clear screen
  POKE(0x286, 1);
  POKE(0xd020, 0);
  POKE(0xd021, 6);
  printf("%c", 0x93);

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
    char cart_id[6];
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

      // check for cartridge: if /EXROM and/or /GAME is low, we have a C64 or M65 cart
      switch (PEEK(0xD67EU) & 0x60) {
        case 0x00: // ROML + ROMH
        case 0x20: // ROML
          search_cart = CORECAP_CART_C64;
          break;
        case 0x40: // Ultimax, check for M65 marker at $8007
          lcopy(0x4008007UL, (long)cart_id, 3);
          if (!memcmp(cart_id, cart_m65_magic, 3))
            search_cart = CORECAP_CART_M65;
          else
            search_cart = CORECAP_CART_C64;
          break;
        case 0x60:
          // check for C128 style cart by looking at signature at 8007 or C007
          for (i = 0; i < 2; i++) {
            lcopy((i ? 0x400C007UL : 0x4008007UL), (long)cart_id, 3);
            if (!memcmp(cart_id, cart_c128_magic, 3)) {
              search_cart = CORECAP_CART_C128;
              break;
            }
          }
          break;
      }

      // determine boot slot by flags (default search is for default slot)
      selected = scan_bitstream_information(search_cart, 0);

      // if we don't have a cart slot, then we use slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
      if (selected == 0xff)
        selected = 1 + ((PEEK(0xD69D) >> 3) & 1);

#if 0
      // debug -- do not use in official builds, may mess things up
      printf("\n\nD67E=%02X,MATCH=%02X,SEARCH=%X,SEL=%X,D7FD=%02X\n", PEEK(0xD67EU), PEEK(0xD67EU) & 0x60, search_cart, selected, PEEK(0xD7FDU));
      lcopy(0x4008004, (long)cart_id, 6);
      printf("\n  $8004: %02X %02X %02X %02X %02X %02X\n", cart_id[0], cart_id[1], cart_id[2], cart_id[3], cart_id[4], cart_id[5]);
      lcopy(0x400C004, (long)cart_id, 6);
      printf("\n  $C004: %02X %02X %02X %02X %02X %02X\n", cart_id[0], cart_id[1], cart_id[2], cart_id[3], cart_id[4], cart_id[5]);
      // wait for key
      while (PEEK(0xD610))
        POKE(0xD610, 0);
      while (!PEEK(0xD610))
        usleep(5000);
      POKE(0xD610, 0);
#endif

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
        printf("WARNING: Flash slot %d seems to be\n"
               "messed up.\n"
               "To avoid seeing this message every time,"
               "either erase or re-flash the slot.\n\n"
               "Press almost any key to continue...\n", selected);
        while (PEEK(0xD610))
          POKE(0xD610, 0);
        // Ignore TAB, since they might still be holding it
        while ((!PEEK(0xD610)) || (PEEK(0xD610) == 0x09)) {
          if (PEEK(0xD610) == 0x09)
            POKE(0xD610, 0);
          continue;
        }
        while (PEEK(0xD610))
          POKE(0xD610, 0);

        printf("%c", 0x93);
      }
    }
  }

  // we need to probe the hardware now, as we are going into the menu
  if (probe_hardware_version())
    hard_exit();

#else /* STANDALONE */
  printf("\njtagflash Version\n  %s\n", utilVersion);

  if (probe_hardware_version()) {
    printf("\nUnknown hardware model id $%02X\n", hw_model_id);
    press_any_key(1, 1);
    hard_exit();
  }
  if (probe_qspi_flash()) {
    // print it a second time, screen has scrolled!
    printf("\njtagflash Version\n  %s\n", utilVersion);
    press_any_key(1, 1);
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
    printf("%cWARNING:%c You appear to have started this"
           "bitstream via JTAG.  This means that you"
           "%ccan't%c use this menu to launch other\n"
           "cores.\n"
           "You will still be able to flash new\n"
           "bitstreams, though.\n\n",
        158, 5, 158, 5);
    reconfig_disabled = 1;
    // wait for key see below
  }

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
  if (atticram_bad)
    printf("%cWARNING:%c Your system does not support\n"
           "attic ram. Because the flasher in this\n"
           "core does not support flashing without\n"
           "attic ram, flashing has been %cdisabled%c.\n\n",
        150, 5, 150, 5);

  // if we gave some warning, wait for a keypress before continuing
  if (reconfig_disabled || atticram_bad) {
    printf("Press almost any key to continue...\n");
    while (PEEK(0xD610))
      POKE(0xD610, 0);
    // Ignore TAB, since they might still be holding it
    while ((!PEEK(0xD610)) || (PEEK(0xD610) == 0x09)) {
      if (PEEK(0xD610) == 0x09)
        POKE(0xD610, 0);
      continue;
    }
    while (PEEK(0xD610))
      POKE(0xD610, 0);
  }

#ifndef FIRMWARE_UPGRADE
  // prepare menu

  // Scan for existing bitstreams
  scan_bitstream_information(0, 0);

  // clear screen
  selected = 0;
  printf("%c", 0x93);
  while (1) {
    // home cursor
    printf("%c%c", 0x13, 0x05);

    for (i = 0; i < slot_count; i++) {
      // Display slot information
      printf("\n %c%c%c %s", slot_core[i].flags & CORECAP_SLOT_DEFAULT ? '>' : '(',
        '0' + i, slot_core[i].flags & CORECAP_SLOT_DEFAULT ? '<' : ')', slot_core[i].name);
      if (i > 0 && slot_core[i].valid == SLOT_VALID) {
        printf("\n     %s\n", slot_core[i].version);
        display_cartridge(i);
      }
      else
        printf("\n\n");

      // highlight slot
      base_addr = 0x0400 + i * (3 * 40);
      if (i == selected) {
        // Highlight selected item
        for (x = 0; x < (3 * 40); x++) {
          POKE(base_addr + x, PEEK(base_addr + x) | 0x80);
          POKE(base_addr + 0xd400 + x, slot_core[i].valid == SLOT_VALID ? 1 : (slot_core[i].valid == SLOT_INVALID ? 2 : 7));
        }
      }
      else {
        // Don't highlight non-selected items
        for (x = 0; x < (3 * 40); x++) {
          POKE(base_addr + x, PEEK(base_addr + x) & 0x7F);
        }
      }
    }
    // Draw footer line with instructions
    for (; i < 8; i++)
      printf("%c%c%c", 17, 17, 17);
    printf("%c0-%u = Launch Core.  CTRL 1-%u = Edit Slo%c", 0x12, slot_count - 1, slot_count - 1, 0x92);
    POKE(1024 + 999, 0x14 + 0x80); // the 't'

    x = 0;
    while (!x) {
      x = PEEK(0xd610);
      y = PEEK(0xd611);
    }
    POKE(0xd610, 0);

    if (x >= '0' && x < slot_count + '0') {
      if (x == '0') {
        reconfig_fpga(0);
      }
      else if (slot_core[x - '0'].valid != 0) // only boot slot if not empty
        reconfig_fpga((x - '0') * SLOT_SIZE + 4096);
      else {
        POKE(0xd020, 2);
        POKE(0xd021, 2);
        usleep(150000L);
        POKE(0xd020, 0);
        POKE(0xd021, 6);
      }
    }

    selected_reflash_slot = 0xff;

    switch (x) {
    case 0x03: // RUN-STOP
    case 0x1b: // ESC
      // Simply exit flash menu without doing anything.

      // Switch back to normal speed control before exiting
      hard_exit();

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
      // Launch selected bitstream
      if (!selected) {
        reconfig_fpga(0);
        printf("%c", 0x93);
      }
      else if (slot_core[selected].valid != SLOT_EMPTY)
        reconfig_fpga(selected * SLOT_SIZE + 4096);
      else {
        POKE(0xd020, 2);
        POKE(0xd021, 2);
        usleep(150000L);
        POKE(0xd020, 0);
        POKE(0xd021, 6);
      }
      break;
#ifdef QSPI_FLASH_INSPECT
    case 0x06: // CTRL-F
      // Flash memory monitor
      printf("%c", 0x93);
      flash_inspector();
      printf("%c", 0x93);
      break;
#endif
// slot 0 flashing is only done with PRG and DIP 3!
#if QSPI_FLASH_SLOT0
    case 0x7e: // TILDE (MEGA-LT)
      // first ask rediculous questions...
      if (confirm_slot0_flash()) {
        selected_reflash_slot = 0;
      }
      printf("%c", 0x93);
      break;
#endif
    case 144: // CTRL-1
      if (y & 0x04)
        selected_reflash_slot = 1;
      break;
    case 5: // CTRL-2
      if (y & 0x04)
        selected_reflash_slot = 2;
      break;
    case 28: // CTRL-3
      if (y & 0x04)
        selected_reflash_slot = 3;
      break;
    case 159: // CTRL-4
      if (y & 0x04)
        selected_reflash_slot = 4;
      break;
    case 156: // CTRL-5
      if (y & 0x04)
        selected_reflash_slot = 5;
      break;
    case 30: // CTRL-6
      if (y & 0x04)
        selected_reflash_slot = 6;
      break;
    case 31: // CTRL-7 && HELP
      if (y & 0x04)
        selected_reflash_slot = 7;
      else
        display_version();
      break;
    }

    // extra security against slot 0 flashing
#if QSPI_FLASH_SLOT0
    if (selected_reflash_slot < slot_count) {
#else
    if (selected_reflash_slot > 0 && selected_reflash_slot < slot_count) {
#endif
      if (atticram_bad) {
        POKE(0xd020, 2);
        POKE(0xd021, 2);
        usleep(150000L);
        POKE(0xd020, 0);
        POKE(0xd021, 6);
      }
      else {
        unsigned char selected_file = select_bitstream_file(selected_reflash_slot);
        if (selected_file) {
          reflash_slot(selected_reflash_slot, selected_file);
          scan_bitstream_information(0, selected_reflash_slot | 0x80);
        }
        printf("%c", 0x93);
      }
    }

    // restore black border
    POKE(0xD020, 0);
  }
#else /* FIRMWARE_UPGRADE */
  if (!confirm_slot0_flash()) {
    printf("\n\nABORTED!\n");
    hard_exit();
  }

#include <ascii_charmap.h>
  strncpy(disk_name_return, "upgrade0.cor", 32);
#include <cbm_screen_charmap.h>
  memcpy(disk_display_return, "UPGRADE0.COR", 12);
  memset(disk_display_return + 12, 0x20, 28);
#include <cbm_petscii_charmap.h>
  reflash_slot(0, SELECTED_FILE_VALID);
#endif

  hard_exit();
}
