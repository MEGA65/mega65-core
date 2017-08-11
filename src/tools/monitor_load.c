/*
  Load the specified program into memory on the C65GS via the serial monitor.

  We add some convenience features:

  1. If an optional file name is provided, then we stuff the keyboard buffer
  with the LOAD command.  We check if we are in C65 mode, and if so, do GO64
  (look for "THE" at $086d for C65 ROM detection).  Keyboard buffer @ $34A, 
  buffer length @ $D0 in C65 mode, same as C128.  Then buffer is $277 in C64
  mode, buffer length @ $C6 in C64 mode.
  
  2. If an optional bitstream file is provided, then we use fpgajtag to load
  the bitstream via JTAG.

Copyright (C) 2014-2017 Paul Gardner-Stephen
Portions Copyright (C) 2013 Serval Project Inc.
 
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.
 
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
 
You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <time.h>
#include <strings.h>
#include <string.h>
#include <ctype.h>
#include <sys/time.h>
#include <errno.h>
#include <getopt.h>

time_t start_time=0;

int process_char(unsigned char c,int live);


void usage(void)
{
  fprintf(stderr,"MEGA65 cross-development tool for booting the MEGA65 using a custom bitstream and/or KICKUP file.\n");
  fprintf(stderr,"usage: monitor_load [-l <serial port>] [-s <230400|2000000|4000000>]  [-b <FPGA bitstream>] [[-k <kickup file>] [-R romfile] [-C charromfile]] [-m modeline] [filename]\n");
  fprintf(stderr,"  -l - Name of serial port to use, e.g., /dev/ttyUSB1\n");
  fprintf(stderr,"  -s - Speed of serial port in bits per second. This must match what your bitstream uses.\n");
  fprintf(stderr,"       (Older bitstream use 230400, and newer ones 2000000 or 4000000).\n");
  fprintf(stderr,"  -b - Name of bitstream file to load.\n");
  fprintf(stderr,"  -k - Name of kickup file to forcibly use instead of the kickstart in the bitstream.\n");
  fprintf(stderr,"  -R - ROM file to preload at $20000-$3FFFF.\n");
  fprintf(stderr,"  -C - Character ROM file to preload.\n");
  fprintf(stderr,"  -4 - Switch to C64 mode before exiting.\n");
  fprintf(stderr,"  -r - Automatically RUN programme after loading.\n");
  fprintf(stderr,"  -m - Set video mode to Xorg style modeline.\n");
  fprintf(stderr,"  filename - Load and run this file in C64 mode before exiting.\n");
  fprintf(stderr,"\n");
  exit(-3);
}

int slow_write(int fd,char *d,int l)
{
  // UART is at 230400bps, but reading commands has no FIFO, and echos
  // characters back, meaning we need a 1 char gap between successive
  // characters.  This means >=1/23040sec delay. We'll allow roughly
  // double that at 100usec.
  //  printf("Writing [%s]\n",d);
  int i;
  for(i=0;i<l;i++)
    {
      usleep(2000);
      int w=write(fd,&d[i],1);
      while (w<1) {
	usleep(1000);
	w=write(fd,&d[i],1);
      }
    }
  return 0;
}

int fd=-1;
int state=99;
int name_len,name_lo,name_hi,name_addr=-1;
int do_go64=0;
int do_run=0;
char *filename=NULL;
char *romfile=NULL;
char *charromfile=NULL;
FILE *f=NULL;
char *search_path=".";
char *bitstream=NULL;
char *kickstart=NULL;
char serial_port[1024]="/dev/ttyUSB1"; // XXX do a better job auto-detecting this
int serial_speed=2000000;
char modeline_cmd[1024]="";


unsigned long long gettime_ms()
{
  struct timeval nowtv;
  // If gettimeofday() fails or returns an invalid value, all else is lost!
  if (gettimeofday(&nowtv, NULL) == -1)
    perror("gettimeofday");
  return nowtv.tv_sec * 1000LL + nowtv.tv_usec / 1000;
}

int stop_cpu(void)
{
  // Stop CPU
  usleep(50000);
  slow_write(fd,"t1\r",3);
  return 0;
}

int load_file(char *filename,int load_addr,int patchKickstart)
{
  char cmd[1024];

  FILE *f=fopen(filename,"r");
  if (!f) {
    fprintf(stderr,"Could not open file '%s'\n",filename);
    exit(-2);
  }
  
  usleep(50000);
  unsigned char buf[16384];
  int max_bytes;
  int byte_limit=1024;
  max_bytes=0x10000-(load_addr&0xffff);
  if (max_bytes>byte_limit) max_bytes=byte_limit;
  int b=fread(buf,1,max_bytes,f);
  while(b>0) {
    if (patchKickstart) {
      printf("patching...\n");
      // Look for BIT $nnnn / BIT $1234, and change to JMP $nnnn to skip
      // all SD card activities
      for(int i=0;i<(b-5);i++)
	{
	  if ((buf[i]==0x2c)
	      &&(buf[i+3]==0x2c)
	      &&(buf[i+4]==0x34)
	      &&(buf[i+5]==0x12)) {
	    fprintf(stderr,"Patching Kickstart @ $%04x to skip SD card and ROM checks.\n",
		    0x8000+i);
	    buf[i]=0x4c;
	  }
	}
    }
    printf("Read to $%04x (%d bytes)\n",load_addr,b);
    fflush(stdout);
    // load_addr=0x400;
    // XXX - The l command requires the address-1, and doesn't cross 64KB boundaries.
    // Thus writing to $xxx0000 requires adding 64K to fix the actual load address
    int munged_load_addr=load_addr;
    if ((load_addr&0xffff)==0x0000) {
      munged_load_addr+=0x10000;
    }
    sprintf(cmd,"l%x %x\r",munged_load_addr-1,munged_load_addr+b-1);
    slow_write(fd,cmd,strlen(cmd));
    usleep(1000);
    int n=b;
    unsigned char *p=buf;
    while(n>0) {
      int w=write(fd,p,n);
      if (w>0) { p+=w; n-=w; } else usleep(1000);
    }
    if (serial_speed==230400) usleep(10000+50*b);
    else if (serial_speed==2000000)
      // 2mbit/sec / 11bits/char (inc space) = ~5.5usec per char
      usleep(5.1*b);
    else
      // 4mbit/sec / 11bits/char (inc space) = ~2.6usec per char
      usleep(2.6*b);
      
    load_addr+=b;

    max_bytes=0x10000-(load_addr&0xffff);
    if (max_bytes>byte_limit) max_bytes=byte_limit;
    b=fread(buf,1,max_bytes,f);	  
  }
  fclose(f);
  fprintf(stderr,"[T+%lldsec] '%s' loaded.\n",(long long)time(0)-start_time,filename);
  
  return 0;
}

int restart_kickstart(void)
{
  // Start executing in new kickstart
  usleep(50000);
  slow_write(fd,"g8100\r",6);
  usleep(10000);
  slow_write(fd,"t0\r",3);
  return 0;
}

int first_load=1;
int first_go64=1;

int process_line(char *line,int live)
{
  int pc,a,x,y,sp,p;
  //  printf("[%s]\n",line);
  if (!live) return 0;
  if (sscanf(line,"%04x %02x %02x %02x %02x %02x",
	     &pc,&a,&x,&y,&sp,&p)==6) {
    // printf("PC=$%04x\n",pc);
    if (pc==0xf4a5||pc==0xf4a2) {
      // Intercepted LOAD command
      state=1;
    } else if (pc>=0x8000&&pc<0xc000
	       &&(kickstart)) {
      int patchKS=0;
      if (romfile||charromfile) patchKS=1;
      fprintf(stderr,"[T+%lldsec] Replacing %skickstart...\n",
	      (long long)time(0)-start_time,
	      patchKS?"and patching ":"");
      stop_cpu();
      if (kickstart) load_file(kickstart,0xfff8000,patchKS); kickstart=NULL;
      if (romfile) load_file(romfile,0x20000,0); romfile=NULL;
      if (charromfile) load_file(charromfile,0xFF7E000,0);
      charromfile=NULL;
      restart_kickstart();
    } else {
      if (state==99) {
	// Synchronised with monitor
	state=0;
	// Send ^U r <return> to print registers and get into a known state.
	usleep(50000);
	slow_write(fd,"\r",1);
	usleep(50000);
	slow_write(fd,"t0\r",3); // and set CPU going
	usleep(20000);
	printf("Synchronised with monitor.\n");
      }
    }
  }
  if (sscanf(line," :00000B7 %02x %*02x %*02x %*02x %02x %02x",
	     &name_len,&name_lo,&name_hi)==3) {
    name_addr=(name_hi<<8)+name_lo;
    printf("Filename is %d bytes long, and is stored at $%04x\n",
	   name_len,name_addr);
    char filename[16];
    snprintf(filename,16,"m%04x\r",name_addr);
    usleep(10000);
    slow_write(fd,filename,strlen(filename));
    printf("Asking for filename from memory: %s\n",filename);
    state=3;
  }
  {
    int addr;
    int b[16];
    if (sscanf(line," :%x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
	       &addr,
	       &b[0],&b[1],&b[2],&b[3],
	       &b[4],&b[5],&b[6],&b[7],
	       &b[8],&b[9],&b[10],&b[11],
	       &b[12],&b[13],&b[14],&b[15])==17) {
      char fname[17];
      // printf("Read memory @ $%04x\n",addr);
      if (addr==name_addr) {
	for(int i=0;i<16;i++) fname[i]=b[i]; fname[16]=0;
	fname[name_len]=0;
	printf("Request to load '%s'\n",fname);
	if (fname[0]=='!') // we use this form in case junk gets typed while we are doing it
	  state=2; // load specified file
	else {
	  printf("Specific file to load is '%s'\n",fname);
	  if (filename) free(filename);
	  filename=strdup(fname);
	  do_go64=1; // load in C64 mode only
	  state=0;
	}
      }
    }
  }
  if (!strcmp(line,
	      " :000086D 14 08 05 20 03 0F 0D 0D 0F 04 0F 12 05 20 03 36")) {

    if (modeline_cmd[0]) {
      fprintf(stderr,"[T+%lldsec] Setting video modeline\n",(long long)time(0)-start_time);
      slow_write(fd,modeline_cmd,strlen(modeline_cmd));
    }

    // We are in C65 mode - switch to C64 mode
    if (do_go64) {
      char *cmd="s34a 47 4f 36 34 d 59 d\rsd0 7\r";
      slow_write(fd,cmd,strlen(cmd));
      if (first_go64) fprintf(stderr,"[T+%lldsec] GO64\nY\n",(long long)time(0)-start_time);
      first_go64=0;
    } else {
      fprintf(stderr,"MEGA65 is in C65 mode.\n");
      exit(0);
    }    
  }
  if (!strcmp(line,
			 " :000042C 2A 2A 2A 2A 20 03 0F 0D 0D 0F 04 0F 12 05 20 36")) {
    // C64 mode BASIC -- set LOAD trap, and then issue LOAD command
    char *cmd;
    if (filename) {
      cmd="bf4a5\r";
      slow_write(fd,cmd,strlen(cmd));
      cmd="s277 4c 6f 22 21 d\rsc6 5\r";
      slow_write(fd,cmd,strlen(cmd));
      if (first_load) fprintf(stderr,"[T+%lldsec] LOAD\"!\n",(long long)time(0)-start_time);
      first_load=0;
    } else {
      fprintf(stderr,"MEGA65 is in C64 mode.\n");
      exit(0);
    }
  }  
  if (state==2)
    {
      printf("Filename is %s\n",filename);
      f=fopen(filename,"r");
      if (f==NULL) {
	fprintf(stderr,"Could not find file '%s'\n",filename);
	exit(-1);
      } else {
	char cmd[64];
	int load_addr=fgetc(f);
	load_addr|=fgetc(f)<<8;
	printf("Load address is $%04x\n",load_addr);
	usleep(50000);
	unsigned char buf[16384];
	int max_bytes=4096;
	int b=fread(buf,1,max_bytes,f);
	while(b>0) {
	  printf("Read to $%04x (%d bytes)\n",load_addr,b);
	  fflush(stdout);
	  // load_addr=0x400;
	  sprintf(cmd,"l%x %x\r",load_addr-1,load_addr+b-1);
	  slow_write(fd,cmd,strlen(cmd));
	  usleep(1000);
	  int n=b;
	  unsigned char *p=buf;
	  while(n>0) {
	    int w=write(fd,p,n);
	    if (w>0) { p+=w; n-=w; } else usleep(1000);
	  }
	  if (serial_speed==230400) usleep(10000+50*b);
	  else usleep(10000+6*b);
	  load_addr+=b;
	  b=fread(buf,1,max_bytes,f);	  
	}
	fclose(f); f=NULL;
	// set end address, clear input buffer, release break point,
	// jump to end of load routine, resume CPU at a CLC, RTS
	usleep(50000);

	sprintf(cmd,"sc6 0\r");
	slow_write(fd,cmd,strlen(cmd));	usleep(20000);
	sprintf(cmd,"b\r");
	slow_write(fd,cmd,strlen(cmd));	usleep(20000);

	// We need to set X and Y to load address before
	// returning: LDX #$ll / LDY #$yy / CLC / RTS
	sprintf(cmd,"s380 a2 %x a0 %x 18 60\r",
		load_addr&0xff,(load_addr>>8)&0xff);
	slow_write(fd,cmd,strlen(cmd));	usleep(20000);

	sprintf(cmd,"g0380\r");
	slow_write(fd,cmd,strlen(cmd));	usleep(20000);

	sprintf(cmd,"t0\r");
	slow_write(fd,cmd,strlen(cmd));	usleep(20000);

	if (do_run) {
	  sprintf(cmd,"s277 52 55 4e d\rsc6 4\r");
	  slow_write(fd,cmd,strlen(cmd));
	  fprintf(stderr,"[T+%lldsec] RUN\n",(long long)time(0)-start_time);
	}

	printf("\n");
	// loaded ok.
	printf("LOADED.\n");
	exit(0);
      }
    }
  return 0;
}


char line[1024];
int line_len=0;

int process_char(unsigned char c, int live)
{
  // printf("char $%02x\n",c);
  if (c=='\r'||c=='\n') {
    line[line_len]=0;
    if (line_len>0) process_line(line,live);
    line_len=0;
  } else {
    if (line_len<1023) line[line_len++]=c;
  }
  return 0;
}

int process_waiting(int fd)
{
  unsigned char  read_buff[1024];
  int b=read(fd,read_buff,1024);
  while (b>0) {
    int i;
    for(i=0;i<b;i++) {
      process_char(read_buff[i],1);
    }
    b=read(fd,read_buff,1024);    
  }
  return 0;
}

int assemble_modeline( int *b,
		       int hpixels,int hwidth,
		       int vpixels,int vheight,
		       int hsync_polarity,int vsync_polarity,
		       int vsync_start,int vsync_end,
		       int hsync_start_in,int hsync_end_in,
		       int rasters_per_vicii_raster)
{

  // VSYNC pulse ends at end of frame. vsync_delay says how many
  // rasters after vpixels the vsync starts
  // (This means that we need to adjust the start of the frame vertically,
  // for which we don't currently have a register)
  int vsync_rasters=vsync_end-vsync_start+1;
  int vsync_delay=vheight-vpixels-vsync_rasters;
  
  // Pixel data starts at 0x80 always on M65, so have to adjust
  // hsync_start and hsync_end accordingly.
  int hsync_start=hsync_start_in+0x80;
  int hsync_end=hsync_end_in+0x80;
  if (hsync_start>=hwidth) hsync_start-=hwidth;
  if (hsync_end>=hwidth) hsync_end-=hwidth;
  
  b[2]=/* $D072 */       vsync_delay; 
  b[3]=/* $D072 */       (hsync_end>>8)&0xf;
  b[4]=/* $D072 */       hsync_end&0xff;
  b[5]=/* $D075 */	 hpixels&0xff;
  b[6]=/* $D076 */	 hwidth&0xff;
  b[7]=/* $D077 */	 ((hpixels>>8)&0xf) + ((hwidth>>4)&0xf0);
  b[8]=/* $D078 */	 vpixels&0xff;
  b[9]=/* $D079 */	 vheight&0xff;
  b[0xa]=/* $D07A */	 ((vpixels>>8)&0xf) + ((vheight>>4)&0xf0);
  b[0xb]=/* $D07B */	 hsync_start&0xff;
  b[0xc]=/* $D07C */	 ((hsync_start>>8)&0xf)
    + (hsync_polarity?0x10:0)
    + (vsync_polarity?0x20:0)
    + (((rasters_per_vicii_raster-1)&0x3) <<6);

  fprintf(stderr,"Assembled mode with hfreq=%.2fKHz, vfreq=%.2fHz, vsync=%d rasters.\n",
	  150000000.0/hwidth,150000000.0/hwidth/vheight,
	  vheight-vpixels-vsync_delay);
  
  return 0;
}

