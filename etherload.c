
/* Sample UDP client */

#include <arpa/inet.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>

unsigned char dma_load_routine[128+1024]={
  // Routine that copies packet contents by DMA
  0xa9, 0x00, 0x8d, 0x05, 0xd7, 0xad, 0x68, 0x68,
  0x8d, 0x06, 0xd7, 0xa9, 0x0d, 0x8d, 0x02, 0xd7,
  0xa9, 0xe8, 0x8d, 0x01, 0xd7, 0xa9, 0xff, 0x8d, 
  0x04, 0xd7, 0xa9, 0x80, 0x8d, 0x00, 0xd7, 0xae, 
  0x67, 0x68, 0x8a, 0x9d, 0x80, 0x06, 0xee, 0x26, 
  0x04, 0xd0, 0x03, 0xee, 0x25, 0x04, 0x60, 0x00,

  // DMA list begins at offset $0030
  0x00, // DMA command ($0030)
#define BYTE_COUNT_OFFSET 0x31
  0x0f, 0x0f,  // DMA byte count ($0031-$0032)
  0x80, 0xe8, 0x0d, // DMA source address (points to data in packet)
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
  0x00, 0x00, 0x00};

// Test routine to increment border colour
unsigned char test_routine[64]={
  0xa9,0x00,0xee,0x21,0xd0,0x60
};


int main(int argc, char**argv)
{
   int sockfd;
   struct sockaddr_in servaddr;
   char sendline[1000];

   if (argc != 2)
   {
      printf("usage:  udpcli <IP address>\n");
      exit(1);
   }

   sockfd=socket(AF_INET,SOCK_DGRAM,0);
   int broadcastEnable=1;
   setsockopt(sockfd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));

   bzero(&servaddr,sizeof(servaddr));
   servaddr.sin_family = AF_INET;
   servaddr.sin_addr.s_addr=inet_addr(argv[1]);
   servaddr.sin_port=htons(4510);

   //   while (fgets(sendline, 10000,stdin) != NULL)
   while(1)
   {     
     sendto(sockfd,dma_load_routine,sizeof dma_load_routine,0,
             (struct sockaddr *)&servaddr,sizeof(servaddr));

     dma_load_routine[PACKET_NUMBER_OFFSET]++;
   }

   return 0;
}
