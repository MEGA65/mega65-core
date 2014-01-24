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

int process_line(char *line)
{
  int pc,a,x,y,sp,p;
  if (sscanf(line,"%04x %02x %02x %02x %02x %02x",
	     &pc,&a,&x,&y,&sp,&p)==6) {
    printf("PC=$%04x\n",pc);
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
  int fd=open(argv[1],O_RDWR);
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
  // Also setup breakpoint
  slow_write(fd,"\025r\rbf4a2\rt0\r",12);

  time_t last_check = time(0);

  while(1)
    {
      char read_buff[1024];
      int b=read(fd,read_buff,1024);
      if (b>0) {
	int i;
	for(i=0;i<b;i++) {
	  process_char(read_buff[i]);
	}
      } else usleep(10000);
      if (time(0)>last_check) {
	slow_write(fd,"\025r\r",3);
	last_check=time(0);
      }
    }

  return 0;
}
