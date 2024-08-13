#include <stdio.h>

#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
// #include <sys/filio.h>
#include <sys/ioctl.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/if_ether.h>
#include <netinet/tcp.h>
#include <netinet/ip.h>
#include <string.h>
#include <signal.h>
#include <netdb.h>
#include <time.h>
#include <poll.h>
#include <termios.h>

#include <libpng16/png.h>

FILE *f=NULL;

unsigned char dbg_vals[4096]={0};
unsigned char dbg_states[4096]={0};

int jiffyDOS = 0 ;
int c1581 = 0;

char *sigs[5][24]={
  {"                        ",
   "xxxxxx   xxxxx  xxxxxx  ",
   "xx   xx xx        xx    ",
   "xx   xx xx        xx    ",
   "xxxxxx   xxxxx    xx    ",
   "xx xx        xx   xx    ",
   "xx  xx       xx   xx    ",
   "xx   xx  xxxxx    xx    "},
  {"                        ",
   "  xxx   xxxxxx xx   xx ",
   " xxxxx    xx   xxx  xx ",
   "xx   xx   xx   xxxx xx ",
   "xxxxxxx   xx   xx xxxx ",
   "xx   xx   xx   xx  xxx ",
   "xx   xx   xx   xx   xx ",
   "xx   xx   xx   xx   xx "},
  {"                        ",
   " xxxxx  xx      xx  xx  ",
   "xx   xx xx      xx xx   ",
   "xx      xx      xxxx    ",
   "xx      xx      xxxx    ",
   "xx      xx      xx xx   ",
   "xx   xx xx      xx  xx  ",
   " xxxxx  xxxxxxx xx  xx  "},
  {"                        ",
   "xxxxxx  xxxxxx   xxx   ",
   "xx   xx   xx    xxxxx  ",
   "xx   xx   xx   xx   xx ",
   "xx   xx   xx   xxxxxxx ",
   "xx   xx   xx   xx   xx ",
   "xx   xx   xx   xx   xx ",
   "xxxxxx    xx   xx   xx "},
  {"                        ",
   " xxxxx  xxxxxx   xxxxx  ",
   "xx      xx   xx xx   xx ",
   "xx      xx   xx xx   xx ",
   " xxxxx  xxxxxx  xx   xx ",
   "     xx xx xx   xx  x x ",
   "     xx xx  xx  xx  xxx ",
   " xxxxx  xx   xx  xxxxxxx"}
};

char *digits[10][8]={
  {"        ",
   " xxxxx  ",
   "x    xx ",
   "x   x x ",
   "x  x  x ",
   "x x   x ",
   "xx    x ",
   " xxxxx  "},
  {"        ",
   "  xxx   ",
   " xxxx   ",
   "   xx   ",
   "   xx   ",
   "   xx   ",
   "   xx   ",
   " xxxxxx "},
  {"        ",
   "  xxxx  ",
   " xx  xx ",
   "    xx  ",
   "   xx   ",
   "  xx    ",
   " xx     ",
   "xxxxxxx "},
  {"        ",
   " xxxxx  ",
   "xx   xx ",
   "     xx ",
   "  xxxxx ",
   "     xx ",
   "xx   xx ",
   " xxxxx  "},
  {"        ",
   "xx  xx  ",
   "xx  xx  ",
   "xx  xx  ",
   "xxxxxx  ",
   "    xx  ",
   "    xx  ",
   "    xx  "},
  {"        ",
   "xxxxxxx ",
   "xx      ",
   "xxxxxx  ",
   "     xx ",
   "     xx ",
   "     xx ",
   "xxxxxx  "},
  {"        ",
   " xxxxx  ",
   "xx   xx ",
   "xx      ",
   "xxxxxx  ",
   "xx   xx ",
   "xx   xx ",
   " xxxxx  "},
  {"        ",
   " xxxxx  ",
   "    xx  ",
   "    xx  ",
   "   xx   ",
   "   xx   ",
   "  xx    ",
   "  xx    "},
  {"        ",
   " xxxxx  ",
   "xx   xx ",
   "xx   xx ",
   " xxxxx  ",
   "xx   xx ",
   "xx   xx ",
   " xxxxx  "},
  {"        ",
   " xxxxx  ",
   "xx   xx ",
   "xx   xx ",
   " xxxxxx ",
   "     xx ",
   "xx   xx ",
   " xxxxx  "}
};

#define MAXX 320
#define MAXY 2048

unsigned int pixels[MAXY][MAXX]={0};

/*
  Our waveform displays use 8x8 blocks to show each signal,
  and the simple 8x8 font elements defined above.

  Each row has room for 1020 ~1usec ticks, and is 40 pixels 
  tall.  Thus for all 4096 ticks, we need four such rows. 
 */
void build_image(void)
{
  // Clear image to white initially
  for(int y=0;y<MAXY;y++)
    for(int x=0;x<MAXX;x++)
      pixels[y][x]=0xffffffff;
  
  // Draw signal legend down the left side
  for(int row = 0; ((row+1)*(9*8)) <= MAXY; row++) {
    for(int sig = 0; sig<5; sig++) {
      for (int charrow=0;charrow<8;charrow++) {
	char *bits=sigs[sig][charrow];
	for(int x=0;bits[x];x++) if (bits[x]!=' ') pixels[row*(9*8)+sig*8+charrow][x]=0xff000000;
      }
    }
  }
  
  int x=32;
  int y=0;

  for(int n=0;n<4096;n++) {

    // Draw state numbers under cells

    if (dbg_states[n]) {
      char num[16];
      snprintf(num,16,"%d",dbg_states[n]);
      int yy=y+5*8;
      for(int c=0;num[c];c++) {
	for(int charrow=0;charrow<8;charrow++) {
	  int d=num[c]-'0';
	  if (d>=0&&d<10) {
	    char *r=digits[d][charrow];
	    for(int col=0;col<8;col++) {
	      int pixel=0;
	      if (r[col]==' ') pixel=1; else pixel=0;
	      pixels[yy+col][x+7-charrow]
		=pixel?0xffffffff:0xff000000;
	    }
	  }
	}
	yy+=8;
      }
    }
    
    // Draw signal states
    for(int sig=0;sig<5;sig++) {
      // RST, ATN, CLK, DATA, SRQ

      int controller=5;
      int device=5;

      int v=dbg_vals[n]^0xc0;
      
      switch(sig) {
      case 0: // RST
	controller=(v&0x80);
	device=5;
	break;
      case 1: // ATN
	controller=(v&0x40);
	device=5;
	break;
      case 2: // CLK
	controller=(v&0x10);
	device=v&0x02;
	break;
      case 3: // DATA
	controller=v&0x08;
	device=v&0x01;
	break;
      case 4: // SRQ
	controller=v&0x20;
	device=v&0x04;
	break;
      }

      int colour = 0x000000;
      int voltage = 5;
      
      if (!device) {
	// Device pulling low
	colour = 0xff0000; // BLUE
	voltage=0;
      } else if (!controller) {
	// Controller pulling low
	colour = 0x0000ff; // RED
	voltage=0;
      } else {
	// Neither pulling low
	colour = 0x000000; // BLACK
	voltage=5;
      }

      // Draw colour to indicate who is pulling low
      for(int xx=0;xx<8;xx++) for(int yy=0;yy<7;yy++) pixels[y+sig*8+yy][x+xx]=0xff000000+colour;
      for(int xx=0;xx<8;xx++) pixels[y+sig*8+7][x+xx]=0xff000000;

      // Draw line at top or bottom
      if (voltage) {
	for(int xx=0;xx<8;xx++) pixels[y+sig*8+0][x+xx]=0xff00ffff; // YELLOW
	for(int xx=0;xx<8;xx++) pixels[y+sig*8+1][x+xx]=0xff00ffff; // YELLOW
      } else {
	for(int xx=0;xx<8;xx++) pixels[y+sig*8+5][x+xx]=0xff00ffff; // YELLOW
	for(int xx=0;xx<8;xx++) pixels[y+sig*8+6][x+xx]=0xff00ffff; // YELLOW
      }
    }

    x+=8;
    if (x>=MAXX) {
      x=32; y+=(9*8);
    }
    if (y>(MAXY-(9*8)+1)) break;
  }
}

void write_png(char *filename)
{
  int y;
  png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
  if (!png) {
    fprintf(stderr,"FATAL: png_create_write_struct() failed\n");
    abort();
  }

  png_infop info = png_create_info_struct(png);
  if (!info) {
    fprintf(stderr,"FATAL: png_create_info_struct() failed\n");
    abort();
  }

  if (setjmp(png_jmpbuf(png))) {
    fprintf(stderr,"FATAL: png_jmpbuf() failed\n");
    abort();
  }

  FILE *f = fopen(filename, "wb");
  if (!f) {
    fprintf(stderr,"FATAL: Failed to open '%s' for write\n",filename);
    abort();
  }

  png_init_io(png, f);

  png_set_IHDR(
      png, info, MAXX, MAXY, 8, PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_DEFAULT);

  png_write_info(png, info);

  for (y = 0; y < MAXY; y++) {
    png_write_row(png, (unsigned char *)pixels[y]);
  }
  
  png_write_end(png, info);
  png_destroy_write_struct(&png, &info);

  fclose(f);

  return;
}


int openFile(char *port)
{
  f = fopen(port, "rb");
  if (f == NULL) {
    perror("fopen");
    return -1;
  }

  return 0;
}

long long time_val;
unsigned int atn, clk_c64, clk_1541, data_c64, data_1541, data_dummy;
unsigned int iec_state,instr_num,pc,reg_a;
char time_units[8192];

int bit_num=0;

