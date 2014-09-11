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

int sendScanCode(int scan_code);

unsigned char bmpHeader[0x36]={
  0x42,0x4d,0x36,0xa0,0x8c,0x00,0x00,0x00,0x00,0x00,0x36,0x00,0x00,0x00,0x28,0x00,
  0x00,0x00,0x80,0x07,0x00,0x00,0xb0,0x04,0x00,0x00,0x01,0x00,0x20,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x00};

unsigned char palette[17][4]={
  {  0,  0,  0,0xff},
  {255,255,255,0xff},
  {116, 67,53,0xff},
  {124,172,186,0xff},
  {123, 72,144,0xff},
  {100,151, 79,0xff},
  { 64, 50,133,0xff},
  {191,205,122,0xff},
  {123, 91, 47,0xff},
  { 79, 69,  0,0xff},
  {163,114,101,0xff},
  { 80, 80, 80,0xff},
  {120,120,120,0xff},
  {164,215,142,0xff},
  {120,106,189,0xff},
  {159,159,159,0xff},
  {  0,  255,  0,0xff}
};

unsigned char imageData[1920*1200*2];
int image_offset=0;
int drawing=0;
int raster_length=0;
int y;

// set for each rasterline modified
int touched[1200];
int touched_min[1200];
int touched_max[1200];

#ifdef WIN32
#define sleep Sleep
#else
#include <unistd.h>
#endif

#include <rfb/rfb.h>
#include <rfb/keysym.h>

static const int bpp=4;
static int maxx=1920, maxy=1200;

