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
  { 53, 67,116,0xff},
  {186,172,124,0xff},
  {144, 72,123,0xff},
  { 79,151,100,0xff},
  {133, 50, 64,0xff},
  {122,205,191,0xff},
  { 47, 91,123,0xff},
  {  0, 69, 79,0xff},
  {101,114,163,0xff},
  { 80, 80, 80,0xff},
  {120,120,120,0xff},
  {142,215,164,0xff},
  {189,106,120,0xff},
  {159,159,159,0xff},
  {  0,  255,  0,0xff}
};

unsigned char imageData[1920*1200*2];
int image_offset=0;
int drawing=0;
int raster_length=0;
int y;

int dumpImage()
{
  printf("Decoded %d bytes of frame.\n",image_offset);

  FILE *out=fopen("c65gs-screen.bmp","w");

  if (!out) {
    fprintf(stderr,"could not create c65gs-screen.bmp\n");
    exit(-1);
  }

  fseek(out,0,SEEK_SET);
  fwrite(bmpHeader,0x36,1,out);
  fflush(out);

  // Write pixel at end of file so that even partially drawn frames should open
  fseek(out,0x36 + (1919 + 1199*1920) * 4,SEEK_SET);
  fwrite(palette[0],4,1,out);

  int x,y;
  for(y=0;y<1200;y++) {
    int address = 0x36 + (0 + (1199-y) * 1920) *4;
    unsigned char linebuffer[1920*4];
    for(x=0;x<1920;x++)
      {
	int colour = imageData[y*1920+x];
	int offset = x * 4;
	if (colour>15) colour=16;
	bcopy(palette[colour],&linebuffer[offset],4);
      }
    fseek(out,address,SEEK_SET);
    fwrite(linebuffer,1920*4,1,out);
  }
  fclose(out);
  printf("Wrote c65gs-screen.bmp\n");

  return 0;
}

int main(int argc,char **argv)
{
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

    while(1) {
      struct pcap_pkthdr hdr;
      hdr.caplen=0;
      const unsigned char *packet = pcap_next(descr,&hdr);
      if (packet) {
	if (hdr.caplen == 2132) {
	  // probably a C65GS compressed video frame.

	  // stop if we see frame overflow
	  // if (image_offset>=1920*1200) { exit(dumpImage()); }

	  for(i=85;i<2133;i++) {
	    //	    	    printf("%02x.",packet[i]);
	    if (drawing) bytes++;
	    if (packet[i]==0x80) {
	      // end of raster marker
	      if ((!firstraster)&&raster_length<100) {
		if (in_vblank==0) {
		  // start of vblank at end of frame
		  if (drawing) {
		    printf("Done drawing.  Frame was encoded in %d bytes (plus packet headers)\n",bytes); fflush(stdout);
		    exit(dumpImage());
		  }
		  drawing=1;
		  printf("Start drawing. raster_length=%d\n",raster_length);
		  image_offset=0;
		  in_vblank=1;
		}
	      }
	      firstraster=0;
	      if (raster_length>=1800) {
		if (in_vblank) { in_vblank=0; y=0; }
		else y++;
	      }
	      
	      // fill in any shortfall in the raster
	      if (raster_length<1920) {
		int skip=1920-(raster_length%1920);
		while(skip--) {
		  if (image_offset<(1920*1200)) {
		    imageData[image_offset++]=0x00;
		  }
		}
	      }

	      if (raster_length>1920) image_offset-=(raster_length-1920);
	      if (image_offset<0) image_offset=0;
	      // printf("Raster %d, length=%d, image raster=%.3f\n",
	      // y,raster_length,image_offset*1.0/1920.0);
	      
	      raster_length=0;
	    } else if (packet[i]&0x80) {
	      // RLE count

	      int count=(packet[i]&0x7f);
	      raster_length+=count-1;
	      if (drawing) {
		int j;
		//		printf("Drawing %d of %02x @ %d\n",count,last_colour,image_offset);
		for(j=2;j<=count;j++)
		  if (image_offset<(1920*1200))
		    imageData[image_offset++]=last_colour;
	      }
	    } else {
	      // colour
	      last_colour = packet[i];
	      raster_length++;
	      if (drawing) {
		//		printf("Drawing 1 %02x\n",last_colour);
		if (image_offset<(1920*1200))
		  imageData[image_offset++]=last_colour;
	      }
	    }
	  }
	  //	  fflush(stdout);
	}
      }
    }

    printf("\nDone with packet sniffing!\n");
    return 0;
}
