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

char *instruction_descriptions[256]={
"BRK",
"ORA ($nn,X)",
"CLE",
"SEE",
"TSB $nn",
"ORA $nn",
"ASL $nn",
"RMB0 $nn",
"PHP",
"ORA #$nn",
"ASL A",
"TSY",
"TSB $nnnn",
"ORA $nnnn",
"ASL $nnnn",
"BBR0 $nn,$rr",
"BPL $rr",
"ORA ($nn),Y",
"ORA ($nn),Z",
"BPL $rrrr",
"TRB $nn",
"ORA $nn,X",
"ASL $nn,X",
"RMB1 $nn",
"CLC",
"ORA $nnnn,Y",
"INC",
"INZ",
"TRB $nnnn",
"ORA $nnnn,X",
"ASL $nnnn,X",
"BBR1 $nn,$rr",
"JSR $nnnn",
"AND ($nn,X)",
"JSR ($nnnn)",
"JSR ($nnnn,X)",
"BIT $nn",
"AND $nn",
"ROL $nn",
"RMB2 $nn",
"PLP",
"AND #$nn",
"ROL A",
"TYS",
"BIT $nnnn",
"AND $nnnn",
"ROL $nnnn",
"BBR2 $nn,$rr",
"BMI $rr",
"AND ($nn),Y",
"AND ($nn),Z",
"BMI $rrrr",
"BIT $nn,X",
"AND $nn,X",
"ROL $nn,X",
"RMB3 $nn",
"SEC",
"AND $nnnn,Y",
"DEC",
"DEZ",
"BIT $nnnn,X",
"AND $nnnn,X",
"ROL $nnnn,X",
"BBR3 $nn,$rr",
"RTI",
"EOR ($nn,X)",
"NEG",
"ASR",
"ASR $nn",
"EOR $nn",
"LSR $nn",
"RMB4 $nn",
"PHA",
"EOR #$nn",
"LSR A",
"TAZ",
"JMP $nnnn",
"EOR $nnnn",
"LSR $nnnn",
"BBR4 $nn,$rr",
"BVC $rr",
"EOR ($nn),Y",
"EOR ($nn),Z",
"BVC $rrrr",
"ASR $nn,X",
"EOR $nn,X",
"LSR $nn,X",
"RMB5 $nn",
"CLI",
"EOR $nnnn,Y",
"PHY",
"TAB",
"MAP",
"EOR $nnnn,X",
"LSR $nnnn,X",
"BBR5 $nn,$rr",
"RTS",
"ADC ($nn,X)",
"RTS #$nn",
"BSR $rrrr",
"STZ $nn",
"ADC $nn",
"ROR $nn",
"RMB6 $nn",
"PLA",
"ADC #$nn",
"ROR A",
"TZA",
"JMP ($nnnn)",
"ADC $nnnn",
"ROR $nnnn",
"BBR6 $nn,$rr",
"BVS $rr",
"ADC ($nn),Y",
"ADC ($nn),Z",
"BVS $rrrr",
"STZ $nn,X",
"ADC $nn,X",
"ROR $nn,X",
"RMB7 $nn",
"SEI",
"ADC $nnnn,Y",
"PLY",
"TBA",
"JMP ($nnnn,X)",
"ADC $nnnn,X",
"ROR $nnnn,X",
"BBR7 $nn,$rr",
"BRA $rr",
"STA ($nn,X)",
"STA ($nn,SP),Y",
"BRA $rrrr",
"STY $nn",
"STA $nn",
"STX $nn",
"SMB0 $nn",
"DEY",
"BIT #$nn",
"TXA",
"STY $nnnn,X",
"STY $nnnn",
"STA $nnnn",
"STX $nnnn",
"BBS0 $nn,$rr",
"BCC $rr",
"STA ($nn),Y",
"STA ($nn),Z",
"BCC $rrrr",
"STY $nn,X",
"STA $nn,X",
"STX $nn,Y",
"SMB1 $nn",
"TYA",
"STA $nnnn,Y",
"TXS",
"STX $nnnn,Y",
"STZ $nnnn",
"STA $nnnn,X",
"STZ $nnnn,X",
"BBS1 $nn,$rr",
"LDY #$nn",
"LDA ($nn,X)",
"LDX #$nn",
"LDZ #$nn",
"LDY $nn",
"LDA $nn",
"LDX $nn",
"SMB2 $nn",
"TAY",
"LDA #$nn",
"TAX",
"LDZ $nnnn",
"LDY $nnnn",
"LDA $nnnn",
"LDX $nnnn",
"BBS2 $nn,$rr",
"BCS $rr",
"LDA ($nn),Y",
"LDA ($nn),Z",
"BCS $rrrr",
"LDY $nn,X",
"LDA $nn,X",
"LDX $nn,Y",
"SMB3 $nn",
"CLV",
"LDA $nnnn,Y",
"TSX",
"LDZ $nnnn,X",
"LDY $nnnn,X",
"LDA $nnnn,X",
"LDX $nnnn,Y",
"BBS3 $nn,$rr",
"CPY #$nn",
"CMP ($nn,X)",
"CPZ #$nn",
"DEW $nn",
"CPY $nn",
"CMP $nn",
"DEC $nn",
"SMB4 $nn",
"INY",
"CMP #$nn",
"DEX",
"ASW $nnnn",
"CPY $nnnn",
"CMP $nnnn",
"DEC $nnnn",
"BBS4 $nn,$rr",
"BNE $rr",
"CMP ($nn),Y",
"CMP ($nn),Z",
"BNE $rrrr",
"CPZ $nn",
"CMP $nn,X",
"DEC $nn,X",
"SMB5 $nn",
"CLD",
"CMP $nnnn,Y",
"PHX",
"PHZ",
"CPZ $nnnn",
"CMP $nnnn,X",
"DEC $nnnn,X",
"BBS5 $nn,$rr",
"CPX #$nn",
"SBC ($nn,X)",
"LDA ($nn,SP),Y",
"INW $nn",
"CPX $nn",
"SBC $nn",
"INC $nn",
"SMB6 $nn",
"INX",
"SBC #$nn",
"EOM",
"ROW $nnnn",
"CPX $nnnn",
"SBC $nnnn",
"INC $nnnn",
"BBS6 $nn,$rr",
"BEQ $rr",
"SBC ($nn),Y",
"SBC ($nn),Z",
"BEQ $rrrr",
"PHW #$nnnn",
"SBC $nn,X",
"INC $nn,X",
"SMB7 $nn",
"SED",
"SBC $nnnn,Y",
"PLX",
"PLZ",
"PHW $nnnn",
"SBC $nnnn,X",
"INC $nnnn,X",
"BBS7 $nn,$rr"
};

