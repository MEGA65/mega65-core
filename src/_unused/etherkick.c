
/* Sample UDP client */

#include <arpa/inet.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>
#include <fcntl.h>

unsigned char all_done_routine[128]={  
  0xa9, 0x00,       // LDA #$00 so that kickstart recognises packet
  0x8d, 0x54, 0xd0, // Clear 16-bit character mode etc, just to be sure
  0xee,0x27,0x04,   // increment $0427 for visual debug indicator  
  0x4c, 0x1f, 0x08  // jmp to $081F, which should be mapped to $000081F.
};

// Routine to copy memory from $0004000-$0007FFF to $FFF8000-$FFFBFFF,
// and then jump to $8100 to simulate reset.
// Actually, we jump to $8200, which by convention must have a reset entry point
// that disables etherkick until next boot, so that no switch fiddling is required.
unsigned char kickstart_replace_routine[128]={
  0xa9, 0x00, 0x5b, 0xa9, 0x00, 0x85, 0x80, 0xa9,
  0x40, 0x85, 0x81, 0xa9, 0x00, 0x85, 0x82, 0xa9,
  0x00, 0x85, 0x83, 0xa9, 0x00, 0x85, 0x84, 0xa9,
  0x80, 0x85, 0x85, 0xa9, 0xff, 0x85, 0x86, 0xa9,
  0x0f, 0x85, 0x87, 0xa3, 0x00, 0xea, 0xb2, 0x80,
  0xea, 0x92, 0x84, 0x1b, 0xd0, 0xf7, 0xe6, 0x81,
  0xe6, 0x85, 0xa5, 0x81, 0xc9, 0x80, 0xd0, 0xed,
  0x4c, 0x00, 0x81
};

unsigned char dma_load_routine[128+1024]={
  // Routine that copies packet contents by DMA
  0xa9, 0xff, 0x8d, 0x05, 0xd7, 0xad, 0x68, 0x68,
  0x8d, 0x06, 0xd7, 0xa9, 0x0d, 0x8d, 0x02, 0xd7,
  0xa9, 0xe8, 0x8d, 0x01, 0xd7, 0xa9, 0xff, 0x8d, 
  0x04, 0xd7, 0xa9, 0x5c, 0x8d, 0x00, 0xd7, 0xae, 
  0x67, 0x68, 0xea, 0x9d, 0x80, 0x06, 0xee, 0x26, 
  0x04, 0xd0, 0x03, 0xee, 0x25, 0x04, 0x60, 0x00,

  // DMA list begins at offset $0030
  0x00, // DMA command ($0030)
#define BYTE_COUNT_OFFSET 0x31
  0x00, 0x04,  // DMA byte count ($0031-$0032)
  0x80, 0xe8, 0x8d, // DMA source address (points to data in packet)
#define DESTINATION_ADDRESS_OFFSET 0x36
  0x00, 0x10, // DMA Destination address (bottom 16 bits)
#define DESTINATION_BANK_OFFSET 0x38
  0x00, // DMA Destination bank
  0x00, 0x00, // DMA modulo (ignored)
  // Packet ID number at offset $003B
#define PACKET_NUMBER_OFFSET 0x3b
  0x30, 
#define DESTINATION_MB_OFFSET 0x3c
  // Destination MB at $003C
  0x00, 
  0x00, 0x00, 0x00
#define DATA_OFFSET (0x80 - 0x2c)
};

// Test routine to increment border colour
unsigned char test_routine[64]={
  0xa9,0x00,0xee,0x21,0xd0,0x60
};

int usage()
{
  printf("usage:  etherkick <run|kickup> <IP address> <programme>\n");
  printf("        etherkick push <IP address> <file> <28-bit address (hex)>\n");
  exit(1);
}

int main(int argc, char**argv)
{
   int sockfd;
   struct sockaddr_in servaddr;

   if (argc < 4)
   {
     printf("Too few arguments.\n");
     usage();
   }

   int runmode=0;
   int address=-1;

   if (!strcmp(argv[1],"run")) runmode=1;
   else if (!strcmp(argv[1],"kickup")) runmode=0;
   else if (!strcmp(argv[1],"push")) {
     runmode=2;
     if (argc<5) {
       printf("Too few arguments for push (argc=%d)\n",argc);
       usage();
     }
     address=strtoll(argv[4],NULL,16);     
   } else {
     usage();
   }

   sockfd=socket(AF_INET,SOCK_DGRAM,0);
   int broadcastEnable=1;
   setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));

   bzero(&servaddr,sizeof(servaddr));
   servaddr.sin_family = AF_INET;
   servaddr.sin_addr.s_addr=inet_addr(argv[2]);
   servaddr.sin_port=htons(4511);

   int fd=open(argv[3],O_RDWR);

   if (fd<0) {
     fprintf(stderr,"Could not open file '%s'\n",argv[3]);
     exit(-1);
   }
   
   unsigned char buffer[1024];
   int offset=0;
   int bytes;
   
   if (runmode==1) {
     // Read 2 byte load address
     bytes=read(fd,buffer,2);
     if (bytes<2) {
       fprintf(stderr,"Failed to read load address from file '%s'\n",
	       argv[2]);
       exit(-1);
     }
     address=buffer[0]+256*buffer[1];
     printf("Load address of programme is $%04x\n",address);
   } else if (runmode==0) {
     printf("Upgrading kickstart: load address fixed at $4000\n");
     address=0x4000;
   } else {
     printf("Load address is $%07x\n",address);
   }

   while((bytes=read(fd,buffer,1024))!=0)
   {     
     printf("Read %d bytes at offset %d\n",bytes,offset);
     offset+=bytes;

     // Set load address of packet
     dma_load_routine[DESTINATION_ADDRESS_OFFSET]=address&0xff;
     dma_load_routine[DESTINATION_ADDRESS_OFFSET+1]=(address>>8)&0xff;
     dma_load_routine[DESTINATION_BANK_OFFSET]=(address>>16)&0x0f;
     dma_load_routine[DESTINATION_MB_OFFSET]=(address>>20)&0xff;
     
     // Copy data into packet
     bcopy(buffer,&dma_load_routine[DATA_OFFSET],bytes);

     sendto(sockfd,dma_load_routine,sizeof dma_load_routine,0,
	    (struct sockaddr *)&servaddr,sizeof(servaddr));
     usleep(150);

     dma_load_routine[PACKET_NUMBER_OFFSET]++;
     address+=bytes;
   }

   if (runmode==1) {
     // Tell C65GS that we are all done
     int i;
     printf("Trying to start program ...\n");
     for(i=0;i<10;i++) {
     sendto(sockfd,all_done_routine,sizeof all_done_routine,0,
	    (struct sockaddr *)&servaddr,sizeof(servaddr));
     usleep(150);
     }
   } else if (runmode==0) {
     int i;
     printf("Telling kickstart to upgrade ...\n");
     for(i=0;i<10;i++) {
     sendto(sockfd,kickstart_replace_routine,sizeof kickstart_replace_routine,0,
	    (struct sockaddr *)&servaddr,sizeof(servaddr));
     usleep(150);
     }
   } else {
     printf("Push mode -- leaving C65GS in etherkick.\n");
   }
     

   return 0;
}