static void initBuffer(unsigned char* buffer)
{
  int i,j;
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
    
/* Here the key events are handled */

static void dokey(rfbBool down,rfbKeySym key,rfbClientPtr cl)
{
  int scan_code = -1;

  switch (key) {
  case XK_Delete: scan_code = 0x66; break; // DEL
  case XK_Return: scan_code = 0x5a; break; // RETURN
  case XK_Right: scan_code = 0x174; break; // RIGHT
  case XK_Left: scan_code = 0x174; break; // RIGHT
  case XK_F1: scan_code = 0x05; break; // F1/F2
  case XK_F2: scan_code = 0x05; break;  // F1/F2
  case XK_F3: scan_code = 0x04; break; // F3/F4
  case XK_F4: scan_code = 0x04; break; // F3/F4
  case XK_F5: scan_code = 0x03; break; // F5/F6
  case XK_F6: scan_code = 0x03; break; // F5/F6
  case XK_F7: scan_code = 0x83; break; // F7/F8
  case XK_F8: scan_code = 0x83; break; // F7/F8
  case XK_Down: scan_code = 0x72; break; // DOWN
  case XK_Up: scan_code = 0x72; break; // DOWN

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
  case '6': case '&': scan_code = 0x36; break;
  case 'C': case 'c': scan_code = 0x21; break;
  case 'F': case 'f': scan_code = 0x2b; break;
  case 'T': case 't': scan_code = 0x2c; break;
  case 'X': case 'x': scan_code = 0x22; break;
    
  case '7': case '\'': scan_code = 0x3d; break;
  case 'Y': case 'y': scan_code = 0x35; break;
  case 'G': case 'g': scan_code = 0x34; break;
  case '8': case '(': scan_code = 0x3e; break;
  case 'B': case 'b': scan_code = 0x32; break;
  case 'H': case 'h': scan_code = 0x33; break;
  case 'U': case 'u': scan_code = 0x3c; break;
  case 'V': case 'v': scan_code = 0x2a; break;
    
  case '9': case ')': scan_code = 0x4e; break;
  case 'I': case 'i': scan_code = 0x4d; break;
  case 'J': case 'j': scan_code = 0x4b; break;
  case '0': scan_code = 0x55; break;
  case 'M': case 'm': scan_code = 0x49; break;
  case 'K': case 'k': scan_code = 0x4c; break;
  case 'O': case 'o': scan_code = 0x54; break;
  case 'N': case 'n': scan_code = 0x41; break;
  
  case '+': case '=': scan_code = 0x4e; break;
  case 'P': case 'p': scan_code = 0x4d; break;
  case 'L': case 'l': scan_code = 0x4b; break;
  case '-': case '_': scan_code = 0x55; break;
  case '.': case '>': scan_code = 0x49; break;
  case ';': case ':': scan_code = 0x4c; break;
  case '@': scan_code = 0x54; break;
  case ',': case '<': scan_code = 0x41; break;
  
  case ']': case '}': scan_code = 0x5b; break; // *
  case XK_Home: scan_code = 0x16c; break;
  case XK_Shift_R: scan_code = 0x59; break;
  case '^': scan_code = 0x171; break;
  case '/': case '?': scan_code = 0x4a; break;    

  case '1': case '!': scan_code = 0x16; break;
  case '`': case '~': scan_code = 0xe; break;
  case XK_Control_L: case XK_Control_R: scan_code = 0xd; break;
  case '2': case '\"': scan_code = 0x1e; break;
  case ' ': scan_code = 0x29; break;
  case XK_Alt_L: scan_code = 0x14; break; // C=
  case 'Q': case 'q': scan_code = 0x16; break;
  case XK_Escape: scan_code = 0x76; // runstop
  }
  if (scan_code!=-1) {
    if (!down) scan_code|=0x1000;
    printf("scan code $%04x\n",scan_code);
    sendScanCode(scan_code);
  }

  if(down) {
    if(key==XK_F10)      rfbCloseClient(cl);
  }
}

int updateFrameBuffer(rfbScreenInfoPtr screen)
{  
  // draw pixels onto VNC frame buffer
  int x,y;
  for(y=0;y<1200;y++) {
    unsigned char linebuffer[1920*4];
    if (touched[y]) {
      for(x=0;x<1920;x++)
	{
	  int colour = imageData[y*1920+x];
	  int offset = x * 4;
	  if (colour>15) colour=16;
	  bcopy(palette[colour],
		&((unsigned char *)screen->frameBuffer)[(y*1920*4)+offset],4);
	}
    }
  }

  // work out which raster lines have been modified and tell VNC
  int ypos=0;
  while (ypos<1200) {
    //    printf("ypos=%d\n",ypos);
    int min=1919;
    int max=0;
    for(y=ypos;y<1200;y++) { 
      if (!touched[y]) break; 
      touched[y]=0; 
      if (touched_min[y]<min) min=touched_min[y];
      if (touched_max[y]>max) max=touched_max[y];
    }
    if (ypos<y) {      
      // mark section of buffer as dirty (we could optimise this)
      rfbMarkRectAsModified(screen,min,ypos,max+1,y);
      //      printf("updateing region [%d,%d]..[%d,%d]\n",min,ypos,max,y);
    }
    // skip unmodified rasters
    ypos=y;
    for(;ypos<1200;ypos++) if (touched[ypos]) break;
  }
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

int keySocket=-1;
struct sockaddr_in addr;
int base_offset=100;

int sendScanCode(int scan_code)
{
  if (keySocket==-1) return -1;
  unsigned char msg[200];
  bzero(msg,200);

  int offset=base_offset;
  offset-=14; // reduce for size of ethernet header
  offset-=28; // reduce for size of IP & UDP header
  offset-=2;

  int i;
  for(i=0;i<20;i++)
    if (offset-i>=0) msg[offset-i]=0xff-i;

  // put magic bytes
  msg[offset++]=0x65;
  msg[offset++]='G';
  msg[offset++]='S';
  msg[offset++]='K';
  msg[offset++]='E';
  msg[offset++]='Y';
  msg[offset++]='C';
  msg[offset++]='O';
  msg[offset++]='D';
  msg[offset++]='E';
  // put scan code
  msg[offset++]=scan_code&0xff;
  msg[offset++]=scan_code>>8;

  for(i=0;i<20;i++)
    msg[offset+i]=0x80+i;


  errno=0;
  sendto(keySocket, msg, sizeof msg, 0, (struct sockaddr *) &addr, sizeof addr);
  printf("sent scan code, base_offset=%d\n",base_offset);
  perror("status");

  //  base_offset--;
  // if (base_offset<54) base_offset=100;

  return 0;
}

int main(int argc,char** argv)
{
  if (argc>1) {
    keySocket = socket(AF_INET, SOCK_DGRAM, 0);
    int on=1;
    errno=0;
    int r=setsockopt(keySocket, SOL_SOCKET, SO_BROADCAST, (char *)&on, sizeof(on));
    
    printf("keySocket=%d, r=%d, errno=%d\n",keySocket,r,errno);
    perror("result");

    addr.sin_family = AF_INET; // sets the server address to type AF_INET.
    inet_aton(argv[1], &addr.sin_addr); // this sets the server address. 
    addr.sin_port = 0x8080; // port is irrelevant, since the C65GS is looking for magic values in the middle of a packet
  }

  rfbScreenInfoPtr rfbScreen = rfbGetScreen(&argc,argv,maxx,maxy,8,3,bpp);
  if(!rfbScreen)
    return 0;
  rfbScreen->desktopName = "C65GS Remote Display";
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
  if (sock==-1) {
    fprintf(stderr,"Could not connect to video proxy on port 6565.\n");
    exit(-1);
  }

    printf("Started.\n"); fflush(stdout);

    int last_colour=0x00;
    int in_vblank=0;
    int firstraster=1;
    int bytes=0;

    unsigned char raster_line[1920];
    int rasternumber;
    int last_raster=0;

    while(1) {
      int i;
      unsigned char packet[8192];
      int len=read(sock,packet,2132);
      if (len<1) usleep(10000);

      if (1) {
	if (len == 2132) {
	  // probably a C65GS compressed video frame.

	  // for some reason not reading the last few bytes of each packet helps
	  // prevent glitches.
	  for(i=85;i<2133-50;i++) {
	    //	    	    printf("%02x.",packet[i]);
	    if (drawing) bytes++;
	    if (packet[i]==0x80) {
	      // end of raster marker
	      rasternumber = packet[i+1]+packet[i+2]*256;
	      if (rasternumber > 1199) rasternumber=1199;
	      i+=4; // skip raster number and audio bytes

	      if (raster_length>1900&&raster_length<=1920) {
		if (rasternumber==last_raster+1)
		  {
		    // copy collected raster to frame buffer, but only if different
		    int i;
		    int min=0, max=1920;
		    for(i=0;i<1920;i++) if (raster_line[i]!=imageData[rasternumber*1920+i]) { min=i; break; }
		    if (min) {
			for(i=1919;i>=0;i--) if (raster_line[i]!=imageData[rasternumber*1920+i]) { max=i; break; }
			touched[rasternumber]=1;
			touched_min[rasternumber]=min;
			touched_max[rasternumber]=max;
			//			printf("touched raster %d\n",rasternumber);
		    }
		    bcopy(raster_line,&imageData[rasternumber*1920],raster_length);
		  }
	      }
	      last_raster=rasternumber;

	      // update image_offset to reflect raster number
	      image_offset=rasternumber*1920;

	      if ((!firstraster)&&raster_length<100) {
		if (in_vblank==0) {
		  // start of vblank at end of frame
		  if (drawing) {
		    // printf("Done drawing.  Frame was encoded in %d bytes (plus packet headers)\n",bytes); fflush(stdout);
		    // exit(dumpImage());
		    updateFrameBuffer(rfbScreen);
		  }
		  drawing=1;
		  // printf("Start drawing. raster_length=%d\n",raster_length);
		  image_offset=0;
		  in_vblank=1;
		}
	      }
	      firstraster=0;
	      if (raster_length>=1800) {
		if (in_vblank) { in_vblank=0; y=0; }
		else y++;
	      }
	      
	      if (raster_length>1920) image_offset-=(raster_length-1920);
	      if (image_offset<0) image_offset=0;
	      // printf("Raster %d, length=%d, image raster=%.3f\n",
	      // y,raster_length,image_offset*1.0/1920.0);
	      
	      raster_length=0;
	    } else if (packet[i]&0x80) {
	      // RLE count

	      int count=(packet[i]&0x7f);
	      if (drawing) {
		int j;
		//		printf("Drawing %d of %02x @ %d\n",count,last_colour,image_offset);
		for(j=2;j<=count;j++) {
		  if (raster_length<1920)
		    raster_line[raster_length]=last_colour;
		  raster_length++;
		}
	      }
	    } else {
	      // colour
	      last_colour = packet[i];
	      if (drawing) {
		//		printf("Drawing 1 %02x\n",last_colour);
		if (raster_length<1920)
		  raster_line[raster_length]=last_colour;
		raster_length++;
	      }
	    }
	  }
	  //	  fflush(stdout);
	}
      }      
    }

  free(rfbScreen->frameBuffer);
  rfbScreenCleanup(rfbScreen);

  return(0);
}
