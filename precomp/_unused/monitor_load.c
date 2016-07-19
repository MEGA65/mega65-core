/*
  Load the specified program into memory on the C65GS via the serial monitor.

Copyright (C) 2014 Paul Gardner-Stephen
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

int process_char(unsigned char c,int live);

int slow_write(int fd,char *d,int l)
{
  // UART is at 230400bps, but reading commands has no FIFO, and echos
  // characters back, meaning we need a 1 char gap between successive
  // characters.  This means >=1/23040sec delay. We'll allow roughly
  // double that at 100usec.
  // printf("Writing [%s]\n",d);
  int i;
  for(i=0;i<l;i++)
    {
      usleep(2000);
      write(fd,&d[i],1);
    }
  return 0;
}

int fd=-1;
int state=99;
int name_len,name_lo,name_hi,name_addr=-1;
char *filename=NULL;
FILE *f=NULL;
char *search_path=".";

unsigned long long gettime_ms()
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
  int addr;
  // printf("[%s]\n",line);
  if (!live) return 0;
  if (sscanf(line,"%04x %02x %02x %02x %02x %02x",
	     &pc,&a,&x,&y,&sp,&p)==6) {
    printf("PC=$%04x\n",pc);
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
	printf("Synchronised with monitor.\n");
      }
    }
  }
  if (sscanf(line," :00000B7 %02x %*02x %*02x %*02x %02x %02x",
	     &name_len,&name_lo,&name_hi)==3) {
    name_addr=(name_hi<<8)+name_lo;
    printf("Filename is %d bytes long, and is stored at $%04x\n",
	   name_len,name_addr);
    snprintf(filename,16,"m%04x\r",name_addr);
    slow_write(fd,filename,strlen(filename));
    state=0;
  }
  if (state==0)
 {
      printf("Filename is %s\n",filename);
      f=fopen(filename,"r");
      if (f==NULL) {
	fprintf(stderr,"Could not find file '%s'\n",filename);
	exit(-1);
      } else {
	int load_addr=fgetc(f);
	load_addr|=fgetc(f)<<8;
	printf("Load address is $%04x\n",load_addr);
	usleep(50000);
	unsigned char buf[1024];
	int b=fread(buf,1,1024,f);
	while(b>0) {
	  int i;
	  int n;
	  for(i=0;i<b;i+=16) {
	    if ((i+16)>b) n=b-i; else n=16;
	    char cmd[64];
	    printf("Read to $%04x\r",load_addr);
	    fflush(stdout);
	    // XXX - writes 16 bytes even if there are less bytes ready.
	    sprintf(cmd,"s%x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x\r",
		    load_addr,
		    buf[i+0],buf[i+1],buf[i+2],buf[i+3],buf[i+4],buf[i+5],buf[i+6],buf[i+7],
		    buf[i+8],buf[i+9],buf[i+10],buf[i+11],buf[i+12],buf[i+13],buf[i+14],buf[i+15]);

	    slow_write(fd,cmd,strlen(cmd));
	    usleep(50000);
	    load_addr+=n;

	    {
	      unsigned char read_buff[1024];
	      int b=read(fd,read_buff,1024);
	      if (b>0) {
		int i;
		for(i=0;i<b;i++) {
		  process_char(read_buff[i],0);
		}
	      }
	    }
	  }
	  b=fread(buf,1,1024,f);
	}
	fclose(f); f=NULL;
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

int main(int argc,char **argv)
{
  filename=argv[2];
  printf("Filename to load is %s\n",filename);
  errno=0;
  fd=open(argv[1],O_RDWR);
  perror("A");
  if (fd==-1) perror("open");
  perror("B");
  fcntl(fd,F_SETFL,fcntl(fd, F_GETFL, NULL)|O_NONBLOCK);
  perror("C");
  struct termios t;
  if (cfsetospeed(&t, B230400)) perror("Failed to set output baud rate");
  perror("D");
  if (cfsetispeed(&t, B230400)) perror("Failed to set input baud rate");
  perror("E");
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
  perror("F");

  unsigned long long last_check = gettime_ms();

  while(1)
    {
      int b;
      char read_buff[1024];
      switch(state) {
      case 0: case 99:
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
	  if (state==99) printf("sending R command to sync.\n");
	  slow_write(fd,"r\r",2);
	  last_check=gettime_ms()+50;
	}
	break;
      case 1: // trapped LOAD, so read file name
	slow_write(fd,"mb7\r",4);
	state=0;
	break;
      }
    }

  return 0;
}
