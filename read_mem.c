/*
  Use serial monitor to extract memory contents from a running C65GS machine.

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

FILE *outfile=NULL;

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
      usleep(100);
      write(fd,&d[i],1);
    }
  return 0;
}

int fd=-1;
int state=99;
int name_len,name_lo,name_hi,name_addr=-1;
char filename[17];
FILE *f=NULL;

unsigned int start_addr=0;
unsigned int end_addr=0x40000;

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
  unsigned int addr;
  char filename[17];
  // printf("[%s]\n",line);
  if (!live) return 0;
  if (sscanf(line,"%04x %02x %02x %02x %02x %02x",
	     &pc,&a,&x,&y,&sp,&p)==6) {
    // printf("PC=$%04x\n",pc);
    if (state==99) {
      // Synchronised with monitor
      state=0;
      // Send ^U r <return> to print registers and get into a known state.
      usleep(50000);
      // Ask for first block of memory
      sprintf(filename,"M%x\r",start_addr);
      slow_write(fd,filename,strlen(filename));
    }
  }
  unsigned char b[16];
  if (line[0]=='.') {
    state=0;
    sprintf(filename,"M%x\r",start_addr);
    slow_write(fd,filename,strlen(filename));
  }
  if (sscanf(line,
	     " :%07x %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx"
	     " %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx",
	     &addr,
	     &b[0],&b[1],&b[2],&b[3],&b[4],&b[5],&b[6],&b[7],
	     &b[8],&b[9],&b[10],&b[11],&b[12],&b[13],&b[14],&b[15])==17) {
    if (addr>=end_addr) {
      printf("Read all requested memory\n");
      fclose(outfile);
      exit(0);
    } else {
      if (addr==start_addr) {
	start_addr+=16;
	printf("%s\n",line);
	if (!outfile) outfile=fopen("memory.bin","w");
	fwrite(b,16,1,outfile);
      }
    }
    state=0;
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
  if (argc>2&&argv[2]) start_addr=strtoll(argv[2],NULL,16);
  if (argc>3&&argv[3]) end_addr=strtoll(argv[3],NULL,16);
  printf("Dumping memory from $%x to $%x\n",start_addr,end_addr);

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
	  if (state==99) printf("sending M command to sync.\n");
	  sprintf(filename,"M%x\r",start_addr);
	  slow_write(fd,filename,strlen(filename));
	  last_check=gettime_ms()+50;
	}
	break;
      }
    }

  return 0;
}
