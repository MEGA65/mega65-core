#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#include <6502.h>

#include "qspicommon.h"
#include "userwarning.c"
unsigned char check_input(char *m, uint8_t case_sensitive);

unsigned char joy_x=100;
unsigned char joy_y=100;


unsigned int base_addr;

unsigned long autoboot_address=0;

void main(void)
{
  unsigned char valid;
  unsigned char selected=0;
  unsigned char selected_reflash_slot;

  mega65_io_enable();

  // White text
  POKE(0x286,1);

  SEI();

  probe_qpsi_flash(0);

  printf("%c",0x93);

  // We care about whether the IPROG bit is set.
  // If the IPROG bit is set, then we are post-config, and we
  // don't want to automatically change config. Rather, we just
  // exit to allow the Hypervisor to boot normally.  The exception
  // is if the fire button on either joystick is held, or the TAB
  // key is being pressed.  In that case, we show the menu of
  // flash slots, and allow the user to select which core to load.

  // Holding ESC on boot will prevent flash menu starting
  if (PEEK(0xD610)==0x1b) {
    // Switch back to normal speed control before exiting
    POKE(0,64);
    POKE(0xCF7f,0x4C);
    asm (" jmp $cf7f ");
  }


  //  while(PEEK(0xD610)) POKE(0xD610,0);

  //  POKE(0x0400,PEEK(0xD610));
  //  while(1) POKE(0xD020,PEEK(0xD020));

  // TAB key or NO SCROLL bucky held forces menu to appear
  if ((PEEK(0xD610)!=0x09)&&(!(PEEK(0xD611)&0x20))) {

    // Select BOOTSTS register
    POKE(0xD6C4,0x16);
    usleep(10);
    // Allow a little while for it to be fetched.
    // (about 40 cycles should be long enough)
    if (PEEK(0xD6C5)&0x01) {
      // FPGA has been reconfigured, so assume that we should boot
      // normally, unless magic keys are being pressed.
      if ((PEEK(0xD610)==0x09)||(!(PEEK(0xDC00)&0x10))||(!(PEEK(0xDC01)&0x10)))
      {
        // Magic key pressed, so proceed to flash menu after flushing keyboard input buffer
        while(PEEK(0xD610)) POKE(0xD610,0);
      }
      else {      
        // We should actually jump ($CF80) to resume hypervisor booting
        // (see src/hyppo/main.asm launch_flash_menu routine for more info)

#if 0
        printf("Continuing booting with this bitstream (a)...\n");
        printf("Trying to return control to hypervisor...\n");

        press_any_key();
#endif

        // Switch back to normal speed control before exiting
        POKE(0,64);
        POKE(0xCF7f,0x4C);
        asm (" jmp $cf7f ");
      }
    } else {
      // FPGA has NOT been reconfigured
      // So if we have a valid upgrade bitstream in slot 1, then run it.
      // Else, just show the menu.
      // XXX - For now, we just always show the menu

      // Check valid flag and empty state of the slot before launching it.

      // Allow booting from slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
      autoboot_address=SLOT_SIZE*(1+((PEEK(0xD69D)>>3)&1));
            
      // XXX Work around weird flash thing where first read of a sector reads rubbish
      read_data(autoboot_address+0*256);
      for(x=0;x<256;x++) {
	if (data_buffer[0]!=0xee) break;
	usleep(50000);
	read_data(autoboot_address+0*256);
	read_data(autoboot_address+0*256);
      }      

      read_data(autoboot_address+0*256);
      y=0xff;
      valid=1;
      for(x=0;x<256;x++) y&=data_buffer[x];
      for(x=0;x<16;x++) if (data_buffer[x]!=bitstream_magic[x]) { valid=0; break; }
      // Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
      if (y==0xff) {
        read_data(autoboot_address+1*256);
        for(x=0;x<256;x++) y&=data_buffer[x];
      } else {
        //      for(i=0;i<255;i++) printf("%02x",data_buffer[i]);
        //      printf("\n");
        printf("(First sector not empty. Code $%02x FOO!)\n",y);
      }

      if (valid) {
        // Valid bitstream -- so start it
        reconfig_fpga(autoboot_address+4096);
      } else if (y==0xff) {
        // Empty slot -- ignore and resume
        // Switch back to normal speed control before exiting

#if 0
        printf("Continuing booting with this bitstream (b)...\n");
        printf("Trying to return control to hypervisor...\n");

        press_any_key();
#endif
	
        POKE(0,64);
        POKE(0xCF7f,0x4C);
        asm (" jmp $cf7f ");
      } else {
        printf("WARNING: Flash slot %d seems to be\n"
            "messed up (code $%02X).\n",
	       1+((PEEK(0xD69D)>>3)&1),
	       y);
        printf("To avoid seeing this message every time,either "
            "erase or re-flash the slot.\n");
        printf("\nPress almost any key to continue...\n");
        while(PEEK(0xD610)) POKE(0xD610,0);
        // Ignore TAB, since they might still be holding it
        while((!PEEK(0xD610))||(PEEK(0xD610)==0x09)) {
          if (PEEK(0xD610)==0x09) POKE(0xD610,0);
          continue;
        }
        while(PEEK(0xD610)) POKE(0xD610,0);

        printf("%c",0x93);

      }
    }
  } else {
    // We have started by holding TAB down
    // So just proceed with showing the menu
  }

  //  printf("BOOTSTS = $%02x%02x%02x%02x\n",
  //	 PEEK(0xD6C7),PEEK(0xD6C6),PEEK(0xD6C5),PEEK(0xD6C4));

  if (PEEK(0xD6C7)==0xFF) {
    // BOOTSTS not reading properly.  This usually means we have
    // started from a bitstream via JTAG, and the ECAPE2 thingy
    // isn't working. This means we can't successfully reconfigure
    // so we should probably display a warning.
    printf("WARNING: You appear to have started this"
        "bitstream via JTAG.  This means that you"
        "can't use this menu to launch other\n"
        "cores.  You will still be able to flash "
        " new bitstreams, though.\n");
    reconfig_disabled=1;
    printf("\nPress almost any key to continue...\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    // Ignore TAB, since they might still be holding it
    while((!PEEK(0xD610))||(PEEK(0xD610)==0x09)) {
      if (PEEK(0xD610)==0x09) POKE(0xD610,0);
      continue;
    }
    while(PEEK(0xD610)) POKE(0xD610,0);

    printf("%c",0x93);
  }

#if 0
  POKE(0xD6C4,0x10);  
  printf("WBSTAR = $%02x%02x%02x%02x\n",
      PEEK(0xD6C7),PEEK(0xD6C6),PEEK(0xD6C5),PEEK(0xD6C4));
#endif  

  while(1)
  {
    // home cursor
    printf("%c",0x13);

    // Draw footer line with instructions
    for(y=0;y<24;y++) printf("%c",0x11);
    if (!slot_count) slot_count=8;
    if (slot_count>8) slot_count=8;
    printf("%c0-%u = Launch Core.  CTRL 1-%u = Edit Slo%c", 0x12, slot_count-1, slot_count-1, 0x92);
    POKE(1024+999,0x14+0x80);

    // Scan for existing bitstreams
    // (ignore golden bitstream at offset #0)
    for(i=0;i<mb;i+=SLOT_MB) {
      // Position cursor for slot
      z=i/SLOT_MB;
      printf("%c%c",0x13,0x11);
      for(y=0;y<z;y++) printf("%c%c%c",0x11,0x11,0x11);

      read_data(i*1048576+0*256);
      //       for(x=0;x<256;x++) printf("%02x ",data_buffer[x]); printf("\n");
      y=0xff;
      valid=1;
      for(x=0;x<256;x++) y&=data_buffer[x];
      for(x=0;x<16;x++) if (data_buffer[x]!=bitstream_magic[x]) { valid=0; break; }

      // Always treat golden bitstream slot as valid
      if (!i) valid=1;

      // Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
      read_data(i*1048576+1*256);
      for(x=0;x<256;x++) y&=data_buffer[x];

      if (!i) {
        // Assume contains golden bitstream
        printf("    (%c) MEGA65 FACTORY CORE",'0'+(i/SLOT_MB));
      }
      else if (y==0xff) printf("    (%c) EMPTY SLOT\n",'0'+(i/SLOT_MB));
      else if (!valid) {
        printf("    (%c) UNKNOWN CONTENT\n",'0'+(i/SLOT_MB));
      } else {
        // Something valid in the slot
        char core_name[32];
        char core_version[32];
        unsigned char j;
        read_data(i*1048576+0*256);
        for(j=0;j<32;j++) {
          core_name[j]=data_buffer[16+j];
          core_version[j]=data_buffer[48+j];
          // ASCII to PETSCII conversion
          if ((core_name[j]>=0x41&&core_name[j]<=0x57)
              ||(core_name[j]>=0x61&&core_name[j]<=0x77)) core_name[j]^=0x20;
        }
        core_name[31]=0;
        core_version[31]=0;

        // Display info about it
        printf("    %c(%c) %s\n",0x05,'0'+(i/SLOT_MB),core_name);
        printf("        %s\n",core_version);
      }

      // Check if entire slot is empty
      //    if (slot_empty_check(i)) printf("  slot is not completely empty.\n");

      base_addr = 0x0400 + (i/SLOT_MB)*(3*40);
      if ((i/SLOT_MB)==selected) {
        // Highlight selected item
        for(x=0;x<(3*40);x++) {
          POKE(base_addr+x,PEEK(base_addr+x)|0x80);
          POKE(base_addr+0xd400+x,valid?1:((y==0xff)?2:7));
        }
      } else {
        // Don't highlight non-selected items
        for(x=0;x<(3*40);x++) {
          POKE(base_addr+x,PEEK(base_addr+x)&0x7F);
        }
      }

    }


    x=0;
    while(!x) {
      x=PEEK(0xd610);
    }

    if (x) {
      POKE(0xd610,0);
      if (x>='0'&&x<slot_count+'0') {
        if (x=='0') {
          reconfig_fpga(0);
        }
        else reconfig_fpga((x-'0')*(SLOT_SIZE)+4096);
      }

      selected_reflash_slot=0;

      switch(x) {
      case 0x03: case 0x1b:
        // Simply exit flash menu without doing anything.

        // Switch back to normal speed control before exiting
        POKE(0,64);
        POKE(0xCF7f,0x4C);
        asm (" jmp $cf7f ");

      case 0x1d: case 0x11:
        selected++;
        if (selected>=(mb/SLOT_MB)) selected=0;
        break;
      case 0x9d: case 0x91:
        if (selected==0) selected=(mb/SLOT_MB)-1; else selected--;
        break;
      case 0x0d:
        // Launch selected bitstream
        if (!selected) {
          reconfig_fpga(0);
          printf("%c",0x93);
        }
        else reconfig_fpga(selected*(SLOT_SIZE)+4096);
        break;
#if 1
      case 0x4d: case 0x6d: // M / m
        // Flash memory monitor
        flash_inspector();
        printf("%c",0x93);
        break;
#endif
      case 0x7e: // TILDE
	if (user_has_been_warned())
          reflash_slot(0);
        printf("%c",0x93);
        break;
      case 144: case 0x42: case 0x62: // CTRL-1
        selected_reflash_slot = 1;
        break;
      case 5: case 0x43: case 0x63: // CTRL-2
        selected_reflash_slot = 2;
        break;
      case 28: case 0x44: case 0x64: // CTRL-3
        selected_reflash_slot = 3;
        break;
      case 159: // CTRL-4
        selected_reflash_slot = 4;
        break;
      case 156: // CTRL-5
        selected_reflash_slot = 5;
        break;
      case 30:  // CTRL-6
        selected_reflash_slot = 6;
        break;
      case 31:  // CTRL-7
        selected_reflash_slot = 7;
        break;
      }

      if (selected_reflash_slot>0 && selected_reflash_slot<slot_count) {
        reflash_slot(selected_reflash_slot);
        printf("%c",0x93);
      }
    }
  }


}

