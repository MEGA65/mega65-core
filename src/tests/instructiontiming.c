/*
  Program to report on the cycle counts for all 6502 opcodes.

  In comparison with SynthMark64, which uses a small number of
  repeated routines (some with different argument addresses in
  each repetition), we here instead time individual instructions
  executing by using a CIA timer, and comparing the remaining
  counter value after executing the instruction.

  At least that is the simple explanation, and largely applies for
  benchmarking on a stock C64.  To more accurately appraise the 
  speed of the MEGA65 or other accelerated machines, we need to
  run each instruction some number of times, to ensure that there
  is time for the timer to decrement by the minimum detectable
  amount.

*/

  
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define POKE(a,v) *((uint8_t *)a)=(uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))

unsigned char opcode;

// Measured cycle counts. Values are 256ths of a cycle
unsigned short cycle_counts[256]={0xFFFF};

// Should be a table of cycle counts of the various
// instructions
unsigned short expected_cycles_6502[256]={0x0000};

// Address on screen of next opcode speed
unsigned short screen_addr;

unsigned char display_mode = 0;

unsigned short expected_cycles;
unsigned short actual_cycles;
char v;
short display_value;
unsigned char colour;

unsigned char selected_opcode=0;

void indicate_display_mode(void)
{
  printf("%c%c%c",0x13,0x11,0x11);
  if (display_mode==0) printf("Showing cycles per instruction         ");
  if (display_mode==9) printf("Showing difference from expected cycles");
  
}

void main(void)
{
  printf("%c%c%cM.E.G.A. 6502 Performance Benchmark v0.1%c%c\n",0x93,0x05,0x12,0x92,0x9a);

  indicate_display_mode();
  
  while(1) {
    if (!opcode) screen_addr=0x0400 + 40 * 4;
    
    expected_cycles=expected_cycles_6502[opcode];
    actual_cycles=0;

    // Update colour
    if (expected_cycles<actual_cycles) colour=8; // orange for slow instructions
    if (expected_cycles>actual_cycles) colour=5; // green for fast instructions
    if (expected_cycles==actual_cycles) colour=14; // light blue for normal speed

    POKE(0xD800U-0x0400U+screen_addr,colour);
    POKE(0xD800U-0x0400U+1+screen_addr,colour);

    // Draw 2-character speed report
    if (display_mode==0) display_value=actual_cycles;
    if (display_mode==1) display_value=actual_cycles-expected_cycles;
    if (display_value<0) {
      // Display negative variance as -<digit> for upto -9.
      // worse than -9 is displayed as -!
      display_value=-display_value;
      POKE(screen_addr+0,'-');
      v=display_value>>8;
      if (v>9)
	{ v='!'; }
      else {
	v+='0';
      }
      POKE(screen_addr+1,v);      
    } else if (display_value==0) {
      POKE(screen_addr+0,' ');
      if (display_mode==0) {
	POKE(screen_addr+1,'0');
      } else {
	POKE(screen_addr+1,'=');
      }
    } else {
      // display_value >0
      if (display_mode==1) {
	POKE(screen_addr+0,'+');
	v=display_value>>8;
	if (v>9) { v='!'; }
	else v+='0';
	POKE(screen_addr+1,v);
      } else {
	// Display exact cycle count
	// fractional cycle counts show as .<digit>
	if (display_value<0x0100) {
	  // <1cycle
	  // Rescale 0-256 to 0-1, but using integer math.
	  // This ends up close enough
	  v=display_value/25;
	  if (v>9) v=9;
	  v+='0';
	  POKE(screen_addr+0,'.');
	  POKE(screen_addr+1,v);
	} else {
	  // at least 1 cycle
	  v=(display_value>>8)/10;
	  if (v>0) POKE(screen_addr+0,v+'0');
	  else POKE(screen_addr+0,' ');
	  v=(display_value>>8)%10;
	  POKE(screen_addr+1,v+'0');
	}
      }
    }

    // Highlight currently selected result for more details
    if (selected_opcode==opcode) {
      POKE(screen_addr+0,PEEK(screen_addr+0)|0x80);
      POKE(screen_addr+1,PEEK(screen_addr+1)|0x80);

      //Draw info about this opcode further down on the screen
      
    }

    // Advance to the next opcode
    opcode++;
    screen_addr+=2;
    
  }
}
