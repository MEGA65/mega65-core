#include <pcap.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/if_ether.h>
#include <netinet/tcp.h>
#include <netinet/ip.h>
#include <string.h>

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

#ifdef WIN32
#define sleep Sleep
#else
#include <unistd.h>
#endif

#include <rfb/rfb.h>
#include <rfb/keysym.h>

static const int bpp=4;
static int maxx=1920, maxy=1200;
/* TODO: odd maxx doesn't work (vncviewer bug) */

/* This initializes a nice (?) background */

static void initBuffer(unsigned char* buffer)
{
  int i,j;
  for(j=0;j<maxy;++j) {
    for(i=0;i<maxx;++i) {
      buffer[(j*maxx+i)*bpp+0]=(i+j)*128/(maxx+maxy); /* red */
      buffer[(j*maxx+i)*bpp+1]=i*128/maxx; /* green */
      buffer[(j*maxx+i)*bpp+2]=j*256/maxy; /* blue */
    }
    buffer[j*maxx*bpp+0]=0xff;
    buffer[j*maxx*bpp+1]=0xff;
    buffer[j*maxx*bpp+2]=0xff;
    buffer[j*maxx*bpp+3]=0xff;
  }
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
  if(down) {
    if(key==XK_Escape)
      rfbCloseClient(cl);
    else if(key==XK_F12)
      /* close down server, disconnecting clients */
      rfbShutdownServer(cl->screen,TRUE);
    else if(key==XK_F11)
      /* close down server, but wait for all clients to disconnect */
      rfbShutdownServer(cl->screen,FALSE);
    else if(key==XK_Page_Up) {
      initBuffer((unsigned char*)cl->screen->frameBuffer);
      rfbMarkRectAsModified(cl->screen,0,0,maxx,maxy);
    }  else if(key>=' ' && key<0x100) {
      ClientData* cd=cl->clientData;
      // rfbMarkRectAsModified(cl->screen,x1,y1,x2-1,y2-1);
    }
  }
}

int updateFrameBuffer(rfbScreenInfoPtr screen)
{  
  // draw pixels onto VNC frame buffer
  int x,y;
  for(y=0;y<1200;y++) {
    unsigned char linebuffer[1920*4];
    for(x=0;x<1920;x++)
      {
	int colour = imageData[y*1920+x];
	int offset = x * 4;
	if (colour>15) colour=16;
	bcopy(palette[colour],
	      &((unsigned char *)screen->frameBuffer)[(y*1920*4)+offset],4);
      }
  }


  // mark whole buffer as dirty (we could optimise this)
  rfbMarkRectAsModified(screen,0,0,1920-1,1200-1);
  return 0;
}

int main(int argc,char** argv)
{
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

    char *dev;
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t* descr;
    struct bpf_program fp;        /* to hold compiled program */
    bpf_u_int32 pMask;            /* subnet mask */
    bpf_u_int32 pNet;             /* ip address*/
    pcap_if_t *alldevs, *d;
    int i =0;

    // Prepare a list of all the devices
    if (pcap_findalldevs(&alldevs, errbuf) == -1)
    {
        fprintf(stderr,"Error in pcap_findalldevs: %s\n", errbuf);
        exit(1);
    }

    if (argv[1]) dev=argv[1]; else {
      fprintf(stderr,"You must specify the interface to listen on.\n");
      exit(-1);
    }

    // If something was not provided
    // return error.
    if(dev == NULL)
    {
        printf("\n[%s]\n", errbuf);
        return -1;
    }

    // fetch the network address and network mask
    pcap_lookupnet(dev, &pNet, &pMask, errbuf);

    // Now, open device for sniffing with big snaplen and 
    // promiscuous mode enabled.
    descr = pcap_open_live(dev, 3000, 1, 10, errbuf);
    if(descr == NULL)
    {
        printf("pcap_open_live() failed due to [%s]\n", errbuf);
        return -1;
    }

    printf("Started.\n"); fflush(stdout);

    int last_colour=0x00;
    int in_vblank=0;
    int firstraster=1;
    int bytes=0;

    unsigned char raster_line[1920];

    while(1) {
      struct pcap_pkthdr hdr;
      hdr.caplen=0;
      const unsigned char *packet = pcap_next(descr,&hdr);
      if (packet) {
	if (hdr.caplen == 2132) {
	  // probably a C65GS compressed video frame.

	  for(i=85;i<2133;i++) {
	    //	    	    printf("%02x.",packet[i]);
	    if (drawing) bytes++;
	    if (packet[i]==0x80) {
	      // end of raster marker
	      int rasternumber = packet[i+1]+packet[i+2]*256;
	      if (rasternumber > 1199) rasternumber=1199;
	      i+=4; // skip raster number and audio bytes

	      if (raster_length>1900&&raster_length<=1920)
		// copy collected raster to frame buffer
		bcopy(raster_line,&imageData[rasternumber*1920],raster_length);

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