unsigned char opcode;

// Measured cycle counts. Values are 256ths of a cycle
unsigned short measured_cycles[256]={0xFFFF};

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

unsigned short addr;

unsigned char overhead=0;

// Where we build the instruction test routine
unsigned char offset=0;
unsigned char test_routine[256];

void indicate_display_mode(void)
{
  printf("%c%c%c",0x13,0x11,0x11);
  if (display_mode==0) printf("Showing cycles per instruction         ");
  if (display_mode==1) printf("Showing difference from expected cycles");
  
}

void update_selected_opcode(void)
{
  addr=0x0400 + 40 * 4 + selected_opcode + selected_opcode;
  POKE(addr,PEEK(addr)|0x80);
  POKE(addr+1,PEEK(addr+1)|0x80);
  
  printf("\023\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"); // home cursor + 20x down
  // blank row, and cursor back up onto it
  addr=0x0400 + 40 * 21;
  for(v=0;v<40;v++) POKE(addr+v,' ');
  // Display expected cycle count
  printf("                 %d cycles (6502 = %d)\n%c",
	 measured_cycles[selected_opcode]>>8,
	 expected_cycles_6502[selected_opcode]>>8,0x91);
  // print the opcode description, and cursor back up
  printf("$%02x %s\n",selected_opcode,instruction_descriptions[selected_opcode]);
}  
  
