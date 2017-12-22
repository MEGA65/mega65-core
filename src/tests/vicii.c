/*
  Test program for VIC-II.
  (C) Copyright Paul Gardner-Stephen, 2017.
  Released under the GNU General Public License, v3.

  The purpose of this program is to test as many functions of
  the VIC-II as possible, in a fully automated manner.  This is
  to allow it to be used to support regression testing for the
  MEGA65.  

  Sprite-Sprite and Sprite-background colission will be used
  as the means of automatically testing many functions.

  This program will likely end up supporting M65 features, to
  support fully automatic operation. In particular, it will
  likely use the pixel debug function, that allows the pixel
  colour at a given coordinate to be read.

  The main challenge for now, using CC65 as compiler is where to
  put sprites in video bank zero.  For now, we use only two
  sprite blocks at $0200 and $0240.

*/
  

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define POKE(a,v) *((uint8_t *)a)=(uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))

void sprite_setxy(uint8_t sprite,uint16_t x,uint16_t y)
{
  uint8_t bit = 1<<sprite;
  if (sprite>7) return;
  POKE(0xd000+(sprite<<1),x & 0xff);
  POKE(0xd001+(sprite<<1),y & 0xff);
  if (x&0x100)
    // MSB set
    POKE(0xD010,PEEK(0xD010)|bit);
  else
    // MSB clear
    POKE(0xD010,PEEK(0xD010)&(0xff-bit));   
}

void sprite_erase(uint8_t sprite)
{
  uint8_t i;
  uint16_t base=0x0380 + ((sprite&1)<<6);
  if (sprite>7) return;
  for(i=0;i<64;i++) POKE((base+i),0);
}

void sprite_reverse(uint8_t sprite)
{
  uint8_t i;
  uint16_t base=0x0380 + ((sprite&1)<<6);
  if (sprite>7) return;
  for(i=0;i<64;i++) POKE((base+i),PEEK((base+i))^0xff);
}

void sprite_setup(void)
{
  uint8_t i;

  for(i=0;i<8;i++) {
    // All sprites red
    POKE(0xD027+i,2);
    sprite_setxy(i,0,0);
    // Set sprite source to $0380-$03FF
    POKE(0x7F8+i,14+(i&1));
    // Make each sprite solid
    sprite_erase(i);
    sprite_reverse(i);
  }
}

void sprites_on(uint8_t v)
{
  POKE(0xD015,v);
}

void setup(void)
{
  sprite_setup();
  sprites_on(0);
  POKE(0xD020,1);
}

void wait_for_vsync(void)
{
  while(!(PEEK(0xD011)&0x80)) continue;
  while((PEEK(0xD011)&0x80)) continue;
}

void fatal(void)
{
  
  while(1) continue;
}

int main(int argc,char **argv)
{
  uint8_t v;
  
  printf("%c"
	 "M.E.G.A.65 VIC-II Test Programme\n"
	 "(C)Copyright Paul Gardner-Stephen, 2017.\n"
	 "GNU General Public License v3 or newer.\n"
	 "\n",0x93);

  // Prepare sprites
  setup();  

  printf("Testing sprite-sprite collision");
  v=PEEK(0xD01E); // clear existing collisions
  // Wait a couple of frames to make sure
  wait_for_vsync();
  wait_for_vsync();
  // Check that there is no collision yet
  v=PEEK(0xD01E);
  if (!v) printf(".");
  else {
    printf("FAIL: Collisions detected with no sprites active.\n");
    fatal();
  }

  sprite_setxy(0,100,100);
  sprite_setxy(1,102,102);
  sprites_on(0x03);
  wait_for_vsync();
  wait_for_vsync();
  v=PEEK(0xD01E);
  if (v==3) printf(".");
  else {
    printf("FAIL: *$D01E != $03 (sprite 0 and 1 collision). Instead saw $%x\n",v);
    fatal();
  }

}
