#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

//#define DEBUG_BITBASH(x) { printf("@%d:%02x",__LINE__,x); }
#define DEBUG_BITBASH(x)

#ifdef A100T
#define SLOT_SIZE (4L*1048576L)
#define SLOT_MB 4
#else
#define SLOT_MB 8
#define SLOT_SIZE (8L*1048576L)
#endif

char *select_bitstream_file(void);
void fetch_rdid(void);
void flash_reset(void);

unsigned char joy_x=100;
unsigned char joy_y=100;

unsigned char latency_code=0xff;
unsigned char reg_cr1=0x00;
unsigned char reg_sr1=0x00;

unsigned char manufacturer;
unsigned short device_id;
unsigned short cfi_data[512];
unsigned short cfi_length=0;

unsigned char reconfig_disabled=0;

unsigned char data_buffer[512];
// Magic string for identifying properly loaded bitstream
unsigned char bitstream_magic[16]=
  // "MEGA65BITSTREAM0";
  { 0x4d, 0x45, 0x47, 0x41, 0x36, 0x35, 0x42, 0x49, 0x54, 0x53, 0x54, 0x52, 0x45, 0x41, 0x4d, 0x30};

unsigned short mb = 0;

unsigned char buffer[512];

short i,x,y,z;
short a1,a2,a3;
unsigned char n=0;

unsigned char safe_lpeek(unsigned long addr)
{
  unsigned char a,b,c;
  a=1; b=2;
  while (a!=b||b!=c) {
    a=lpeek(addr);
    b=lpeek(addr);
    c=lpeek(addr);
  }
  return a;
}

