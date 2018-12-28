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

unsigned char game_grid[80][50];
unsigned char a,b;
unsigned char player_x[4];
unsigned char player_y[4];
unsigned int player_tiles[4];
unsigned int player_feature[4];

void redraw_game_grid(void)
{
  // Work out how to display all combinations of the five colours:
  for(a=0;a<80;a++)
    for(b=0;b<25;b++)
      draw_pixel_char(a,b,game_grid[a][b<<1],game_grid[a][1+(b<<1)]);
}

void flash(unsigned char n)
{
  POKE(0x8050U+n,(PEEK(0x8050U+n)+1));
  POKE(0xD850U+n,1);
}

void main(void)
{
  // Setup game state
  for(a=0;a<4;a++) {
    // Initial player placement
    if (a<2) player_x[a]=0; else player_x[a]=79;
    if (a&1) player_y[a]=49; else player_y[a]=0;
    // Player initially has no tiles allocated
    player_tiles[a]=0;
    // Players have no special feature initially
    player_feature[a]=0;    
  }
  // Clear game grid
  for(a=0;a<80;a++)
    for(b=0;b<50;b++)
      game_grid[a][b]=0;
  
  // Set DDR on port for protovision/CGA joystick expander
  POKE(0xDD03U,0x80);
  POKE(0xDD01U,0x00); // And ready to read joystick 3 initially
  
  videomode_game();

  // then redraw it (this takes a few frames to do completely)
  redraw_game_grid();
  
  while(1) {

    // Run game state update once per frame
    while(PEEK(0xD012U)<0xFE) continue;
    
    // Read state of the four joysticks
    for(a=0;a<4;a++) {
      // Get joystick state
      switch(a) {
      case 0: b=PEEK(0xDC00U)&0x1f; break;
      case 1: b=PEEK(0xDC01U)&0x1f; break;
	// PEEK must come before POKE in the following to make sure CC65 doesn't optimise the PEEK away
      case 2: b=PEEK(0xDD01U)&0x1f; POKE(0xDD01U,0x80); break;
      case 3: b=(PEEK(0xDD01U)&0xf)+((PEEK(0xDD01U)>>1)&0x10); POKE(0xDD01U,0x00); break;
      }
      // Make joystick data active high
      b^=0x1f;
      POKE(0x8000U+a,b);
      POKE(0xd800U+a,1);

      // Move based on new joystick position
      if (b&1) { if (player_y[a]) player_y[a]--; flash(0); }
      if (b&2) { if (player_y[a]<49) player_y[a]++; flash(1); }
      if (b&4) { if (player_x[a]) player_x[a]--; flash(2); }
      if (b&8) { if (player_x[a]<79) player_x[a]++; flash(3); }

      POKE(0x8008U + (a*8)+0,player_x[a]);
      POKE(0x8008U + (a*8)+1,player_y[a]);
      
      // Leave unicorn rainbow trail behind us
      b=game_grid[player_x[a]][player_y[a]];	
      if (b!=(a+1)) {
	// take over this tile

	// But first, take it away from the previous owner
	if (b&&(b<5))
	  if (player_tiles[b-1])
	    player_tiles[b-1]--;

	// Update grid to show our ownership
	game_grid[player_x[a]][player_y[a]]=a+1;

	// Add to our score for the take over
	player_tiles[a]++;

	// Update the on-screen display
	draw_pixel_char(player_x[a],player_y[a]>>1,
			game_grid[player_x[a]][player_y[a]&0xfe],
			game_grid[player_x[a]][player_y[a]|0x01]);
			
      }
    }
  
    continue;
  }
}
