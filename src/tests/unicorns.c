/*
  Simple "colour in the screen in your colour" game as
  demo of C65.

*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define POKE(a, v) *((uint8_t *)a) = (uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))

#include "horses.h"

unsigned char player_names[4][10] = {
  // Fluffy
  { 6, 12, 21, 6, 6, 25, 46, 46, 46, 46 },
  // Misty
  { 13, 9, 19, 20, 25, 46, 46, 46, 46, 46 },
  // Puff Puff
  { 16, 21, 6, 6, 32, 16, 21, 6, 6, 46 },
  // Breeze
  { 2, 18, 5, 5, 26, 5, 46, 46, 46, 46 }
};

unsigned short i;

struct dmagic_dmalist {
  // F018B format DMA request
  unsigned char command;
  unsigned int count;
  unsigned int source_addr;
  unsigned char source_bank;
  unsigned int dest_addr;
  unsigned char dest_bank;
  unsigned char sub_cmd; // F018B subcmd
  unsigned int modulo;
};

struct dmagic_dmalist dmalist;
unsigned char dma_byte;

void do_dma(void)
{
  // Now run DMA job (to and from anywhere, and list is in low 1MB)
  POKE(0xd702U, 0);
  POKE(0xd701U, (((unsigned int)&dmalist) >> 8));
  POKE(0xd700U, ((unsigned int)&dmalist) & 0xff); // triggers enhanced DMA

  POKE(0x0401U, (((unsigned int)&dmalist) >> 8));
  POKE(0x0400U, ((unsigned int)&dmalist) & 0xff); // triggers enhanced DMA
}

void lpoke(long address, unsigned char value)
{
  dma_byte = value;
  dmalist.command = 0x00; // copy
  dmalist.sub_cmd = 0;
  dmalist.modulo = 0;
  dmalist.count = 1;
  dmalist.source_addr = (unsigned int)&dma_byte;
  dmalist.source_bank = 0;
  dmalist.dest_addr = address & 0xffff;
  dmalist.dest_bank = (address >> 16);

  do_dma();
  return;
}

unsigned char lpeek(long address)
{
  dmalist.command = 0x00; // copy
  dmalist.count = 1;
  dmalist.source_addr = address & 0xffff;
  dmalist.source_bank = (address >> 16) & 0x7f;
  dmalist.dest_addr = (unsigned int)&dma_byte;
  dmalist.source_bank = 0;
  dmalist.dest_addr = address & 0xffff;
  dmalist.dest_bank = (address >> 16) & 0x7f;
  // Make list work on either old or new DMAgic
  dmalist.sub_cmd = 0;
  dmalist.modulo = 0;

  do_dma();
  return dma_byte;
}

void lcopy(long source_address, long destination_address, unsigned int count)
{
  dmalist.command = 0x00; // copy
  dmalist.count = count;
  dmalist.sub_cmd = 0;
  dmalist.modulo = 0;
  dmalist.source_addr = source_address & 0xffff;
  dmalist.source_bank = (source_address >> 16) & 0x0f;
  //  if (source_address>=0xd000 && source_address<0xe000)
  //    dmalist.source_bank|=0x80;
  dmalist.dest_addr = destination_address & 0xffff;
  dmalist.dest_bank = (destination_address >> 16) & 0x0f;
  //  if (destination_address>=0xd000 && destination_address<0xe000)
  //    dmalist.dest_bank|=0x80;

  do_dma();
  return;
}

void lfill(long destination_address, unsigned char value, unsigned int count)
{
  dmalist.command = 0x03; // fill
  dmalist.sub_cmd = 0;
  dmalist.count = count;
  dmalist.source_addr = value;
  dmalist.dest_addr = destination_address & 0xffff;
  dmalist.dest_bank = (destination_address >> 16) & 0x7f;
  if (destination_address >= 0xd000 && destination_address < 0xe000)
    dmalist.dest_bank |= 0x80;

  do_dma();
  return;
}

unsigned char flipped[256];

unsigned char frame_count = 0;

unsigned short addr;
unsigned char a, b, c, d, v;

// Play grid. Contains 0x00 for blank, 0x01-0x04 for
// trail from a given player, or 0x10-0xFF for special poop
unsigned char game_grid[80][50];
#define SPECIAL_FAST 0x00
#define SPECIAL_SUPERFAST 0x01
#define SPECIAL_LONGERTAIL 0x02
#define SPECIAL_DETACHTAIL 0x03
#define SPECIAL_GLOWWORM0 0x04
#define SPECIAL_GLOWWORM1 0x05
#define SPECIAL_GLOWWORM2 0x06
#define SPECIAL_GLOWWORM3 0x07
#define SPECIAL_RAINBOWPOOP 0x08
#define SPECIAL_LESSMAGIC 0x09
#define SPECIAL_MOREMAGIC 0x0a
#define SPECIAL_MAGICSQUIRTS 0x0b
#define SPECIAL_SLOW 0x0c
#define SPECIAL_MAX 0x0d

// Position of players on the grid
unsigned char player_x[4];
unsigned char player_y[4];

// How many tiles does the player have to their credit?
unsigned int player_tiles[4];

// How long the player's tails are allowed to grow to
unsigned char player_tail_max_lengths[4];
// History of player tails, so that we can erase them
unsigned char player_tail_history_x[4][256];
unsigned char player_tail_history_y[4][256];
// Start (head) and end (tail) of player trails
// start is advanced when drawing a new piece
// end is advanced when erasing the end of a tail
unsigned char player_tail_start[4];
unsigned char player_tail_end[4];
// For convenience we track the length, so we can apply max_length as required
unsigned char player_tail_length[4];

// Indicates what powerups etc that each player currently has
unsigned short player_features[4];
#define FEATURE_FAST 0x01
#define FEATURE_SUPERFAST 0x02
#define FEATURE_RAINBOWPOOP 0x03
// How many frames before the powerup on each player times out
unsigned short player_feature_timeouts[4];

// Which colour do we paint our tail in?
unsigned char player_paint_colour[4];
unsigned char player_fire_action_timeout[4];

// bitmask used with rand() to decide if we are pooping something special each movement
unsigned char player_poop_mask[4];

// Which frame of the running/standing unicorn should we display for each player?
unsigned int player_animation_frame[4];
// Which direction did the player last move in? (so we can show the correct standing unicorn frame)
unsigned int player_direction[4];

void prepare_sprites(void)
{
  // Enable all sprites.
  POKE(0xD015U, 0xFF);

  // Set first four sprites to light grey for unicorn outlines
  POKE(0xD02BU, 0xf);
  POKE(0xD02CU, 0xf);
  POKE(0xD02DU, 0xf);
  POKE(0xD02EU, 0xf);
  // And second four sprites to player colours for unicorn bodies
  POKE(0xD027U, 0x2);
  POKE(0xD028U, 0x5);
  POKE(0xD029U, 0x6);
  POKE(0xD02AU, 0x7);

  // Set second four sprites to player colours

  // Make horizontally flipped sprites
  a = 0;
  do {
    flipped[a] = 0;
    if (a & 0x01)
      flipped[a] ^= 0x80;
    if (a & 0x02)
      flipped[a] ^= 0x40;
    if (a & 0x04)
      flipped[a] ^= 0x20;
    if (a & 0x08)
      flipped[a] ^= 0x10;
    if (a & 0x10)
      flipped[a] ^= 0x08;
    if (a & 0x20)
      flipped[a] ^= 0x04;
    if (a & 0x40)
      flipped[a] ^= 0x02;
    if (a & 0x80)
      flipped[a] ^= 0x01;
  } while (++a);

  // Make horizontally flipped sprites
  for (a = 0; a < 32; a++) {
    for (b = 0; b < 21; b++) {
      POKE(0xC000U + 32 * 64 + a * 64 + b * 3 + 0, flipped[PEEK(0xC000U + a * 64 + b * 3 + 2)]);
      POKE(0xC000U + 32 * 64 + a * 64 + b * 3 + 1, flipped[PEEK(0xC000U + a * 64 + b * 3 + 1)]);
      POKE(0xC000U + 32 * 64 + a * 64 + b * 3 + 2, flipped[PEEK(0xC000U + a * 64 + b * 3 + 0)]);
    }
  }

  // Now make 90 degree rotated versions
  for (a = 0; a < 32; a++) {
    {
      for (b = 0; b < 21; b++)  // y in destination
        for (c = 0; c < 3; c++) // x BYTE in destination
        {
          // Work out which bit of bytes to read
          v = 0;
          d = b & 7;
          d = 1 << d;
          addr = a * 64 + (c * 24) + (2 - (b >> 3));

          if (horse_sprites[addr] & d) {
            v |= 0x80;
          }
          addr += 3;
          if (horse_sprites[addr] & d) {
            v |= 0x40;
          }
          addr += 3;
          if (horse_sprites[addr] & d) {
            v |= 0x20;
          }
          addr += 3;
          if (horse_sprites[addr] & d) {
            v |= 0x10;
          }
          addr += 3;
          if (horse_sprites[addr] & d) {
            v |= 0x08;
          }
          addr += 3;
          if (c < 2) {
            if (horse_sprites[addr] & d) {
              v |= 0x04;
            }
            addr += 3;
            if (horse_sprites[addr] & d) {
              v |= 0x02;
            }
            addr += 3;
            if (horse_sprites[addr] & d) {
              v |= 0x01;
            }
            addr += 3;
          }
          else
            addr += 3 * 3;

          if (a < 32)
            lpoke(0xC000U + 64 * 64 + a * 64 + b * 3 + c, v);
          else
            lpoke(0xC000U + 64 * 64 + a * 64 + (63 - b * 3) + c, v);
        }

      POKE(0xD020U, a & 0xf);
    }
  }
  // And then the vertical flipped copies of them
  lcopy(0xD000U, 0xD800U, 2048);
  for (a = 0; a < 32; a++) {
    for (b = 0; b < 21; b++)  // y in destination
      for (c = 0; c < 3; c++) // x BYTE in destination
      {
        lcopy(0xD800U + a * 64 + (63 - b * 3), 0xD000U + a * 64 + b * 3, 3);
      }
    POKE(0xD020U, a & 0xf);
  }

  POKE(0xD020U, 0xa);
}

void videomode_game(void)
{

  // Enable C65 VIC-III IO registers
  POKE(0xD02FU, 0xA5);
  POKE(0xD02FU, 0x96);

  // 80 column text mode, 3.5MHz CPU
  POKE(0xD031U, 0xE0);

  // Put screen at $F000, get charrom from $E800
  // Will be 2K for 80x25 text mode
  POKE(0xDD00U, 0x00);
  POKE(0xD018U, 0xCB);

  // Pink border, black background
  POKE(0xD020U, 0x0a);
  POKE(0xD021U, 0x00);

  // Red, Green, Yellow in EBC mode colours
  POKE(0xD022, 0x02);
  POKE(0xD023, 0x05);
  POKE(0xD024, 0x06);

  // Extended background colour mode
  // (so we can do fake 80x50 graphics mode with character 0x62 (half filled block)
  POKE(0xD011U, 0x5b);

  // Clear screen
  lfill(0xf000U, 0x20, 2000);
  // Set colour of characters to yellow
  lfill(0x1f800U, 0x07, 2000);

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
  lfill(0xC000U, 0, 0x2800U); // Erase all sprites first
  lcopy((long)&horse_sprites[0], 0xC000U, sizeof(horse_sprites));
  prepare_sprites();

  // Copy charrom to $F000-$F7FF
  lcopy(0x29000U, 0xe800U, 2048);
  // Patch char $1F to be half block (like char $62 in normal char ROM)
  POKE(0xe800U + 0x1f * 8 + 0, 0);
  POKE(0xe800U + 0x1f * 8 + 1, 0);
  POKE(0xe800U + 0x1f * 8 + 2, 0);
  POKE(0xe800U + 0x1f * 8 + 3, 0);
  POKE(0xe800U + 0x1f * 8 + 4, 0xff);
  POKE(0xe800U + 0x1f * 8 + 5, 0xff);
  POKE(0xe800U + 0x1f * 8 + 6, 0xff);
  POKE(0xe800U + 0x1f * 8 + 7, 0xff);
  // Patch char $1E to be inverted half block
  POKE(0xe800U + 0x1e * 8 + 0, 0xff);
  POKE(0xe800U + 0x1e * 8 + 1, 0xff);
  POKE(0xe800U + 0x1e * 8 + 2, 0xff);
  POKE(0xe800U + 0x1e * 8 + 3, 0xff);
  POKE(0xe800U + 0x1e * 8 + 4, 0);
  POKE(0xe800U + 0x1e * 8 + 5, 0);
  POKE(0xe800U + 0x1e * 8 + 6, 0);
  POKE(0xe800U + 0x1e * 8 + 7, 0);
  // Patch char $1D to be solid block
  POKE(0xe800U + 0x1d * 8 + 0, 0xff);
  POKE(0xe800U + 0x1d * 8 + 1, 0xff);
  POKE(0xe800U + 0x1d * 8 + 2, 0xff);
  POKE(0xe800U + 0x1d * 8 + 3, 0xff);
  POKE(0xe800U + 0x1d * 8 + 4, 0xff);
  POKE(0xe800U + 0x1d * 8 + 5, 0xff);
  POKE(0xe800U + 0x1d * 8 + 6, 0xff);
  POKE(0xe800U + 0x1d * 8 + 7, 0xff);
}

unsigned char colour_lookup[5] = { 0, 2, 5, 6, 7 };
unsigned short screen_offset;
void draw_pixel_char(unsigned char x, unsigned char y, unsigned char c_upper, unsigned char c_lower)
{
  if (y > 24)
    return;
  if (x > 79)
    return;

  // For special poop, we have more or less random colours allocated for it.
  // XXX - Make sure to distribute the good and bad things evenly among the four colours!
  if (c_lower > 4)
    c_lower = 1 + (c_lower & 0x03);
  if (c_upper > 4)
    c_upper = 1 + (c_upper & 0x03);

  screen_offset = y * 80 + x;
  if (c_upper < 4) {
    // Use half-char block with active pixels in bottom half.
    // Set colour of upper half using extended background
    POKE(0xF000U + screen_offset, (c_upper << 6) + 0x1f);
    lpoke(0x1f800U + screen_offset, colour_lookup[c_lower]);
  }
  else {
    if (c_lower < 4) {
      POKE(0xF000U + screen_offset, (c_lower << 6) + 0x1e);
      lpoke(0x1f800U + screen_offset, colour_lookup[c_upper]);
    }
    else {
      // Both halves are the last colour, so just use a solid char
      POKE(0xF000U + screen_offset, 0x1d);
      lpoke(0x1f800U + screen_offset, colour_lookup[c_upper]);
    }
  }
}

void redraw_game_grid(void)
{
  // Work out how to display all combinations of the five colours:
  for (a = 0; a < 80; a++)
    for (b = 0; b < 25; b++)
      if (game_grid[a][b << 1] != 0xff)
        // Normal character
        draw_pixel_char(a, b, game_grid[a][b << 1], game_grid[a][1 + (b << 1)]);
      else {
        // Score box character.  Will be drawn separately
        continue;
      }

  lcopy((long)player_names[0], 0xF000U, 10);
  lcopy((long)player_names[1], 0xF000U + 22 * 80, 10);
  lcopy((long)player_names[2], 0xF000U + 70, 10);
  lcopy((long)player_names[3], 0xF000U + 22 * 80 + 70, 10);
  lfill(0x1F800U, 2, 10);
  lfill(0x1F800U + 22 * 80, 5, 10);
  lfill(0x1F800U + 70, 6, 10);
  lfill(0x1F800U + 22 * 80 + 70, 7, 10);

  lfill(0x1F800U + 80, 1, 10);
  lfill(0x1F800U + 22 * 80 + 80, 1, 10);
  lfill(0x1F800U + 70 + 80, 1, 10);
  lfill(0x1F800U + 22 * 80 + 70 + 80, 1, 10);

  lfill(0x1F800U + 2 * 80, 1, 10);
  lfill(0x1F800U + 22 * 80 + 2 * 80, 1, 10);
  lfill(0x1F800U + 70 + 2 * 80, 1, 10);
  lfill(0x1F800U + 22 * 80 + 70 + 2 * 80, 1, 10);
}

unsigned char sprite_y;
unsigned short sprite_x;

unsigned char colour_phase = 0;

char score_string[11];

unsigned char cx, cy;

void main(void)
{
  // Setup game state
  for (a = 0; a < 4; a++) {
    // Initial player placement
    if (a < 2) {
      POKE(0xD000U + a * 2, 21);
      POKE(0xD008U + a * 2, 21);
      player_x[a] = 0;
      player_direction[a] = 0;
    }
    else {
      POKE(0xD000U + a * 2, 8 + 79 * 4);
      POKE(0xD008U + a * 2, 8 + 79 * 4);
      POKE(0xD010U, PEEK(0xD010U) | (0x11 << a));
      player_x[a] = 79;
      player_direction[a] = 0x20;
    }
    // Start player clear of score boxes
    if (a & 1) {
      POKE(0xD001U + a * 2, 43 + 40 * 4);
      POKE(0xD009U + a * 2, 43 + 40 * 4);
      player_y[a] = 40;
    }
    else {
      POKE(0xD001U + a * 2, 43 + 10 * 4);
      POKE(0xD009U + a * 2, 43 + 10 * 4);
      player_y[a] = 10;
    }

    // Player initially has no tiles allocated
    player_tiles[a] = 0;
    // Players have no special feature initially
    player_features[a] = 0;
    // Begin with unicorns in stationary pose
    player_animation_frame[a] = 11;

    // By default paint in the correct colour
    player_paint_colour[a] = a;
    // Immediately be primed to drop a trap
    player_fire_action_timeout[a] = 0;
    // Only produce magic poop relatively rarely
    player_poop_mask[a] = 0x1f;

    // Clear powerups, and reset maximum tail lengths etc
    player_features[a] = 0;
    player_tail_max_lengths[a] = 8;
    player_tail_start[a] = 0;
    player_tail_end[a] = 0;
    player_tail_length[a] = 0;
  }
  // Clear game grid
  for (a = 0; a < 80; a++)
    for (b = 0; b < 50; b++)
      game_grid[a][b] = 0;
  // Mark score boxes off-limits
  for (a = 0; a < 10; a++)
    for (b = 0; b < 6; b++)
      game_grid[a][b] = 0xff;
  for (a = 70; a < 80; a++)
    for (b = 0; b < 6; b++)
      game_grid[a][b] = 0xff;
  for (a = 0; a < 10; a++)
    for (b = 44; b < 50; b++)
      game_grid[a][b] = 0xff;
  for (a = 70; a < 80; a++)
    for (b = 44; b < 50; b++)
      game_grid[a][b] = 0xff;

  // See random number generator
  srand(PEEK(0xD012U));

  // Set DDR on port for protovision/CGA joystick expander
  POKE(0xDD03U, 0x80);
  POKE(0xDD01U, 0x00); // And ready to read joystick 3 initially

  videomode_game();

  // then redraw it (this takes a few frames to do completely)
  redraw_game_grid();

  while (1) {

    // Run game state update once per frame
    while (PEEK(0xD012U) < 0xFE)
      continue;

    frame_count++;

    // Clear some magic poop each frame
    // This stops magic items building up too much.
    for (a = 0; a < 10; a++) {
      // Do pseudo-random cleanup
      cx += 23;
      if (cx > 79) {
        cx -= 80;
        cy++;
      }
      if (cy > 49)
        cy = 0;

      // clear and re-draw the cell if required
      if ((game_grid[cx][cy] >= 0x10) && (game_grid[cx][cy] != 0xff)) {
        game_grid[cx][cy] = 0;
        draw_pixel_char(cx, cy >> 1, game_grid[cx][cy & 0xfe], game_grid[cx][cy | 0x01]);
      }
    }

    // Pulse grey of the unicorns
    if (!(frame_count & 3)) {
      colour_phase++;
      if (colour_phase > 25)
        colour_phase = 0;
      if (colour_phase < 14) {
        POKE(0xD10Fu, 2 + colour_phase);
        POKE(0xD20FU, 2 + colour_phase);
        POKE(0xD30FU, 2 + colour_phase);
      }
      else {
        POKE(0xD10FU, 2 + 25 - colour_phase);
        POKE(0xD20FU, 2 + 25 - colour_phase);
        POKE(0xD30FU, 2 + 25 - colour_phase);
      }
    }

    // Update score displays
    for (a = 0; a < 4; a++) {
      snprintf(score_string, 11, "%10d", player_tiles[a]);
      lcopy((long)score_string, 0xF000U + 80 + ((a & 2) ? 70 : 0) + ((a & 1) ? (22 * 80) : 0), 10);

      // Timeout specials
      if (player_feature_timeouts[a]) {
        player_feature_timeouts[a]--;
      }
      else {
        // Immediately go back to painting in your own colour

        player_paint_colour[a] = a;
        POKE(0xD02BU + a, 0x0f);
        lfill(0x1F800U + ((a & 1) ? 22 * 80 : 0) + ((a & 2) ? 70 : 0), (!a) ? 2 : (a == 1) ? 5 : (a == 2) ? 6 : 7, 10);

        // Clear fast/super fast/rainbow painting etc
        player_features[a] = 0;
        // stop magic diarrhoea / slow down rate of pooping extra stuff
        if (!player_poop_mask[a])
          player_poop_mask[a] = 0x1f;
        else if (player_poop_mask[a] < 0x1f) {
          player_poop_mask[a] = (player_poop_mask[a] << 1) | 0x01;
          player_feature_timeouts[a] = 120;
        }
        else if (player_poop_mask[a] > 0x3f) {
          player_poop_mask[a] = player_poop_mask[a] >> 1;
          player_feature_timeouts[a] = 120;
        }
      }
    }

    // Read state of the four joysticks
    for (a = 0; a < 4; a++) {

      // If tail is longer than allowed, then make it quickly zip back up to the correct length
      if (player_tail_length[a] > player_tail_max_lengths[a]) {
        b = player_tail_end[a];
        c = player_tail_history_x[a][b];
        d = player_tail_history_y[a][b];
        b = game_grid[c][d];
        if (b && (b < 5))
          if (player_tiles[b - 1])
            player_tiles[b - 1]--;
        game_grid[c][d] = 0;
        draw_pixel_char(c, d >> 1, game_grid[c][d & 0xfe], game_grid[c][d | 0x01]);
        player_tail_end[a]++;
        player_tail_length[a]--;
      }

      // Get joystick state
      switch (a) {
      case 0:
        b = PEEK(0xDC00U) & 0x1f;
        break;
      case 1:
        b = PEEK(0xDC01U) & 0x1f;
        break;
        // PEEK must come before POKE in the following to make sure CC65 doesn't optimise the PEEK away
      case 2:
        b = (PEEK(0xDD01U) & 0xf) + ((PEEK(0xDD01U) >> 1) & 0x10);
        POKE(0xDD01U, 0x80);
        break;
      case 3:
        b = PEEK(0xDD01U) & 0x1f;
        POKE(0xDD01U, 0x00);
        break;
      }
      // Make joystick data active high
      b ^= 0x1f;

      if ((!(frame_count & 0x03)) || ((frame_count & 1) && (player_features[a] & FEATURE_FAST))
          || (player_features[a] & FEATURE_SUPERFAST)) {
        // Move based on new joystick position
        if (b & 1) {
          if (player_y[a] && (game_grid[player_x[a]][player_y[a] - 1] != 0xff))
            player_y[a]--;
        }
        if (b & 2) {
          if (player_y[a] < 49 && (game_grid[player_x[a]][player_y[a] + 1] != 0xff))
            player_y[a]++;
        }
        if (b & 4) {
          if (player_x[a] && (game_grid[player_x[a] - 1][player_y[a]] != 0xff))
            player_x[a]--;
        }
        if (b & 8) {
          if (player_x[a] < 79 && (game_grid[player_x[a] + 2][player_y[a]] != 0xff))
            player_x[a]++;
        }
        if (b & 0xf) {
          // Player is being moved, so update animation frame
          player_animation_frame[a]++;
          if (player_animation_frame[a] > 10)
            player_animation_frame[a] = 0;
        }
        else
          // Stationary player, so show standing unicorn
          player_animation_frame[a] = 11;
        if (player_animation_frame[a] > 11)
          player_animation_frame[a] = 0;
        // Work out which direction, and from that, the position of the
        // sprite
        if (b & 1) {
          // Moving up
          player_direction[a] = 0x60;
          POKE(0xF7F8U + a, 0x60 + 16 + player_animation_frame[a]); // colour sprite
          POKE(0xF7F8U + 4 + a, 0x60 + player_animation_frame[a]);  // outline sprite
          sprite_x = 18 + player_x[a] * 4;
          sprite_y = 33 + player_y[a] * 4;
        }
        if (b & 2) {
          // Moving down
          player_direction[a] = 0x40;
          POKE(0xF7F8U + a, 0x40 + 16 + player_animation_frame[a]); // colour sprite
          POKE(0xF7F8U + 4 + a, 0x40 + player_animation_frame[a]);  // outline sprite
          sprite_x = 18 + player_x[a] * 4;
          sprite_y = 49 + player_y[a] * 4;
        }
        if (b & 4) {
          // Moving left
          player_direction[a] = 0x20;
          POKE(0xF7F8U + a, 32 + 16 + player_animation_frame[a]); // colour sprite
          POKE(0xF7F8U + 4 + a, 32 + player_animation_frame[a]);  // outline sprite
          sprite_x = 8 + player_x[a] * 4;
          sprite_y = 43 + player_y[a] * 4;
        }
        if (b & 8) {
          // Moving right
          player_direction[a] = 0x00;
          POKE(0xF7F8U + a, 16 + player_animation_frame[a]);    // colour sprite
          POKE(0xF7F8U + 4 + a, 0 + player_animation_frame[a]); // outline sprite
          sprite_x = 21 + player_x[a] * 4;
          sprite_y = 43 + player_y[a] * 4;
        }
        if (b & 0xf) {
          POKE(0xD000U + a * 2, sprite_x & 0xff);
          POKE(0xD001U + a * 2, sprite_y);
          POKE(0xD008U + a * 2, sprite_x & 0xff);
          POKE(0xD009U + a * 2, sprite_y);
          if (sprite_x & 0x100)
            POKE(0xD010U, PEEK(0xD010U) | (0x11 << a));
          else
            POKE(0xD010U, PEEK(0xD010U) & (0xFF - (0x11 << a)));
        }
        else {
          // No movement, just switch to stationary unicorn pose
          POKE(0xF7F8U + a, player_direction[a] + 16 + player_animation_frame[a]); // colour sprite
          POKE(0xF7F8U + 4 + a, player_direction[a] + player_animation_frame[a]);  // outline sprite
        }

        if (player_fire_action_timeout[a])
          player_fire_action_timeout[a]--;

        // Leave unicorn rainbow trail behind us
        if (b & 0x10) {
          // XXX DEBUG firebutton makes us poop lots of magic things while held
          // player_poop_mask[a]=0; player_feature_timeouts[a]=16;

          // Pressing button let's us poop traps for the other players.
          // For now, just making them paint our colour.
          // We should limit how often this can be done.
          if (!player_fire_action_timeout[a]) {
            // Can only do every so often
            player_fire_action_timeout[a] = 60;
            // Drop a special that causes anyone who runs over it to paint in our colour
            // ... well, actually, to paint in whatever colour we are painting!  So it's
            // bad to hold the button down if you step on someone else's trap
            game_grid[player_x[a]][player_y[a]] = 0x10 + SPECIAL_GLOWWORM0 + player_paint_colour[a];
            // Update the on-screen display
            draw_pixel_char(player_x[a], player_y[a] >> 1, game_grid[player_x[a]][player_y[a] & 0xfe],
                game_grid[player_x[a]][player_y[a] | 0x01]);
          }
          else
            b &= 0x0f;
        }

        if (b & 0xf) {

          b = game_grid[player_x[a]][player_y[a]];

          if (b >= 0x10) {
            // There is something special here!
            // You get 10 points for each special, regardless of what it is
            player_tiles[a] += 10;

            // Consume the special
            game_grid[player_x[a]][player_y[a]] = 0;
            // Update the on-screen display
            draw_pixel_char(player_x[a], player_y[a] >> 1, game_grid[player_x[a]][player_y[a] & 0xfe],
                game_grid[player_x[a]][player_y[a] | 0x01]);

            // The special things are really quite random as to what they do, and whether
            // they are helpful or not

            // Flash border so we know magic has happened
            if (PEEK(0xD020U) != 0xe) // don't use colour 15 that we are cycling the brightness of
              POKE(0xD020U, (PEEK(0xD020U) + 1) & 0x0f);
            else
              POKE(0xD020U, 0);

            switch (b - 0x10) {
            case SPECIAL_SLOW:
              player_features[a] = 0; // back to normal speed
              break;
            case SPECIAL_FAST: // you go fast for a while
              player_features[a] = FEATURE_FAST;
              player_feature_timeouts[a] = 480;
              break;
            case SPECIAL_SUPERFAST: // you go super fast for a while
              player_features[a] = FEATURE_SUPERFAST;
              player_feature_timeouts[a] = 300;
              break;
            case SPECIAL_LONGERTAIL: // your rainbow trail is forced to be a bit shorter
              if (player_tail_max_lengths[a] < 0xf7)
                player_tail_max_lengths[a] += 8;
              break;
            case SPECIAL_DETACHTAIL: // your tail that is currently drawn stays for others to run over
              player_tail_length[a] = 0;
              player_tail_start[a] = 0;
              player_tail_end[a] = 0;
              break;
            case SPECIAL_GLOWWORM0: // you paint player 0's colour for a while
              POKE(0xD02BU + a, 2); // Make unicorn go the colour it is painting
              lfill(0x1F800U + ((a & 1) ? 22 * 80 : 0) + ((a & 2) ? 70 : 0), 2, 10);
              player_poop_mask[a] = 0xff; // and only draw in the other player's colour, instead of pooping lots
              player_paint_colour[a] = 0;
              player_feature_timeouts[a] = 300;
              break;
            case SPECIAL_GLOWWORM1: // you paint player 1's colour for a while
              POKE(0xD02BU + a, 5); // Make unicorn go the colour it is painting
              lfill(0x1F800U + ((a & 1) ? 22 * 80 : 0) + ((a & 2) ? 70 : 0), 5, 10);
              player_poop_mask[a] = 0xff; // and only draw in the other player's colour, instead of pooping lots
              player_paint_colour[a] = 1;
              player_feature_timeouts[a] = 300;
              break;
            case SPECIAL_GLOWWORM2: // you paint player 2's colour for a while
              POKE(0xD02BU + a, 6); // Make unicorn go the colour it is painting
              lfill(0x1F800U + ((a & 1) ? 22 * 80 : 0) + ((a & 2) ? 70 : 0), 6, 10);
              player_poop_mask[a] = 0xff; // and only draw in the other player's colour, instead of pooping lots
              player_paint_colour[a] = 2;
              player_feature_timeouts[a] = 300;
              break;
            case SPECIAL_GLOWWORM3: // you paint player 3's colour for a while
              POKE(0xD02BU + a, 7); // Make unicorn go the colour it is painting
              lfill(0x1F800U + ((a & 1) ? 22 * 80 : 0) + ((a & 2) ? 70 : 0), 7, 10);
              player_poop_mask[a] = 0xff; // and only draw in the other player's colour, instead of pooping lots
              player_paint_colour[a] = 3;
              player_feature_timeouts[a] = 300;
              break;
            case SPECIAL_RAINBOWPOOP:
              player_features[a] = FEATURE_RAINBOWPOOP;
              break;
            case SPECIAL_LESSMAGIC: // you poop stuff less often
              player_poop_mask[a] = 0x01 | (player_poop_mask[a] << 1);
              break;
            case SPECIAL_MOREMAGIC: // you poop stuff more often
              player_poop_mask[a] = (player_poop_mask[a] >> 1) | 0x03;
              break;
            case SPECIAL_MAGICSQUIRTS: // you poop only stuff for a while
              player_poop_mask[a] = 0;
              player_features[a] = FEATURE_SUPERFAST; // the squirts makes you go fast!
              player_feature_timeouts[a] = 60;
              break;
            }
          }
          else if (!(rand() & player_poop_mask[a])) {
            // Poop something special!
            b = rand() % SPECIAL_MAX;
            b += 0x10;
            game_grid[player_x[a]][player_y[a]] = b;
            // Update the on-screen display
            draw_pixel_char(player_x[a], player_y[a] >> 1, game_grid[player_x[a]][player_y[a] & 0xfe],
                game_grid[player_x[a]][player_y[a] | 0x01]);
          }
          else {
            // Leave trail as per normal
            if (player_paint_colour[a] == a) {
              // Only delete trails left for ourselves.  When painting for others it just helpss them until deleted
              player_tail_start[a]++;
              player_tail_history_x[a][player_tail_start[a]] = player_x[a];
              player_tail_history_y[a][player_tail_start[a]] = player_y[a];
              player_tail_length[a]++;
            }

            if (b != (player_paint_colour[a] + 1)) {
              // take over this tile

              // But first, take it away from the previous owner
              if (b && (b < 5))
                if (player_tiles[b - 1]) {
                  player_tiles[b - 1]--;
                  // and we get extra points when running over other people's tails
                  player_tiles[a]++;
                }

              // Update grid to show our ownership (or that of whoever's colour we are now drawing in)
              game_grid[player_x[a]][player_y[a]] = 1 + player_paint_colour[a];

              // Add to our score for the take over
              player_tiles[player_paint_colour[a]]++;

              // Update the on-screen display
              draw_pixel_char(player_x[a], player_y[a] >> 1, game_grid[player_x[a]][player_y[a] & 0xfe],
                  game_grid[player_x[a]][player_y[a] | 0x01]);
            }
          }
        }
      }
    }

    continue;
  }
}
