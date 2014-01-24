/*
  LOAD wedge for C65GS serial monitor.
  Activates a break point at $F4A2, and then checks periodically to see if the
  CPU is there.  If so, extract file name, look for it in search path, and
  then either load it, set X & Y to upper address, and then return success (gf5a9),
  or return file not found error (gf704), and then resume the CPU (t0).

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

int slow_write(int fd,char *d,int l)
{
  // UART is at 230400bps, but reading commands has no FIFO, and echos
  // characters back, meaning we need a 1 char gap between successive
  // characters.  This means >=1/23040sec delay. We'll allow roughly
  // double that at 100usec.
  int i;
  for(i=0;i<l;i++)
    {
      usleep(100);
      write(fd,&d[i],1);
    }
  return 0;
}

int fd=-1;
int state=0;
int name_len,name_lo,name_hi,name_addr=-1;
char filename[17];
FILE *f=NULL;

int process_line(char *line)
{
  int pc,a,x,y,sp,p;
  int addr;
  char filename[17];
  printf("[%s]\n",line);
  if (sscanf(line,"%04x %02x %02x %02x %02x %02x",
	     &pc,&a,&x,&y,&sp,&p)==6) {
    printf("PC=$%04x\n",pc);
    if (pc==0xf4a5) {
      // Intercepted LOAD command
      state=1;
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
  if (sscanf(line," :%07x"
	     " %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx"
	     " %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx %02hhx",
	     &addr,
	     &filename[0],&filename[1],&filename[2],&filename[3],
	     &filename[4],&filename[5],&filename[6],&filename[7],
	     &filename[8],&filename[9],&filename[10],&filename[11],
	     &filename[12],&filename[13],&filename[14],&filename[15])==17) {
    if (addr==name_addr) {
      // Got filename to load
      filename[16]=0;
      filename[name_len]=0;
      // Invert case
      int i; for(i=0;i<name_len;i++) if (isalpha(filename[i])) filename[i]^=0x20;
      printf("Filename is %s\n",filename);
      f=fopen(filename,"r");
      if (f==NULL) {
	// file not found error
	usleep(50000);
	slow_write(fd,"gf704\r",6);
	usleep(50000);
	slow_write(fd,"t0\r",3);
	usleep(50000);
      }
      fclose(f); f=NULL;
    }
  }
  return 0;
}


char line[1024];
int line_len=0;

int process_char(unsigned char c)
{
  if (c=='\r'||c=='\n') {
    line[line_len]=0;
    if (line_len>0) process_line(line);
    line_len=0;
  } else {
    if (line_len<1023) line[line_len++]=c;
  }
  return 0;
}

int main(int argc,char **argv)
{
  fd=open(argv[1],O_RDWR);
  if (fd==-1) perror("open");
  fcntl(fd,F_SETFL,fcntl(fd, F_GETFL, NULL)|O_NONBLOCK);
  struct termios t;
  if (cfsetospeed(&t, B230400)) perror("Failed to set output baud rate");
  if (cfsetispeed(&t, B230400)) perror("Failed to set input baud rate");
  t.c_cflag &= ~PARENB;
  t.c_cflag &= ~CSTOPB;
  t.c_cflag &= ~CSIZE;
  t.c_cflag |= CS8;
  t.c_lflag &= ~(ICANON | ISIG | IEXTEN | ECHO | ECHOE);
  t.c_iflag &= ~(BRKINT | ICRNL | IGNBRK | IGNCR | INLCR |
                 INPCK | ISTRIP | IXON | IXOFF | IXANY | PARMRK);
  t.c_oflag &= ~OPOST;
  if (tcsetattr(fd, TCSANOW, &t)) perror("Failed to set terminal parameters");

  // Send ^U r <return> to print registers and get into a known state.
  slow_write(fd,"\025r\r",3);
  usleep(50000);
  slow_write(fd,"bf4a2\r",6);   // Also setup breakpoint
  usleep(50000);
  slow_write(fd,"sffd0c01 0\r",11); // and make keyboard workaround CIA bug
  usleep(50000);
  slow_write(fd,"t0\r",3); // and set CPU going
  usleep(50000);

  time_t last_check = time(0);

  while(1)
    {
      int b;
      char read_buff[1024];
      switch(state) {
      case 0:
	b=read(fd,read_buff,1024);
	if (b>0) {
	  int i;
	  for(i=0;i<b;i++) {
	    process_char(read_buff[i]);
	  }
	} else usleep(10000);
	if (time(0)>last_check) {
	  slow_write(fd,"r\r",2);
	  last_check=time(0);
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