void parse_video_mode(int b[16+5])
{
  int vsync_delay=b[2];
  int hsync_end=((b[3]&0xf)<<8)+b[4];
  int hpixels=b[5]+((b[7]&0xf)<<8);
  int hwidth=b[6]+((b[7]&0xf0)<<4);
  int vpixels=b[8]+((b[0xa]&0xf)<<8);
  int vheight=b[9]+((b[0xa]&0xf0)<<4);
  int hsync_start=b[0xb]+((b[0xc]&0xf)<<8);
  int hsync_polarity=b[0xc]&0x10;
  int vsync_polarity=b[0xc]&0x20;
  int rasters_per_vicii_raster=((b[0xc]&0xc0)>>6);
  
  float pixelclock=150000000;
  float frame_hertz=pixelclock/(hwidth*vheight);
  float hfreq=pixelclock/hwidth/1000.0;
  
  fprintf(stderr,"Video mode is %dx%d pixels, %dx%d frame, sync=%c/%c, vertical stretch=2+%d, frame rate=%.1fHz, hfreq=%.3fKHz.\n",
	  hpixels,vpixels,hwidth,vheight,
	  hsync_polarity ? '-' : '+',
	  vsync_polarity ? '-' : '+',
	  rasters_per_vicii_raster,
	  frame_hertz,hfreq);
  fprintf(stderr,"   hpixels=$%04x (%d) $D075,$D077.0-3\n",
	  hpixels,hpixels);
  fprintf(stderr,"   hwidth=$%04x (%d) $D076,$D077.7-4\n",
	  hwidth,hwidth);
  fprintf(stderr,"   vpixels=$%04x (%d) $D078,$D07A.0-3\n",
	  vpixels,vpixels);
  fprintf(stderr,"   vsync=$%04x (%d) - $%04x (%d)\n",
	  vpixels+vsync_delay,vpixels+vsync_delay,
	  vheight,vheight);
  fprintf(stderr,"   hsync=$%04x (%d) -- $%04x (%d)\n",
	  hsync_start,hsync_start,
	  hsync_end,hsync_end);
  
  return;
}

