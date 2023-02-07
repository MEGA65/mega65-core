#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspicommon.h"
// not needed, no slot 0 flashing in core flasher!
// #include "userwarning.c"

unsigned char joy_x = 100;
unsigned char joy_y = 100;

unsigned int base_addr;

unsigned long autoboot_address = 0;

// mega65r3 QSPI has the most space currently with 8x8MB
#define MAX_SLOTS 8
unsigned char slot_core_valid[MAX_SLOTS];
char slot_core_name[MAX_SLOTS][32];
char slot_core_version[MAX_SLOTS][32];

void display_version(void)
{
  unsigned char key;
  uint8_t hardware_model_id = PEEK(0xD629);
  uint8_t core_hash_1 = PEEK(0xD632);
  uint8_t core_hash_2 = PEEK(0xD633);
  uint8_t core_hash_3 = PEEK(0xD634);
  uint8_t core_hash_4 = PEEK(0xD635);

  printf("%c%c%c", 0x93, 0x11, 0x11);
  printf("  MEGAFLASH/Core hash:\n    %02x%02x%02x%02x%s\n\n", core_hash_4, core_hash_3, core_hash_2, core_hash_1,
      reconfig_disabled ? " (booted via JTAG)" : "");
  printf("  Slot 0 Version:\n    %s\n\n", slot_core_version[0]);
  printf("  Hardware model id:\n    $%02X - %s\n\n", hardware_model_id, get_model_name(hardware_model_id));

  // wait for ESC or RUN/STOP
  do {
    while (!(key = PEEK(0xD610)))
      ;
    POKE(0xD610, 0);
  } while (key != 0x1b && key != 0x03);

  // CLR screen for redraw
  printf("%c", 0x93);
}

void scan_bitstream_information(void)
{
  short i, j, x, y;
  unsigned char valid;

  for (i = 0; i < slot_count; i++) {
    read_data(i * SLOT_SIZE + 0 * 256);
    //       for(x=0;x<256;x++) printf("%02x ",data_buffer[x]); printf("\n");
    y = 0xff;
    valid = 1;
    for (x = 0; x < 256; x++)
      y &= data_buffer[x];
    for (x = 0; x < 16; x++)
      if (data_buffer[x] != bitstream_magic[x]) {
        valid = 0;
        break;
      }

    // extract names
    for (j = 0; j < 31; j++) {
      slot_core_name[i][j] = data_buffer[16 + j];
      slot_core_version[i][j] = data_buffer[48 + j];
      // ASCII to PETSCII conversion
      if ((slot_core_name[i][j] >= 0x41 && slot_core_name[i][j] <= 0x5f)
          || (slot_core_name[i][j] >= 0x61 && slot_core_name[i][j] <= 0x7f))
        slot_core_name[i][j] ^= 0x20;
      if ((slot_core_version[i][j] >= 0x41 && slot_core_version[i][j] <= 0x5f)
          || (slot_core_version[i][j] >= 0x61 && slot_core_version[i][j] <= 0x7f))
        slot_core_version[i][j] ^= 0x20;
    }
    slot_core_name[i][31] = 0;
    slot_core_version[i][31] = 0;
    slot_core_valid[i] = 1;

    // Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
    if (y == 0xff) {
      read_data(i * SLOT_SIZE + 1 * 256);
      for (x = 0; x < 256; x++)
        y &= data_buffer[x];
    }

    if (i == 0) {
      // slot 0 is always displayed as FACTORY CORE
      strncpy(slot_core_name[i], "MEGA65 FACTORY CORE            ", 32);
    }
    else if (y == 0xff) {
      // 0xff in the first 512 bytes, this is empty
      strncpy(slot_core_name[i], "EMPTY SLOT                     ", 32);
      memset(slot_core_version[i], ' ', 31);
      slot_core_version[i][31] = 0;
      slot_core_valid[i] = 0;
    }
    else if (!valid) {
      // no bitstream magic at the start of the slot
      strncpy(slot_core_name[i], "UNKNOWN CONTENT                ", 32);
      memset(slot_core_version[i], ' ', 31);
      slot_core_version[i][31] = 0;
      slot_core_valid[i] = 2;
    }

    // Check if entire slot is empty
    //    if (slot_empty_check(i)) then do write it into slot info...
  }
}

