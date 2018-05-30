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

int sendScanCode(int scan_code);

int raster_line_number=-1;
unsigned int raster_line[800];

int colour0,colour1,colour2,colour3,colour4;

int image_offset=0;
int drawing=0;
int y;

#ifdef WIN32
#define sleep Sleep
#else
#include <unistd.h>
#endif

#include <rfb/rfb.h>
#include <rfb/keysym.h>

static const int bpp=4;
static int maxx=800, maxy=600;

static void initBuffer(unsigned char* buffer)
{
  bzero(buffer,maxx*maxy);
}

/* Here we create a structure so that every client has it's own pointer */

typedef struct ClientData {
  rfbBool oldButton;
  int oldx,oldy;
} ClientData;

static void clientgone(rfbClientPtr cl)
{
  free(cl->clientData);
}

static enum rfbNewClientAction newclient(rfbClientPtr cl)
{
  cl->clientData = (void*)calloc(sizeof(ClientData),1);
  cl->clientGoneHook = clientgone;
  return RFB_CLIENT_ACCEPT;
}

#if 0
/* switch to new framebuffer contents */
static void newframebuffer(rfbScreenInfoPtr screen, int width, int height)
{
  unsigned char *oldfb, *newfb;

  maxx = width;
  maxy = height;
  oldfb = (unsigned char*)screen->frameBuffer;
  newfb = (unsigned char*)malloc(maxx * maxy * bpp);
  initBuffer(newfb);
  rfbNewFramebuffer(screen, (char*)newfb, maxx, maxy, 8, 3, bpp);
  free(oldfb);
}
#endif
    
/* Here the key events are handled */

static void dokey(rfbBool down,rfbKeySym key,rfbClientPtr cl)
{
  int scan_code = -1;

  switch (key) {
  case XK_Delete: case XK_BackSpace: scan_code = 0x66; break; // DEL
  case XK_Return: scan_code = 0x5a; break; // RETURN
  case XK_Right: scan_code = 0x174; break; // RIGHT
  case XK_Left: scan_code = 0x174; break; // RIGHT
  case XK_F1: scan_code = 0x05; break; // F1/F2
  case XK_F2: scan_code = 0x04; break; // F3/F4
  case XK_F3: scan_code = 0x03; break; // F5/F6
  case XK_F4: scan_code = 0x83; break; // F7/F8
  case XK_Down: scan_code = 0x72; break; // DOWN
  case XK_Up: scan_code = 0x72; break; // DOWN
  case XK_F9: scan_code = 0x17d; break; // RESTORE

  case '3': case '#': scan_code = 0x26; break; // 3
  case 'W': case 'w': scan_code = 0x1d; break; // W
  case 'A': case 'a': scan_code = 0x1c; break; // A
  case '4': case '$': scan_code = 0x25; break; // 4
  case 'Z': case 'z': scan_code = 0x1a; break;
  case 'S': case 's': scan_code = 0x1b; break;
  case 'E': case 'e': scan_code = 0x24; break;
  case XK_Shift_L: scan_code = 0x12;  break; // left-SHIFT

  case '5': case '%': scan_code = 0x2e; break;
  case 'R': case 'r': scan_code = 0x2d; break;
  case 'D': case 'd': scan_code = 0x23; break;
  case '6': case '^': scan_code = 0x36; break;
  case 'C': case 'c': scan_code = 0x21; break;
  case 'F': case 'f': scan_code = 0x2b; break;
  case 'T': case 't': scan_code = 0x2c; break;
  case 'X': case 'x': scan_code = 0x22; break;
    
  case '7': case '&': scan_code = 0x3d; break;
  case 'Y': case 'y': scan_code = 0x35; break;
  case 'G': case 'g': scan_code = 0x34; break;
  case '8': case '*': scan_code = 0x3e; break;
  case 'B': case 'b': scan_code = 0x32; break;
  case 'H': case 'h': scan_code = 0x33; break;
  case 'U': case 'u': scan_code = 0x3c; break;
  case 'V': case 'v': scan_code = 0x2a; break;
    
  case '9': case '(': scan_code = 0x46; break;
  case 'I': case 'i': scan_code = 0x43; break;
  case 'J': case 'j': scan_code = 0x3b; break;
  case '0': case ')': scan_code = 0x45; break;
  case 'M': case 'm': scan_code = 0x3a; break;
  case 'K': case 'k': scan_code = 0x42; break;
  case 'O': case 'o': scan_code = 0x44; break;
  case 'N': case 'n': scan_code = 0x31; break;
  
  case '-': case '_': scan_code = 0x4e; break;
  case 'P': case 'p': scan_code = 0x4d; break;
  case 'L': case 'l': scan_code = 0x4b; break;
  case '+': case '=': scan_code = 0x55; break;
  case '.': case '>': scan_code = 0x49; break;
  case ';': case ':': scan_code = 0x4c; break;
  case '[': case '{': scan_code = 0x54; break; // @
  case ',': case '<': scan_code = 0x41; break;
  
  case XK_F7: scan_code = 0x170; break; // pound
  case ']': case '}': scan_code = 0x5b; break; // *
  case '\'': case '\"': scan_code = 0x52; break; // ;
  case XK_Home: scan_code = 0x16c; break;  // home
  case XK_Shift_R: scan_code = 0x59; break;  // right shift
  case XK_F6: scan_code = 0x5d; break; // =
  case XK_F8: case XK_backslash: case '|': scan_code = 0x171; break; // up-arrow 
  case '/': case '?': scan_code = 0x4a; break;

  case '1': case '!': scan_code = 0x16; break;
  case '`': case '~': scan_code = 0xe; break;
  case XK_Control_L: case XK_Control_R: scan_code = 0xd; break;
  case '2': case '@': scan_code = 0x1e; break;
  case ' ': scan_code = 0x29; break;
  case XK_Alt_L: scan_code = 0x14; break; // C=
  case 'Q': case 'q': scan_code = 0x15; break;
  case XK_Escape: scan_code = 0x76; // runstop
  }
  if (scan_code!=-1) {
    if (!down) scan_code|=0x1000;
    //    printf("scan code $%04x\n",scan_code);
    sendScanCode(scan_code);
  } else {
    //    printf("unknown key $%04x\n",key);
  }

  if(down) {
    if(key==XK_F10)      rfbCloseClient(cl);
  }
}

