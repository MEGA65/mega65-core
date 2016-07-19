/*
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

int debug_x=0;
int debug_y=310;
int toggle=0;

int process_char(unsigned char c,int live);

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
      if (write(fd,&d[i],1)<1) perror("write");
    }
  return 0;
}

int fd=-1;
int state=0;
int name_len,name_lo,name_hi,name_addr=-1;
char filename[17];
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
  int x_chargen_start_minus16_low,x_chargen_start_minus16_high;
  int next_card_number_low,next_card_number_high,cycles_to_next_card,flags;
  int char_fetch_cycle;
  int char_address_low,char_address_high,next_charrow;
  // printf("[%s]\n",line);
  if (!live) return 0;
  if (sscanf(line," :FFD30F0 %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
	     &x_chargen_start_minus16_low,
	     &x_chargen_start_minus16_high,
	     &next_card_number_low,&next_card_number_high,
	     &cycles_to_next_card,
	     &flags,&char_fetch_cycle,
	     &char_address_low,&char_address_high,
	     &next_charrow
	     )==10) {
    int chargen_active_soon=flags&1;
    int chargen_active=flags&2;
    printf("display_y=%d, display_x=%d, x_chargen_start_minus16=%d, next_card_number=%d, cycles_to_next_card=%d, char_fetch_cycle=%d, chargen_active=%d, chargen_active_soon=%d, charaddress=$%04x, next_charrow=$%02x\n",
	   debug_y,debug_x,
	   (x_chargen_start_minus16_high<<8)+x_chargen_start_minus16_low,
	   next_card_number_low+(next_card_number_high<<8),
	   cycles_to_next_card,char_fetch_cycle,
	   chargen_active,chargen_active_soon,
	   (char_address_low+(char_address_high)*256),next_charrow);
  }
  return 0;
}


char line[1024];
int line_len=0;

int process_char(unsigned char c, int live)
{
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
  search_path=argv[2];
  fd=open(argv[1],O_RDWR);
  if (fd==-1) perror("open");
  if (fcntl(fd,F_SETFL,fcntl(fd, F_GETFL, NULL)|O_NONBLOCK))
    perror("fcntl");
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
  usleep(20000);
  slow_write(fd,"\r",1);
  usleep(50000);
  slow_write(fd,"r\r",2);

  unsigned long long last_check = gettime_ms();

  while(1)
    {
      int b;
      char read_buff[1024];
	b=read(fd,read_buff,1024);
	if (b>0) {
	  int i;
	  for(i=0;i<b;i++) {
	    process_char(read_buff[i],1);
	  }
	} else usleep(10000);
	if (gettime_ms()>last_check) {
	  if (!toggle) {
	    char cmd[1024];
	    // set debug coordinates
	    debug_x++;
	    debug_x&=0xfff;
	    sprintf(cmd,"sffd30fc %02x %02x %02x %02x\r",
		    debug_x&0xff,debug_x>>8,debug_y&0xff,debug_y>>8);
	    slow_write(fd,cmd,strlen(cmd));
	  } else {
	    // read debug registers
	    slow_write(fd,"mffd30f0\r",9);
	  }
	  toggle^=1;
	  // Allow 2 frames before advancing debug point
	  last_check=gettime_ms()+(1000/60)*2;
	}
    }

  return 0;
}
