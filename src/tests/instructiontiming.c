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

int speed;
int fractional_speed;

// Measured cycle counts. Values are 256ths of a cycle
unsigned short measured_cycles[256]={0xFFFF};

// Should be a table of cycle counts of the various
// instructions
unsigned short expected_cycles_6502[256]={
  // 6502 timings from  "Graham's table" (Oxyron)
  0x700,0x600,0x000,0x800,0x300,0x300,0x500,0x500,0x300,0x200,0x200,0x200,0x400,0x400,0x600,0x600,
  0x200,0x500,0x000,0x800,0x400,0x400,0x600,0x600,0x200,0x400,0x200,0x700,0x400,0x400,0x700,0x700,
  0x600,0x600,0x000,0x800,0x300,0x300,0x500,0x500,0x400,0x200,0x200,0x200,0x400,0x400,0x600,0x600,
  0x200,0x500,0x000,0x800,0x400,0x400,0x600,0x600,0x200,0x400,0x200,0x700,0x400,0x400,0x700,0x700,
  0x600,0x600,0x000,0x800,0x300,0x300,0x500,0x500,0x300,0x200,0x200,0x200,0x300,0x400,0x600,0x600,
  0x200,0x500,0x000,0x800,0x400,0x400,0x600,0x600,0x200,0x400,0x200,0x700,0x400,0x400,0x700,0x700,
  0x600,0x600,0x000,0x800,0x300,0x300,0x500,0x500,0x400,0x200,0x200,0x200,0x500,0x400,0x600,0x600,
  0x200,0x500,0x000,0x800,0x400,0x400,0x600,0x600,0x200,0x400,0x200,0x700,0x400,0x400,0x700,0x700,
  0x200,0x600,0x200,0x600,0x300,0x300,0x300,0x300,0x200,0x200,0x200,0x200,0x400,0x400,0x400,0x400,
  0x200,0x600,0x000,0x600,0x400,0x400,0x400,0x400,0x200,0x500,0x200,0x500,0x500,0x500,0x500,0x500,
  0x200,0x600,0x200,0x600,0x300,0x300,0x300,0x300,0x200,0x200,0x200,0x200,0x400,0x400,0x400,0x400,
  0x200,0x500,0x000,0x500,0x400,0x400,0x400,0x400,0x200,0x400,0x200,0x400,0x400,0x400,0x400,0x400,
  0x200,0x600,0x200,0x800,0x300,0x300,0x500,0x500,0x200,0x200,0x200,0x200,0x400,0x400,0x600,0x600,
  0x200,0x500,0x000,0x800,0x400,0x400,0x600,0x600,0x200,0x400,0x200,0x700,0x400,0x400,0x700,0x700,
  0x200,0x600,0x200,0x800,0x300,0x300,0x500,0x500,0x200,0x200,0x200,0x200,0x400,0x400,0x600,0x600,
  0x200,0x500,0x000,0x800,0x400,0x400,0x600,0x600,0x200,0x400,0x200,0x700,0x400,0x400,0x700,0x700
};