int prepare_modeline(char *modeline)
{
  // Parse something like:
  // Modeline "1920x1200" 151.138 1920 1960 1992 2040 1200 1201 1204 1232 -hsync

  char opt1[1024],opt2[1024];
  float pixel_clock_mhz;
  int hpixels,hsync_start,hsync_end,hwidth;
  int vpixels,vsync_start,vsync_end,vheight;
  int hsync_polarity=0;
  int vsync_polarity=0;

  fprintf(stderr,"Parsing [%s] as modeline\n",modeline);
  if (sscanf(modeline,"Modeline \"%*dx%*d\" %f %d %d %d %d %d %d %d %d %s %s",
	     &pixel_clock_mhz,
	     &hpixels,&hsync_start,&hsync_end,&hwidth,
	     &vpixels,&vsync_start,&vsync_end,&vheight,
	     opt1,opt2)>=9)
    {
      int pixel_clock=pixel_clock_mhz*1000000;
      int rasters_per_vicii_raster=(vpixels-80)/200;
      int b[16+5];

      if (!strcasecmp("-hsync",opt1)) hsync_polarity=1;
      if (!strcasecmp("-hsync",opt2)) hsync_polarity=1;
      if (!strcasecmp("-vsync",opt1)) vsync_polarity=1;
      if (!strcasecmp("-vsync",opt2)) vsync_polarity=1;
      
      assemble_modeline(b,hpixels,hwidth,vpixels,vheight,
			hsync_polarity,vsync_polarity,
			vsync_start,vsync_end,
			hsync_start,hsync_end,
			rasters_per_vicii_raster);

      snprintf(modeline_cmd,1024,
	       "\nsffd3072 %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x\nsffd3011 1b\n",
	       b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[0xa],b[0xb],b[0xc]);

      parse_video_mode(b);
      
    }
  else {
    fprintf(stderr,"modeline is badly formatted.\n");
    usage();
  }

  return 0;
}