int getUpdate(void)
{

  int line_len=0;
 char line[1024];

  char bytes[1024];

  while(!feof(f)) {   
    int n = fread(bytes,1,1,f);
    if (n>0) {
      for(int i=0;i<n;i++) {
	int c=bytes[i];
	if (c=='\n'||c=='\r') {
	  if (line_len) {
	    // Parse lines like this:	    
	    // /home/paul/Projects/mega65/mega65-core/src/vhdl/tb_iec_serial.vhdl:%*d:9:@6173ps:(report note): IECBUSSTATE: ATN='1', CLK(c64)='1', CLK(1541)='1', DATA(c64)='1', DATA(1541)='1', DATA(dummy)='1'
	    int r = sscanf(line,"/home/paul/Projects/mega65/mega65-core/src/vhdl/tb_iec_serial.vhdl:%*d:%*d:@%lld%[^:]:(report note): IECBUSSTATE: ATN='%d', CLK(c64)='%d', CLK(1541)='%d', DATA(c64)='%d', DATA(1541)='%d', DATA(dummy)='%d'",
			   &time_val,time_units,
			   &atn,&clk_c64,&clk_1541,&data_c64,&data_1541,&data_dummy);
	    if (strstr(line,"IECBUSSTATE")) fprintf(stderr,"DEBUG: r=%d, Line = '%s'\n",r,line);

	    if (r==8) {
	      int ofs=0;
	      int colons=5;
	      while(colons) if (line[ofs++]==':') colons--;
	      // fprintf(stderr,"%s\n",&line[ofs+1]);
	      return 0;
	    }

	    {
	      char drive_cap[1024];
	      if (sscanf(line,"/home/paul/Projects/mega65/mega65-core/src/vhdl/tb_iec_serial.vhdl:%*d:%*d:@%lld%[^:]:(report note): DRIVEINFO: %[^\n]",&time_val,time_units,drive_cap)==3) {
		fprintf(stderr,"DRIVEINFO: %s\n",drive_cap);		       
		}
	  }
	    
	    if (sscanf(line,"/home/paul/Projects/mega65/mega65-core/src/vhdl/iec_serial.vhdl:%*d:%*d:@%lld%[^:]:(report note): iec_state = %d",
		       &time_val,time_units,&iec_state)==3) {
	      fprintf(stderr,"            iec_state = %d\n",iec_state);
	    }

	    if (strstr(line,"IEC:")) { fprintf(stderr,"%s\n",&line[99]); fflush(stderr); }
	    if (strstr(line,": MOS6522")) {
	      int ofs=0;
	      int colons=5;
	      while(colons) if (line[ofs++]==':') colons--;
	      fprintf(stderr,"%s\n",&line[ofs+1]);
	    }
	    
	    if (sscanf(line,"/home/paul/Projects/mega65/mega65-core/src/vhdl/simple_cpu6502.vhdl:%*d:%*d:@%lld%[^:]:(report note): Instr#:%d PC: $%x, A:%02X",
		       &time_val,time_units,&instr_num,&pc,&reg_a)==5) {

	      pc=pc &0xffff;
	      
	      switch(pc) {
	      case 0xCFB7: fprintf(stderr,"$%04X            1541: Write to channel \n",pc); break;
	      case 0xCFE8: fprintf(stderr,"$%04X            1541: Check for end of command \n",pc); break;
	      case 0xCFED: fprintf(stderr,"$%04X            1541: L45 (Indicate command waiting for processing) \n",pc); break;
	      }
	      if (c1581) {
		// From chapter 10 of 1581 user guide
		// and also from the 1581 ROM routine list in https://www.lyonlabs.org/commodore/onrequest/The_1581_Toolkit.pdf
		  switch(pc) {

		  case 0x8000: fprintf(stderr,"$%04X        1581: CHECKSUM CHECKSUM used by routines to verify the integrity of the DOS ROMs\n",pc); break;
		  case 0x8004: fprintf(stderr,"$%04X        1581: EXECMD Execute command string\n",pc); break;
		  case 0x804C: fprintf(stderr,"$%04X        1581: ENDCMD End of computer command\n",pc); break;
		  case 0x8050: fprintf(stderr,"$%04X        1581: ENDO Generate an error message\n",pc); break;
		  case 0x805B: fprintf(stderr,"$%04X        1581: END1 End command but don't write BAM\n",pc); break;
		  case 0x8067: fprintf(stderr,"$%04X        1581: END2 End command ignore error\n",pc); break;
		  case 0x8071: fprintf(stderr,"$%04X        1581: CLRCMD End command no error message prepared\n",pc); break;
		  case 0x8085: fprintf(stderr,"$%04X        1581: SCAN Clear command buffer\n",pc); break;
		  case 0x8099: fprintf(stderr,"$%04X        1581: SCANCOLON Look for \":\" and drive number in command string\n",pc); break;
		  case 0x80A2: fprintf(stderr,"$%04X        1581: TEST2FILES Look for colon in command string\n",pc); break;
		  case 0x811C: fprintf(stderr,"$%04X        1581: SCANCHARINA Test command with two filenames for syntax\n",pc); break;
		  case 0x8165: fprintf(stderr,"$%04X        1581: LOOKCMD Search input line for character in the accumulator\n",pc); break;
		  case 0x81AF: fprintf(stderr,"$%04X        1581: CLRCMDVAR Set all flags and look at command string table\n",pc); break;
		  case 0x81E5: fprintf(stderr,"$%04X        1581: FLASHOFF Clear and set back table, pointers and flags\n",pc); break;
		  case 0x81F1: fprintf(stderr,"$%04X        1581: FLASHON Flash error LED off\n",pc); break;
		  case 0x81FD: fprintf(stderr,"$%04X        1581: GETDRV Get drive number and set into file table\n",pc); break;
		  case 0x8224: fprintf(stderr,"$%04X        1581: GETDRVFROMCMD Get drive number from command string\n",pc); break;
		  case 0x8251: fprintf(stderr,"$%04X        1581: INITWITHLEDON Initialize drive and switch LED on\n",pc); break;
		  case 0x8270: fprintf(stderr,"$%04X        1581: SETFILE Set and determine file type\n",pc); break;
		  case 0x8295: fprintf(stderr,"$%04X        1581: CHKDRV Test valid drive number\n",pc); break;
		  case 0x82A2: fprintf(stderr,"$%04X        1581: INTDRVFNAME Initialize drive given in filename\n",pc); break;
		  case 0x82B9: fprintf(stderr,"$%04X        1581: FINDFILE Look for file entry in the directory\n",pc); break;
		  case 0x8327: fprintf(stderr,"$%04X        1581: SCANDIR Search directory entry\n",pc); break;
		  case 0x8336: fprintf(stderr,"$%04X        1581: SCANNEXT Search next entry\n",pc); break;
		  case 0x83D7: fprintf(stderr,"$%04X        1581: NEWSEARCH Reinitialize file search flags\n",pc); break;
		  case 0x83E2: fprintf(stderr,"$%04X        1581: QUITSEARCH Quit search for filename\n",pc); break;
		  case 0x83FA: fprintf(stderr,"$%04X        1581: WCARD 1581 extended wild card check\n",pc); break;
		  case 0x8424: fprintf(stderr,"$%04X        1581: SETSEARCH Set indicator to search in directory\n",pc); break;
		  case 0x84AE: fprintf(stderr,"$%04X        1581: INTDSK Initialize diskette\n",pc); break;
		  case 0x84EE: fprintf(stderr,"$%04X        1581: WRTNAME Copy filename from input buffer to directory buffer\n",pc); break;
		  case 0x8508: fprintf(stderr,"$%04X        1581: COPYDATA Copy part of the input buffer and the current data buffer\n",pc); break;
		  case 0x8526: fprintf(stderr,"$%04X        1581: FNAMELEN Search length of filename in input buffer (starting position in .X)\n",pc); break;
		  case 0x854D: fprintf(stderr,"$%04X        1581: READFROMDIR Read file from directory\n",pc); break;
		  case 0x855D: fprintf(stderr,"$%04X        1581: DIROUTPUT Establish directory for output to buffer\n",pc); break;
		  case 0x861C: fprintf(stderr,"$%04X        1581: DELBUF Delete buffer for data name with empty character\n",pc); break;
		  case 0x868B: fprintf(stderr,"$%04X        1581: BLKFRE Set up closing line of directory with \"BLOCKS FREE\" message\n",pc); break;
		  case 0x867C: fprintf(stderr,"$%04X        1581: BLKFREMSG \"BLOCKS FREE\" message\n",pc); break;
		  case 0x8688: fprintf(stderr,"$%04X        1581: SCRATCH Scratch command - \"S\"\n",pc); break;
		  case 0x86DB: fprintf(stderr,"$%04X        1581: FRESIDE Free side sector blocks in a REL file\n",pc); break;
		  case 0x8713: fprintf(stderr,"$%04X        1581: FREEUP Pursue sectors on hand and free up in BAM\n",pc); break;
		  case 0x8732: fprintf(stderr,"$%04X        1581: FREEUP1 Free sector in BAM and continue\n",pc); break;
		  case 0x873B: fprintf(stderr,"$%04X        1581: DELFILE File entry in file type of directory marked as scratched\n",pc); break;
		  case 0x8746: fprintf(stderr,"$%04X        1581: NEW New routine for 1581 \"NEW\" command (format disk) - \"N\"\n",pc); break;
		  case 0x876E: fprintf(stderr,"$%04X        1581: COPY Copy command for copying files - \"C\"\n",pc); break;
		  case 0x8793: fprintf(stderr,"$%04X        1581: COPYFILE Copy files\n",pc); break;
		  case 0x87F4: fprintf(stderr,"$%04X        1581: COPYSING Copy single files\n",pc); break;
		  case 0x8800: fprintf(stderr,"$%04X        1581: COPYMULT Copy multiple files\n",pc); break;
		  case 0x8841: fprintf(stderr,"$%04X        1581: OPENREAD Open channel to read file\n",pc); break;
		  case 0x8876: fprintf(stderr,"$%04X        1581: GETBYTE Read a byte from a file\n",pc); break;
		  case 0x8895: fprintf(stderr,"$%04X        1581: COPYREL Copy a relative file\n",pc); break;
		  case 0x88C5: fprintf(stderr,"$%04X        1581: RENAME Rename a file command - IIRM\n",pc); break;
		  case 0x8903: fprintf(stderr,"$%04X        1581: CHKEXIST See if file entry exists\n",pc); break;
		  case 0x891E: fprintf(stderr,"$%04X        1581: CMPNAMES Compare with two filenames\n",pc); break;
		  case 0x892F: fprintf(stderr,"$%04X        1581: MEMCMD Memory command routines\n",pc); break;
		  case 0x8954: fprintf(stderr,"$%04X        1581: MEMREAD Memory read command get a byte from drive\n",pc); break;
		  case 0x8983: fprintf(stderr,"$%04X        1581: MEMWRT Memory write command write a byte into drive memory - \"M-W\"\n",pc); break;
		  case 0x898F: fprintf(stderr,"$%04X        1581: USER User commands to start programs in DOS buffer at $0500\n",pc); break;
		  case 0x8996: fprintf(stderr,"$%04X        1581: BURSTCMD Routine for burst user commands (\"U0\")\n",pc); break;
		  case 0x89CC: fprintf(stderr,"$%04X        1581: EXECUSER Execute a user command\n",pc); break;
		  case 0x89E4: fprintf(stderr,"$%04X        1581: DIRECT \"#\" command - open a direct channel\n",pc); break;
		  case 0x8A5D: fprintf(stderr,"$%04X        1581: BLKCMDS Block commands\n",pc); break;
		  case 0x8A9F: fprintf(stderr,"$%04X        1581: BLKPARAM Get and set block command parameters\n",pc); break;
		  case 0x8AAC: fprintf(stderr,"$%04X        1581: TESTPARAM Test block command parameters\n",pc); break;
		  case 0x8AD0: fprintf(stderr,"$%04X        1581: ASCII2BIN Convert/set block command parameters from ASCII to binary\n",pc); break;
		  case 0x8B20: fprintf(stderr,"$%04X        1581: BINVAL Binary value table $01, $0A, $64\n",pc); break;
		  case 0x8B23: fprintf(stderr,"$%04X        1581: BLKFRE Block free command - free a block in the BAM - \"B-F\"\n",pc); break;
		  case 0x8B2F: fprintf(stderr,"$%04X        1581: BLKALLOC Block allocate command - mark a block in the BAM as used - \"B-A\"\n",pc); break;
		  case 0x8B65: fprintf(stderr,"$%04X        1581: TESTBR Test block read (\"B-R\") parameters and read sector into buffer\n",pc); break;
		  case 0x8B6B: fprintf(stderr,"$%04X        1581: GETBUFBYTE Get byte from buffer\n",pc); break;
		  case 0x8B71: fprintf(stderr,"$%04X        1581: READSECINTPTR Read sector from diskette to buffer and initialize pointer\n",pc); break;
		  case 0x8B85: fprintf(stderr,"$%04X        1581: BLKREAD Read sector from diskette for \"B-R\" command\n",pc); break;
		  case 0x8B8E: fprintf(stderr,"$%04X        1581: BREXTEND Block shift read command - extended track reader\n",pc); break;
		  case 0x8B9A: fprintf(stderr,"$%04X        1581: USER1CMD Routine for \"U1\" command read sector from diskette\n",pc); break;
		  case 0x8BAE: fprintf(stderr,"$%04X        1581: BLKWRT Routine for block write command \"B-W\"\n",pc); break;
		  case 0x8BD1: fprintf(stderr,"$%04X        1581: BWEXTEND Block shift write command - extended track writer\n",pc); break;
		  case 0x8BD7: fprintf(stderr,"$%04X        1581: USER2CMD Routine for \"U2\" command write sector to diskette\n",pc); break;
		  case 0x8BE3: fprintf(stderr,"$%04X        1581: BLKEXEC Routine for block execute command read sector and execute code in DOS buffer \"B-E\"\n",pc); break;
		  case 0x8BFA: fprintf(stderr,"$%04X        1581: BLKPTR Routine for block pointer command set buffer pointer (\"B-P\")\n",pc); break;
		  case 0x8C0F: fprintf(stderr,"$%04X        1581: ALLOCOPEN Allocate buffer open channel\n",pc); break;
		  case 0x8C2F: fprintf(stderr,"$%04X        1581: CHKPARAM And test parameters for valid sector assignment\n",pc); break;
		  case 0x8C44: fprintf(stderr,"$%04X        1581: SKIPILLEGAL Same as above, but does not flag illegal tracks and/or sectors\n",pc); break;
		  case 0x8C5C: fprintf(stderr,"$%04X        1581: ALLOCBUF Allocate RAM buffer - .A contains the buffer number (1 = buffer 0, 2 = buffer 2, etc.)\n",pc); break;
		  case 0x8C61: fprintf(stderr,"$%04X        1581: BLKCMDTAB Block command table \"AFRWEPRW*\"\n",pc); break;
		  case 0x8C6B: fprintf(stderr,"$%04X        1581: BLKADDR Addresses of 10 block commands in low, high byte format\n",pc); break;
		  case 0x8C7F: fprintf(stderr,"$%04X        1581: AUTHOR Block-? command author/designer message in error channel - \"B-?\"\n",pc); break;
		  case 0x8C84: fprintf(stderr,"$%04X        1581: DEDICATE Block-* command dedication message in error channel - \"B-*\"\n",pc); break;
		  case 0x8C89: fprintf(stderr,"$%04X        1581: GETREC Get record relative file\n",pc); break;
		  case 0x8CC1: fprintf(stderr,"$%04X        1581: NUMBYTES Compute number of bytes up to record\n",pc); break;
		  case 0x8D06: fprintf(stderr,"$%04X        1581: DIV254 Division of math register by 254 (sector length)\n",pc); break;
		  case 0x8D09: fprintf(stderr,"$%04X        1581: DIV120 Division of math register by 120 (record entries in side-sector)\n",pc); break;
		  case 0x8D38: fprintf(stderr,"$%04X        1581: CLRMATH1 Clear math register 1\n",pc); break;
		  case 0x8D41: fprintf(stderr,"$%04X        1581: MULTTIMES4 Multiply math register 2 four times\n",pc); break;
		  case 0x8D44: fprintf(stderr,"$%04X        1581: DOUBLEREG2 Double math register 2\n",pc); break;
		  case 0x8D4C: fprintf(stderr,"$%04X        1581: ADD1TO2 Add math register 2 to math register 1\n",pc); break;
		  case 0x8D59: fprintf(stderr,"$%04X        1581: INTBUFCHAN Initialize buffer channel table\n",pc); break;
		  case 0x8D68: fprintf(stderr,"$%04X        1581: TESTCHANNUM Test channel number in buffer channel table\n",pc); break;
		  case 0x8D7D: fprintf(stderr,"$%04X        1581: MAMBUF Manage and assign buffers\n",pc); break;
		  case 0x8E3C: fprintf(stderr,"$%04X        1581: FINDFREBUF Look for a free buffer\n",pc); break;
		  case 0x8E4D: fprintf(stderr,"$%04X        1581: SETBUFSTATUS Toggle buffer from active to passive and back again\n",pc); break;
		  case 0x8E5C: fprintf(stderr,"$%04X        1581: WRTINTERNAL Write bytes over internal channel into buffer\n",pc); break;
		  case 0x8E78: fprintf(stderr,"$%04X        1581: WRT2FILE Write byte into file\n",pc); break;
		  case 0x8EB1: fprintf(stderr,"$%04X        1581: WRT2BUF Write byte in current buffer\n",pc); break;
		  case 0x8EC5: fprintf(stderr,"$%04X        1581: INITIALIZE Initialize command - \"I0\"\n",pc); break;
		  case 0x8FD6: fprintf(stderr,"$%04X        1581: READ2BUF Read sector from diskette to buffer\n",pc); break;
		  case 0x8FEA: fprintf(stderr,"$%04X        1581: READNEXT Read in given sector and sector after that\n",pc); break;
		  case 0x8FFE: fprintf(stderr,"$%04X        1581: READSEC Read sector from disk\n",pc); break;
		  case 0x9002: fprintf(stderr,"$%04X        1581: WRTSEC Write sector to disk\n",pc); break;
		  case 0x9027: fprintf(stderr,"$%04X        1581: OPENREAD Open channel for reading\n",pc); break;
		  case 0x9042: fprintf(stderr,"$%04X        1581: SCANANDOPEN Search for and open channel\n",pc); break;
		  case 0x905F: fprintf(stderr,"$%04X        1581: GETFILETYPE Get current file type\n",pc); break;
		  case 0x9069: fprintf(stderr,"$%04X        1581: GETCHANANDBUFF Get channel and matching buffer number\n",pc); break;
		  case 0x9071: fprintf(stderr,"$%04X        1581: GETFROMBUF Get byte from current buffer\n",pc); break;
		  case 0x909B: fprintf(stderr,"$%04X        1581: GETFROMFILE Get byte from file\n",pc); break;
		  case 0x9112: fprintf(stderr,"$%04X        1581: WRT2FILE Write byte in file\n",pc); break;
		  case 0x9138: fprintf(stderr,"$%04X        1581: NEXTCHAR Set current buffer pointer to next character\n",pc); break;
		  case 0x9145: fprintf(stderr,"$%04X        1581: SWITCHAUTO Switch for autoloader boot on initialize or burst inquiry/query\n",pc); break;
		  case 0x9157: fprintf(stderr,"$%04X        1581: SCANWRTCHAN Look for write channel and buffer\n",pc); break;
		  case 0x915A: fprintf(stderr,"$%04X        1581: SCANREADCHAN Look for read channel and buffer\n",pc); break;
		  case 0x919E: fprintf(stderr,"$%04X        1581: FRECHAN Free up channel\n",pc); break;
		  case 0x91CE: fprintf(stderr,"$%04X        1581: FREBUFCHAN Free up buffer and corresponding channel\n",pc); break;
		  case 0x9204: fprintf(stderr,"$%04X        1581: SCAN4BUF Look for buffer\n",pc); break;
		  case 0x9228: fprintf(stderr,"$%04X        1581: SCAN4FREBUF Look for free buffer\n",pc); break;
		  case 0x923E: fprintf(stderr,"$%04X        1581: FREINACT Free up all inactive buffers\n",pc); break;
		  case 0x9252: fprintf(stderr,"$%04X        1581: FREEINDEX Free up buffer index\n",pc); break;
		  case 0x9262: fprintf(stderr,"$%04X        1581: CLOSECHAN Close channels 0 to 14\n",pc); break;
		  case 0x926E: fprintf(stderr,"$%04X        1581: FREEALLCHAN Free up all channels on current drive\n",pc); break;
		  case 0x9291: fprintf(stderr,"$%04X        1581: GETBUFF Get a buffer\n",pc); break;
		  case 0x92DB: fprintf(stderr,"$%04X        1581: LAYOUTFREE Seek and layout a free channel\n",pc); break;
		  case 0x92F4: fprintf(stderr,"$%04X        1581: GETFROMCHAN Get a byte from a channel\n",pc); break;
		  case 0x9303: fprintf(stderr,"$%04X        1581: READFROMFILE Read byte from a file\n",pc); break;
		  case 0x933A: fprintf(stderr,"$%04X        1581: READFROMREL Get byte from a relative file\n",pc); break;
		  case 0x9348: fprintf(stderr,"$%04X        1581: GETNEXT Get next byte from file\n",pc); break;
		  case 0x934A: fprintf(stderr,"$%04X        1581: GETCURREN Get current byte from file\n",pc); break;
		  case 0x9370: fprintf(stderr,"$%04X        1581: READERRCHAN Read error channel\n",pc); break;
		  case 0x9396: fprintf(stderr,"$%04X        1581: ERRPTR Set pointer for error message pointer\n",pc); break;
		  case 0x939F: fprintf(stderr,"$%04X        1581: INITERRCHAN Initialize error message channel\n",pc); break;
		  case 0x93AA: fprintf(stderr,"$%04X        1581: READNXTSEC Read next sector of a file\n",pc); break;
		  case 0x93B0: fprintf(stderr,"$%04X        1581: JOBREAD Take job code for read sector ($80)\n",pc); break;
		  case 0x93C1: fprintf(stderr,"$%04X        1581: JOBWRT Take job code for write sector ($90)\n",pc); break;
		  case 0x93CF: fprintf(stderr,"$%04X        1581: OPENSEQREAD Open sequential file for reading\n",pc); break;
		  case 0x93E0: fprintf(stderr,"$%04X        1581: OPENSEQWRITE Open file for writing\n",pc); break;
		  case 0x93E7: fprintf(stderr,"$%04X        1581: WRTNEXTDIR Write next directory sector\n",pc); break;
		  case 0x9422: fprintf(stderr,"$%04X        1581: SETBUFPTR1 Set buffer pointer to given position\n",pc); break;
		  case 0x9434: fprintf(stderr,"$%04X        1581: CLOSEINTERNAL Close internal channels\n",pc); break;
		  case 0x9442: fprintf(stderr,"$%04X        1581: CURRENTBUF Determine current buffer pointer\n",pc); break;
		  case 0x9445: fprintf(stderr,"$%04X        1581: SETBUFPTR2 Set buffer pointer (buffer number in .A)\n",pc); break;
		  case 0x9450: fprintf(stderr,"$%04X        1581: GETBUFBYTE Read any byte from buffer (.A must contain position of the character)\n",pc); break;
		  case 0x9460: fprintf(stderr,"$%04X        1581: CHKTRKSEC Test for valid track and sector numbers then set job code\n",pc); break;
		  case 0x94A8: fprintf(stderr,"$%04X        1581: GETTRKSEC Get track and sector of current job from job memory\n",pc); break;
		  case 0x94B5: fprintf(stderr,"$%04X        1581: RANGECHK Check current track and sector for allowable range\n",pc); break;
		  case 0x94CB: fprintf(stderr,"$%04X        1581: FALSEFORMAT Display error message for false format\n",pc); break;
		  case 0x94D3: fprintf(stderr,"$%04X        1581: SENDJOBCURBUF Send job for current buffer to job loop\n",pc); break;
		  case 0x94DE: fprintf(stderr,"$%04X        1581: READNWAIT Send job code for read to job loop and wait until execution\n",pc); break;
		  case 0x94E2: fprintf(stderr,"$%04X        1581: WRTNWAIT Same as above except write\n",pc); break;
		  case 0x94E4: fprintf(stderr,"$%04X        1581: EXECJOB Execute job for current drive (job code in .A)\n",pc); break;
		  case 0x94E6: fprintf(stderr,"$%04X        1581: EXECJOB2 Execute job code (job code in .A, buffer number in .X)\n",pc); break;
		  case 0x94E8: fprintf(stderr,"$%04X        1581: EXECJOB3 Execute job\n",pc); break;
		  case 0x94ED: fprintf(stderr,"$%04X        1581: JOBDONE Wait until job is executed and an error message is prepared\n",pc); break;
		  case 0x94F8: fprintf(stderr,"$%04X        1581: SUPERVISE Supervise the current job run\n",pc); break;
		  case 0x951A: fprintf(stderr,"$%04X        1581: NXTRKONERR Set head to next track after a read error - search some more\n",pc); break;
		  case 0x9564: fprintf(stderr,"$%04X        1581: WAITTILDONE Job code executes until successful or until counter in $30 = 0\n",pc); break;
		  case 0x9585: fprintf(stderr,"$%04X        1581: SENDCURRENT Send current track and sector numbers to job loop\n",pc); break;
		  case 0x9588: fprintf(stderr,"$%04X        1581: SENDTRKSEC Send track and sector numbers to job loop (buffer in .A)\n",pc); break;
		  case 0x959D: fprintf(stderr,"$%04X        1581: DIRECTCALL Direct 1581 controller call\n",pc); break;
		  case 0x95AB: fprintf(stderr,"$%04X        1581: CLOSEFILE Close a file entry in the directory\n",pc); break;
		  case 0x9678: fprintf(stderr,"$%04X        1581: OPENCMD Take on open command with a secondary address 0 to 14\n",pc); break;
		  case 0x97A2: fprintf(stderr,"$%04X        1581: SAVEREPLACE Overwrite corresponding file entry\n",pc); break;
		  case 0x984D: fprintf(stderr,"$%04X        1581: OPENREADFILE Open a file for reading\n",pc); break;
		  case 0x9890: fprintf(stderr,"$%04X        1581: OPENWRTFILE Open a file for writing\n",pc); break;
		  case 0x98AB: fprintf(stderr,"$%04X        1581: SETCMD Set up file type and file operation as command string\n",pc); break;
		  case 0x98CC: fprintf(stderr,"$%04X        1581: APPEND2FILE Prepare file for append\n",pc); break;
		  case 0x98F7: fprintf(stderr,"$%04X        1581: XMITDIR Transmit directory to computer\n",pc); break;
		  case 0x995C: fprintf(stderr,"$%04X        1581: CLOSEAFILE Close a file\n",pc); break;
		  case 0x9986: fprintf(stderr,"$%04X        1581: CLOSEALL Close all files\n",pc); break;
		  case 0x999F: fprintf(stderr,"$%04X        1581: CLOSE2ND Files declared through secondary address closed\n",pc); break;
		  case 0x9A2A: fprintf(stderr,"$%04X        1581: WRTLASTSEC Write the last sector of a file to diskette\n",pc); break;
		  case 0x9A72: fprintf(stderr,"$%04X        1581: CLOSEWRT Close directory entry after write operation\n",pc); break;
		  case 0x9B0D: fprintf(stderr,"$%04X        1581: OPENREADCHAN Open channel to read file\n",pc); break;
		  case 0x9B9B: fprintf(stderr,"$%04X        1581: INITOPENPTR Initialize channel open pointer\n",pc); break;
		  case 0x9BC3: fprintf(stderr,"$%04X        1581: OPENWRTCHAN Open channel to write to a file\n",pc); break;
		  case 0x9C82: fprintf(stderr,"$%04X        1581: SETRELSS Set up a REL file side sector\n",pc); break;
		  case 0x9CCA: fprintf(stderr,"$%04X        1581: WRT2SS Write a byte to current side sector\n",pc); break;
		  case 0x9CD3: fprintf(stderr,"$%04X        1581: CHANINFT Channel number in file type flag set (carry = 1) or cleared (carry = 0)\n",pc); break;
		  case 0x9CD5: fprintf(stderr,"$%04X        1581: CHFT1 Value combined in file type (bit = 1 is set)\n",pc); break;
		  case 0x9CDB: fprintf(stderr,"$%04X        1581: CHFT2 Remove value from the file type flag (bit = 1 is taken out/not set)\n",pc); break;
		  case 0x9CE4: fprintf(stderr,"$%04X        1581: CHFT3 Check for set file type flag (the flag value is in .A)\n",pc); break;
		  case 0x9CE9: fprintf(stderr,"$%04X        1581: CHFT4 Check to see if job code is set up for writing\n",pc); break;
		  case 0x9CF5: fprintf(stderr,"$%04X        1581: TESTFPTR Test file pointer\n",pc); break;
		  case 0x9D2E: fprintf(stderr,"$%04X        1581: BUF2DSK Write buffer to disk\n",pc); break;
		  case 0x9D3A: fprintf(stderr,"$%04X        1581: SETCHAIN Set chained bytes which point to the next sector\n",pc); break;
		  case 0x9D49: fprintf(stderr,"$%04X        1581: GETCHAIN Get linked bytes which point to the next sector\n",pc); break;
		  case 0x9D56: fprintf(stderr,"$%04X        1581: SETENDLNK Set sector link bytes as last sector in chain of linked bytes and/or sectors\n",pc); break;
		  case 0x9D69: fprintf(stderr,"$%04X        1581: BUFPTRO Set current buffer pointer to zero\n",pc); break;
		  case 0x9D79: fprintf(stderr,"$%04X        1581: GETCURTRKSEC Get current track and sector of current job/get chan of current secondary address\n",pc); break;
		  case 0x9D7C: fprintf(stderr,"$%04X        1581: GETCUR2 Get track and sector of current job/determine buffer\n",pc); break;
		  case 0x9D8E: fprintf(stderr,"$%04X        1581: SENDJOB Give job codes to job loop\n",pc); break;
		  case 0x9DCE: fprintf(stderr,"$%04X        1581: NXTLINK Next sectors parameters set by linked bytes that are on hand\n",pc); break;
		  case 0x9DDE: fprintf(stderr,"$%04X        1581: BUFCOPY Copy file from one buffer to another buffer. The .A contains the number of bytes to transfer, .YR is the source buffer number, and .XR is the destination buffer number.\n",pc); break;
		  case 0x9DFA: fprintf(stderr,"$%04X        1581: CLRBUFF Clear the buffer number in .A with zeros\n",pc); break;
		  case 0x9E0B: fprintf(stderr,"$%04X        1581: SETSSNUM Get the number of the current side sector\n",pc); break;
		  case 0x9E15: fprintf(stderr,"$%04X        1581: SETBUFPTR Set the buffer pointers $64/$65 to any position in the buffer\n",pc); break;
		  case 0x9E23: fprintf(stderr,"$%04X        1581: SETBUFPTR Set the buffer pointer\n",pc); break;
		  case 0x9E32: fprintf(stderr,"$%04X        1581: READSIDE Read a side sector into a buffer and set up pointers\n",pc); break;
		  case 0x9E56: fprintf(stderr,"$%04X        1581: READSEC Read a sector - the buffer pointer of the current buffer must use the track and sector parameters of the link bytes\n",pc); break;
		  case 0x9E75: fprintf(stderr,"$%04X        1581: SETSSPTR Set the side sector pointer\n",pc); break;
		  case 0x9E7D: fprintf(stderr,"$%04X        1581: CALCNUMSS Calculate the number of side sectors in a relative file\n",pc); break;
		  case 0x9EE4: fprintf(stderr,"$%04X        1581: SSSTATUS Test status of a side sector\n",pc); break;
		  case 0x9F11: fprintf(stderr,"$%04X        1581: CURBUF Determine number of the current buffer\n",pc); break;
		  case 0x9F1C: fprintf(stderr,"$%04X        1581: CURBUFST Get current buffer status\n",pc); break;
		  case 0x9F33: fprintf(stderr,"$%04X        1581: BUFFREORNOT Test whether buffer is free\n",pc); break;
		  case 0x9F3E: fprintf(stderr,"$%04X        1581: TWOBUFF Activate buffers for two buffer operations\n",pc); break;
		  case 0x9F4C: fprintf(stderr,"$%04X        1581: WRTREC Write a record for a relative file\n",pc); break;
		  case 0x9FB6: fprintf(stderr,"$%04X        1581: PTR2LAST Set pointer to last character\n",pc); break;
		  case 0x9FBF: fprintf(stderr,"$%04X        1581: PREPRECSEC Prepare sector of the record\n",pc); break;
		  case 0x9FFC: fprintf(stderr,"$%04X        1581: WRTRECCHAR Write a character of the record into the buffer\n",pc); break;
		  case 0xA033: fprintf(stderr,"$%04X        1581: WRTREC2DATABUF Write record to the data buffer\n",pc); break;
		  case 0xA07B: fprintf(stderr,"$%04X        1581: FILREC Fill the rest of a record with empty bytes ($00/0)\n",pc); break;
		  case 0xA08D: fprintf(stderr,"$%04X        1581: DATAALT Flag for buffer data altered is set\n",pc); break;
		  case 0xA09C: fprintf(stderr,"$%04X        1581: DATANOTALT Flag for buffer data altered is cleared\n",pc); break;
		  case 0xA0A6: fprintf(stderr,"$%04X        1581: GETFROMREC Get a byte from a record\n",pc); break;
		  case 0xA0E1: fprintf(stderr,"$%04X        1581: OUTPUTAREC Get a record and output it\n",pc); break;
		  case 0xA0EC: fprintf(stderr,"$%04X        1581: RECNOTHERE Record not present error\n",pc); break;
		  case 0xA0FD: fprintf(stderr,"$%04X        1581: LSTRECCHAR Set pointer to last character of the record\n",pc); break;
		  case 0xA143: fprintf(stderr,"$%04X        1581: FINDENDREC Search for the end of a record\n",pc); break;
		  case 0xA15C: fprintf(stderr,"$%04X        1581: FINDENDREL Search for the end of a relative file\n",pc); break;
		  case 0xA1A1: fprintf(stderr,"$%04X        1581: RECORD Record command routine (\"P\")\n",pc); break;
		  case 0xA20D: fprintf(stderr,"$%04X        1581: READREC Read a record into the buffer\n",pc); break;
		  case 0xA235: fprintf(stderr,"$%04X        1581: READRECSEC Read the record sector contained in the buffer\n",pc); break;
		  case 0xA273: fprintf(stderr,"$%04X        1581: CHKSEC Check to see if sector is already in the buffer\n",pc); break;
		  case 0xA298: fprintf(stderr,"$%04X        1581: ADDREC Enter a new record in the sector\n",pc); break;
		  case 0xA2BC: fprintf(stderr,"$%04X        1581: CALCRECPOS Calculate position of a new record in the sector\n",pc); break;
		  case 0xA2D6: fprintf(stderr,"$%04X        1581: INSERTNEWREC Insert a new record in a relative file\n",pc); break;
		  case 0xA459: fprintf(stderr,"$%04X        1581: NEWSS Prepare a new side sector\n",pc); break;
		  case 0xA547: fprintf(stderr,"$%04X        1581: SUPERSS Routines for handling super side sectors\n",pc); break;
		    //		  case 0xA602: fprintf(stderr,"$%04X        1581: ERRMSGS Error messages stored as ASCII text\n",pc); break;
		  case 0xA602: fprintf(stderr,"$%04X        1581: E00 Error number \"00\" text \"OK\"\n",pc); break;
		  case 0xA606: fprintf(stderr,"$%04X        1581: E02 Error number \"02\" text \"Partition Selected\"\n",pc); break;
		  case 0xA61A: fprintf(stderr,"$%04X        1581: E20ETC Error numbers \"20-24,27\" text \"Read Error\"\n",pc); break;
		  case 0xA625: fprintf(stderr,"$%04X        1581: E52 Error number \"52\" text \"File Too Large\"\n",pc); break;
		  case 0xA631: fprintf(stderr,"$%04X        1581: E50 Error number \"50\" text \"Record Not Present\"\n",pc); break;
		  case 0xA63C: fprintf(stderr,"$%04X        1581: E51 Error number \"51\" text \"Overflow in Record\"\n",pc); break;
		  case 0xA649: fprintf(stderr,"$%04X        1581: E25 Error number \"25\" text \"Write Error\"\n",pc); break;
		  case 0xA64D: fprintf(stderr,"$%04X        1581: E26 Error number \"26\" text \"Write Protect On\"\n",pc); break;
		  case 0xA65A: fprintf(stderr,"$%04X        1581: E29 Error number \"29\" text \"Disk ID Mismatch\"\n",pc); break;
		  case 0xA66C: fprintf(stderr,"$%04X        1581: E30ETC Error number \"30-34\" text \"Syntax Error\"\n",pc); break;
		  case 0xA660: fprintf(stderr,"$%04X        1581: E60 Error number \"60\" text \"Write File Open\"\n",pc); break;
		  case 0xA670: fprintf(stderr,"$%04X        1581: E63 Error number \"63\" text \"File Exists\"\n",pc); break;
		  case 0xA679: fprintf(stderr,"$%04X        1581: E64 Error number \"64\" text \"File Type Mismatch\"\n",pc); break;
		  case 0xA681: fprintf(stderr,"$%04X        1581: E65 Error number \"65\" text \"No Block\"\n",pc); break;
		  case 0xA68A: fprintf(stderr,"$%04X        1581: E66ETC Error number \"66-67\" text \"Illegal Track or Sector\"\n",pc); break;
		  case 0xA6A3: fprintf(stderr,"$%04X        1581: E61 Error number \"61\" text \"File Not Open\"\n",pc); break;
		  case 0xA6A7: fprintf(stderr,"$%04X        1581: E39/62 Error number \"39,62\" text \"File Not Found\"\n",pc); break;
		  case 0xA6AC: fprintf(stderr,"$%04X        1581: E01 Error number \"01\" text \"Files Scratched\"\n",pc); break;
		  case 0xA6B9: fprintf(stderr,"$%04X        1581: E70 Error number \"70\" text \"No Channel\"\n",pc); break;
		  case 0xA6C4: fprintf(stderr,"$%04X        1581: E71 Error number \"71\" text \"Directory Error\"\n",pc); break;
		  case 0xA6C9: fprintf(stderr,"$%04X        1581: E72 Error number \"72\" text \"Disk Full\"\n",pc); break;
		  case 0xA6D0: fprintf(stderr,"$%04X        1581: E73 Error number \"73\" text \"Copyright CBM DOS V10 1581\"\n",pc); break;
		  case 0xA6EB: fprintf(stderr,"$%04X        1581: E74 Error number \"74\" text \"Drive Not Ready\"\n",pc); break;
		  case 0xA6F8: fprintf(stderr,"$%04X        1581: E75 Error number \"75\" text \"Format Error\"\n",pc); break;
		  case 0xA705: fprintf(stderr,"$%04X        1581: E76 Error number \"76\" text \"Controller Error\"\n",pc); break;
		  case 0xA716: fprintf(stderr,"$%04X        1581: E77 Error number \"77\" text \"Selected Partition Illegal\"\n",pc); break;
		  case 0xA731: fprintf(stderr,"$%04X        1581: E79 Error number \"79\" text \"Software by David Siracusa. Hardware by Greg Berlin\"\n",pc); break;
		  case 0xA75F: fprintf(stderr,"$%04X        1581: E7A Error number \"7A\" text \"Dedicated to My Wife Lisa\"\n",pc); break;
		    //		  case 0xA779: fprintf(stderr,"$%04X        1581: MESSAGE TOKENS\n",pc); break;
		  case 0xA779: fprintf(stderr,"$%04X        1581: T09 Error token number \"09\" text \"Error\"\n",pc); break;
		  case 0xA77F: fprintf(stderr,"$%04X        1581: TOA Error token number \"0A\" text \"Write\"\n",pc); break;
		  case 0xA785: fprintf(stderr,"$%04X        1581: T03 Error token number \"03\" text \"File\"\n",pc); break;
		  case 0xA78A: fprintf(stderr,"$%04X        1581: T04 Error token number \"04\" text \"Open\"\n",pc); break;
		  case 0xA78F: fprintf(stderr,"$%04X        1581: T05 Error token number \"05\" text \"Mismatch\"\n",pc); break;
		  case 0xA798: fprintf(stderr,"$%04X        1581: T06 Error token number \"06\" text \"Not\"\n",pc); break;
		  case 0xA79C: fprintf(stderr,"$%04X        1581: T07 Error token number \"07\" text \"Found\"\n",pc); break;
		  case 0xA7A2: fprintf(stderr,"$%04X        1581: T08 Error token number \"08\" text \"Disk\"\n",pc); break;
		  case 0xA7A7: fprintf(stderr,"$%04X        1581: TOB Error token number \"0B\" text \"Record\"\n",pc); break;
		  case 0xA7AE: fprintf(stderr,"$%04X        1581: DOERR Error message output routine. .A must contain the error number\n",pc); break;
		  case 0xA7F1: fprintf(stderr,"$%04X        1581: PREPMSG Prepare error message\n",pc); break;
		  case 0xA7F4: fprintf(stderr,"$%04X        1581: ACTMSG Activate error message\n",pc); break;
		  case 0xA83E: fprintf(stderr,"$%04X        1581: BIN2BCD Convert a binary number to a BCD number\n",pc); break;
		  case 0xA850: fprintf(stderr,"$%04X        1581: BCD2ASCII Convert a BCD number into two ASCII characters\n",pc); break;
		  case 0xA862: fprintf(stderr,"$%04X        1581: OKMSG Prepare \"00, OK\" error message\n",pc); break;
		  case 0xA867: fprintf(stderr,"$%04X        1581: ERRTRKSEC Output error message with track and sector numbers = 0\n",pc); break;
		  case 0xA86D: fprintf(stderr,"$%04X        1581: ERRBUF Produce error message in buffer (buffer number in .A)\n",pc); break;
		  case 0xA8AD: fprintf(stderr,"$%04X        1581: WRTMSG2BUF Write error message in text form to error buffer\n",pc); break;
		  case 0xA8F8: fprintf(stderr,"$%04X        1581: WRTASCIIMSG Write ASCII characters into a buffer. Non-ASCII characters interpreted as error numbers\n",pc); break;
		  case 0xA90E: fprintf(stderr,"$%04X        1581: ERRMSGFROMROM Get a character of error text from the error message text table in ROM\n",pc); break;
		  case 0xA91C: fprintf(stderr,"$%04X        1581: GETBYTETAB Get the current byte from the table\n",pc); break;
		  case 0xA926: fprintf(stderr,"$%04X        1581: AUTOFILENAME Auto execute file name. First character is the \"&\" command \"&COPYRIGHT CBM 86\"\n",pc); break;
		  case 0xA938: fprintf(stderr,"$%04X        1581: AUTOLOADER CBM auto loader routine\n",pc); break;
		  case 0xA94C: fprintf(stderr,"$%04X        1581: DISABLEAUTO Return from the auto loader with the auto loader disabled\n",pc); break;
		  case 0xA956: fprintf(stderr,"$%04X        1581: UTILITYCMD Utility loader command \"&\" find and get utility loader program block\n",pc); break;
		  case 0xA9F5: fprintf(stderr,"$%04X        1581: GETUTL Read in a byte from utility loader program block\n",pc); break;
		  case 0xAA07: fprintf(stderr,"$%04X        1581: UTLCHKSUM Implement a checksum for utility loader program block\n",pc); break;
		  case 0xAA0F: fprintf(stderr,"$%04X        1581: SETERRVEC Set error vectors to routine at $A94C\n",pc); break;
		  case 0xAA27: fprintf(stderr,"$%04X        1581: INTERLEAVE \"UO>SXM\" command set sector format for CBM diskettes (interleave)\n",pc); break;
		  case 0xAA2D: fprintf(stderr,"$%04X        1581: READATTEMPT \"UO>RX\" command set number of read attempts\n",pc); break;
		  case 0xAA33: fprintf(stderr,"$%04X        1581: SIEEETIMING \"UO>IX\" command function set SIEEE timing\n",pc); break;
		  case 0xAA39: fprintf(stderr,"$%04X        1581: TESTROM \"UO>T\" command test ROM checksum aka ROM signature analysis\n",pc); break;
		  case 0xAA3C: fprintf(stderr,"$%04X        1581: BURSTUTL Decode and execute drive status and control functions\n",pc); break;
		  case 0xAA65: fprintf(stderr,"$%04X        1581: SETDEVICE Set device number via \"UO>\"+CHR$(X)\n",pc); break;
		  case 0xAA83: fprintf(stderr,"$%04X        1581: SYNTAXERR Syntax error message\n",pc); break;
		  case 0xAA88: fprintf(stderr,"$%04X        1581: BUSMODE \"UOBX\" command set serial bus mode (slow or fast)\n",pc); break;
		  case 0xAA9A: fprintf(stderr,"$%04X        1581: VERIFYMODE \"UO>VX\" command sets verify mode selection (on or off)\n",pc); break;
		  case 0xAAA8: fprintf(stderr,"$%04X        1581: BURSTMEMCMDS Burst memory read and write commands\n",pc); break;
		  case 0xAAC3: fprintf(stderr,"$%04X        1581: BURSTMEMREAD Burst memory-read command\n",pc); break;
		  case 0xAAD7: fprintf(stderr,"$%04X        1581: BURSTMEMWRT Burst memory-write command\n",pc); break;
		  case 0xAB09: fprintf(stderr,"$%04X        1581: SETVERIFY Check verify mode select value either zero or one\n",pc); break;
		  case 0xAB1D: fprintf(stderr,"$%04X        1581: SIGNATURERTN ROM signature analysis routine test ROM via checksum\n",pc); break;
		  case 0xABCF: fprintf(stderr,"$%04X        1581: ATN Routine for controlling the serial bus (serial bus ATN server)\n",pc); break;
		  case 0xAC60: fprintf(stderr,"$%04X        1581: Assert ATN_ACK\n",pc); break;
		  case 0xACBB: fprintf(stderr,"$%04X        1581: BUS2INPUT Switch 1581 bus to input\n",pc); break;
		  case 0xACD4: fprintf(stderr,"$%04X        1581: BUS2OUTPUT Switch 1581 bus to output\n",pc); break;
		  case 0xACE8: fprintf(stderr,"$%04X        1581: DATALOW Data line set low (5V)\n",pc); break;
		  case 0xACF1: fprintf(stderr,"$%04X        1581: DATAHI Data line set high (0V)\n",pc); break;
		  case 0xACFA: fprintf(stderr,"$%04X        1581: CLOCKHI Clock line set high (0V)\n",pc); break;
		  case 0xAD03: fprintf(stderr,"$%04X        1581: CLOCKLOW Clock line set low (5V)\n",pc); break;
		  case 0xAD0C: fprintf(stderr,"$%04X        1581: SERVAL Values read from serial bus\n",pc); break;
		  case 0xAD2F: fprintf(stderr,"$%04X        1581: DELAY1 Cycle delay\n",pc); break;
		  case 0xAD34: fprintf(stderr,"$%04X        1581: DELAY2 Cycle delay\n",pc); break;
		  case 0xAD3C: fprintf(stderr,"$%04X        1581: UICMD \"UI\" command bus mode command 1541/1540 speed\n",pc); break;
		  case 0xAD5C: fprintf(stderr,"$%04X        1581: TALK Serial bus talk routine\n",pc); break;
		  case 0xAE42: fprintf(stderr,"$%04X        1581: ACPTR (Serial bus receive byte)\n",pc); bit_num=0; break;
		  case 0xAE99: fprintf(stderr,"$%04X        1581: ACPTR: received C128 FAST byte\n",pc); break;
		  case 0xAEA2: fprintf(stderr,"$%04X        1581: ACPTR: Sampled bit %d of serial bus byte\n",pc,bit_num++); break;
		  case 0xEAB5: fprintf(stderr,"$%04X        1581: ACPTR: Returning data byte stored in $54\n",pc); break;
		    
		  case 0xAEB8: fprintf(stderr,"$%04X        1581: LISTEN Serial bus listen routine\n",pc); break;
		  case 0xAED9: fprintf(stderr,"$%04X        1581: RESETBUS Reset bus control register and wait for next command\n",pc); break;
		  case 0xAEEA: fprintf(stderr,"$%04X        1581: SETSERIAL Setup fast serial direction as input or output (carry set = SPOUT, carry clear = SPINP)\n",pc); break;
		  case 0xAEF2: fprintf(stderr,"$%04X        1581: RAMORROMERR RAM or ROM error (test/checksum)\n",pc); break;
		  case 0xAF24: fprintf(stderr,"$%04X        1581: TESTRAM&ROM Test the 1581's RAM and ROM\n",pc); break;
		  case 0xAFCA: fprintf(stderr,"$%04X        1581: INITZPG Initialize zero page\n",pc); break;
		  case 0xAFDE: fprintf(stderr,"$%04X        1581: PUPMSG Generate DOS power up message\n",pc); break;
		  case 0xB0B3: fprintf(stderr,"$%04X        1581: INITLAYOUT Initialize disk layout variables (max track, dir track, etc.)\n",pc); break;
		  case 0xB0CF: fprintf(stderr,"$%04X        1581: FORMATNORM Set up a \"normal\" DOS format for burst format command\n",pc); break;
		  case 0xB0F0: fprintf(stderr,"$%04X        1581: IDLE Main idle loop\n",pc); break;
		  case 0xB17C: fprintf(stderr,"$%04X        1581: LOADDIR Load directory \"$\"\n",pc); break;
		  case 0xB201: fprintf(stderr,"$%04X        1581: DIREND Directory output ended\n",pc); break;
		  case 0xB237: fprintf(stderr,"$%04X        1581: COPYDIR Copy directory entry into current buffer\n",pc); break;
		  case 0xB245: fprintf(stderr,"$%04X        1581: GETDIRBYTE Get a byte from the directory\n",pc); break;
		  case 0xB262: fprintf(stderr,"$%04X        1581: VALIDATE Validate command routine\n",pc); break;
		  case 0xB286: fprintf(stderr,"$%04X        1581: REPAIRBAM All blocks of a file put into BAM allocates blocks according to file link bytes\n",pc); break;
		  case 0xB2C7: fprintf(stderr,"$%04X        1581: TSTBLOCKS All blocks following a file are tested for validity\n",pc); break;
		  case 0xB2EF: fprintf(stderr,"$%04X        1581: TSTILLEGAL Check for illegal system track or sectors\n",pc); break;
		  case 0xB348: fprintf(stderr,"$%04X        1581: NEW/FORMAT Format command (new)\n",pc); break;
		  case 0xB390: fprintf(stderr,"$%04X        1581: NEWBAM Create a new BAM (all sectors free)\n",pc); break;
		  case 0xB430: fprintf(stderr,"$%04X        1581: CLRBAMBUF Clear BAM buffers\n",pc); break;
		  case 0xB44A: fprintf(stderr,"$%04X        1581: NEWBAM2 Produce a new 1581 BAM for validate command\n",pc); break;
		  case 0xB546: fprintf(stderr,"$%04X        1581: FRESEC Sector released and marked as free\n",pc); break;
		  case 0xB572: fprintf(stderr,"$%04X        1581: SECUSED Mark a sector in the BAM as used. If none are free then a \"Disk Full\" error is produced.\n",pc); break;
		  case 0xB5B4: fprintf(stderr,"$%04X        1581: DRVNOTREADY Produces \"Drive Not Ready\" error\n",pc); break;
		  case 0xB5D8: fprintf(stderr,"$%04X        1581: BAMPTR BAM buffer pointer set to bit for current sector and bit retrieved\n",pc); break;
		  case 0xB5EA: fprintf(stderr,"$%04X        1581: ISOLATEMASKS Masks to isolate BAM bits\n",pc); break;
		  case 0xB668: fprintf(stderr,"$%04X        1581: SCANFREBLK Look for next free block in the BAM\n",pc); break;
		  case 0xB6BF: fprintf(stderr,"$%04X        1581: NXTFREONTRK Look for next free sector on this track\n",pc); break;
		  case 0xB6ED: fprintf(stderr,"$%04X        1581: NXTOPTSEC Layout next optimum sector\n",pc); break;
		  case 0xB75E: fprintf(stderr,"$%04X        1581: NUMFREALL Check number of free blocks in BAM for every track\n",pc); break;
		  case 0xB781: fprintf(stderr,"$%04X        1581: PARTITION Command to create or switch partitions\n",pc); break;
		  case 0xB7F7: fprintf(stderr,"$%04X        1581: SETSUBDIR Move through sub directories to root directory\n",pc); break;
		  case 0xB888: fprintf(stderr,"$%04X        1581: ILLEGALPAP An illegal partition was selected\n",pc); break;
		  case 0xB8D5: fprintf(stderr,"$%04X        1581: FASTLOAD Fastload file over 1581 bus (PRG, SEQ, USR)\n",pc); break;
		  case 0xB95F: fprintf(stderr,"$%04X        1581: XFERFAST Fast sector transfer\n",pc); break;
		  case 0xB990: fprintf(stderr,"$%04X        1581: XFERLAST Fast load last file sector\n",pc); break;
		  case 0xB9D3: fprintf(stderr,"$%04X        1581: SHOWERR Display error messages\n",pc); break;
		  case 0xB9DF: fprintf(stderr,"$%04X        1581: LOADERR Load error\n",pc); break;
		  case 0xBA06: fprintf(stderr,"$%04X        1581: FNAMESETUP Shift file name to beginning of input buffer\n",pc); break;
		  case 0xBA40: fprintf(stderr,"$%04X        1581: SENDFAST Byte sent over 1581 bus for fast load\n",pc); break;
		  case 0xBA64: fprintf(stderr,"$%04X        1581: SETUPCRASH This routine sets the RAM error vectors to point to ROM. The vector at $01BA is set to $DFDF which will crash the DOS.\n",pc); break;
		  case 0xBA7C: fprintf(stderr,"$%04X        1581: SAVEVEC Store error vectors in save vector area\n",pc); break;
		  case 0xBA95: fprintf(stderr,"$%04X        1581: RESTOREVEC Retrieve error vectors from save vector area\n",pc); break;
		  case 0xBAB3: fprintf(stderr,"$%04X        1581: BURSTREAD Burst read track and sector handler\n",pc); break;
		  case 0xBAD6: fprintf(stderr,"$%04X        1581: BURSTREAD2 Burst read number of sectors handling routine\n",pc); break;
		  case 0xBAF7: fprintf(stderr,"$%04X        1581: IDMISMATCH Disk ID mismatch error\n",pc); break;
		  case 0xBAF9: fprintf(stderr,"$%04X        1581: DRVNOTREADY Drive not ready error\n",pc); break;
		  case 0xBAFC: fprintf(stderr,"$%04X        1581: COMMSTERROUT Combine command status flag and output with error\n",pc); break;
		  case 0xBB02: fprintf(stderr,"$%04X        1581: EVENTERR Eventual error output (otherwise return)\n",pc); break;
		  case 0xBB0A: fprintf(stderr,"$%04X        1581: DOERRINXR Output error message number (number in .XR)\n",pc); break;
		  case 0xBB11: fprintf(stderr,"$%04X        1581: BURSTREADCMD Burst read command\n",pc); break;
		  case 0xBC01: fprintf(stderr,"$%04X        1581: BURSTWRTCMD Burst write command\n",pc); break;
		  case 0xBCB2: fprintf(stderr,"$%04X        1581: INQUIREDISK Burst command inquire disk\n",pc); break;
		  case 0xBD06: fprintf(stderr,"$%04X        1581: MOREVALUES Values $00, $10, $0A, $05\n",pc); break;
		  case 0xBD0A: fprintf(stderr,"$%04X        1581: DRVNOTREADY2 Drive not ready error\n",pc); break;
		  case 0xBD12: fprintf(stderr,"$%04X        1581: BURSTFORMAT Burst format command\n",pc); break;
		  case 0xBD4A: fprintf(stderr,"$%04X        1581: FORMATSTRING \"NO:COPYRIGHT CBM,86\" in ASCII (used to do 1581 default burst format)\n",pc); break;
		  case 0xBD5E: fprintf(stderr,"$%04X        1581: FORMATSTANDARD Format using standard DOS format via burst format command\n",pc); break;
		  case 0xBD7C: fprintf(stderr,"$%04X        1581: CUSTOMFORMAT Custom format via burst format command/setup format variables\n",pc); break;
		  case 0xBDF8: fprintf(stderr,"$%04X        1581: MOREVALUES2 Values $0E, $16, $26, $44\n",pc); break;
		  case 0xBDFC: fprintf(stderr,"$%04X        1581: SYNTAXERR Syntax error\n",pc); break;
		  case 0xBE06: fprintf(stderr,"$%04X        1581: QUERYDISK Burst query disk format command\n",pc); break;
		  case 0xBE79: fprintf(stderr,"$%04X        1581: SENDQUERY Send out the results of the query disk format\n",pc); break;
		  case 0xBEBB: fprintf(stderr,"$%04X        1581: INQUIRESTATUS Burst inquire status command\n",pc); break;
		  case 0xBEF1: fprintf(stderr,"$%04X        1581: SETSTATUS Set command status byte\n",pc); break;
		  case 0xBEF8: fprintf(stderr,"$%04X        1581: SYNTAXERR Syntax error\n",pc); break;
		  case 0xBF02: fprintf(stderr,"$%04X        1581: DUMPCACHE Burst command dump track cache buffer\n",pc); break;
		  case 0xBF66: fprintf(stderr,"$%04X        1581: PREPERROUT Prepare error byte output\n",pc); break;
		  case 0xBF7F: fprintf(stderr,"$%04X        1581: PREPDATA Values $00, $10, $20, $30\n",pc); break;
		  case 0xBF86: fprintf(stderr,"$%04X        1581: SENDBYTEFAST Send byte over serial bus using burst protocol\n",pc); break;
		  case 0xBFE3: fprintf(stderr,"$%04X        1581: DUMPTRK Dump a track from cache buffer to disk\n",pc); break;
		  case 0xC097: fprintf(stderr,"$%04X        1581: SMTOGRT Determine smallest and greatest sector numbers\n",pc); break;
		  case 0xC0BE: fprintf(stderr,"$%04X        1581: JMPCTRLER Jump to the disk controller routine\n",pc); break;
		  case 0xC163: fprintf(stderr,"$%04X        1581: CTRLBYTES Drive controller bytes/codes containing 8 flag bits for each of the 33 available jobs\n",pc); break;
		  case 0xC184: fprintf(stderr,"$%04X        1581: CTRLBYTES2 Drive controller bytes/codes containing 3 more flag bits for each of the 33 available jobs\n",pc); break;
		    //		  case 0xC1A5: fprintf(stderr,"$%04X        1581: JOBCMDS Job queue vectors\n",pc); break;
		  case 0xC1A5: fprintf(stderr,"$%04X        1581: READ DV $80 $C900\n",pc); break;
		  case 0xC1A7: fprintf(stderr,"$%04X        1581: RESET DV $82 $C2E7\n",pc); break;
		  case 0xC1A9: fprintf(stderr,"$%04X        1581: MOTON DV $84 $C390\n",pc); break;
		  case 0xC1AB: fprintf(stderr,"$%04X        1581: MOTOFF DV $86 $C393\n",pc); break;
		  case 0xC1AD: fprintf(stderr,"$%04X        1581: MOTONI DV $88 $C396\n",pc); break;
		  case 0xC1AF: fprintf(stderr,"$%04X        1581: MOTOFFI DV $8A $C3A9\n",pc); break;
		  case 0xC1B1: fprintf(stderr,"$%04X        1581: SEEK DV $8C $C3AF\n",pc); break;
		  case 0xC1B3: fprintf(stderr,"$%04X        1581: FORMAT DV $8E $C3BB\n",pc); break;
		  case 0xC1B5: fprintf(stderr,"$%04X        1581: WRSTD DV $90 $C900\n",pc); break;
		  case 0xC1B7: fprintf(stderr,"$%04X        1581: DISKIN DV $92 $C6D7\n",pc); break;
		  case 0xC1B9: fprintf(stderr,"$%04X        1581: LEDACTON DV $94 $C546\n",pc); break;
		  case 0xC1BB: fprintf(stderr,"$%04X        1581: LEDACTOFF DV $96 $C54F\n",pc); break;
		  case 0xC1BD: fprintf(stderr,"$%04X        1581: ERRLEDON DV $98 $C558\n",pc); break;
		  case 0xC1BF: fprintf(stderr,"$%04X        1581: ERRLEDOFF DV $9A $C561\n",pc); break;
		  case 0xC1C1: fprintf(stderr,"$%04X        1581: SIDE DV $9C $C56A\n",pc); break;
		  case 0xC1C3: fprintf(stderr,"$%04X        1581: BUFMOVE DV $9E $C589\n",pc); break;
		  case 0xC1C5: fprintf(stderr,"$%04X        1581: WRTVER DV $A0 $C9E1\n",pc); break;
		  case 0xC1C7: fprintf(stderr,"$%04X        1581: TRKWRT DV $A2 $C5AC\n",pc); break;
		  case 0xC1C9: fprintf(stderr,"$%04X        1581: SP READ $A4 $C800\n",pc); break;
		  case 0xC1CB: fprintf(stderr,"$%04X        1581: SP WRITE $A6 $C700\n",pc); break;
		  case 0xC1CD: fprintf(stderr,"$%04X        1581: PSEEK DV $A8 $C6D7\n",pc); break;
		  case 0xC1CF: fprintf(stderr,"$%04X        1581: TREAD DV $AA $CB09\n",pc); break;
		  case 0xC1D1: fprintf(stderr,"$%04X        1581: TWRT DV $AC $CAE4\n",pc); break;
		  case 0xC1D3: fprintf(stderr,"$%04X        1581: SEEKHD DV $B0 $CB0F\n",pc); break;
		  case 0xC1D5: fprintf(stderr,"$%04X        1581: TPREAD DV $B2 $CB26\n",pc); break;
		  case 0xC1D7: fprintf(stderr,"$%04X        1581: TPWRT DV $B4 $CB26\n",pc); break;
		  case 0xC1D9: fprintf(stderr,"$%04X        1581: DETWP DV $B6 $CB35\n",pc); break;
		  case 0xC1DB: fprintf(stderr,"$%04X        1581: SEEKPHD DV $B8 $C900\n",pc); break;
		  case 0xC1DD: fprintf(stderr,"$%04X        1581: RESTORE DV $C0 $C900\n",pc); break;
		  case 0xC1DF: fprintf(stderr,"$%04X        1581: JUMPC DV $D0 $C900\n",pc); break;
		  case 0xC1E1: fprintf(stderr,"$%04X        1581: EXBUF DV $E0 $C900\n",pc); break;
		  case 0xC1E3: fprintf(stderr,"$%04X        1581: FORMATDK DV $F0 $CB76\n",pc); break;
		  case 0xC1E5: fprintf(stderr,"$%04X        1581: CTRLERR_DV None $CB85\n",pc); break;
		  case 0xC1E7: fprintf(stderr,"$%04X        1581: DATABYTES Eight data bytes for each of the controller commands listed above/job index for 33 jobs\n",pc); break;
		  case 0xC2E7: fprintf(stderr,"$%04X        1581: JOBRESET Reset command - resets the disk controller and variables ($82)\n",pc); break;
		  case 0xC30C: fprintf(stderr,"$%04X        1581: SETWDCMDS Restore default WD177X command table\n",pc); break;
		  case 0xC390: fprintf(stderr,"$%04X        1581: JOBMOTON Motor on command - turns on the drive spindle motor ($84)\n",pc); break;
		  case 0xC393: fprintf(stderr,"$%04X        1581: JOBMOTOFF Motor off command - turns off the drive spindle motor ($86)\n",pc); break;
		  case 0xC396: fprintf(stderr,"$%04X        1581: JOBMOTONI Motor on immediately ($88)\n",pc); break;
		  case 0xC3A9: fprintf(stderr,"$%04X        1581: JOBMOTOFFI Motor off immediately ($8A)\n",pc); break;
		  case 0xC3AF: fprintf(stderr,"$%04X        1581: JOBSEEKTRK Seeks track command ($8C)\n",pc); break;
		  case 0xC3BB: fprintf(stderr,"$%04X        1581: JOBFORMATTRK Format one physical track ($8E)\n",pc); break;
		  case 0xC3EC: fprintf(stderr,"$%04X        1581: WRTINDEX Write track index/save after index hole\n",pc); break;
		  case 0xC52C: fprintf(stderr,"$%04X        1581: STOPITRKFORMAT Terminate physical track format\n",pc); break;
		  case 0xC546: fprintf(stderr,"$%04X        1581: JOBACTLEDON Turn on disk activity LED ($94)\n",pc); break;
		  case 0xC54F: fprintf(stderr,"$%04X        1581: JOBACTLEDOFF Turn off disk activity LED ($96)\n",pc); break;
		  case 0xC558: fprintf(stderr,"$%04X        1581: JOBERRLEDON Turn on disk error LED ($98)\n",pc); break;
		  case 0xC561: fprintf(stderr,"$%04X        1581: JOBERRLEDOFF Turn off disk error LED ($9A)\n",pc); break;
		  case 0xC56A: fprintf(stderr,"$%04X        1581: JOBSETSIDE Set up side select electronics to the value in the sides table ($9C)\n",pc); break;
		  case 0xC589: fprintf(stderr,"$%04X        1581: JOBMOVEDATA Move data between the job queue buffers and track cache ($9E)\n",pc); break;
		  case 0xC5AC: fprintf(stderr,"$%04X        1581: JOBDUMPCACHE Dumps track cache to disk (if \"dirty\") ($A2)\n",pc); break;
		  case 0xC5AF: fprintf(stderr,"$%04X        1581: DUMPOLD Dump old track cache data\n",pc); break;
		  case 0xC600: fprintf(stderr,"$%04X        1581: DUALJOB Checks to see if a disk is in the drive and seeks a preset physical track ($92 and $A8)\n",pc); break;
		  case 0xC6D7: fprintf(stderr,"$%04X        1581: JOBWRTPHYS Write a physical sector directly ($A6)\n",pc); break;
		  case 0xC6DD: fprintf(stderr,"$%04X        1581: JOBREADPHYS Read a physical sector directly ($A4)\n",pc); break;
		  case 0xC700: fprintf(stderr,"$%04X        1581: MULTIJOB Executes controller commands\n",pc); break;
		  case 0xC9E1: fprintf(stderr,"$%04X        1581: JOBVERCACHE Verify cache data against a logical track's data ($A0)\n",pc); break;
		  case 0xC9F6: fprintf(stderr,"$%04X        1581: NOT USED BY DOS\n",pc); break;
		  case 0xCA00: fprintf(stderr,"$%04X        1581: FORMATVER Verify disk format\n",pc); break;
		  case 0xCAE4: fprintf(stderr,"$%04X        1581: JOBWRTLOG Write a logical address without transfer from job queue buffer ($AC)\n",pc); break;
		  case 0xCB09: fprintf(stderr,"$%04X        1581: JOBREADLOG Read a logical address without transfer from job queue buffer ($AA)\n",pc); break;
		  case 0xCB0F: fprintf(stderr,"$%04X        1581: JOBREADHDR Read header data from first disk sector found ($B0)\n",pc); break;
		  case 0xCB26: fprintf(stderr,"$%04X        1581: JOBWRTPHYS Write a physical address without transfer from job queue buffer ($B2)\n",pc); break;
		  case 0xCB2B: fprintf(stderr,"$%04X        1581: XXX - ADDR SUSPICIOUS JOBREADPHYS Read a physical address without transfer from job queue buffer ($B4)\n",pc); break;
		  case 0xCB35: fprintf(stderr,"$%04X        1581: JOBWRTPROTECT Checks to see if the current disk is write protected ($00 = no, $08 = yes) ($B6)\n",pc); break;
		  case 0xCB76: fprintf(stderr,"$%04X        1581: JOBFORMATDSK Format the disk with the default physical format ($F0)\n",pc); break;
		  case 0xCBB1: fprintf(stderr,"$%04X        1581: MOTORON Spindle motor on\n",pc); break;
		  case 0xCBBA: fprintf(stderr,"$%04X        1581: MOTOROFF Spindle motor off\n",pc); break;
		  case 0xCBC3: fprintf(stderr,"$%04X        1581: ACTLEDOFF Green activity LED off\n",pc); break;
		  case 0xCBCC: fprintf(stderr,"$%04X        1581: ACTLEDON Green activity LED on\n",pc); break;
		  case 0xCBEC: fprintf(stderr,"$%04X        1581: WDCMDWAIT Wait until current command on WD177X is done\n",pc); break;
		  case 0xDA63: fprintf(stderr,"$%04X        1581: CHKSUM Routine to do the cyclic redundancy checksum\n",pc); break;
		  case 0xDAFD: fprintf(stderr,"$%04X        1581: IRQRTN 1581 IRQ routine\n",pc); break;
		  case 0xDB40: fprintf(stderr,"$%04X        1581: $BAFA - Drive not ready\n",pc); break;
		  case 0xDB42: fprintf(stderr,"$%04X        1581: $BD12 - Burst format diskette\n",pc); break;
		  case 0xDB44: fprintf(stderr,"$%04X        1581: $BD12 - Burst format diskette\n",pc); break;
		  case 0xDB46: fprintf(stderr,"$%04X        1581: $BDFC - Syntax error #31\n",pc); break;
		  case 0xDB48: fprintf(stderr,"$%04X        1581: $BDFC - Syntax error #31\n",pc); break;
		  case 0xDB4A: fprintf(stderr,"$%04X        1581: $BE06 - Burst determine sector sequence\n",pc); break;
		  case 0xDB4C: fprintf(stderr,"$%04X        1581: $BAFA - Drive not ready\n",pc); break;
		  case 0xDB4E: fprintf(stderr,"$%04X        1581: $BEBB - Burst inquire status\n",pc); break;
		  case 0xDB50: fprintf(stderr,"$%04X        1581: $BAFA - Drive not ready\n",pc); break;
		  case 0xDB52: fprintf(stderr,"$%04X        1581: $BEF8 - Syntax error #31\n",pc); break;
		  case 0xDB54: fprintf(stderr,"$%04X        1581: $BEF8 - Syntax error #31\n",pc); break;
		  case 0xDB56: fprintf(stderr,"$%04X        1581: $BB11 - Burst read sector\n",pc); break;
		  case 0xDB58: fprintf(stderr,"$%04X        1581: $BAFA - Drive not ready\n",pc); break;
		  case 0xDB5A: fprintf(stderr,"$%04X        1581: $BC01 - Burst write sector\n",pc); break;
		  case 0xDB5C: fprintf(stderr,"$%04X        1581: $BBF9 - Drive not ready\n",pc); break;
		  case 0xDB5E: fprintf(stderr,"$%04X        1581: $BCB2 - Burst read sector header\n",pc); break;
		  case 0xDB60: fprintf(stderr,"$%04X        1581: $BAFA - Drive not ready\n",pc); break;
		  case 0xDB62: fprintf(stderr,"$%04X        1581: $BD12 - Burst format diskette\n",pc); break;
		  case 0xDB64: fprintf(stderr,"$%04X        1581: $BD12 - Burst format diskette\n",pc); break;
		  case 0xDB66: fprintf(stderr,"$%04X        1581: $89CB - RTS instruction no function\n",pc); break;
		  case 0xDB68: fprintf(stderr,"$%04X        1581: $89CB - RTS instruction no function\n",pc); break;
		  case 0xDB6A: fprintf(stderr,"$%04X        1581: $BE06 - Burst determine sector sequence\n",pc); break;
		  case 0xDB6C: fprintf(stderr,"$%04X        1581: $BAFA - Drive not ready\n",pc); break;
		  case 0xDB6E: fprintf(stderr,"$%04X        1581: $BF02 - Read next sector header\n",pc); break;
		  case 0xDB70: fprintf(stderr,"$%04X        1581: $BF02 - Read next sector header\n",pc); break;
		  case 0xDB72: fprintf(stderr,"$%04X        1581: $AA3C - Execute 1581 status command\n",pc); break;
		  case 0xDB74: fprintf(stderr,"$%04X        1581: $B8D5 - Fast load a file over the 1581 bus\n",pc); break;
		  case 0xDB76: fprintf(stderr,"$%04X        1581: BAMUSE Number of bytes in BAM for each disk track ($06/6)\n",pc); break;
		  case 0xDB77: fprintf(stderr,"$%04X        1581: NAMEOFFSET Disk name offset in BAM ($04/4)\n",pc); break;
		  case 0xDB78: fprintf(stderr,"$%04X        1581: DOSCMDTABLE Table of DOS commands V, I, /, M, B, U, P, &, C, R, S, N\n",pc); break;
		  case 0xDB84: fprintf(stderr,"$%04X        1581: DOSCMDLO DOS command vectors low bytes\n",pc); break;
		  case 0xDB90: fprintf(stderr,"$%04X        1581: DOSCMDHI DOS command vectors high bytes\n",pc); break;
		  case 0xDB9C: fprintf(stderr,"$%04X        1581: CMDIMAGES Structure images for DOS commands\n",pc); break;
		    // case 0xDBA1: fprintf(stderr,"$%04X        1581: FILEMODE Mode table\n",pc); break;
		  case 0xDBA1: fprintf(stderr,"$%04X        1581: $52 R = Read mode\n",pc); break;
		  case 0xDBA2: fprintf(stderr,"$%04X        1581: $57 W = Write mode\n",pc); break;
		  case 0xDBA3: fprintf(stderr,"$%04X        1581: $41 A = Append mode\n",pc); break;
		  case 0xDBA4: fprintf(stderr,"$%04X        1581: $4D M = Modify mode (read an improperly closed file)\n",pc); break;
		    //		  case 0xDBA5: fprintf(stderr,"$%04X        1581: FILETYPE File type table\n",pc); break;
		  case 0xDBA5: fprintf(stderr,"$%04X        1581: FTO First byte of file type (D, S, P, U, L, C) for file operations\n",pc); break;
		  case 0xDBAB: fprintf(stderr,"$%04X        1581: FT1 First byte of file type (D, S, P, U, R, C)\n",pc); break;
		  case 0xDBB1: fprintf(stderr,"$%04X        1581: FT2 Second byte of file type (E, E, R, S, E, B)\n",pc); break;
		  case 0xDBB7: fprintf(stderr,"$%04X        1581: FT3 Third byte of file type (L, Q, G, R, L, M)\n",pc); break;
		    //		  case 0xalid: fprintf(stderr,"$%04X        1581: file types are: DEL, SEQ, PRG, USR, REL, CBM\n",pc); break;
		  case 0xDBBD: fprintf(stderr,"$%04X        1581: ERRFLAG Error flag variables for use by BIT commands\n",pc); break;
		  case 0xDBC2: fprintf(stderr,"$%04X        1581: ERROFFSETS Offsets for error recovery\n",pc); break;
		  case 0xDBC7: fprintf(stderr,"$%04X        1581: SPINPATCH Spin routine patch to clear the shift register\n",pc); break;
		  case 0xDBE0: fprintf(stderr,"$%04X        1581: SPOUTPATCH Spinout routine patch to clear the shift register\n",pc); break;
		  case 0xDBEE: fprintf(stderr,"$%04X        1581: RELEASESEC Release sectors in BAM after scratching a file/used after scratching a partition file to update the disk BAM\n",pc); break;
		  case 0xDBF4: fprintf(stderr,"$%04X        1581: SEEKNCHK Seek a header and check disk format\n",pc); break;
		  case 0xDC01: fprintf(stderr,"$%04X        1581: CRMSG Commodore DOS copyright message \"©1987 Commodore Electronics Ltd., All Rights Reserved\"\n",pc); break;
		  case 0xFF00: fprintf(stderr,"$%04X        1581: IDLE Execute the JIDLE routine via an indirect jump to the vector at $0190. JIDLE at $B0F0\n",pc); break;
		  case 0xFF03: fprintf(stderr,"$%04X        1581: IRQ Execute the JIRQ routine via an indirect jump to the vector at $0192. JIRQ at $DAF0\n",pc); break;
		  case 0xFF06: fprintf(stderr,"$%04X        1581: NMI Execute the JNMI routine via an indirect jump to the vector at $0194. JNMI at $AFCA\n",pc); break;
		  case 0xFF09: fprintf(stderr,"$%04X        1581: VERDIR Execute the JVERDIR routine via an indirect jump to the vector at $0196. JVERDIR at $B262\n",pc); break;
		  case 0xFF0C: fprintf(stderr,"$%04X        1581: INTDRV Execute the JINTDRV routine via an indirect jump to the vector at $0198. JINTDRV at $8EC5\n",pc); break;
		  case 0xFF0F: fprintf(stderr,"$%04X        1581: PART Execute the JPART routine via an indirect jump to the vector at $019A. JPART at $B781\n",pc); break;
		  case 0xFF12: fprintf(stderr,"$%04X        1581: MEM Execute the JMEM routine via an indirect jump to the vector at $019C. JMEM at $892F\n",pc); break;
		  case 0xFF15: fprintf(stderr,"$%04X        1581: BLOCK Execute the JBLOCK routine via an indirect jump to the vector at $019E. JBLOCK at $8A5D\n",pc); break;
		  case 0xFF18: fprintf(stderr,"$%04X        1581: USERVEC Execute the JUSER routine via an indirect jump to the vector at $01A0. JUSER at $898F\n",pc); break;
		  case 0xFF1B: fprintf(stderr,"$%04X        1581: RECORD Execute the JRECORD routine via an indirect jump to the vector at $01A2. JRECORD at $A1A1\n",pc); break;
		  case 0xFF1E: fprintf(stderr,"$%04X        1581: UTLODR Execute the JUTLODR routine via an indirect jump to the vector at $01A4. JUTLODR at $A956\n",pc); break;
		  case 0xFF21: fprintf(stderr,"$%04X        1581: DSKCOPY Execute the JDSKCPY routine via an indirect jump to the vector at $01A6. JDSKCPY at $876E\n",pc); break;
		  case 0xFF24: fprintf(stderr,"$%04X        1581: RENAMEVEC Execute the JRENAME routine via an indirect jump to the vector at $01A8. JRENAME at $88C5\n",pc); break;
		  case 0xFF27: fprintf(stderr,"$%04X        1581: SCRTCH Execute the JSCRTCH routine via an indirect jump to the vector at $01AA. JSCRTCH at $8688\n",pc); break;
		  case 0xFF2A: fprintf(stderr,"$%04X        1581: NEW Execute the JNEW routine via an indirect jump to the vector at $01AC. JNEW at $B348\n",pc); break;
		  case 0xFF2D: fprintf(stderr,"$%04X        1581: ERROR Execute the ERROR routine via an indirect jump to the vector at $01AE. ERROR at $A7AE\n",pc); break;
		  case 0xFF30: fprintf(stderr,"$%04X        1581: ATNSERV Execute the JATNSRV routine via an indirect jump to the vector at $01B0. JATNSRV at $ABCF\n",pc); break;
		  case 0xFF33: fprintf(stderr,"$%04X        1581: TALK Execute the JTALK routine via an indirect jump to the vector at $01B2. JTALK at $AD5C\n",pc); break;
		  case 0xFF36: fprintf(stderr,"$%04X        1581: LISTEN Execute the JLISTEN routine via an indirect jump to the vector at $01B4. JLISTEN at $AEB8\n",pc); break;
		  case 0xFF39: fprintf(stderr,"$%04X        1581: LCC Execute the JLCC routine via an indirect jump to the vector at $01B6. JLCC at $C0BE\n",pc); break;
		  case 0xFF3C: fprintf(stderr,"$%04X        1581: TRANSTS Execute the JTRANSTS routine via an indirect jump to the vector at $01B8. JTRANSTS at $CEDC\n",pc); break;
		  case 0xFF3F:
		    fprintf(stderr,"$%04X        1581: CMDERR Error = $%02x\n",pc,reg_a);
		    // fprintf(stderr,"$%04X        1581: CMDERR Execute the CMDERR routine via an indirect jump to the vector at $01BA. CMDERR at $A7F1\n",pc);
		    break;
		  case 0xFF42: fprintf(stderr,"$%04X        1581: STROBECTRLER Not used by DOS\n",pc); break;
		  case 0xFF54: fprintf(stderr,"$%04X        1581: CBMBOOT Execute the JSTROBE_CTRLER routine via a direct jump to $FF54. JSTROBE_CTRLER at $959D\n",pc); break;
		  case 0xFF57: fprintf(stderr,"$%04X        1581: CBMBOOTRTN Execute the JCBMBOOT routine via a direct jump to $FF57. JCBMBOOT at $A938\n",pc); break;
		  case 0xFF5A: fprintf(stderr,"$%04X        1581: SIGNATURE Execute the JCBMBOOTRTN routine via a direct jump to $FF5A. JCBMBOOTRTN at $A94C\n",pc); break;
		  case 0xFF5D: fprintf(stderr,"$%04X        1581: DEJAVU Execute the JSIGNATURE routine via a direct jump to $FF5D. JSIGNATURE at $AB1D\n",pc); break;
		  case 0xFF60: fprintf(stderr,"$%04X        1581: SPINOUT Execute the JDEJAVU routine via a direct jump to $FF60. JDEJAVU at $9145\n",pc); break;
		  case 0xFF63: fprintf(stderr,"$%04X        1581: ALLOCBUFF Execute the JSPINOUT routine via a direct jump to $FF63. JSPINOUT at $AEEA\n",pc); break;
		  case 0xFF66: fprintf(stderr,"$%04X        1581: TESTTRKSEC Execute the JALLOCBUFF routine via a direct jump to $FF66. JALLOCBUFF at $8C5C\n",pc); break;
		  case 0xFF69: fprintf(stderr,"$%04X        1581: TESTTRKSEC Execute the JTESTTRKSEC routine via a direct jump to $FF69. JTESTTRKSEC at $9460\n",pc); break;
		  case 0xFF6C: fprintf(stderr,"$%04X        1581: DUMPTRK Execute the dump track to disk routine at $BFE3\n",pc); break;
		  case 0xFF75: fprintf(stderr,"$%04X        1581: RAMVECDATA Vectors for RAM jump table at $0190 (defaults see $FF00-$FF3F above)\n",pc); break;
		  case 0xFFAD: fprintf(stderr,"$%04X        1581: INITJMP Routine to initialize RAM jump table at $0190\n",pc); break;
		  case 0xFFEA: fprintf(stderr,"$%04X        1581: USER1 \"U1/A\" vector points to $8B9A\n",pc); break;
		  case 0xFFEC: fprintf(stderr,"$%04X        1581: USER2 \"U2/B\" vector points to $8BD7\n",pc); break;
		  case 0xFFEE: fprintf(stderr,"$%04X        1581: USER3 \"U3/C\" vector points to $0500\n",pc); break;
		  case 0xFFF0: fprintf(stderr,"$%04X        1581: USER4 \"U4/D\" vector points to $0503\n",pc); break;
		  case 0xFFF2: fprintf(stderr,"$%04X        1581: USER5 \"U5/E\" vector points to $0506\n",pc); break;
		  case 0xFFF4: fprintf(stderr,"$%04X        1581: USER6 \"U6/F\" vector points to $0509\n",pc); break;
		  case 0xFFF6: fprintf(stderr,"$%04X        1581: USER7 \"U7/G\" vector points to $050C\n",pc); break;
		  case 0xFFF8: fprintf(stderr,"$%04X        1581: USER8 \"U8/H\" vector points to $050F\n",pc); break;
		  case 0xFFFA: fprintf(stderr,"$%04X        1581: NNMI \"U9/I\" NNMI routine points to $AD3C\n",pc); break;
		  case 0xFFFC: fprintf(stderr,"$%04X        1581: DSKINT \"U:/J\" DSKINT routine points to $AF24\n",pc); break;
		  case 0xFFFE: fprintf(stderr,"$%04X        1581: SYSIRQ \"UK\" SYSIRQ routine points to $FF03 (sending a \"UK\" command crashes the drive)\n",pc); break;
									     
		  }
	      } else {		    
		// 1541
		if (!jiffyDOS) 
		  switch(pc) {
		  case 0xE853: fprintf(stderr,"$%04X            1541: ATN IRQ occurred, and ATN queued for processing\n",pc); break;
		  case 0xE85B: fprintf(stderr,"$%04X            1541: Servicing ATN request\n",pc); break;		
		  case 0xE89F: fprintf(stderr,"$%04X            1541: Received TALK command for device\n",pc); break;		
		  case 0xE8BE: fprintf(stderr,"$%04X            1541: Received secondary address\n",pc); break;
		  case 0xE8F1: fprintf(stderr,"$%04X            1541: TURNAROUND (Serial bus wants to become talker)\n",pc); break;
		  case 0xE909: fprintf(stderr,"$%04X            1541: TALK (Serial bus wants to send a byte)\n",pc); break;
		  case 0xE9C9: fprintf(stderr,"$%04X            1541: ACPTR (Serial bus receive byte)\n",pc); bit_num=0; break;
		  case 0xE9CD: fprintf(stderr,"$%04X            1541: ACP00A (wait for CLK to go to 5V)\n",pc); break;
		  case 0xE9DF: fprintf(stderr,"$%04X            1541: ACP00 (saw CLK get released)\n",pc); break;
		  case 0xE9F2: fprintf(stderr,"$%04X            1541: ACP00B (Pulse data low and wait for turn-around)\n",pc); break;
		  case 0xE9FD: fprintf(stderr,"$%04X            1541: ACP02A (EOI check)\n",pc); break;
		  case 0xEA07: fprintf(stderr,"$%04X            1541:   Clear EOI flag\n",pc); break;
		  case 0xEA0C: fprintf(stderr,"$%04X            1541:   Set EOI flag\n",pc); break;
		  case 0xEA12: fprintf(stderr,"$%04X            1541: ACP03+10 Sampled bit %d of serial bus byte\n",pc,bit_num++); break;
		  case 0xEA18: fprintf(stderr,"$%04X            1541: ACP03+13 Stashing sampled bit into $85\n",pc); break;
		  case 0xEA24: fprintf(stderr,"$%04X            1541: ACP03A Got bit of serial bus byte\n",pc); break;
		  case 0xEA28: fprintf(stderr,"$%04X            1541: ACKNOWLEDGE BYTE\n",pc); break;
		  case 0xEA2B: fprintf(stderr,"$%04X            1541: ACP03A+17 Got all 8 bits\n",pc); break;
		  case 0xEA2E: fprintf(stderr,"$%04X            1541: LISTEN (Starting to receive a byte)\n",pc); break;
		  case 0xEA41: fprintf(stderr,"$%04X            1541: LISTEN BAD CHANNEL (abort listening, due to lack of active channel)\n",pc); break;
		  case 0xEA44: fprintf(stderr,"$%04X            1541: LISTEN OPEN  (abort listening, due to lack of active channel)\n",pc); break;
		  case 0xEB34: fprintf(stderr,"$%04X            1541: Write to $180D\n",pc); break;
		  case 0xEBE7: fprintf(stderr,"$%04X            1541: Enter IDLE loop\n",pc); break;
		  case 0xFF0D: fprintf(stderr,"$%04X            1541: NNMI10 (Set C64/VIC20 speed)\n",pc); break;
		  default:
		    break;
		  }
		else {
		  // JiffyDOS ROM
		  switch(pc) {
		  case 0xE853: fprintf(stderr,"$%04X            1541: ATN IRQ occurred, and ATN queued for processing\n",pc); break;
		  case 0xE85B: fprintf(stderr,"$%04X            1541: Servicing ATN request\n",pc); break;		
		  case 0xE89F: fprintf(stderr,"$%04X            1541: Received TALK command for device\n",pc); break;		
		  case 0xE8BE: fprintf(stderr,"$%04X            1541: Received secondary address\n",pc); break;
		  case 0xE8F1: fprintf(stderr,"$%04X            1541: TURNAROUND (Serial bus wants to become talker)\n",pc); break;
		  case 0xE909: fprintf(stderr,"$%04X            1541: TALK (Serial bus wants to send a byte)\n",pc); break;
		  case 0xE9C9: fprintf(stderr,"$%04X            1541: ACPTR (Serial bus receive byte)\n",pc); bit_num=0; break;
		  case 0xE9CD: fprintf(stderr,"$%04X            1541: ACP00A (wait for CLK to go to 5V)\n",pc); break;
		  case 0xE9DF: fprintf(stderr,"$%04X            1541: ACP00 (saw CLK get released)\n",pc); break;
		  case 0xE9F2: fprintf(stderr,"$%04X            1541: ACP00B (Pulse data low and wait for turn-around)\n",pc); break;
		  case 0xE9FD: fprintf(stderr,"$%04X            1541: ACP02A (EOI check)\n",pc); break;
		  case 0xEA07: fprintf(stderr,"$%04X            1541:   Clear EOI flag\n",pc); break;
		  case 0xEA0C: fprintf(stderr,"$%04X            1541:   Set EOI flag\n",pc); break;
		  case 0xEA12: fprintf(stderr,"$%04X            1541: ACP03+10 Sampled bit %d of serial bus byte\n",pc,bit_num++); break;
		  case 0xEA24: fprintf(stderr,"$%04X            1541: ACP03A Got bit of serial bus byte\n",pc); break;
		  case 0xEA28: fprintf(stderr,"$%04X            1541: ACKNOWLEDGE BYTE\n",pc); break;
		  case 0xEA2B: fprintf(stderr,"$%04X            1541: ACP03A+17 Got all 8 bits\n",pc); break;
		  case 0xEA2E: fprintf(stderr,"$%04X            1541: LISTEN (Starting to receive a byte)\n",pc); break;
		  case 0xEA41: fprintf(stderr,"$%04X            1541: LISTEN BAD CHANNEL (abort listening, due to lack of active channel)\n",pc); break;
		  case 0xEA44: fprintf(stderr,"$%04X            1541: LISTEN OPEN  (abort listening, due to lack of active channel)\n",pc); break;
		  case 0xEB34: fprintf(stderr,"$%04X            1541: Write to $180D\n",pc); break;
		  case 0xEBE7: fprintf(stderr,"$%04X            1541: Enter IDLE loop\n",pc); break;
		  case 0xEBF5: fprintf(stderr,"$%04X            1541: Executing pending command\n",pc); break;
		  case 0xEC00: fprintf(stderr,"$%04X            1541: Checking if ATN request pending\n",pc); break;		
		  case 0xFF0D: fprintf(stderr,"$%04X            1541: NNMI10 (Set C64/VIC20 speed)\n",pc); break;
		  case 0xFF79: fprintf(stderr,"$%04X            JIFFYDOS: Send byte to computer\n",pc); break;
		  case 0xFFB5: fprintf(stderr,"$%04X            JIFFYDOS: Waiting for computer to indicate ready to RX byte\n",pc); break;
		  case 0xFBD3: fprintf(stderr,"$%04X            JIFFYDOS: Receive byte from computer\n",pc); break;
		  case 0xFBE2: fprintf(stderr,"$%04X            JIFFYDOS: Latch bits 4 and 5\n",pc); break;
		  case 0xFBE8: fprintf(stderr,"$%04X            JIFFYDOS: Latch bits 6 and 7\n",pc); break;
		  case 0xFBF0: fprintf(stderr,"$%04X            JIFFYDOS: Latch low nybl bits 1 of 2\n",pc); break;
		  case 0xFBF6: fprintf(stderr,"$%04X            JIFFYDOS: Latch low nybl bits 2 of 2\n",pc); break;
		  case 0xFC00: fprintf(stderr,"$%04X            JIFFYDOS: Latch status bits\n",pc); break;
		  case 0xFC0E: fprintf(stderr,"$%04X            JIFFYDOS: Drive detected EOI when receiving byte\n",pc); break;
		  default:
		    break;
		  }
		}
	      }
	    }
	  }
	  line[0]=0; line_len=0;
	} else {
	  if (line_len<1024) { line[line_len++]=c;  line[line_len]=0; }
	}
      }
    }
  }

  return -1;

}

