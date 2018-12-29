/*
  Simple "colour in the screen in your colour" game as
  demo of C65.

*/

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define POKE(a,v) *((uint8_t *)a)=(uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))

#include "horses.h"

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

unsigned char flipped[256];

unsigned char frame_count=0;

unsigned char game_grid[80][50];
unsigned char a,b;
unsigned char player_x[4];
unsigned char player_y[4];
unsigned int player_tiles[4];
unsigned int player_direction[4];
unsigned int player_features[4];
unsigned int player_animation_frame[4]; 
#define FEATURE_FAST 0x01
#define FEATURE_SUPERFAST 0x02

void prepare_sprites(void)
{
  // Enable all sprites.
  POKE(0xD015U,0xFF);

  // Set first four sprites to light grey for unicorn outlines
  POKE(0xD027U,0x2);
  POKE(0xD028U,0x5);
  POKE(0xD029U,0x6);
  POKE(0xD02AU,0x7);
  // And second four sprites to player colours for unicorn bodies
  POKE(0xD027U,0xf);
  POKE(0xD028U,0xf);
  POKE(0xD029U,0xf);
  POKE(0xD02AU,0xf);
  
  // Set second four sprites to player colours
  
  // Make horizontally flipped sprites
  a=0;
  do {
    flipped[a]=0;
    if (a&0x01) flipped[a]^=0x80;
    if (a&0x02) flipped[a]^=0x40;
    if (a&0x04) flipped[a]^=0x20;
    if (a&0x08) flipped[a]^=0x10;
    if (a&0x10) flipped[a]^=0x08;
    if (a&0x20) flipped[a]^=0x04;
    if (a&0x40) flipped[a]^=0x02;
    if (a&0x80) flipped[a]^=0x01;
  } while(++a);

  // Make horizontally flipped sprites
  for(a=0;a<16;a++) {
    for(b=0;b<21;b++) {
      POKE(0xC000U+32*64
	   +a*64+b*3+0,flipped[PEEK(0xC000U+a*64+b*3+2)]);
      POKE(0xC000U+32*64
	   +a*64+b*3+1,flipped[PEEK(0xC000U+a*64+b*3+1)]);
      POKE(0xC000U+32*64
	   +a*64+b*3+2,flipped[PEEK(0xC000U+a*64+b*3+0)]);
    }
  }

  // XXX Now make 90 degree rotated versions
  
  
}

void videomode_game(void)
{

  // Enable C65 VIC-III IO registers
  POKE(0xD02FU,0xA5);
  POKE(0xD02FU,0x96);
  
  // 80 column text mode, 3.5MHz CPU
  POKE(0xD031U,0xE0);

  // Put screen at $F000, get charrom from $E800
  // Will be 2K for 80x25 text mode
  POKE(0xDD00U,0x00);
  POKE(0xD018U,0xCB);
  
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
  
  // Clear screen
  lfill(0xf000U,0x20,2000);
  // Set colour of characters to yellow
  lfill(0x1f800U,0x07,2000);

  // $C000-$E7FF is free for sprites.
  // This is $2800 bytes total = 10KB, enough for 160 sprites.
  // We need 11 sprites for the horses facing each directions,
  // so a total of 44 sprites.
  // It would also be good to be able to make the horses hollow,
  // and have 2nd sprite that overlays each frame to have a coloured
  // body that matches the player's colour.
  // So that makes 88 sprites, which easily fits
  // We copy the sprites into place, and then make the horizontally flipped
  // and 90 degree rotated versions
  lfill(0xC000U,0,0x2800U); // Erase all sprites first
  lcopy((long)&horse_sprites[0],0xC000U,sizeof(horse_sprites));  
  prepare_sprites();
  
  // Copy charrom to $F000-$F7FF
  lcopy(0x29000U,0xe800U,2048);
  // Patch char $1F to be half block (like char $62 in normal char ROM)
  POKE(0xe800U+0x1f*8+0,0);
  POKE(0xe800U+0x1f*8+1,0);
  POKE(0xe800U+0x1f*8+2,0);
  POKE(0xe800U+0x1f*8+3,0);
  POKE(0xe800U+0x1f*8+4,0xff);
  POKE(0xe800U+0x1f*8+5,0xff);
  POKE(0xe800U+0x1f*8+6,0xff);
  POKE(0xe800U+0x1f*8+7,0xff);
  // Patch char $1E to be inverted half block
  POKE(0xe800U+0x1e*8+0,0xff);
  POKE(0xe800U+0x1e*8+1,0xff);
  POKE(0xe800U+0x1e*8+2,0xff);
  POKE(0xe800U+0x1e*8+3,0xff);
  POKE(0xe800U+0x1e*8+4,0);
  POKE(0xe800U+0x1e*8+5,0);
  POKE(0xe800U+0x1e*8+6,0);
  POKE(0xe800U+0x1e*8+7,0);
  // Patch char $1D to be solid block
  POKE(0xe800U+0x1d*8+0,0xff);
  POKE(0xe800U+0x1d*8+1,0xff);
  POKE(0xe800U+0x1d*8+2,0xff);
  POKE(0xe800U+0x1d*8+3,0xff);
  POKE(0xe800U+0x1d*8+4,0xff);
  POKE(0xe800U+0x1d*8+5,0xff);
  POKE(0xe800U+0x1d*8+6,0xff);
  POKE(0xe800U+0x1d*8+7,0xff);

  
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
    POKE(0xF000U+screen_offset,(c_upper<<6)+0x1f);
    lpoke(0x1f800U+screen_offset,colour_lookup[c_lower]);
  } else {
    if (c_lower<4) {
      POKE(0xF000U+screen_offset,(c_lower<<6)+0x1e);
      lpoke(0x1f800U+screen_offset,colour_lookup[c_upper]);
    } else {
      // Both halves are the last colour, so just use a solid char
      POKE(0xF000U+screen_offset,0x1d);
      lpoke(0x1f800U+screen_offset,colour_lookup[c_upper]);
    }
  }
}