int updateFrameBuffer(rfbScreenInfoPtr screen)
{  
  // Tell VNC that everything has changed, and let it do the optimisation.
  rfbMarkRectAsModified(screen,0,0,maxx-1,maxy-1);

  return 0;
}

int connect_to_port(int port)
{
  struct hostent *hostent;
  hostent = gethostbyname("127.0.0.1");
  if (!hostent) {
    return -1;
  }

  struct sockaddr_in addr;  
  addr.sin_family = AF_INET;     
  addr.sin_port = htons(port);   
  addr.sin_addr = *((struct in_addr *)hostent->h_addr);
  bzero(&(addr.sin_zero),8);     

  int sock=socket(AF_INET, SOCK_STREAM, 0);
  if (sock==-1) {
    perror("Failed to create a socket.");
    return -1;
  }

  if (connect(sock,(struct sockaddr *)&addr,sizeof(struct sockaddr)) == -1) {
    perror("connect() to port failed");
    close(sock);
    return -1;
  }
  return sock;
}

int serialfd=-1;

int sendScanCode(int scan_code)
{
  if (serialfd==-1) return -1;
  unsigned char msg[4]={27,'K',scan_code&0xff,scan_code>>8};

  write(serialfd,msg,4);

  //  perror("sent scan code");

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
      if (d[i]=='\r'||d[i]=='\n') {
	// CR/LF can cause the output of upto 256 bytes of data.
	// We need to allow time for this.
	// In reality for memory setting, we expect no more than ~40 characters
	// so we can get away with less.
	usleep(25000);
      }
    }
  return 0;
}

#define MAX_CLIENTS 256
int clients[MAX_CLIENTS];
int client_count=0;

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

int listen_sock=-1;