void main(void)
{
  unsigned char selected = 0, valid, atticram_bad = 0;
  unsigned char selected_reflash_slot;

  mega65_io_enable();

  SEI();

  // white text, blue screen, black border, clear screen
  POKE(0x286, 1);
  POKE(0xd020, 0);
  POKE(0xd021, 6);
  printf("%c", 0x93);

  // We care about whether the IPROG bit is set.
  // If the IPROG bit is set, then we are post-config, and we
  // don't want to automatically change config. Rather, we just
  // exit to allow the Hypervisor to boot normally.  The exception
  // is if the fire button on either joystick is held, or the TAB
  // key is being pressed.  In that case, we show the menu of
  // flash slots, and allow the user to select which core to load.

  // Holding ESC on boot will prevent flash menu starting
  if (PEEK(0xD610) == 0x1b) {
    // Switch back to normal speed control before exiting
    POKE(0, 64);
    POKE(0xCF7f, 0x4C);
    asm(" jmp $cf7f ");
  }

  probe_qspi_flash();
  
  // The following section starts a core, but only if certain keys
  // are NOT pressed, depending on the system
  // this is the non-interactive part, where megaflash just
  // starts a core from slot 1 or 2
  // if this failes, got to GUI anyway
#ifdef A100T
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
      POKE(0, 64);
      POKE(0xCF7f, 0x4C);
      asm(" jmp $cf7f ");
    }
    else {
      // FPGA has NOT been reconfigured
      // So if we have a valid upgrade bitstream in slot 1, then run it.
      // Else, just show the menu.
      // XXX - For now, we just always show the menu

      // Check valid flag and empty state of the slot before launching it.

      // Allow booting from slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
      autoboot_address = SLOT_SIZE * (1 + ((PEEK(0xD69D) >> 3) & 1));

      // XXX Work around weird flash thing where first read of a sector reads rubbish
      read_data(autoboot_address + 0 * 256);
      for (x = 0; x < 256; x++) {
        if (data_buffer[0] != 0xee)
          break;
        usleep(50000L);
        read_data(autoboot_address + 0 * 256);
        read_data(autoboot_address + 0 * 256);
      }

      read_data(autoboot_address + 0 * 256);
      y = 0xff;
      valid = 1;
      for (x = 0; x < 256; x++)
        y &= data_buffer[x];
      for (x = 0; x < 16; x++)
        if (data_buffer[x] != bitstream_magic[x]) {
          valid = 0;
          break;
        }
      // Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
      if (y == 0xff) {
        read_data(autoboot_address + 1 * 256);
        for (x = 0; x < 256; x++)
          y &= data_buffer[x];
      }
      else {
        //      for(i=0;i<255;i++) printf("%02x",data_buffer[i]);
        //      printf("\n");
        printf("(First sector not empty. Code $%02x FOO!)\n", y);
      }

      if (valid) {
        // Valid bitstream -- so start it
        reconfig_fpga(autoboot_address + 4096);
      }
      else if (y == 0xff) {
        // Empty slot -- ignore and resume
        // Switch back to normal speed control before exiting

#if 0
        printf("Continuing booting with this bitstream (b)...\n");
        printf("Trying to return control to hypervisor...\n");

        press_any_key(0, 0);
#endif

        POKE(0, 64);
        POKE(0xCF7f, 0x4C);
        asm(" jmp $cf7f ");
      }
      else {
        printf("WARNING: Flash slot %d seems to be\n"
               "messed up (code $%02X).\n",
            1 + ((PEEK(0xD69D) >> 3) & 1), y);
        printf("To avoid seeing this message every time,either "
               "erase or re-flash the slot.\n");
        printf("\nPress almost any key to continue...\n");
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

  // We are now in interactive mode, do some tests,
  // then start the GUI

  //  printf("BOOTSTS = $%02x%02x%02x%02x\n",
  //	 PEEK(0xD6C7),PEEK(0xD6C6),PEEK(0xD6C5),PEEK(0xD6C4));

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
           "bitstreams, though.\n\n", 158, 5, 158, 5);
    reconfig_disabled = 1;
    // wait for key see below
  }

#if 0
  POKE(0xD6C4,0x10);
  printf("WBSTAR = $%02x%02x%02x%02x\n",
      PEEK(0xD6C7),PEEK(0xD6C6),PEEK(0xD6C5),PEEK(0xD6C4));
#endif

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
    printf("WARNING: Your system does not support\n"
           "attic ram. Because the flasher in this\n"
           "core does not support flashing without\n"
           "attic ram, flashing has been disabled.\n\n");

  // if we gave some warning, wait for a keypress before continuing
  if (reconfig_disabled || atticram_bad) {
    printf("\nPress almost any key to continue...\n");
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

  // prepare menu
  // sanity check for slot count, determined by probe_qspi_flash
  if (slot_count == 0 || slot_count > 8)
    slot_count = 8;

  // Scan for existing bitstreams
  scan_bitstream_information();

  // clear screen
  printf("%c", 0x93);
  while (1) {
    // home cursor
    printf("%c%c", 0x13, 0x05);

    for (i = 0; i < slot_count; i++) {
      // Display info about it
      printf("\n    (%c) %s\n", '0' + i, slot_core_name[i]);
      if (i > 0 && slot_core_valid[i] == 1)
        printf("        %s\n", slot_core_version[i]);
      else
        printf("\n");

      // highlight slot
      base_addr = 0x0400 + i * (3 * 40);
      if (i == selected) {
        // Highlight selected item
        for (x = 0; x < (3 * 40); x++) {
          POKE(base_addr + x, PEEK(base_addr + x) | 0x80);
          POKE(base_addr + 0xd400 + x, slot_core_valid[i] == 1 ? 1 : (slot_core_valid[i] == 0 ? 2 : 7));
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
    POKE(1024 + 999, 0x14 + 0x80);

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
      else if (slot_core_valid[x - '0'] != 0) // only boot slot if not empty
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
      POKE(0, 64);
      POKE(0xCF7f, 0x4C);
      asm(" jmp $cf7f ");

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
      else if (slot_core_valid[selected] != 0)
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
#if 0
    case 0x7e: // TILDE (MEGA-LT)
      // first ask rediculous questions...
      if (user_has_been_warned()) {
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
    if (selected_reflash_slot > 0 && selected_reflash_slot < slot_count) {
      if (atticram_bad) {
        POKE(0xd020, 2);
        POKE(0xd021, 2);
        usleep(150000L);
        POKE(0xd020, 0);
        POKE(0xd021, 6);
      }
      else {
        reflash_slot(selected_reflash_slot);
        scan_bitstream_information();
        printf("%c", 0x93);
      }
    }

    // restore black border
    POKE(0xD020, 0);
  }
}