#define FREQ_FLAT 0
#define FREQ_BASIC 1
#define FREQ_BOULDERDASH 2
#define FREQ_BITCOIN64 3
#define FREQ_MAX 4
char *freq_descriptions[FREQ_MAX]={"FLAT      ","C64 BASIC ","BLDERDASH ","BITCOIN64"};
unsigned char instruction_frequencies[FREQ_MAX][256]={
  // FREQ_FLAT
  {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
   1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
  // FREQ_BASIC
 {1,1,1,1,1,1,20,1,13,11,4,1,1,6,1,1,
159,1,1,1,1,1,5,1,23,1,1,1,1,1,1,1,
70,1,1,1,6,1,58,1,13,27,20,1,1,1,1,1,
25,1,1,1,1,1,1,1,19,1,1,1,1,1,1,1,
1,1,1,1,1,3,1,1,25,7,42,1,24,1,1,1,
1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,
70,1,1,1,1,14,12,1,25,23,7,1,5,1,1,1,
1,1,1,1,1,1,32,1,1,25,1,1,1,1,1,1,
1,1,1,1,20,132,17,1,130,1,8,1,1,8,1,1,
47,255,1,1,9,27,1,1,15,1,1,1,1,1,1,1,
15,1,22,1,19,115,19,1,19,28,11,1,1,17,2,1,
135,253,1,1,8,32,1,1,1,1,1,1,1,8,1,1,
42,1,1,1,7,12,2,1,59,39,73,1,1,6,1,1,
139,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
7,1,1,1,2,25,9,1,15,13,1,1,1,1,1,1,
  55,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
  // FREQ_BOULDERDASH
 {1,1,1,1,1,1,1,1,1,1,29,1,1,1,1,1,
12,1,1,1,1,1,1,1,11,1,1,1,1,1,1,1,
11,1,1,1,1,1,1,1,1,3,1,1,1,1,1,1,
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
1,1,1,1,1,1,1,1,1,1,1,1,4,1,1,1,
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
11,1,1,1,1,1,1,1,2,16,1,1,4,1,1,1,
1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
1,1,1,1,1,16,1,1,14,1,3,1,1,6,1,1,
2,1,1,1,1,1,1,1,1,7,1,1,1,135,1,1,
71,1,17,1,1,53,1,1,1,6,62,1,1,2,1,1,
1,73,1,1,1,1,1,1,1,1,1,1,1,201,1,1,
3,1,1,1,1,1,1,1,3,50,154,1,1,1,1,1,
255,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,
6,1,1,1,1,1,60,1,7,1,1,1,1,1,1,1,
  71,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
  // Bitcoin64
  {1,1,1,1,1,1,1,1,1,1,49,1,1,1,1,1,
1,29,1,1,1,1,1,1,52,1,1,1,1,1,1,1,
158,1,1,1,1,1,109,1,1,1,1,1,1,1,1,1,
1,47,1,1,1,1,1,1,43,1,1,1,1,1,1,1,
1,1,1,1,1,1,27,1,71,3,1,1,36,1,1,1,
1,30,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
158,1,1,1,1,34,55,1,71,19,27,1,1,1,1,1,
1,30,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
1,1,1,1,18,255,66,1,134,1,91,1,15,8,7,1,
69,148,1,1,1,1,1,1,43,1,1,1,1,1,1,1,
94,1,17,1,21,217,36,1,9,7,63,1,1,81,34,1,
9,43,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
1,1,1,1,1,1,1,1,141,1,27,1,1,1,1,1,
30,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
1,1,1,1,1,3,2,1,1,41,1,1,1,1,1,1,
4,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1}

};

unsigned long this_cycles;
unsigned long total_cycles;
unsigned long expected_total_cycles;
  
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
unsigned short offset=0;
// unsigned char test_routine[256];
unsigned char *test_routine=(unsigned char *)0xc000U;

unsigned char rts_lo_offset,rts_hi_offset;

char *mode;

unsigned char legal_and_runnable_6502_opcode(unsigned char op)
{
  switch(op&0xf) {
    // First deal with the columns that are all illegal
  case 0x3: case 0x7: case 0xb: case 0xf: return 0;
    // Then with the columns that are all legal
  case 0x1: case 0x5: case 0x6: case 0x8: case 0xd: return 1;
    // Now in order:
  case 0x0:
    // Column zero has BRK $00 and illegal on $80
    if (op&0x70) return 1; else return 0;
  case 0x2: if (op==0xa2) return 1; else return 0;
  case 0x4:
    switch(op) {
    case 0x24: case 0x84: case 0x94: case 0xa4: case 0xb4: case 0xc4: case 0xe4: return 1;
    default: return 0;
    }
  case 0x9:
    if (op==0x89) return 0; else return 1;
  case 0xa:
    if (!(op&0x10)) return 1;
    if (op==0x9a||op==0xba) return 1;
    return 0;
  case 0xc:
    if (op&0xf0) {
      if (!(op&0x10)) return 1;
      if (op==0xBC) return 1;
    }
    return 0;
  case 0xe:
    if (op==0x9e) return 0; else return 1;
  }
   printf("Uncaught opcode $%02x\n",op);
  while(1) continue;
}

void indicate_display_mode(void)
{
  printf("%c%c%c",0x13,0x11,0x11);
  if (display_mode==0) printf("Showing cycles per instruction         ");
  if (display_mode==1) printf("Showing difference from expected cycles");
  
}

unsigned short byte_to_percent(unsigned char v)
{
  if (v<250) return (v*4)/10; else return 99;
}

unsigned short measured;

void update_selected_opcode(void)
{
  addr=0x0400 + 40 * 4 + selected_opcode + selected_opcode;
  POKE(addr,PEEK(addr)|0x80);
  POKE(addr+1,PEEK(addr+1)|0x80);
  
  printf("\023\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"); // home cursor + 17x down
  // blank row, and cursor back up onto it
  addr=0x0400 + 40 * 17;
  for(v=0;v<40;v++) POKE(addr+v,' ');
  // Display expected cycle count
  measured=measured_cycles[selected_opcode]>>8;
  if (measured>9)
    printf("                 %4d cycles (6502 = %d)\n%c",
	   measured,
	   expected_cycles_6502[selected_opcode]>>8,0x91);
  else {
    printf("                 %1d.%02d cycles (6502 = %d)\n%c",
	   measured_cycles[selected_opcode]>>8,
	   byte_to_percent(measured_cycles[selected_opcode]&0xff),
	   expected_cycles_6502[selected_opcode]>>8,0x91);
  }
  // print the opcode description, and cursor back up
  printf("$%02x %s\n",selected_opcode,instruction_descriptions[selected_opcode]);
}  

unsigned char *freqs;
void update_speed_estimates(void)
{
  printf("\023\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"); // home cursor + 19x down
  for(v=0;v<FREQ_MAX;v++) printf("%s",freq_descriptions[v]);
  if (v%4) printf("\n");

  addr=0x0400 + 40 * 19;
  for(v=0;v<40;v++) POKE(addr+v,' ');

  for(v=0;v<FREQ_MAX;v++) {
    printf(" .....    %c%c%c%c%c%c%c%c%c",0x9d,0x9d,0x9d,0x9d,0x9d,0x9d,0x9d,0x9d,0x9d);
    total_cycles=0L;
    expected_total_cycles=0L;
    opcode=0;
    freqs=instruction_frequencies[v];
    __asm__("cld");
    do {
	if (legal_and_runnable_6502_opcode(opcode)) {
	  this_cycles=((long)*freqs)* ((long)measured_cycles[opcode]);
	  total_cycles+=this_cycles;
	  expected_total_cycles+=((long)*freqs)*(long)expected_cycles_6502[opcode];
	  freqs++;
	}
    } while(++opcode);

    // Calculate speed
    if (total_cycles)
      speed=((long)expected_total_cycles*(long)100L)/(long)total_cycles;
    else
      speed=9999;
    if (speed>9999) speed=9999;
    fractional_speed=speed%100;
    speed=speed/100;
    printf("%2d.%02dx    ",speed,fractional_speed);
    // printf("%08lx ",total_cycles);

  }
}

unsigned char single_run_opcode;
unsigned char byte_count;
unsigned char instruction_offset;

void main(void)
{
  printf("%c%c%cM.E.G.A. 6502 Performance Benchmark v0.1%c%c\n",0x93,0x05,0x12,0x92,0x9a);

  indicate_display_mode();

  // No sprites to mess up timing
  POKE(0xd015U,0);
  
  // Catch BRK instructions to aid debugging
  POKE(0xcf00U,0xee);
  POKE(0xcf01U,0x20);
  POKE(0xcf02U,0xd0);
  POKE(0xcf03U,0x4c);
  POKE(0xcf04U,0x00);
  POKE(0xcf05U,0xc8);
  POKE(0x316U,0x00);
  POKE(0x317U,0xcf);
  POKE(0x318U,0x00);
  POKE(0x319U,0xcf);
  
  while(1) {

    //    POKE(0x0400U,opcode);
    
    v=0;
    //    while(!v) {
      __asm__("jsr $ffe4");
      __asm__("sta %v",v);
      //    }
    //    selected_opcode=opcode;
    switch(v) {
    case ' ': display_mode^=1; indicate_display_mode(); break;
    case 'p':
      POKE(0xD02FU,0x47); POKE(0xD02FU,0x53); POKE(0xD06FU,0); POKE(0xD02FU,0);
      break;
    case 'n':
      POKE(0xD02FU,0x47); POKE(0xD02FU,0x53); POKE(0xD06FU,0x80); POKE(0xD02FU,0);
      break;
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

    v= legal_and_runnable_6502_opcode(opcode);

    if (v) {

      // Instructions that touch the stack cannot be run 256x
      // (except PLA, since the stack will end up back where it was)
      // (in theory, PLP as well, except CPU might end up with interrupts
      // enabled for a short while)
      // (except it sometimes crashes if either PLA or PLP is used here, presumably
      // because some interrupt happens)
      single_run_opcode=0;
      switch(opcode) {
      case 0x40: // RTI
      case 0x60: // RTS
      case 0x20: case 0x22: // JSR
      case 0x28: // PLP
      case 0x08: // PHP
      case 0x48: // PHA
      case 0x6c: // JMP ($nnnn) since we would need 256 pointers
      case 0x68: // PLA
	single_run_opcode=1;
      }
      
      // Mark instruction black while running test
      POKE(0xD800U-0x0400U+screen_addr,0);
      POKE(0xD800U-0x0400U+1+screen_addr,0);
      
      // Use CIA timer b
      // Disable interrupts and blank screen during test to prevent messed up timing
      // Disable CIA interrupt before SEI so that any pending IRQ gets handled
      POKE(0xdc0d,0x7f);
      v=PEEK(0xdc0d);      
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
      POKE(0xDC07U,0xFF); POKE(0xDC06U,0xFF);   // set counter to 65535
      
      // Now build the routine to call
      offset=0;

      
      // ---------  Setup instructions go here
      if (!strcmp(instruction_descriptions[opcode],"RTS")) {
	// Push two bytes to the stack for return address
	// (the actual return address will be re-written later
	test_routine[offset++]=0xA9; // LDA #$nn
	rts_hi_offset=offset++;
	test_routine[offset++]=0x48; // PHA
	test_routine[offset++]=0xA9; // LDA #$nn
	rts_lo_offset=offset++;
	test_routine[offset++]=0x48; // PHA
      }
      if (!strcmp(instruction_descriptions[opcode],"RTI")) {
	test_routine[offset++]=0xA9; // LDA #$nn
	rts_hi_offset=offset++;
	test_routine[offset++]=0x48; // PHA
	test_routine[offset++]=0xA9; // LDA #$nn
	rts_lo_offset=offset++;
	test_routine[offset++]=0x48; // PHA
	test_routine[offset++]=0x08; // PHP
      }      

      
      test_routine[offset++]=0xA2; test_routine[offset++]=0x00;  // LDX #$00
      test_routine[offset++]=0xA0; test_routine[offset++]=0x00;  // LDY #$00
      if ((instruction_descriptions[opcode][0]=='P')&&(instruction_descriptions[opcode][1]=='L')) {
	// Push something safe on the stack for pull instructions to yank
	test_routine[offset++]=0x08; // PHP
      }
      if (opcode==0x9A) // TXS
	test_routine[offset++]=0xBA; // TSX, so SP stays same

      // ---------  Start timer and make sure branches are not taken
      // LDA #$11
      test_routine[offset++]=0xA9; test_routine[offset++]=0x11;
      switch(opcode) {
      case 0x10:
	// BPL set N via CMP #$90 
	test_routine[offset++]=0xC9; test_routine[offset++]=0x90;
	break;
      case 0x30:
	// BMI -- nothing to do as N cleared by LDA #$11
	break;
      case 0x50:
	// BVC -- set V flag via LDA #$80 + CLC + ADC #$91
	test_routine[offset-1]=0x80;
	test_routine[offset++]=0x18;
	test_routine[offset++]=0x69; test_routine[offset++]=0x91;
	break;
      case 0x70:
	// BVS -- clear V flag via CLV
	test_routine[offset++]=0xb8;
	break;
      case 0x90:
	// BCC -- set carry flag via SEC
	test_routine[offset++]=0x38;
	break;
      case 0xb0:
	// BCS -- clear carry flag via CLC
	test_routine[offset++]=0x18;
	break;
      case 0xd0:
	// BNE so clear Z via CMP #$11
	test_routine[offset++]=0xC9; test_routine[offset++]=0x11;
	break;
      }
      
      // STA $DC0F
      test_routine[offset++]=0x8D; test_routine[offset++]=0x0F; test_routine[offset++]=0xDC;
      // ---------  Instruction goes here
      instruction_offset=offset;
      test_routine[offset++]=opcode;
      // Now work out the arguments to go with instruction
      mode=&instruction_descriptions[opcode][3];
      if (!mode[0]) {
	// Implied mode instruction -- nothing to do
	// XXX - Note that CLI can get executed, so there is a small risk of the CLI
	// instruction then getting billed for the cost of an entire interrupt!
      } else if (!strcmp(mode," A")) {
	// Accumulator mode -- so no args
      } else if ((!strcmp(mode," $nn"))
	  ||(!strcmp(mode," $nn,X"))
	  ||(!strcmp(mode," $nn,Y"))) {
	  // ZP
	  test_routine[offset++]=0xFD;
      } else if (!strcmp(mode," #$nn")) {
	// Immediate mode
	test_routine[offset++]=0xFD;
      } else if ((!strcmp(mode," ($nnnn)"))
		 ||(!strcmp(mode," ($nnnn,X)"))) {
	// Absolute indirect -- only exists for JMP and JSR
	// so point to an address that will jump to next instruction
	// We use the variable addr to fulfill this role
	test_routine[offset++]=((unsigned short)&addr)&0xff;
	test_routine[offset++]=((unsigned short)&addr)>>8;
	// Set destination of jump/jsr to the following instruction
	addr=(unsigned short)&test_routine[offset];
      } else if ((!strcmp(mode," $nnnn"))
		 ||(!strcmp(mode," $nnnn,X"))
		 ||(!strcmp(mode," $nnnn,Y"))) {
	// Absolute.  It could be a load, a store or a JMP/JSR
	// For JMP/JSR, we need to give it the address of the following
	// instruction. That would also be fine for loads, but not RMWs
	// or stores.  So we will instead use somewhere else for everything
	// that is not a JMP or JSR
	if (instruction_descriptions[opcode][0]=='J') {
	  addr=(unsigned short)&test_routine[offset+2];
	  test_routine[offset++]=addr&0xff;
	  test_routine[offset++]=addr>>8;
	} else {
	  test_routine[offset++]=((unsigned short)&addr)&0xff;
	  test_routine[offset++]=((unsigned short)&addr)>>8;
	}
      } else if (!strcmp(mode," $rr")) {
	// Branch instruction.
	// So provide argument that causes branch to continue to next instruction
	test_routine[offset++]=0x00;
      } else if ((!strcmp(mode," ($nn,X)"))
		 ||(!strcmp(mode," ($nn),Y"))) {
	// ZP indirect.
	// Write a valid pointer to ZP and use that
	test_routine[offset++]=0xFD;
	POKE(0xFDU,((unsigned short)&addr)&0xFF);
	POKE(0xFEU,((unsigned short)&addr)>>8);
      } else {
	printf("Unhandled addressing mode '%s'\n",mode);
	while(1) continue;
      }

      if (!single_run_opcode) {
	// Repeat instruction 256x
	v=1;
	byte_count=offset-instruction_offset;
	do {
	  test_routine[offset++]=test_routine[instruction_offset];
	  if (opcode==0x4c) {
	    // JMP $nnnn -- so point to next address
	    addr=0xc000 + offset+2;
	    test_routine[offset++]=addr&0xff;
	    test_routine[offset++]=addr>>8;
	  } else {
	    if (byte_count>1) test_routine[offset++]=test_routine[instruction_offset+1];
	    if (byte_count>2) test_routine[offset++]=test_routine[instruction_offset+2];
	  }
	} while(++v);
      }
      
      
      // If instruction was RTS or RTI, rewrite the pushed PC to correctly point here
      if (!strcmp(instruction_descriptions[opcode],"RTS")) {
	addr=(unsigned short)(&test_routine[offset-1]);
	test_routine[rts_lo_offset]=addr&0xff;
	test_routine[rts_hi_offset]=addr>>8;
      }
      if (!strcmp(instruction_descriptions[opcode],"RTI")) {
	addr=(unsigned short)(&test_routine[offset]);
	test_routine[rts_lo_offset]=addr&0xff;
	test_routine[rts_hi_offset]=addr>>8;
      }

      // ---------  Stop the timer
      // LDA #$08
      test_routine[offset++]=0xA9; test_routine[offset++]=0x08;
      // STA $DC0F
      test_routine[offset++]=0x8D; test_routine[offset++]=0x0F; test_routine[offset++]=0xDC;
      // ---------  Fixup instructions go here
      test_routine[offset++]=0xD8; // CLD
      if ((instruction_descriptions[opcode][0]=='P')&&(instruction_descriptions[opcode][1]=='H')) {
	// Remove whatever push instruction put on the stack
	test_routine[offset++]=0x68; // PLA
      }
      
      // ---------  Return from routine
      test_routine[offset++]=0x60; // RTS
      
      
      // Make sure we aren't on a badline
      while((PEEK(0xD012)&7)!=1) continue;
      
      // Do dry-run without instruction to calculate overhead
      // (we do this each time, since someone might change the CPU speed
      // while it is running);
      // Run 16 times and average overhead, so that we can get more reliable
      // results on fast CPUs
      overhead=0;
      for(v=0;v<64;v++) {
	POKE(0xDC0FU,0x11); // load timer, start counter
	POKE(0xDC0FU,0x08); // stop counter again
	overhead=0xff-PEEK(0xDC06U);
      }
      //      overhead=overhead>>6;

      // Make sure a bad line isn't due for a long time
      // the job can finish in time, without badline interference
      while(!(PEEK(0xD011)&0x80)) continue;

      POKE(0xd020U,1);

      // Call the routine
      __asm__("jsr $c000");

      POKE(0xd020U,14);

      // Now get cycle count
      actual_cycles=PEEK(0xDC06U)+((PEEK(0xDC07U)<<8U));
      actual_cycles=0xffff-actual_cycles;
      actual_cycles-=overhead; // subtract overhead
      if (actual_cycles>0x6300) actual_cycles=0x6300;  // max 99 cycles per instruction

      // For single run opcodes, our inner loop tests it only once,
      // so to smooth things out, we should run it some number of times
      if (single_run_opcode) {
	total_cycles=actual_cycles;

	v=1;
	do {

	  POKE(0xDC0FU,0x08); // one-shot, don't start, count cpu clock
	  POKE(0xDC07U,0xFF); POKE(0xDC06U,0xFF);   // set counter to 65535

	  // Make sure a bad line isn't due for a long time
	  // the job can finish in time, without badline interference
	  while(!(PEEK(0xD011)&0x80)) continue;
	  
	  POKE(0xd020U,2);
	  
	  // Call the routine
	  __asm__("jsr $c000");
	  
	  POKE(0xd020U,14);
	  
	  // Now get cycle count
	  actual_cycles=PEEK(0xDC06U)+((PEEK(0xDC07U)<<8U));
	  actual_cycles=0xffff-actual_cycles;
	  actual_cycles-=overhead; // subtract overhead
	  if (actual_cycles>0x6300) actual_cycles=0x6300;  // max 99 cycles per instruction

	  total_cycles += actual_cycles;
	  
	} while(++v);

	actual_cycles = total_cycles;
      }
	
      measured_cycles[opcode]= actual_cycles;

      POKE(0xdc0d,0x81);
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

    if (!opcode) update_speed_estimates();
        
  }
}

