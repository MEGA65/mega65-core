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
unsigned int iec_state,instr_num,pc;
char time_units[8192];

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
	    // if (strstr(line,"IECBUSSTATE")) fprintf(stderr,"DEBUG: r=%d, Line = '%s'\n",r,line);

	    if (r==8) {
	      int ofs=0;
	      int colons=5;
	      while(colons) if (line[ofs++]==':') colons--;
	      // fprintf(stderr,"%s\n",&line[ofs+1]);
	      return 0;
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
	    
	    if (sscanf(line,"/home/paul/Projects/mega65/mega65-core/src/vhdl/simple_cpu6502.vhdl:%*d:%*d:@%lld%[^:]:(report note): Instr#:%d PC: $%x",
		       &time_val,time_units,&instr_num,&pc)==4) {

	      pc=pc &0xffff;
	      
	      switch(pc) {
	      case 0xCFB7: fprintf(stderr,"$%04X            1541: Write to channel \n",pc); break;
	      case 0xCFE8: fprintf(stderr,"$%04X            1541: Check for end of command \n",pc); break;
	      case 0xCFED: fprintf(stderr,"$%04X            1541: L45 (Indicate command waiting for processing) \n",pc); break;
	      case 0xE89F: fprintf(stderr,"$%04X            1541: Received TALK command for device\n",pc); break;
	      case 0xE8BE: fprintf(stderr,"$%04X            1541: Received secondary address\n",pc); break;
	      case 0xE8F1: fprintf(stderr,"$%04X            1541: TURNAROUND (Serial bus wants to become talker)\n",pc); break;
	      case 0xE909: fprintf(stderr,"$%04X            1541: TALK (Serial bus wants to send a byte)\n",pc); break;
	      case 0xE9C9: fprintf(stderr,"$%04X            1541: ACPTR (Serial bus receive byte)\n",pc); break;
	      case 0xE9CD: fprintf(stderr,"$%04X            1541: ACP00A (wait for CLK to go to 5V)\n",pc); break;
	      case 0xE9DF: fprintf(stderr,"$%04X            1541: ACP00 (saw CLK get released)\n",pc); break;
	      case 0xE9F2: fprintf(stderr,"$%04X            1541: ACP00B (Pulse data low and wait for turn-around)\n",pc); break;
	      case 0xE9FD: fprintf(stderr,"$%04X            1541: ACP02A (EOI check)\n",pc); break;
	      case 0xEA07: fprintf(stderr,"$%04X            1541:   Clear EOI flag\n",pc); break;
	      case 0xEA0C: fprintf(stderr,"$%04X            1541:   Set EOI flag\n",pc); break;
	      case 0xEA12: fprintf(stderr,"$%04X            1541: ACP03+7 Received bit of serial bus byte\n",pc); break;
	      case 0xEA1A: fprintf(stderr,"$%04X            1541: ACP03A Got bit of serial bus byte\n",pc); break;
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
  openFile(argv[1]);

  iecDataTrace("VHDL IEC Simulation");

  return 0;
}