int checkSerialActivity()
{
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
  fds[0].fd=serialfd; fds[0].events=POLLIN; fds[0].revents=0;
  for (i=0;i<client_count;i++)
    fds[1+i].fd=clients[i]; fds[1+i].events=POLLIN; fds[1+i].revents=0;
  
  // read from serial port and write to client socket(s)
  poll(fds,1+client_count,500);
  if (fds[0].revents&POLLIN) {
    int c=read(serialfd,buffer,1024);
    int i;
    for(i=0;i<client_count;i++) write(clients[i],buffer,c);
  }
  // read from client sock and write to serial port slowly
  for(i=0;i<client_count;i++)
    if (fds[1+i].revents&POLLIN) {
      int c=read(clients[i],buffer,1024);
      slow_write(serialfd,(char *)buffer,c);
      if (c<1) { 
	close(clients[i]); 
	clients[i]=clients[--client_count];
	printf("Closed client connection, %d remaining.\n",client_count); }
    }

  return 0;
}

pthread_t serialThread;

void *serial_handler(void *arg)
{
  printf("Monitoring serial port.\n");
  while(1) checkSerialActivity();
}

int openSerialPort(char *port)
{
  serialfd=open(port,O_RDWR);  
  if (serialfd==-1) { perror("open"); return -1; }
  fcntl(serialfd,F_SETFL,fcntl(serialfd, F_GETFL, NULL)|O_NONBLOCK);
  struct termios t;
  if (cfsetospeed(&t, B230400)) perror("Failed to set output baud rate");
  if (cfsetispeed(&t, B230400)) perror("Failed to set input baud rate");
  t.c_cflag &= ~PARENB;
  t.c_cflag &= ~CSTOPB;
  t.c_cflag &= ~CSIZE;
  t.c_cflag &= ~CRTSCTS;
  t.c_cflag |= CS8 | CLOCAL;
  t.c_lflag &= ~(ICANON | ISIG | IEXTEN | ECHO | ECHOE);
  t.c_iflag &= ~(BRKINT | ICRNL | IGNBRK | IGNCR | INLCR |
                 INPCK | ISTRIP | IXON | IXOFF | IXANY | PARMRK);
  t.c_oflag &= ~OPOST;
  if (tcsetattr(serialfd, TCSANOW, &t)) perror("Failed to set terminal parameters");
  perror("F");

  listen_sock = create_listen_socket(4510);
  if (listen_sock==-1) { perror("Couldn't listen to port 4510"); exit(-1); }
  printf("Listening for remote serial connections on port 4510, fd=%d.\n",listen_sock);

  pthread_create(&serialThread,NULL,serial_handler,NULL);

  return 0;
}

int setPixel(rfbScreenInfoPtr screen,int x,int y,uint32_t v)
{
  if (y>=0&&y<maxy&&x>=0&&x<maxx) {  
    ((unsigned char *)screen->frameBuffer)[(y*maxx*4)+x*4+3]=0;
    ((unsigned char *)screen->frameBuffer)[(y*maxx*4)+x*4+2]=v&0xff;
    ((unsigned char *)screen->frameBuffer)[(y*maxx*4)+x*4+1]=(v>>8)&0xff;
    ((unsigned char *)screen->frameBuffer)[(y*maxx*4)+x*4+0]=(v>>16)&0xff;
  }
  return 0;
}

int dump_bytes(char *msg,unsigned char *bytes,int length)
{
  fprintf(stdout,"%s:\n",msg);
  for(int i=0;i<length;i+=16) {
    fprintf(stdout,"%04X: ",i);
    for(int j=0;j<16;j++) if (i+j<length) fprintf(stdout," %02X",bytes[i+j]);
    fprintf(stdout,"\n");
  }
  return 0;
}

