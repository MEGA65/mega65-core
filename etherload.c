
/* Sample UDP client */

#ifdef _WIN32
#include <winsock2.h>
#else
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#endif
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>
#include <fcntl.h>

char all_done_routine[128]={
  // Dummy inc $d020 jmp *-3 routine for debugging
  // 0xa9, 0x00, 0xee, 0x20, 0xd0, 0x4c, 0x2c, 0x68,

  // 0xa9, 0x00, 0xee, 0x20, 0xd0, 0x4c, 0x2e, 0x68, 
  0xa9, 0x00, 0xea, 0xea, 0xea, 0xea, 0xea, 0xea,

  0xa2, 0x00, 0xbd, 0x44, 0x68, 0x9d, 0x40, 0x03,
  0xe8, 0xe0, 0x40, 0xd0, 0xf5, 0x4c, 0x40, 0x03, 0xa9, 0x47, 0x8d, 0x2f, 0xd0, 0xa9, 0x53, 0x8d,
  0x2f, 0xd0, 0xa9, 0x00, 0xa2, 0x0f, 0xa0, 0x00, 0xa3, 0x00, 0x5c, 0xea, 0xa9, 0x00, 0xa2, 0x00,
  0xa0, 0x00, 0xa3, 0x00, 0x5c, 0xea, 0x68, 0x68, 0x60
};

char dma_load_routine[128+1024]={
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
char test_routine[64]={
  0xa9,0x00,0xee,0x21,0xd0,0x60
};


int main(int argc, char**argv)
{
   int sockfd;
   struct sockaddr_in servaddr;

   if (argc != 3)
   {
      printf("usage:  udpcli <IP address> <programme>\n");
      exit(1);
   }

   sockfd=socket(AF_INET,SOCK_DGRAM,0);
   int broadcastEnable=1;
   setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, (char*)&broadcastEnable, sizeof(broadcastEnable));

   memset(&servaddr,0,sizeof(servaddr));
   servaddr.sin_family = AF_INET;
   servaddr.sin_addr.s_addr=inet_addr(argv[1]);
   servaddr.sin_port=htons(4510);

   int fd=open(argv[2],O_RDWR);
   unsigned char buffer[1024];
   int offset=0;
   int bytes;

   // Read 2 byte load address
   bytes=read(fd,buffer,2);
   if (bytes<2) {
     fprintf(stderr,"Failed to read load address from file '%s'\n",
	     argv[2]);
     exit(-1);
   }
   int address=buffer[0]+256*buffer[1];
   printf("Load address of programme is $%04x\n",address);

   while((bytes=read(fd,buffer,1024))!=0)
   {     
     printf("Read %d bytes at offset %d\n",bytes,offset);
     offset+=bytes;

     // Set load address of packet
     dma_load_routine[DESTINATION_ADDRESS_OFFSET]=address&0xff;
     dma_load_routine[DESTINATION_ADDRESS_OFFSET+1]=(address>>8)&0xff;

     // Copy data into packet
     memcpy(&dma_load_routine[DATA_OFFSET],buffer,bytes);

     sendto(sockfd,dma_load_routine,sizeof dma_load_routine,0,
	    (struct sockaddr *)&servaddr,sizeof(servaddr));
     usleep(150);

     dma_load_routine[PACKET_NUMBER_OFFSET]++;
     address+=bytes;
   }

   if (1) {
     // Tell C65GS that we are all done
     int i;
     for(i=0;i<10;i++) {
     sendto(sockfd,all_done_routine,sizeof all_done_routine,0,
	    (struct sockaddr *)&servaddr,sizeof(servaddr));
     usleep(150);
     }
   }

   return 0;
}
