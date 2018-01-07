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
  POKE(0xD020,11);
}

void wait_for_vsync(void)
{
  while(!(PEEK(0xD011)&0x80)) continue;
  while((PEEK(0xD011)&0x80)) continue;
}

void fatal(void)
{
  sprites_on(0);
  while(1) continue;
}

void ok(void)
{
  printf("\n%c%cPASS %c\n",
	 0x91,30,5);
}

uint8_t screen_buffer[1024];
uint8_t colour_buffer[1024];
void stash_screen(void)
{
  uint16_t i;
  for(i=0;i<1000;i++) {
    screen_buffer[i]=PEEK(0x0400+i);
    colour_buffer[i]=PEEK(0xD800+i);
  }
}

void restore_screen(void)
{
  uint16_t i;
  for(i=0;i<1000;i++) {
    POKE(0x0400+i,screen_buffer[i]);
    POKE(0xD800+i,colour_buffer[i]);
  }
}

void clear_screen(void)
{
  uint16_t i;
  for(i=0;i<1000;i++) {
    POKE(0x0400+i,0x20);
    POKE(0xD800+i,1);
  }
}

uint8_t v;
uint16_t x,y,first_contact,last_contact;

void sweep_sprite_from_right_to_left(uint16_t x_high,uint16_t x_low,uint8_t blockP)
{
  sprite_erase(0);
  if (blockP) sprite_reverse(0);
  else for(y=0;y<21;y++) POKE(0x380+y*3,0x80);
  sprites_on(1+4+16);

  first_contact=999;
  last_contact=999;
  for(x=x_high;x>x_low;x--) {
    sprite_setxy(0,x,100);
    wait_for_vsync();
    v=PEEK(0xD01F);
    wait_for_vsync();
    v=PEEK(0xD01F);
    if ((v&1)==1) {
      if (first_contact==999) {
	first_contact=x;
	sprite_setxy(2,x,100-21);
      }
      last_contact=x;
      sprite_setxy(4,x,100+21);      
    } else {
      // Stop as soon as we have found it
      if (last_contact!=999) return;
    }
  }
  return;
}

void sweep_sprite_from_bottom_to_top(uint16_t y_high,uint16_t y_low, uint8_t blockP)
{
  // Sprite is horizontal line 1 pixel high
  sprite_erase(0);
  if (blockP) sprite_reverse(0);
  else for(y=0;y<3;y++) POKE(0x380+y,0xFF);
  sprites_on(1+4+16);

  first_contact=999;
  last_contact=999;
  for(y=y_high;y>y_low;y--) {
    sprite_setxy(0,100,y);
    wait_for_vsync();
    v=PEEK(0xD01F);
    wait_for_vsync();
    v=PEEK(0xD01F);
    if ((v&1)==1) {
      if (first_contact==999) {
	first_contact=y;
	sprite_setxy(2,100-24,y);
      }
      last_contact=y;
      sprite_setxy(4,100+24,y);      
    } else {
      // Stop as soon as we have found it
      if (last_contact!=999) return;
    }
  }
  return;
}


void check_sprite_contact(uint16_t expected_first,uint16_t expected_last)
{
  if (first_contact!=expected_first||last_contact!=expected_last) {
    printf("\nFAIL: Wrong sprite position/dimensions.\n");
    if (first_contact!=expected_first) {
      printf("* First contact should be at $%x.\n"
	     "  On this machine it is at $%x\n",
	     expected_first,first_contact);
    }
    if (last_contact!=expected_last) {
      printf("* Last contact should be at $%x.\n"
	     "  On this machine it is at $%x\n",
	     expected_last,last_contact);
    }
    fatal();
  } else ok();
  return;
}

void sprite_x_tests(void)
{
  
  printf("     Expanded Sprite @ column 8");
  stash_screen();
  clear_screen();
  // Draw a vertical bar in 8th column.
  for(v=0;v<25;v++) POKE(0x0408+40*v,0x65);
  POKE(0xD01D,0xff);
  sweep_sprite_from_right_to_left(200,0,0);
  restore_screen();
  check_sprite_contact(0x59,0x57);
  POKE(0xD01D,0);

  printf("     Sprite X position @ left edge");
  stash_screen();
  clear_screen();  
  // Draw vertical bar 2 pixels wide on left edge of the screen
  for(v=0;v<25;v++) POKE(0x0400+40*v,0x65);
  sweep_sprite_from_right_to_left(100,0,0);
  restore_screen();
  check_sprite_contact(0x19,0x18);

  printf("     Sprite X position @ column 8");
  stash_screen();
  clear_screen();
  // Draw a vertical bar in 8th column.
  for(v=0;v<25;v++) POKE(0x0408+40*v,0x65);
  sweep_sprite_from_right_to_left(200,0,0);
  restore_screen();
  check_sprite_contact(0x59,0x58);

  printf("     Sprite X position @ column 38");
  stash_screen();
  clear_screen();
  // Draw a vertical bar in 38th column.
  for(v=0;v<25;v++) POKE(0x0400+38+40*v,0x65);
  sweep_sprite_from_right_to_left(400,0,0);
  restore_screen();
  check_sprite_contact(0x149,0x148);

  printf("     Sprite X position @ right edge");
  stash_screen(); clear_screen();
  // Draw a vertical bar on right edge of column 39
  for(v=0;v<25;v++) POKE(0x0400+39+40*v,0x67);
  sweep_sprite_from_right_to_left(400,0,0);
  restore_screen();
  check_sprite_contact(0x157,0x156);

  printf("     Sprite X scale is correct");
  stash_screen();
  clear_screen();
  // Draw a vertical bar in 8th column.
  for(v=0;v<25;v++) POKE(0x0408+40*v,0x65);
  sweep_sprite_from_right_to_left(200,0,1);
  restore_screen(); sprites_on(0);
  check_sprite_contact(0x59,0x58-24+1);

  return;
}