int main(int argc,char **argv)
{
  start_time=time(0);
  
  int opt;
  while ((opt = getopt(argc, argv, "4l:s:b:k:rR:C:m:")) != -1) {
    switch (opt) {
    case 'R': romfile=strdup(optarg); break;
    case 'C': charromfile=strdup(optarg); break;      
    case '4': do_go64=1; break;
    case 'r': do_run=1; break;
    case 'l': strcpy(serial_port,optarg); break;
    case 'm': prepare_modeline(optarg); break;
    case 's':
      serial_speed=atoi(optarg);
      switch(serial_speed) {
      case 230400: case 2000000: break; case 4000000:
      default: usage();
      }
      break;
    case 'b':
      bitstream=strdup(optarg); break;
    case 'k': kickstart=strdup(optarg); break;
    default: /* '?' */
      usage();
    }
  }  

  if ((romfile||charromfile)&&(!kickstart)) {
    fprintf(stderr,"-k is required with -R or -C\n");
    usage();
  }
  
  if (argv[optind]) filename=strdup(argv[optind]);
  if (argc-optind>1) usage();
  
  // Load bitstream if file provided
  if (bitstream) {
    char cmd[1024];
    snprintf(cmd,1024,"fpgajtag -a %s",bitstream);
    fprintf(stderr,"%s\n",cmd);
    system(cmd);
    fprintf(stderr,"[T+%lldsec] Bitstream loaded\n",(long long)time(0)-start_time);
  }
  
  errno=0;
  fd=open(serial_port,O_RDWR);
  if (fd==-1) {
    fprintf(stderr,"Could not open serial port '%s'\n",serial_port);
    perror("open");
    exit(-1);
  }
  fcntl(fd,F_SETFL,fcntl(fd, F_GETFL, NULL)|O_NONBLOCK);
  struct termios t;
  if (serial_speed==230400) {
    if (cfsetospeed(&t, B230400)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B230400)) perror("Failed to set input baud rate");
  } else if (serial_speed==2000000) {
    if (cfsetospeed(&t, B2000000)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B2000000)) perror("Failed to set input baud rate");
  } else {
    if (cfsetospeed(&t, B4000000)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B4000000)) perror("Failed to set input baud rate");
  }
  t.c_cflag &= ~PARENB;
  t.c_cflag &= ~CSTOPB;
  t.c_cflag &= ~CSIZE;
  t.c_cflag &= ~CRTSCTS;
  t.c_cflag |= CS8 | CLOCAL;
  t.c_lflag &= ~(ICANON | ISIG | IEXTEN | ECHO | ECHOE);
  t.c_iflag &= ~(BRKINT | ICRNL | IGNBRK | IGNCR | INLCR |
                 INPCK | ISTRIP | IXON | IXOFF | IXANY | PARMRK);
  t.c_oflag &= ~OPOST;
  if (tcsetattr(fd, TCSANOW, &t)) perror("Failed to set terminal parameters");

  unsigned long long last_check = gettime_ms();
  int phase=0;

  while(1)
    {
      int b;
      char read_buff[1024];
      switch(state) {
      case 0: case 2: case 3: case 99:
	errno=0;
	b=read(fd,read_buff,1024);
	if (b>0) {
	  int i;
	  for(i=0;i<b;i++) {
	    process_char(read_buff[i],1);
	  }
	} else {
	  usleep(1000);
	}
	if (gettime_ms()>last_check) {
	  if (state==99) printf("sending R command to sync @ %dpbs.\n",serial_speed);
	  switch (phase%3) {
	  case 0: slow_write(fd,"r\r",2); break; // PC check
	  case 1: slow_write(fd,"m86d\r",5); break; // C65 Mode check
	  case 2: slow_write(fd,"m42c\r",5); break; // C64 mode check
	  default: phase=0;
	  }
	  phase++;	  
	  last_check=gettime_ms()+50;
	}
	break;
      case 1: // trapped LOAD, so read file name
	slow_write(fd,"mb7\r",4);
	state=0;
	break;
      default:
	usleep(1000);	
      }
    }

  return 0;
}
