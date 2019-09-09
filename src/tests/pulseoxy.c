/*
  Simple "colour in the screen in your colour" game as
  demo of C65.

*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define POKE(a,v) *((uint8_t *)a)=(uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))

unsigned short i;

struct dmagic_dmalist {
  // F018B format DMA request
  unsigned char command;
  unsigned int count;
  unsigned int source_addr;
  unsigned char source_bank;
  unsigned int dest_addr;
  unsigned char dest_bank;
  unsigned char sub_cmd;  // F018B subcmd
  unsigned int modulo;
};

struct dmagic_dmalist dmalist;
unsigned char dma_byte;

void do_dma(void)
{
  // Now run DMA job (to and from anywhere, and list is in low 1MB)
  POKE(0xd702U,0);
  POKE(0xd701U,(((unsigned int)&dmalist)>>8));
  POKE(0xd700U,((unsigned int)&dmalist)&0xff); // triggers enhanced DMA

  POKE(0x0401U,(((unsigned int)&dmalist)>>8));
  POKE(0x0400U,((unsigned int)&dmalist)&0xff); // triggers enhanced DMA
  
}


void lpoke(long address, unsigned char value)
{  
  dma_byte=value;
  dmalist.command=0x00; // copy
  dmalist.sub_cmd=0;
  dmalist.modulo=0;
  dmalist.count=1;
  dmalist.source_addr=(unsigned int)&dma_byte;
  dmalist.source_bank=0;
  dmalist.dest_addr=address&0xffff;
  dmalist.dest_bank=(address>>16);

  do_dma(); 
  return;
}


unsigned char lpeek(long address)
{
  dmalist.command=0x00; // copy
  dmalist.count=1;
  dmalist.source_addr=address&0xffff;
  dmalist.source_bank=(address>>16)&0x7f;
  dmalist.dest_addr=(unsigned int)&dma_byte;
  dmalist.source_bank=0;
  dmalist.dest_addr=address&0xffff;
  dmalist.dest_bank=(address>>16)&0x7f;
  // Make list work on either old or new DMAgic
  dmalist.sub_cmd=0;  
  dmalist.modulo=0;
  
  do_dma(); 
  return dma_byte;
}

void lcopy(long source_address, long destination_address,
          unsigned int count)
{
  dmalist.command=0x00; // copy
  dmalist.count=count;
  dmalist.sub_cmd=0;
  dmalist.modulo=0;
  dmalist.source_addr=source_address&0xffff;
  dmalist.source_bank=(source_address>>16)&0x0f;
  //  if (source_address>=0xd000 && source_address<0xe000)
  //    dmalist.source_bank|=0x80;  
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x0f;
  //  if (destination_address>=0xd000 && destination_address<0xe000)
  //    dmalist.dest_bank|=0x80;

  do_dma();
  return;
}

void lfill(long destination_address, unsigned char value,
          unsigned int count)
{
  dmalist.command=0x03; // fill
  dmalist.sub_cmd=0;
  dmalist.count=count;
  dmalist.source_addr=value;
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x7f;
  if (destination_address>=0xd000 && destination_address<0xe000)
    dmalist.dest_bank|=0x80;

  do_dma();
  return;
}

unsigned char offset=0;
unsigned char v;

unsigned char frame[5];

unsigned char fnum=0;
unsigned char flast=99;
unsigned char spo2;
unsigned short prh;
unsigned short pr;

unsigned long j;

void main(void)
{
  // Fast CPU
  POKE(0,65);

  // Enable access to serial port and other devices
  POKE(53295L,0x47);
  POKE(53295L,0x53);

  // Set serial port speed to 9600
  POKE(0xd0e6U,0x46);
  POKE(0xd0e7U,0x10);

  while(1) {

    v=PEEK(0xd0e0U);
    if (v) {

      frame[0]=frame[1];
      frame[1]=frame[2];
      frame[2]=frame[3];
      frame[3]=frame[4];
      frame[4]=v;
      
      if (frame[0]==0x01) {
	if (frame[2]&0x80)
	  if (!(frame[3]&0x80))
	    {
	      flast=fnum;
	      if (frame[1]&1) {
		fnum=0;
	      } else fnum++;

	      switch(fnum) {
	      case 0: prh=frame[3]; break;
	      case 1:
		if (flast==0) {
		  pr=(frame[3]&0x7f); //+((prh&3)<<7);
		}
		break;
	      case 2:
		if (flast==1) printf("pr = %d\n",pr);
		spo2=frame[3];
		break;
	      case 3:
		if (flast==2)
		  printf("spo2 = %d\n",spo2);
		break;
	      }
	    }
      }
      
    }
  }
}
