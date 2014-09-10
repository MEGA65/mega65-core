/*
  (C) Paul Gardner-Stephen 2014.

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
#include <errno.h>
#include <sys/socket.h>
#include <sys/filio.h>
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

int client_sock=-1;

int create_listen_socket(int port)
{
  int sock = socket(AF_INET,SOCK_STREAM,0);
  if (sock==-1) return -1;

  int on=1;
  if (setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, (char *)&on, sizeof(on)) == -1) {
    close(sock); return -1;
  }
  if (ioctl(sock, FIONBIO, (char *)&on) == -1) {
    close(sock); return -1;
  }
  
  /* Bind it to the next port we want to try. */
  struct sockaddr_in address;
  bzero((char *) &address, sizeof(address));
  address.sin_family = AF_INET;
  address.sin_addr.s_addr = INADDR_ANY;
  address.sin_port = htons(port);
  if (bind(sock, (struct sockaddr *) &address, sizeof(address)) == -1) {
    close(sock); return -1;
  } 

  if (listen(sock, 20) != -1) return sock;

  close(sock);
  return -1;
}

int accept_incoming(int sock)
{
  struct sockaddr addr;
  unsigned int addr_len = sizeof addr;
  int asock;
  if ((asock = accept(sock, &addr, &addr_len)) != -1) {
    // XXX show remote address
    return asock;
  }

  return -1;
}

int read_from_socket(int sock,unsigned char *buffer,int *count,int buffer_size,
		     int timeout)
{
  fcntl(sock,F_SETFL,fcntl(sock, F_GETFL, NULL)|O_NONBLOCK);


  int t=time(0)+timeout;
  if (*count>=buffer_size) return 0;
  int r=read(sock,&buffer[*count],buffer_size-*count);
  while(r!=0) {
    if (r>0) {
      (*count)+=r;
      break;
    }
    r=read(sock,&buffer[*count],buffer_size-*count);
    if (r==-1&&errno!=EAGAIN) {
      perror("read() returned error. Stopping reading from socket.");
      return -1;
    } else usleep(100000);
    // timeout after a few seconds of nothing
    if (time(0)>=t) break;
  }
  buffer[*count]=0;
  return 0;
}

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
      if (d[i]!='\r') {
	usleep(100);
	write(fd,&d[i],1);
      }
    }
  return 0;
}

int max(int a, int b)
{
  if (a>b) return a; else return b;
}

#define MAX_CLIENTS 256
int clients[MAX_CLIENTS];
int client_count=0;

int main(int argc,char **argv)
{
  if (argc!=2) {
    fprintf(stderr,"You must specify the serial port to proxy.\n");
    exit(-1);
  }
  
  int listen_sock = create_listen_socket(4510);
  if (listen_sock==-1) { perror("Couldn't listen to port 4510"); exit(-1); }

  int fd=open(argv[1],O_RDWR);  
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

  while(1) {
    if (client_count<MAX_CLIENTS) {
      int client_sock = accept_incoming(listen_sock);
      if (client_sock!=-1) {
	clients[client_count]=client_sock;
	client_count++;
	printf("New connection. %d total.\n",client_count);
      }
    }

    int i;
    unsigned char buffer[1024];
    struct pollfd fds[1+MAX_CLIENTS];
    fds[0].fd=fd; fds[0].events=POLLIN; fds[0].revents=0;
    for (i=0;i<client_count;i++)
      fds[1+i].fd=clients[i]; fds[1+i].events=POLLIN; fds[1+i].revents=0;

    // read from serial port and write to client socket(s)
    int s=poll(fds,1+client_count,500);
    if (fds[0].revents&POLLIN) {
      int c=read(fd,buffer,1024);
      int i;
      for(i=0;i<client_count;i++) write(clients[i],buffer,c);
    }
    // read from client sock and write to serial port slowly
    for(i=0;i<client_count;i++)
      if (fds[1+i].revents&POLLIN) {
	int c=read(clients[i],buffer,1024);
      slow_write(fd,buffer,c);
      if (c<1) { 
	close(clients[i]); 
	clients[i]=clients[--client_count];
	printf("Closed client connection, %d remaining.\n",client_count); }
    }
  }

  return 0;
}
