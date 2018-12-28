/*
  Simple "colour in the screen in your colour" game as
  demo of C65.

*/

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define POKE(a,v) *((uint8_t *)a)=(uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))

void main(void)
{
  // Enable C65 VIC-III IO registers
  POKE(0xD02FU,0xA5);
  POKE(0xD02FU,0x96);
  
  // Put screen at $8000
  // Will be 2K for 80x25 text mode
  POKE(0xDD00U,0x01);
  POKE(0xD018U,0x05);

  // 80 column text mode, 3.5MHz CPU
  POKE(0xD031U,0xE0);
  
  POKE(0x8000U,1);
  
  while(1) continue;
}