void sprite_y_tests(void)
{
  printf("     Sprite Y position at top edge");
  stash_screen(); clear_screen();
  // Draw a horizontal bar at top of screen
  for(v=0;v<40;v++) POKE(0x0400+0*40+v,0x63);
  sweep_sprite_from_bottom_to_top(100,0,0);
  restore_screen();
  check_sprite_contact(0x32,0x32);

  printf("     Sprite Y position at row 10");
  stash_screen(); clear_screen();
  // Draw a horizontal bar at top of screen
  for(v=0;v<40;v++) POKE(0x0400+10*40+v,0x63);
  sweep_sprite_from_bottom_to_top(200,0,0);
  restore_screen();
  check_sprite_contact(0x82,0x82);

  printf("     Sprite Y position at bottom edge");
  stash_screen(); clear_screen();
  // Draw a horizontal bar at top of screen
  for(v=0;v<40;v++) POKE(0x0400+24*40+v,0x64);
  sweep_sprite_from_bottom_to_top(255,0,0);
  restore_screen();
  check_sprite_contact(0xf9,0xf9);

  printf("     Sprite Y scale correct");
  sprite_erase(0);
  sprite_reverse(0);
  stash_screen(); clear_screen();
  // Draw a horizontal bar at top of screen
  for(v=0;v<40;v++) POKE(0x0400+10*40+v,0x63);
  sweep_sprite_from_bottom_to_top(200,0,1);
  restore_screen(); sprites_on(0);
  check_sprite_contact(0x82,0x82-21+1);
  
  return;
}

int main(int argc,char **argv)
{
  
  printf("%c%c"
	 "M.E.G.A.65 VIC-II Test Programme\n"
	 "(C)Copyright Paul Gardner-Stephen, 2017.\n"
	 "GNU General Public License v3 or newer.\n"
	 "\n",0x93,5);

  // Prepare sprites
  setup();  

  printf("     No S:S collide when no sprites");
  v=PEEK(0xD01E); // clear existing collisions
  // Wait a couple of frames to make sure
  wait_for_vsync();
  wait_for_vsync();
  // Check that there is no collision yet
  v=PEEK(0xD01E);
  if (!v) ok();
  else {
    printf("\nFAIL: Collisions detected with no sprites active.\n");
    fatal();
  }

  printf("     Detect simple S:S collisions");
  sprite_setxy(0,100,100);
  sprite_setxy(1,102,102);
  sprites_on(0x03);
  wait_for_vsync();
  wait_for_vsync();
  v=PEEK(0xD01E);
  if (v==3) {
    // Read result for next test first, as it is timing sensitive
    v=PEEK(0xD01E);
    ok();
  }
  else {
    printf("\nFAIL: *$D01E != $03 (sprite 0 and 1 collision). Instead saw $%x\n",v);
    fatal();
  }
  printf("     Reading $D01E clears collisions");
  if (!v) ok();
  else {
    printf("\nFAIL: Reading $D01E does not clear sprite:sprite collisions.\n");
    fatal();
  }  
  printf("     X MSB separates sprites");
  sprite_setxy(0,90,100);
  sprite_setxy(1,90+256,100);
  wait_for_vsync();
  v=PEEK(0xD01E);
  wait_for_vsync();
  wait_for_vsync();
  v=PEEK(0xD01E);
  
  if (!v) ok();
  else {
    printf("\nFAIL: Collisions detected with sprites separated by 256 pixels ($D01E=$%x)\n",v);
    fatal();
  }
  printf("     Sprites don't collide in border");
  // Consider scanning across to the right, to see if right border / sprite positioning
  // is accurate?
  // But for now, just place fixed in side border
  sprite_setxy(0,24+320+10,100);
  sprite_setxy(1,24+320+10,100);
  wait_for_vsync();
  v=PEEK(0xD01E);
  wait_for_vsync();
  if (!v) ok();
  else {
    printf("\nFAIL: *$D01E != $00: Saw $%x\n",v);
    fatal();
  }

  /* At this point, we know that sprite collisions work to some basic degree.
     What we don't know is if the sprites are displayed at the correct location, or 
     are rendered the correct size.
     These two are somewhat interrelated.
     We begin by testing sprite:background collision, and from there drawing particular things
     on the screen and in the sprites to determine exactly where a sprite is drawn, and if 
     it is drawn at the correct size.

     As we are using the C64 character set by default, we are limited in the shapes we can try
     to collide with. Char $65 is a vertical bar 2 pixels wide on the left edge of a character.
     
  */
  sprite_x_tests();
  sprite_y_tests();

}
