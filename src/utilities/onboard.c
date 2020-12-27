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
  unsigned char valid;
  unsigned char selected=0;
  
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
    }

  }

}




#define SCREEN_ADDRESS 0x0400
#define COLOUR_RAM_ADDRESS 0x1f800