int main(int argc,char** argv)
{
  int do_dummy=0;
  int debug=0; //x806; //0x21b;

  if (!do_dummy) {
    if (argc>1) openSerialPort(argv[1]);
  }

  rfbScreenInfoPtr rfbScreen = rfbGetScreen(&argc,argv,maxx,maxy,8,3,bpp);
  if(!rfbScreen)
    return 0;
  rfbScreen->desktopName = "MEGA65 Remote Display";
  rfbScreen->frameBuffer = (char*)malloc(maxx*maxy*bpp);
  rfbScreen->alwaysShared = TRUE;
  rfbScreen->kbdAddEvent = dokey;
  rfbScreen->newClientHook = newclient;
  rfbScreen->httpDir = "../webclients";
  rfbScreen->httpEnableProxyConnect = TRUE;

  initBuffer((unsigned char*)rfbScreen->frameBuffer);

  /* initialize the server */
  rfbInitServer(rfbScreen);

  /* this is the non-blocking event loop; a background thread is started */
  rfbRunEventLoop(rfbScreen,-1,TRUE);
  fprintf(stderr, "Running background loop...\n");

  int sock = connect_to_port(6565);
  if (!do_dummy)  {
    if (sock==-1) {
      fprintf(stderr,"Could not connect to video proxy on port 6565.\n");
      exit(-1);
    }
  }

  printf("Started.\n"); fflush(stdout);

  int y=-1;
  int x=0;
  
  char bit_sequence[21];

  // Put end of string marker in place
  bit_sequence[20]=0;

  while(1) {    
    unsigned char packet[8192];
    int len;

    if (do_dummy) {
      // Feed dummy data (from simulation) to test
      FILE *f=fopen("dummy.dat","r");
      if (f) {
	char line[1024];
	len=0x56;
	line[0]=0; fgets(line,1024,f);
	while(line[0]&&(len<8000)) {
	  packet[len++]=strtoll(line,NULL,16);
	  line[0]=0; fgets(line,1024,f);
	}
	fclose(f);
      }
    } else {
      len=read(sock,packet,2132);
      if (len<1) usleep(10000);
    }
    
    if (len > 2100) {
      // probably a C65GS compressed video frame.
      // printf("."); fflush(stdout);

      if (debug&2) printf("--------------- Packet.\n");
      
      // Packet consists solely of bit-packed data

      // Erase any banked up bits before starting decode of next packet
      memset(bit_sequence,'.',20);

      // Start from beginning of data
      int offset=0x56;
      int bn=0;

      int counter=0;
      
      // Process all bits in packet

      // Start outside frame so that we can synchronise without visible artefacts
      int lasty=-1;
      y=-1;
      
      for(;offset<len;offset++) {
	if (debug&0x200) printf("> 0x%02x\n",packet[offset]);
	for(bn=7;bn>=0;bn--) {
	  counter++;

	  int bit=(packet[offset]>>bn)&1;
	  // Shuffle bits down
	  bcopy(&bit_sequence[1],&bit_sequence[0],19);
	  bit_sequence[19]='0'+bit;
	  if (debug&0x200) {
	    if (bit_sequence[0]!='.')
	      printf(">> %-8d %s\n",counter,bit_sequence);
	  }
	  
	  if (!strncmp("11110",bit_sequence,5)) {
	    // Explcit colour (12 bits)
	    int s=bit_sequence[17]; bit_sequence[17]=0;
	    int c=strtol(&bit_sequence[5],NULL,2);
	    colour4=colour3;
	    colour3=colour2;
	    colour2=colour1;
	    colour1=colour0;
	    colour0=((c&0xf)<<4)|((c&0xf0)<<8)|((c&0xf00)<<12);
	    if (debug&0x800)
	      printf("Saw new colour #%06x at (%d,%d)\n",colour0,x,y);
	    bit_sequence[17]=s;
	    memset(bit_sequence,'.',17);
	    setPixel(rfbScreen,x++,y,colour0);
	  } else if (!strncmp("111110",bit_sequence,6)) {
	    // Indicate raster (10 bits)
	    int s=bit_sequence[16]; bit_sequence[16]=0;
	    if (x!=-1) for(;x<maxx;x++) setPixel(rfbScreen,x,y,colour0);	    
	    y=strtol(&bit_sequence[6],NULL,2);
	    if (lasty==-1) { lasty=y; y=-1; } else {
	      if (y!=(1+lasty)) {
		// Non successive raster linese, block drawing
		lasty=y;
		y=-1;
	      } else lasty=y;
	    }
	    
	    bit_sequence[16]=s;
	    if (debug&2) printf("Raster #%d (x got to %d)\n",y,x);
	    x=0;
	    colour0=0x000000;
	    colour1=0xf0f0f0;
	    colour2=0x303030;
	    colour3=0x707070;
	    colour4=0xb0b0b0;
	    memset(bit_sequence,'.',16);
	  } else if (!strncmp("11111110",bit_sequence,8)) {
	    // RLE run of 0 - 255 pixels
	    int s=bit_sequence[16]; bit_sequence[16]=0;
	    int r=strtol(&bit_sequence[8],NULL,2);
	    bit_sequence[16]=s;
	    if (debug&8) printf("Run of %d at %d,%d\n",r,x,y);
	    if (x!=-1)
	      for(;r&&(x<800);r--) {
		setPixel(rfbScreen,x++,y,colour0);
	      }
	    memset(bit_sequence,'.',16);
	    if (debug&8) printf("After run, x=%d\n",x);
	  } else if (!strncmp("11111100",bit_sequence,8)) {
	    // New frame
	    if (debug&1) printf("New frame (y got to %d)\n",y);
	    if (x!=-1) for(;x<maxx;x++) setPixel(rfbScreen,x,y,colour0);	    
	    y=-1; x=-1;
	    memset(bit_sequence,'.',8);
	    colour0=0x000000;
	    colour1=0xf0f0f0;
	    colour2=0x303030;
	    colour3=0x707070;
	    colour4=0xb0b0b0;
	    updateFrameBuffer(rfbScreen);	    
	  } else if (!strncmp("11111101",bit_sequence,8)) {
	    // Reserved -- this is an error for now
	    if (debug&0x100) printf("Reserved token.\n");
	    memset(bit_sequence,'.',8);
	  } else if (!strncmp("1100",bit_sequence,4)) {
	    // Colour 2
	    int t=colour2; colour2=colour1; colour1=colour0; colour0=t;
	    if (debug&4) printf("Colour 2 @ x=%d (colour=#%06x)\n",x,colour0);
	    if (x!=-1) setPixel(rfbScreen,x++,y,colour0);
	    memset(bit_sequence,'.',4);
	  } else if (!strncmp("1101",bit_sequence,4)) {
	    // Colour 3
	    int t=colour3; colour3=colour2; colour2=colour1; colour1=colour0; colour0=t;
	    if (debug&4) printf("Colour 3\n");
	    if (x!=-1) setPixel(rfbScreen,x++,y,colour0);
	    memset(bit_sequence,'.',4);
	  } else if (!strncmp("1110",bit_sequence,4)) {
	    // Colour 4
	    int t=colour4; colour4=colour3; colour3=colour2; colour2=colour1; colour1=colour0; colour0=t;
	    if (debug&4) printf("Colour 4 @ %d,%d\n",x,y);
	    if (x!=-1) setPixel(rfbScreen,x++,y,colour0);
	    memset(bit_sequence,'.',4);
	  } else if (!strncmp("10",bit_sequence,2)) {
	    // Colour 1
	    int t=colour1; colour1=colour0; colour0=t;
	    if (debug&4)
	      printf("Previous colour @ %d,%d\n",x,y);
	    if (x!=-1) setPixel(rfbScreen,x++,y,colour0);
	    //	    if (debug&4)
	    memset(bit_sequence,'.',2);
	  } else if (!strncmp("0",bit_sequence,1)) {
	    // Repeat last colour
	    if (debug&4) printf("Same colour at %d,%d\n",x,y);
	    if (x!=-1) setPixel(rfbScreen,x++,y,colour0);
	    memset(bit_sequence,'.',1);
	  }
	  //	  if (debug&0x800)
	  if (0)
	    printf("Colours = #%06x, #%06x, #%06x, #%06x, #%06x\n",
		   colour0,colour1,colour2,colour3,colour4);
	}
      }
    }      
  }
  
  free(rfbScreen->frameBuffer);
  rfbScreenCleanup(rfbScreen);

  return(0);
}
