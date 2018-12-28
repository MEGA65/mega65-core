/*
  Simple "colour in the screen in your colour" game as
  demo of C65.

*/

#include <stdio.h>
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
  dmalist.dest_bank=(address>>16)&0x7f;

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
  if (source_address>=0xd000 && source_address<0xe000)
    dmalist.source_bank|=0x80;  
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x0f;
  if (destination_address>=0xd000 && destination_address<0xe000)
    dmalist.dest_bank|=0x80;

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


void videomode_game(void)
{
  // Enable C65 VIC-III IO registers
  POKE(0xD02FU,0xA5);
  POKE(0xD02FU,0x96);
  
  // 80 column text mode, 3.5MHz CPU
  POKE(0xD031U,0xE0);

  lpoke(0x8000U,1);
  
  // Clear screen
  lfill(0x8000U,0x20,2000);
  // Set colour of characters to yellow
  lfill(0x1f800U,0x07,2000);

  // Copy charrom to $A000
  lcopy(0x29000U,0xa000U,2048);
  // Patch char $1F to be half block (like char $62 in normal char ROM)
  POKE(0xa000U+0x1f*8+0,0);
  POKE(0xa000U+0x1f*8+1,0);
  POKE(0xa000U+0x1f*8+2,0);
  POKE(0xa000U+0x1f*8+3,0);
  POKE(0xa000U+0x1f*8+4,0xff);
  POKE(0xa000U+0x1f*8+5,0xff);
  POKE(0xa000U+0x1f*8+6,0xff);
  POKE(0xa000U+0x1f*8+7,0xff);
  // Patch char $1E to be inverted half block
  POKE(0xa000U+0x1e*8+0,0xff);
  POKE(0xa000U+0x1e*8+1,0xff);
  POKE(0xa000U+0x1e*8+2,0xff);
  POKE(0xa000U+0x1e*8+3,0xff);
  POKE(0xa000U+0x1e*8+4,0);
  POKE(0xa000U+0x1e*8+5,0);
  POKE(0xa000U+0x1e*8+6,0);
  POKE(0xa000U+0x1e*8+7,0);
  // Patch char $1D to be solid block
  POKE(0xa000U+0x1d*8+0,0xff);
  POKE(0xa000U+0x1d*8+1,0xff);
  POKE(0xa000U+0x1d*8+2,0xff);
  POKE(0xa000U+0x1d*8+3,0xff);
  POKE(0xa000U+0x1d*8+4,0xff);
  POKE(0xa000U+0x1d*8+5,0xff);
  POKE(0xa000U+0x1d*8+6,0xff);
  POKE(0xa000U+0x1d*8+7,0xff);

  
  // Put screen at $8000, get charrom from $A000
  // Will be 2K for 80x25 text mode
  POKE(0xDD00U,0x01);
  POKE(0xD018U,0x08);
  
  // Pink border, black background
  POKE(0xD020U,0x0a);
  POKE(0xD021U,0x00);

  // Red, Green, Yellow in EBC mode colours
  POKE(0xD022,0x02);
  POKE(0xD023,0x05);
  POKE(0xD024,0x06);
  
  // Extended background colour mode
  // (so we can do fake 80x50 graphics mode with character 0x62 (half filled block)
  POKE(0xD011U,0x5b);
  
}

unsigned char colour_lookup[5]={0,2,5,6,7};
unsigned short screen_offset;
void draw_pixel_char(unsigned char x,unsigned char y,
		     unsigned char c_upper,unsigned char c_lower)
{
  if (y>24) return;
  if (x>79) return;
  if (c_lower>4) return;
  if (c_upper>4) return;
  screen_offset=y*80+x;
  if (c_upper<4) {
    // Use half-char block with active pixels in bottom half.
    // Set colour of upper half using extended background
    POKE(0x8000U+screen_offset,(c_upper<<6)+0x1f);
    lpoke(0x1f800U+screen_offset,colour_lookup[c_lower]);
  } else {
    if (c_lower<4) {
      POKE(0x8000U+screen_offset,(c_lower<<6)+0x1e);
      lpoke(0x1f800U+screen_offset,colour_lookup[c_upper]);
    } else {
      // Both halves are the last colour, so just use a solid char
      POKE(0x8000U+screen_offset,0x1d);
      lpoke(0x1f800U+screen_offset,colour_lookup[c_upper]);
    }
  }
}

unsigned char a,b;
void main(void)
{
  videomode_game();

  // Work out how to display all combinations of the five colours:
  for(a=0;a<5;a++)
    for(b=0;b<5;b++)
      draw_pixel_char(a,b,a,b);
  
  while(1) continue;
}
