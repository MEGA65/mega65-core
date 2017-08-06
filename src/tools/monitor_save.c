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

FILE  *o=NULL;

unsigned long long gettime_ms(void);

unsigned long long last_check;


int process_char(unsigned char c,int live);

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
int start_addr=-1;
int end_addr=-1;
char *filename=NULL;
FILE *f=NULL;
char serial_port[1024]="/dev/ttyUSB1"; // XXX do a better job auto-detecting this
int serial_speed=2000000;



unsigned long long gettime_ms(void)
{
  struct timeval nowtv;
  // If gettimeofday() fails or returns an invalid value, all else is lost!
  if (gettimeofday(&nowtv, NULL) == -1)
    perror("gettimeofday");
  return nowtv.tv_sec * 1000LL + nowtv.tv_usec / 1000;
}

int process_line(char *line,int live)
{
  int pc,a,x,y,sp,p;
  // printf("[%s]\n",line);
  if (!live) return 0;
  if (sscanf(line,"%04x %02x %02x %02x %02x %02x",
	     &pc,&a,&x,&y,&sp,&p)==6) {
    // printf("PC=$%04x\n",pc);
    if (pc==0xf4a5||pc==0xf4a2) {
      // Intercepted LOAD command
      state=1;
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
	slow_write(fd,"m2b\r",4); // and ask for BASIC memory pointers
	usleep(20000);	
	printf("Synchronised with monitor.\n");
      }
    }
  }
  {
    int bs_low,bs_high,be_low,be_high;
    if (sscanf(line," :000002B %02x %02x %02x %02x",
	       &bs_low,&bs_high,&be_low,&be_high)==4) {
      start_addr=bs_low+(bs_high<<8);
      end_addr=be_low+(be_high<<8)-1;
      fprintf(stderr,"BASIC program occupies $%04x -- $%04x\n",
	      start_addr,end_addr);
      state=1;
    }
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
      last_check=gettime_ms()+50;
      if (addr==start_addr) {
	for(int i=0;i<16&&(start_addr+i)<=end_addr;i++) fputc(b[i],o);
	start_addr+=0x10;
	if (start_addr>end_addr) {
	  // All done
	  fprintf(stderr,"[T+%lldsec] Finished saving $0801 -- $%04x.\n",
		  (long long)time(0)-start_time,end_addr);
	  fclose(o);
	  exit(0);
	}
      }
    }
  }
  return 0;
}


char line[1024];
int line_len=0;

int process_char(unsigned char c, int live)
{
  // printf("char $%02x\n",c);
  if ((!line_len)&&(c=='.')) {
    if (state==1) {
      char cmd[1024];
      snprintf(cmd,1024,"M%x\r",start_addr);
      slow_write(fd,cmd,strlen(cmd));
    }
  }
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

void usage(void)
{
  fprintf(stderr,"MEGA65 cross-development tool for saving from a running MEGA65.\n");
  fprintf(stderr,"usage: monitor_load [-l <serial port>] [-s <230400|2000000|4000000>]  filename\n");
  fprintf(stderr,"  -l - Name of serial port to use, e.g., /dev/ttyUSB1\n");
  fprintf(stderr,"  -s - Speed of serial port in bits per second. This must match what your bitstream uses.\n");
  fprintf(stderr,"       (Older bitstream use 230400, and newer ones 2000000 or 4000000).\n");
  fprintf(stderr,"  filename - Name of file to save memory into.\n");
  fprintf(stderr,"\n");
  exit(-3);
}

int main(int argc,char **argv)
{
  start_time=time(0);
  last_check = gettime_ms();
  
  int opt;
  while ((opt = getopt(argc, argv, "l:s:")) != -1) {
    switch (opt) {
    case 'l': strcpy(serial_port,optarg); break;
    case 's':
      serial_speed=atoi(optarg);
      switch(serial_speed) {
      case 230400: case 2000000: case 4000000: break;
      default: usage();
      }
      break;
    default: /* '?' */
      usage();
    }
  }  
  
  if (argv[optind]) filename=strdup(argv[optind]);
  if (argc-optind>1) usage();

  if (!filename) usage();

  o=fopen(filename,"w");
  if (!o) {
    perror("Could not open output file.");
    exit(-3);
  }
  // C64 BASIC header
  fputc(1,o); fputc(8,o);
  
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
  } else if (serial_speed==4000000) {
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

  int phase=0;

  while(1)
    {
      int b;
      char read_buff[1024];
      switch(state) {
      case 0: case 1: case 2: case 3: case 99:
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
	  slow_write(fd,"r\r",2); break; // PC check
	  last_check=gettime_ms()+50;
	}
	break;
      default:
	usleep(1000);	
      }
    }

  return 0;
}
