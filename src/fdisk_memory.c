/*
  MEGA65 Memory Access routines that allow access to the full RAM of the MEGA65,
  even though the program is stuck living in the first 64KB of RAM, because CC65
  doesn't (yet) understand how to make multi-bank MEGA65 programs.

*/

#include "fdisk_memory.h"


struct dmagic_dmalist {
  unsigned char command;
  unsigned int count;
  unsigned int source_addr;
  unsigned char source_bank;
  unsigned int dest_addr;
  unsigned char dest_bank;
  unsigned int modulo;
};

struct dmagic_dmalist dmalist;
unsigned char dma_byte;

void do_dma(void)
{
  m65_io_enable();
  
  // Now run DMA job (to and from low 1MB, and list is in low 1MB)
  POKE(0xd702U,0);
  POKE(0xd704U,0);
  POKE(0xd705U,0);
  POKE(0xd706U,0);
  POKE(0xd701U,((unsigned int)&dmalist)>>8);
  POKE(0xd700U,((unsigned int)&dmalist)&0xff); // triggers DMA
}

unsigned char lpeek(long address)
{
  // Read the byte at <address> in 28-bit address space
  // XXX - Optimise out repeated setup etc
  // (separate DMA lists for peek, poke and copy should
  // save space, since most fields can stay initialised).
  dmalist.command=0x00; // copy
  dmalist.count=1;
  dmalist.source_addr=address&0xffff;
  dmalist.source_bank=(address>>16)&0x7f;
  dmalist.dest_addr=(unsigned int)&dma_byte;
  dmalist.dest_bank=0;

  do_dma();
   
  return dma_byte;
}

void lpoke(long address, unsigned char value)
{  
  dma_byte=value;
  dmalist.command=0x00; // copy
  dmalist.count=1;
  dmalist.source_addr=(unsigned int)&dma_byte;
  dmalist.source_bank=0;
  dmalist.dest_addr=address&0xffff;
  dmalist.dest_bank=(address>>16)&0x7f;

  do_dma(); 
  return;
}

void lcopy(long source_address, long destination_address,
	  unsigned int count)
{
  dmalist.command=0x00; // copy
  dmalist.count=count;
  dmalist.source_addr=source_address&0xffff;
  dmalist.source_bank=(source_address>>16)&0x7f;
  if (source_address>=0xd000 && source_address<0xe000)
    dmalist.source_bank|=0x80;  
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x7f;
  if (destination_address>=0xd000 && destination_address<0xe000)
    dmalist.dest_bank|=0x80;

  do_dma();
  return;
}

void lfill(long destination_address, unsigned char value,
	  unsigned int count)
{
  dmalist.command=0x03; // fill
  dmalist.count=count;
  dmalist.source_addr=value;
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x7f;
  if (destination_address>=0xd000 && destination_address<0xe000)
    dmalist.dest_bank|=0x80;

  do_dma();
  return;
}

void m65_io_enable(void)
{
  // Gate C65 IO enable
  POKE(0xd02fU,0x47);
  POKE(0xd02fU,0x53);
  // Force to full speed
  POKE(0,65);
}