void main(void)
{
  printf("%c%c%cM.E.G.A. 6502 Performance Benchmark v0.1%c%c\n",0x93,0x05,0x12,0x92,0x9a);

  indicate_display_mode();
  
  while(1) {

    __asm__("jsr $ffe4");
    __asm__("sta %v",v);
    switch(v) {
    case ' ': display_mode^=1; indicate_display_mode(); break;
    case 0x11: case 0x91: case 0x1d: case 0x9d:
      addr=0x0400 + 40 * 4 + selected_opcode + selected_opcode;
      POKE(addr,PEEK(addr)&0x7f);
      POKE(addr+1,PEEK(addr+1)&0x7f);

      if (v==0x11) selected_opcode+=20;
      if (v==0x91) selected_opcode-=20;
      if (v==0x1d) selected_opcode+=1;
      if (v==0x9d) selected_opcode-=1;

      update_selected_opcode();
      
      break;
    }
    
    if (!opcode) screen_addr=0x0400 + 40 * 4;
    
    expected_cycles=expected_cycles_6502[opcode];

    // Use CIA timer b
    // Disable interrupts and blank screen during test to prevent messed up timing
    __asm__("sei");

    // For PHA/PHP we have to pop something from the stack after
    // For PLA/PLP we have to push something to the stack first
    // For JSR we have to pull 2 bytes from stack after
    // For RTS we have to first push a dummy return address to the stack
    // For branches we need to make the branch land on the next instruction
    // (we also have to set/clear the appropriate flags to either force the branch
    // taken or not, so that we can differentiate between the cycle timings for both)
    // For branches we also have to test page crossing versus non-page-crossing timing.
    // We just don't test BRK or JAM instructions.
    // For ,X and ,Y indexed modes, we need to test page crossing versus non-crossing.
    // XXX - Maybe add keyboard options to toggle between taken/not taken and
    // page-crossing versus non-page-crossing, and have four sets of the expected
    // cycle counts.

    POKE(0xDC0FU,0x08); // one-shot, don't start, count cpu clock
    POKE(0xDC07U,0x00); POKE(0xDC06U,0xFF);   // set counter to 255

    // Now build the routine to call
    offset=0;

    // ---------  Setup instructions
    // ---------  Start timer
    // LDA #$11
    test_routine[offset++]=0xA9; test_routine[offset++]=0x11;
    // STA $DC0F
    test_routine[offset++]=0x8D; test_routine[offset++]=0x0F; test_routine[offset++]=0xDC;
    // ---------  Instruction goes here

    // ---------  Stop the timer
    // LDA #$08
    test_routine[offset++]=0xA9; test_routine[offset++]=0x08;
    // STA $DC0F
    test_routine[offset++]=0x8D; test_routine[offset++]=0x0F; test_routine[offset++]=0xDC;
    // ---------  Fixup instructions
    // ---------  Return from routine
    test_routine[offset++]=0x60; // RTS
    
    
    // Make sure we aren't on a badline
    while(PEEK(0xD012)&7) continue;

    // Do dry-run without instruction to calculate overhead
    // (we do this each time, since someone might change the CPU speed
    // while it is running);
    POKE(0xDC0FU,0x11); // load timer, start counter
    POKE(0xDC0FU,0x08); // stop counter again
    overhead=0xff-PEEK(0xDC06U);

    // Call the routine
    __asm__("jsr %v",test_routine);
    
    // Now get cycle count
    actual_cycles=0xff-PEEK(0xDC06U);
    actual_cycles-=overhead; // subtract overhead
    if (actual_cycles>99) actual_cycles=99;
    // Scale it up
    actual_cycles=actual_cycles<<8;
    measured_cycles[opcode]=actual_cycles;

    __asm__("cli");

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
      update_selected_opcode();
    }

    // Advance to the next opcode
    opcode++;
    screen_addr+=2;
    
  }
}