void reconfig_fpga(unsigned long addr)
{

  if (reconfig_disabled) {
    printf("%cERROR: Remember that warning about\n"
	   "having started from JTAG?\n"
	   "I really did mean it, when I said that\n"
	   "it would stop you being able to launch\n"
	   "another core.\n",0x93);
    printf("\nPress any key to return to the menu...\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    while(!PEEK(0xD610)) continue;
    while(PEEK(0xD610)) POKE(0xD610,0);
    printf("%c",0x93);
    return;
  }
  
  // Black screen when reconfiguring
  POKE(0xd020,0); 
  POKE(0xd011,0);
 
  mega65_io_enable();

  // Addresses for WBSTAR are shifted by 8 bits
  POKE(0xD6C8U,(addr>>8)&0xff);
  POKE(0xD6C9U,(addr>>16)&0xff);
  POKE(0xD6CAU,(addr>>24)&0xff);
  POKE(0xD6CBU,0x00);

  // Wait a little while, to make sure that the WBSTAR slot in
  // the reconfig sequence gets set before we instruct the FPGA
  // to reconfigure.
  usleep(255);
  
  // Try to reconfigure
  POKE(0xD6CFU,0x42);
  while(1) {
    POKE(0xD020,PEEK(0xD012));
    POKE(0xD6CFU,0x42);

    // Grey screen if reconfig failing
    POKE(0xd020,0x0d);     
  }
}

unsigned char check_input(char *m)
{
  while(PEEK(0xD610)) POKE(0xD610,0);

  while(*m) {
    // Weird CC65 PETSCII/ASCII fix ups
    if (*m==0x0a) *m=0x0d;
    
    if (!PEEK(0xD610)) continue;
    if (PEEK(0xD610)!=((*m)&0x7f)) {
      return 0;
    }
    POKE(0xD610,0);
    m++;
  }
  return 1;
}

unsigned char video_mode=0,c;
struct m65_tm tm;

char *month_name(int month)
{
  switch(month) {
  case 1: return "Jan";
  case 2: return "Feb";
  case 3: return "Mar";
  case 4: return "Apr";
  case 5: return "May";
  case 6: return "Jun";
  case 7: return "Jul";
  case 8: return "Aug";
  case 9: return "Sep";
  case 10: return "Oct";
  case 11: return "Nov";
  case 12: return "Dec";
  }
  return "???";
}

void main(void)
{
  mega65_io_enable();

  // Disable OSK
  lpoke(0xFFD3615L,0x7F);  

  // Enable VIC-III attributes
  POKE(0xD031,0x20);

  printf("%cWelcome to the MEGA65!\n",0x93);
  printf("\nBefore you go further, there are couple of things you need to do.\n");
  printf("\nPress F1 to cycle through the default   video modes. \n");
  printf("\nIf no picture displays within a few     seconds, press HELP to revert.\n");
  printf("\nPress F3 - F13 to set the time and date.\n");
  printf("\nPress RETURN when done.\n");
 
  while(1) {
    POKE(0x286,1);
    printf("%c\n\n\n\n\n\n\n\n\n\n",0x13);    
    printf("Video: %c",0x12);
    POKE(0x286,7);
    switch(video_mode) {
    case 0: printf("DVI (no sound), NTSC 60Hz       "); break;
    case 1: printf("DVI (no sound), PAL 50Hz        "); break;
    case 2: printf("Enhanced (with sound), NTSC 60Hz"); break;
    case 3: printf("Enhanced (with sound), PAL 50Hz "); break;
    }
    printf("%c\n",0x92);
    POKE(0x286,14);
    printf("       F1\n");
    
    tm.tm_sec=0;
    tm.tm_min=0;
    tm.tm_hour=0;
    tm.tm_mday=0;
    tm.tm_mon=0;
    tm.tm_year=0;
    tm.tm_isdst=0;
    tm.tm_wday=0;

    getrtc(&tm);
    
    POKE(0x286,1);
    printf("\nTime:  ");
    POKE(0x286,7);
    printf("%c%02d:%02d.%02d %02d/%s/%04d%c  ",
	   0x12,tm.tm_hour,tm.tm_min,tm.tm_sec,tm.tm_mday,month_name(tm.tm_mon),tm.tm_year+1900,0x92);
    POKE(0x286,14);
    printf("\n       F3 F5 F7 F9 F11 F13\n");
    POKE(0x286,1);
    printf("\n");

    printf("Press ");
    POKE(0x286,7);
    printf("%cRETURN%c",0x12,0x92);
    POKE(0x286,1);
    printf(" when done to continue.\n");
    
    c=PEEK(0xD610);
    if (c) POKE(0xD610,0);
    switch(c) {
    case 0x1F:
      video_mode=3;
      // FALL THROUGH
    case 0xF1:
      video_mode++; video_mode&=0x03;
      // NTSC / PAL
      if (video_mode&1) POKE(0xD06F,0x00); else POKE(0xD06F,0x80);
      // DVI / Enhanced
      if (video_mode&2) POKE(0xD61A,0x02); else POKE(0xD61A,0x00);
      break;
    case 0xF3: case 0xF4:
      if (c&1) tm.tm_hour++; else tm.tm_hour--;
      if (tm.tm_hour>127) tm.tm_hour=23;
      if (tm.tm_hour>23) tm.tm_hour=0;
      setrtc(&tm);
      break;
    case 0xF5: case 0xF6:
      if (c&1) tm.tm_min++; else tm.tm_min--;
      if (tm.tm_min>127) tm.tm_min=59;
      if (tm.tm_min>59) tm.tm_min=0;
      setrtc(&tm);
      break;
    case 0xF7: case 0xF8:
      if (c&1) tm.tm_sec++; else tm.tm_sec--;
      if (tm.tm_sec>127) tm.tm_sec=59;
      if (tm.tm_sec>59) tm.tm_sec=0;
      setrtc(&tm);
      break;
    case 0xF9: case 0xFA:
      if (c&1) tm.tm_mday++; else tm.tm_mday--;
      if (!tm.tm_mday) tm.tm_mday=31;
      if (tm.tm_mday>127) tm.tm_mday=31;
      if (tm.tm_mday>31) tm.tm_mday=1;
      switch (tm.tm_mon) {
      case 2:
	if (tm.tm_mday>29) tm.tm_mday=1;
	if ((tm.tm_year&3)||(tm.tm_year==0)||(tm.tm_year==200))
	  { if (tm.tm_mday>28) tm.tm_mday=1; }
	break;
      case 4: case 6: case 9: case 11:
	if (tm.tm_mday>30) tm.tm_mday=1;
	break;
      }
      setrtc(&tm);
      break;
    case 0xFB: case 0xFC:
      if (c&1) tm.tm_mon++; else tm.tm_mon--;
      if (!tm.tm_mon) tm.tm_mon=12;
      if (tm.tm_mon>127) tm.tm_mon=12;
      if (tm.tm_mon>12) tm.tm_mon=1;
      // Clip date to fit month
      switch (tm.tm_mon) {
      case 2:
	if (tm.tm_mday>29) tm.tm_mday=29;
	if ((tm.tm_year&3)||(tm.tm_year==0)||(tm.tm_year==200))
	  { if (tm.tm_mday>28) tm.tm_mday=28; }
	break;
      case 4: case 6: case 9: case 11:
	if (tm.tm_mday>30) tm.tm_mday=30;
	break;
      }
      setrtc(&tm);
      break;
    case 0xFD: case 0xFE:
      if (c&1) tm.tm_year++; else tm.tm_year--;
      if (tm.tm_year>299) tm.tm_year=0;
      setrtc(&tm);
      break;
    case 0x0d: case 0x0a:
      // Return = save settings and proceed.
      /*
	We write a valid default configuration sector.
      */

      // First make sure we have the config sector freshly loaded
      lpoke(0xffd3681,0x01);
      lpoke(0xffd3682,0x00);
      lpoke(0xffd3683,0x00);
      lpoke(0xffd3684,0x00);
      lpoke(0xffd3680,0x02);
      while (lpeek(0xffd3680)&0x03) continue;

      // Write version header
      lpoke(0xffd6e00,0x01);
      lpoke(0xffd6e01,0x01);

      // Write PAL/NTSC flag
      if (video_mode&1) lpoke(0xffd6e02,0x00); else lpoke(0xffd6e02,0x80);
      // Write DVI/audio enable flag
      if (video_mode&2) lpoke(0xffd6e0d,0x02); else lpoke(0xffd6e0d,0x00);
      
      // Write onboarding complete byte
      lpoke(0xffd6e0e,0x80);

      // write config sector back
      lpoke(0xffd3680,0x57);  // open write gate
      lpoke(0xffd3680,0x03);  // actually write the sector
      while (lpeek(0xffd3680)&0x03) continue;

      // Now restart by reconfiguring the FPGA
      reconfig_fpga(0);
    }

  }

}




#define SCREEN_ADDRESS 0x0400
#define COLOUR_RAM_ADDRESS 0x1f800