void redraw_game_grid(void)
{
  // Work out how to display all combinations of the five colours:
  for(a=0;a<80;a++)
    for(b=0;b<25;b++)
      draw_pixel_char(a,b,game_grid[a][b<<1],game_grid[a][1+(b<<1)]);
}

unsigned char sprite_y;
unsigned short sprite_x;

void main(void)
{
  // Setup game state
  for(a=0;a<4;a++) {
    // Initial player placement
    if (a<2) { player_x[a]=0; player_direction[a]=0; } else { player_x[a]=79; player_direction[a]=0x20; }
    if (a&1) player_y[a]=49; else player_y[a]=0;
    // Player initially has no tiles allocated
    player_tiles[a]=0;
    // Players have no special feature initially
    player_features[a]=0;
    // Begin with unicorns in stationary pose
    player_animation_frame[a]=11;
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

    frame_count++;
    
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

      if ((!(frame_count&0x03))
	  ||((frame_count&1)&&(player_features[a]&FEATURE_FAST))
	  ||(player_features[a]&FEATURE_SUPERFAST))
	{
	  // Move based on new joystick position
	  if (b&1) { if (player_y[a]) player_y[a]--; }
	  if (b&2) { if (player_y[a]<49) player_y[a]++; }
	  if (b&4) { if (player_x[a]) player_x[a]--; }
	  if (b&8) { if (player_x[a]<79) player_x[a]++; }
	  if (b&0xf) {
	    // Player is being moved, so update animation frame
	    player_animation_frame[a]++;
	    if (player_animation_frame[a]>10) player_animation_frame[a]=0;
	  } else
	    // Stationary player, so show standing unicorn
	    player_animation_frame[a]=11;
	  if (player_animation_frame[a]>11) player_animation_frame[a]=0;
	  // Work out which direction, and from that, the position of the
	  // sprite
	  if (b&1) {
	    // Moving up
	    player_direction[a]=0x60;
	  }
	  if (b&2) {
	    // Moving down
	    player_direction[a]=0x40;
	  }
	  if (b&4) {
	    // Moving left
	    player_direction[a]=0x20;
	    POKE(0xF7F8U+a,32+player_animation_frame[a]);      // outline sprite
	    POKE(0xF7F8U+4+a,32+16+player_animation_frame[a]); // colour sprite
	    sprite_x=8+player_x[a]*4;
	    sprite_y=40+player_y[a]*4;
	  }
	  if (b&8) {
	    // Moving right
	    player_direction[a]=0x00;
	    POKE(0xF7F8U+a,player_animation_frame[a]);      // outline sprite
	    POKE(0xF7F8U+4+a,16+player_animation_frame[a]); // colour sprite
	    sprite_x=19+player_x[a]*4;
	    sprite_y=40+player_y[a]*4;
	  }
	  if (b&0xf) {
	    POKE(0xD000U+a*2,sprite_x&0xff);
	    POKE(0xD001U+a*2,sprite_y);
	    POKE(0xD008U+a*2,sprite_x&0xff);
	    POKE(0xD009U+a*2,sprite_y);
	    if (sprite_x&0x100) POKE(0xD010U,PEEK(0xD010U)|(0x11<<a));
	    else POKE(0xD010U,PEEK(0xD010U)&(0xFF-(0x11<<a)));
	  } else {
	    // No movement, just switch to stationary unicorn pose
	    POKE(0xF7F8U+a,player_direction[a]+player_animation_frame[a]);      // outline sprite
	    POKE(0xF7F8U+4+a,player_direction[a]+player_animation_frame[a]); // colour sprite
	  }
	}

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