char *describe_line(int c64, int drive, int dummy)
{
  int v=0;
  if (c64) v|=1;
  if (drive) v|=2;
  if (dummy) v|=4;

  switch(v) {
  case 0: return "0(ALL)";
  case 1: return "0(DRIVES)";
  case 2: return "0(C64+DUMMY)";
  case 3: return "0(DUMMY)";
  case 4: return "0(C64+DRIVE)";
  case 5: return "0(DRIVE)";
  case 6: return "0(C64)";
  case 7: return "1";
  }
  return "UNKNOWN";
}

int iecDataTrace(char *msg)
{

  double prev_time = 0;
  
  fprintf(stderr,"DEBUG: Fetching IEC data trace...\n");
  for(int i=0;i<4096;i++) {
    if (getUpdate()) break;

    double time_norm = time_val;
    if (!strcmp(time_units,"ps")) time_norm /= 1000000.0;
    else if (!strcmp(time_units,"ns")) time_norm /= 1000.0;
    else if (!strcmp(time_units,"us")) time_norm *= 1.0;
    else if (!strcmp(time_units,"ms")) time_norm *= 1000.0;
    else {
      fprintf(stderr,"FATAL: Unknown time units '%s'\n",time_units);
    }

    double time_diff = time_norm - prev_time;
    prev_time = time_norm;
    
    printf(" %+12.3f : ATN=%d, DATA=%s, CLK=%s\n",
	   time_diff,
	   atn,
	   describe_line(data_c64,data_1541,data_dummy),
	   describe_line(clk_c64,clk_1541,1)
	   );
    fflush(stdout);
  }
    
  build_image();
  write_png("iectrace.png");

  printf("\n");
  return 0;
}

int main(int argc,char **argv)
{
  if (argc<2) {
    fprintf(stderr,"usage: iecwaveform <VUnit output.txt> [JD|81]\n");
    exit(-1);
  }

  if (argc>2) {
    if (!strcasecmp(argv[2],"JD")) jiffyDOS=1;
    if (!strcasecmp(argv[2],"81")) c1581=1;
    else {
      fprintf(stderr,"ERROR: JD and 81 are the only supported drive ROM variants (default is stock 1541).\n");
      exit(-1);
    }
  }
  
  openFile(argv[1]);

  iecDataTrace("VHDL IEC Simulation");

  return 0;
}

