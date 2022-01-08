#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <stdlib.h>

int do_screen_shot_ascii(FILE *f);
int do_screen_shot(char *filename);

#define MEM_WRITE16(CPU,ADDR,VALUE) if (write_mem28(CPU,addr_to_28bit(CPU,ADDR,1),VALUE)) { fprintf(stderr,"ERROR: Memory write failed to %s.\n",describe_address(addr_to_28bit(CPU,ADDR,1))); return -1; }
#define MEM_WRITE28(CPU,ADDR,VALUE) if (write_mem28(CPU,ADDR,VALUE)) { fprintf(stderr,"ERROR: Memory write failed to %s.\n",describe_address(ADDR)); return -1; }

struct regs {
  unsigned int pc;
  unsigned char a;
  unsigned char x;
  unsigned char y;
  unsigned char z;
  unsigned char flags;
  unsigned char b;
  unsigned char sph;
  unsigned char spl;
  unsigned char in_hyper;
  unsigned char map_irq_inhibit;
  unsigned short maplo,maphi;
  unsigned char maplomb,maphimb;
  
};

struct termination_conditions {
  // Indicates that execution has terminated
  int done;

  // Indicates that an error was detected
  int error;
  
  // Terminate when number of RTS (minus JSRs) is encountered
  int rts;

  // Terminated on BRK
  int brk;

  // Log DMA requests
  int log_dma;
  
};


struct cpu {
  unsigned int instruction_count;
  struct regs regs;
  struct termination_conditions term;
  unsigned char stack_overflow;
  unsigned char stack_underflow;
};

#define FLAG_N 0x80
#define FLAG_V 0x40
#define FLAG_E 0x20
#define FLAG_D 0x08
#define FLAG_I 0x04
#define FLAG_Z 0x02
#define FLAG_C 0x01


// By default we log to stderr
FILE *logfile=NULL;
char logfilename[8192]="";
#define TESTLOGFILE "/tmp/hyppotest.tmp"

int log_on_failure=0;
int test_passes=0;
int test_fails=0;
char test_name[1024]="unnamed test";
char safe_name[1024]="unnamed_test";

unsigned char breakpoints[65536];

#define COLOURRAM_SIZE (32*1024)
#define CHIPRAM_SIZE (384*1024)
#define HYPPORAM_SIZE (16*1024)

// Current memory state
unsigned char chipram[CHIPRAM_SIZE];
unsigned char hypporam[HYPPORAM_SIZE];
unsigned char colourram[COLOURRAM_SIZE];
unsigned char ffdram[65536];

// Expected memory state 
unsigned char chipram_expected[CHIPRAM_SIZE];
unsigned char hypporam_expected[HYPPORAM_SIZE];
unsigned char colourram_expected[COLOURRAM_SIZE];
unsigned char ffdram_expected[65536];


// Instructions which modified the memory location last
unsigned int chipram_blame[CHIPRAM_SIZE];
unsigned int hypporam_blame[HYPPORAM_SIZE];
unsigned int colourram_blame[COLOURRAM_SIZE];
unsigned int ffdram_blame[65536];

#define MAX_HYPPO_SYMBOLS HYPPORAM_SIZE
typedef struct hyppo_symbol {
  char *name;
  unsigned int addr;
} hyppo_symbol;
hyppo_symbol hyppo_symbols[MAX_HYPPO_SYMBOLS];
int hyppo_symbol_count=0;  

#define MAX_SYMBOLS CHIPRAM_SIZE
hyppo_symbol symbols[MAX_SYMBOLS];
int symbol_count=0;  

hyppo_symbol *sym_by_addr[CHIPRAM_SIZE]={NULL};


struct cpu cpu;
struct cpu cpu_expected;

// Instruction log
typedef struct instruction_log {
  unsigned int pc;
  unsigned char bytes[6];
  unsigned char len;
  unsigned char dup;
  unsigned char zp16;
  unsigned char zp32;
  unsigned int zp_pointer;
  unsigned int zp_pointer_addr;
  struct regs regs;
  unsigned int count;

#define MAX_POPS 4
  unsigned char pops;
  unsigned int pop_blame[MAX_POPS];
} instruction_log;
#define MAX_LOG_LENGTH (16*1024*1024)
instruction_log *cpulog[MAX_LOG_LENGTH];
int cpulog_len=0;

#define INFINITE_LOOP_THRESHOLD 65536

instruction_log *lastataddr[65536]={NULL};

char *describe_address(unsigned int addr);
char *describe_address_label(struct cpu *cpu,unsigned int addr);
char *describe_address_label28(struct cpu *cpu,unsigned int addr);
unsigned int addr_to_28bit(struct cpu *cpu,unsigned int addr,int writeP);
void disassemble_instruction(FILE *f,struct instruction_log *log);
int write_mem28(struct cpu *cpu, unsigned int addr,unsigned char value);
unsigned int memory_blame(struct cpu *cpu,unsigned int addr16);

int rel8_delta(unsigned char c)
{
  if (c<0x80) return c;
  return c-0x100;
}

int rel16_delta(unsigned char c)
{
  if (c<0x8000) return c;
  return c-0x10000;
}

void disassemble_rel8(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%04X",log->pc+2+rel8_delta(log->bytes[1]));
}

void disassemble_rel16(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%04X",log->pc+2+rel16_delta(log->bytes[1]+(log->bytes[1]<<8)));
}

void disassemble_imm(FILE *f,struct instruction_log *log)
{
  fprintf(f,"#$%02X",log->bytes[1]);
}

void disassemble_abs(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X",log->bytes[2],log->bytes[1]);
}

void disassemble_absz(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X,Z",log->bytes[2],log->bytes[1]);
}

void disassemble_iabs(FILE *f,struct instruction_log *log)
{
  struct cpu fakecpu;

  bzero(&fakecpu,sizeof(fakecpu));
  fakecpu.regs=log->regs;
  
  fprintf(f,"($%02X%02X) {PTR=$%04X,ADDR=$%04X",log->bytes[2],log->bytes[1],
	  log->zp_pointer,log->zp_pointer_addr);
  fprintf(f,", Pointer written by ");
  // XXX Need regs from cpulog[], not current CPU mapping state
  // XXX Actually, we need to keep track of $00 and $01 andd $D031 in cpu->regs as well, so that we can examine
  // historical memory mappings.
  if (memory_blame(&fakecpu,log->zp_pointer+0)) {
    fprintf(f,"I%d: ",memory_blame(&fakecpu,log->zp_pointer+0));
    disassemble_instruction(f,cpulog[memory_blame(&fakecpu,log->zp_pointer+0)]);
  }
  else fprintf(f,"<uninitialised memory>");
  fprintf(f," and ");
  if (memory_blame(&fakecpu,log->zp_pointer+1)) {
    fprintf(f,"I%d: ",memory_blame(&fakecpu,log->zp_pointer+1));
    disassemble_instruction(f,cpulog[memory_blame(&fakecpu,log->zp_pointer+1)]);
  }
  else fprintf(f,"<uninitialised memory>");
  fprintf(f,"}");
  
}

void disassemble_iabsx(FILE *f,struct instruction_log *log)
{
  fprintf(f,"($%02X%02X,X)",log->bytes[2],log->bytes[1]);
}


void disassemble_absx(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X,X",log->bytes[2],log->bytes[1]);
}

void disassemble_absy(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X,Y",log->bytes[2],log->bytes[1]);
}

void disassemble_zp(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X",log->bytes[1]);
}

void disassemble_zpx(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X,X",log->bytes[1]);
}

void disassemble_zpy(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X,Y",log->bytes[1]);
}

void disassemble_izpy(FILE *f,struct instruction_log *log)
{
  fprintf(f,"($%02X),Y {PTR=$%04X,ADDR16=$%04X}",log->bytes[1],
	  log->zp_pointer,log->zp_pointer_addr);
}

void disassemble_izpx(FILE *f,struct instruction_log *log)
{
  fprintf(f,"($%02X,X) {PTR=$%04X,ADDR16=$%04X}",log->bytes[1],
	  log->zp_pointer,log->zp_pointer_addr);
}


void disassemble_izpz(FILE *f,struct instruction_log *log)
{
  fprintf(f,"($%02X),Z {PTR=$%04X,ADDR16=$%04X}",log->bytes[1],
	  log->zp_pointer,log->zp_pointer_addr);
}

void disassemble_izpz32(FILE *f,struct instruction_log *log)
{
  fprintf(f,"[$%02X],Z {PTR=$%04X,ADDR32=$%07X}",log->bytes[1],
	  log->zp_pointer,log->zp_pointer_addr);
}

void disassemble_stack_source(FILE *f,struct instruction_log *log)
{
  fprintf(f," {Pushed by ");
  if (log->pop_blame[0]) {
    fprintf(f,"$%04X ",cpulog[log->pop_blame[0]]->pc);
    disassemble_instruction(f,cpulog[log->pop_blame[0]]);
  } else fprintf(f,"<unitialised stack location>");
}

void disassemble_instruction(FILE *f,struct instruction_log *log)
{
  
  if (!log->len) return;
  switch(log->bytes[0]) {
  case 0x00: fprintf(f,"BRK "); disassemble_imm(f,log); break;
  case 0x03: fprintf(f,"SEE"); break;
  case 0x05: fprintf(f,"ORA "); disassemble_zp(f,log); break;
  case 0x06: fprintf(f,"ASL "); disassemble_zp(f,log); break;
  case 0x08: fprintf(f,"PHP"); break;
  case 0x09: fprintf(f,"ORA "); disassemble_imm(f,log); break;
  case 0x0A: fprintf(f,"ASL A"); break;
  case 0x0c: fprintf(f,"TSB "); disassemble_abs(f,log); break;
  case 0x0d: fprintf(f,"ORA "); disassemble_abs(f,log); break;
  case 0x10: fprintf(f,"BPL "); disassemble_rel8(f,log); break;
  case 0x13: fprintf(f,"BPL "); disassemble_rel16(f,log); break;
  case 0x18: fprintf(f,"CLC"); break;
  case 0x1A: fprintf(f,"INC"); break;
  case 0x1B: fprintf(f,"INZ"); break;
  case 0x1c: fprintf(f,"TRB "); disassemble_abs(f,log); break;
  case 0x20: fprintf(f,"JSR "); disassemble_abs(f,log); break;
  case 0x22: fprintf(f,"JSR "); disassemble_iabs(f,log); break;
  case 0x26: fprintf(f,"ROL "); disassemble_zp(f,log); break;
  case 0x28: fprintf(f,"PLP"); disassemble_stack_source(f,log); break;
  case 0x29: fprintf(f,"AND "); disassemble_imm(f,log); break;
  case 0x2A: fprintf(f,"ROL A"); break;
  case 0x2B: fprintf(f,"TYS"); break;
  case 0x2C: fprintf(f,"BIT "); disassemble_abs(f,log); break;
  case 0x30: fprintf(f,"BMI "); disassemble_rel8(f,log); break;
  case 0x31: fprintf(f,"AND "); disassemble_izpy(f,log); break;
  case 0x33: fprintf(f,"BMI "); disassemble_rel16(f,log); break;
  case 0x38: fprintf(f,"SEC"); break;
  case 0x3A: fprintf(f,"DEC"); break;
  case 0x40: fprintf(f,"RTI"); break;
  case 0x46: fprintf(f,"LSR "); disassemble_zp(f,log); break;
  case 0x48: fprintf(f,"PHA"); break;
  case 0x49: fprintf(f,"EOR "); disassemble_imm(f,log); break;
  case 0x4B: fprintf(f,"TAZ"); break;
  case 0x4C: fprintf(f,"JMP "); disassemble_abs(f,log); break;
  case 0x58: fprintf(f,"CLI"); break;
  case 0x5a: fprintf(f,"PHY"); break;
  case 0x5b: fprintf(f,"TAB"); break;
  case 0x5c: fprintf(f,"MAP"); break;
  case 0x60:
    fprintf(f,"RTS {Address pushed by ");
    if (log->pop_blame[0]!=log->pop_blame[1]) {
      fprintf(f," two different instructions: ");
      if (log->pop_blame[0]) {
	fprintf(f,"$%04X ",cpulog[log->pop_blame[0]]->pc);
	disassemble_instruction(f,cpulog[log->pop_blame[0]]);
      } else fprintf(f,"<unitialised stack location>");
      fprintf(f," and ");
      if (log->pop_blame[1]) {
	fprintf(f,"$%04X ",cpulog[log->pop_blame[1]]->pc);
	disassemble_instruction(f,cpulog[log->pop_blame[1]]);
      } else fprintf(f,"<unitialised stack location>");      
    } else 
      if (log->pop_blame[0]) {
	fprintf(f,"$%04X ",cpulog[log->pop_blame[0]]->pc);
	disassemble_instruction(f,cpulog[log->pop_blame[0]]);
      } else fprintf(f,"<unitialised stack location>");
    fprintf(f,"}");
    break;
  case 0x65: fprintf(f,"ADC "); disassemble_zp(f,log); break;
  case 0x66: fprintf(f,"ROR "); disassemble_zp(f,log); break;
  case 0x68: fprintf(f,"PLA"); disassemble_stack_source(f,log); break;
  case 0x69: fprintf(f,"ADC "); disassemble_imm(f,log); break;
  case 0x6A: fprintf(f,"ROR A"); break;
  case 0x6B: fprintf(f,"TZA"); break;
  case 0x6C: fprintf(f,"JMP "); disassemble_iabs(f,log); break;
  case 0x6D: fprintf(f,"ADC "); disassemble_abs(f,log); break;
  case 0x72: fprintf(f,"ADC "); disassemble_izpz(f,log); break;
  case 0x78: fprintf(f,"SEI"); break;
  case 0x7A: fprintf(f,"PLY"); disassemble_stack_source(f,log); break;
  case 0x7B: fprintf(f,"TBA"); break;
  case 0x80: fprintf(f,"BRA "); disassemble_rel8(f,log); break;
  case 0x83: fprintf(f,"BRA "); disassemble_rel16(f,log); break;
  case 0x84: fprintf(f,"STY "); disassemble_zp(f,log); break;
  case 0x85: fprintf(f,"STA "); disassemble_zp(f,log); break;
  case 0x86: fprintf(f,"STX "); disassemble_zp(f,log); break;
  case 0x88: fprintf(f,"DEY"); break;
  case 0x89: fprintf(f,"BIT "); disassemble_imm(f,log); break;
  case 0x8A: fprintf(f,"TXA"); break;
  case 0x8c: fprintf(f,"STY "); disassemble_abs(f,log); break;
  case 0x8d: fprintf(f,"STA "); disassemble_abs(f,log); break;
  case 0x8e: fprintf(f,"STX "); disassemble_abs(f,log); break;
  case 0x90: fprintf(f,"BCC "); disassemble_rel8(f,log); break;
  case 0x91: fprintf(f,"STA "); disassemble_izpy(f,log); break;
  case 0x92: fprintf(f,"STA ");
    if (log->zp32) disassemble_izpz32(f,log);
    else disassemble_izpz(f,log);
    break;
  case 0x93: fprintf(f,"BCC "); disassemble_rel16(f,log); break;
  case 0x95: fprintf(f,"STA "); disassemble_zpx(f,log); break;
  case 0x98: fprintf(f,"TYA"); break;
  case 0x99: fprintf(f,"STA "); disassemble_absy(f,log); break;
  case 0x9A: fprintf(f,"TXS"); break;
  case 0x9C: fprintf(f,"STZ "); disassemble_abs(f,log); break;
  case 0x9d: fprintf(f,"STA "); disassemble_absx(f,log); break;
  case 0xa0: fprintf(f,"LDY "); disassemble_imm(f,log); break;
  case 0xa1: fprintf(f,"LDA "); disassemble_izpx(f,log); break;
  case 0xa2: fprintf(f,"LDX "); disassemble_imm(f,log); break;
  case 0xa3: fprintf(f,"LDZ "); disassemble_imm(f,log); break;
  case 0xa4: fprintf(f,"LDY "); disassemble_zp(f,log); break;
  case 0xa5: fprintf(f,"LDA "); disassemble_zp(f,log); break;
  case 0xa6: fprintf(f,"LDX "); disassemble_zp(f,log); break;
  case 0xA8: fprintf(f,"TAY"); break;
  case 0xa9: fprintf(f,"LDA "); disassemble_imm(f,log); break;
  case 0xAA: fprintf(f,"TAX"); break;
  case 0xac: fprintf(f,"LDY "); disassemble_abs(f,log); break;
  case 0xad: fprintf(f,"LDA "); disassemble_abs(f,log); break;
  case 0xae: fprintf(f,"LDX "); disassemble_abs(f,log); break;
  case 0xB0: fprintf(f,"BCS "); disassemble_rel8(f,log); break;
  case 0xB1: fprintf(f,"LDA "); disassemble_izpy(f,log); break;
  case 0xb5: fprintf(f,"LDA "); disassemble_zpx(f,log); break;
  case 0xb9: fprintf(f,"LDA "); disassemble_absy(f,log); break;
  case 0xba: fprintf(f,"TSX"); break;
  case 0xbd: fprintf(f,"LDA "); disassemble_absx(f,log); break;
  case 0xC0: fprintf(f,"CPY "); disassemble_imm(f,log); break;
  case 0xC5: fprintf(f,"CMP "); disassemble_zp(f,log); break;
  case 0xC6: fprintf(f,"DEC "); disassemble_zp(f,log); break;
  case 0xC8: fprintf(f,"INY"); break;
  case 0xC9: fprintf(f,"CMP "); disassemble_imm(f,log); break;
  case 0xCA: fprintf(f,"DEX"); break;
  case 0xCC: fprintf(f,"CPY "); disassemble_abs(f,log); break;
  case 0xCD: fprintf(f,"CMP "); disassemble_abs(f,log); break;
  case 0xce: fprintf(f,"DEC "); disassemble_abs(f,log); break;
  case 0xd0: fprintf(f,"BNE "); disassemble_rel8(f,log); break;
  case 0xD8: fprintf(f,"CLD"); break;
  case 0xDA: fprintf(f,"PHX"); break;
  case 0xDB: fprintf(f,"PHZ"); break;
  case 0xE0: fprintf(f,"CPX "); disassemble_imm(f,log); break;
  case 0xE5: fprintf(f,"SBC "); disassemble_zp(f,log); break;
  case 0xE6: fprintf(f,"INC "); disassemble_zp(f,log); break;
  case 0xE8: fprintf(f,"INX"); break;
  case 0xE9: fprintf(f,"SBC "); disassemble_imm(f,log); break;
  case 0xea: fprintf(f,"EOM"); break;
  case 0xEC: fprintf(f,"CPX "); disassemble_abs(f,log); break;
  case 0xED: fprintf(f,"SBC "); disassemble_abs(f,log); break;
  case 0xee: fprintf(f,"INC "); disassemble_abs(f,log); break;
  case 0xf0: fprintf(f,"BEQ "); disassemble_rel8(f,log); break;
  case 0xf3: fprintf(f,"BEQ "); disassemble_rel16(f,log); break;
  case 0xf6: fprintf(f,"INC "); disassemble_zpx(f,log); break;
  case 0xFA: fprintf(f,"PLX"); disassemble_stack_source(f,log); break;
  case 0xFB: fprintf(f,"PLZ"); disassemble_stack_source(f,log); break;
  }
  
}

int show_recent_instructions(FILE *f,char *title,
			     struct cpu *cpu,
			     int first_instruction, int count,
			     unsigned int highlight_address)
{
  int last_was_dup=0;
  fprintf(f,"INFO: %s\n",title);
  if (!first_instruction) {
    fprintf(f," --- No relevant instruction history available (location not written?) ---\n");
    return 0;
  }
  if (first_instruction<0) { count-=-first_instruction; first_instruction=0; }
  for(int i=first_instruction;count>0&&i<cpulog_len;count--,i++) {
    if (!i) { fprintf(f,"I0        -- Machine reset --\n"); continue; }
    if (cpulog[i]->dup&&(i>first_instruction)) {
      if (!last_was_dup) fprintf(f,"                 ... duplicated instructions omitted ...\n");
      last_was_dup=1;
    } else {
      last_was_dup=0;
      if (cpulog_len-i-1) fprintf(f,"I%-7d ",i);
      else fprintf(f,"     >>> ");
      if (cpulog[i]->count>1)
	fprintf(f,"$%04X x%-6d : ",cpulog[i]->pc,cpulog[i]->count);
      else
	fprintf(f,"$%04X         : ",cpulog[i]->pc);
      fprintf(f,"A:%02X ",cpulog[i]->regs.a);
      fprintf(f,"X:%02X ",cpulog[i]->regs.x);
      fprintf(f,"Y:%02X ",cpulog[i]->regs.y);
      fprintf(f,"Z:%02X ",cpulog[i]->regs.z);
      fprintf(f,"SP:%02X%02X ",cpulog[i]->regs.sph,cpulog[i]->regs.spl);
      fprintf(f,"B:%02X ",cpulog[i]->regs.b);
      fprintf(f,"M:%04x+%02x/%04x+%02x ",
	      cpulog[i]->regs.maplo,cpulog[i]->regs.maplomb,
	      cpulog[i]->regs.maphi,cpulog[i]->regs.maphimb);
      fprintf(f,"%c%c%c%c%c%c%c%c ",
	     cpulog[i]->regs.flags&FLAG_N?'N':'.',
	     cpulog[i]->regs.flags&FLAG_V?'V':'.',
	     cpulog[i]->regs.flags&FLAG_E?'E':'.',
	     cpulog[i]->regs.flags&0x10?'B':'.',
	     cpulog[i]->regs.flags&FLAG_D?'D':'.',
	     cpulog[i]->regs.flags&FLAG_I?'I':'.',
	     cpulog[i]->regs.flags&FLAG_Z?'Z':'.',
	     cpulog[i]->regs.flags&FLAG_C?'C':'.');
      fprintf(f," : ");

      fprintf(f,"%32s : ",describe_address_label28(cpu,addr_to_28bit(cpu,cpulog[i]->regs.pc,0)));

      for(int j=0;j<3;j++) {
	if (j<cpulog[i]->len) fprintf(f,"%02X ",cpulog[i]->bytes[j]);
	else fprintf(f,"   ");
      }
      fprintf(f," : ");
      // XXX - Show instruction disassembly
      disassemble_instruction(f,cpulog[i]);
      fprintf(f,"\n");
    }
  }

  return 0;
}

int identical_cpustates(struct instruction_log *a, struct instruction_log *b)
{
  unsigned int count=a->count;
  a->count=b->count; 
  int r=memcmp(a,b,sizeof(struct instruction_log));
  a->count=count;
  
  if (r) return 0; else return 1;
}

char addr_description[8192];
char *describe_address(unsigned int addr)
{
  struct hyppo_symbol *s=NULL;
  
  for(int i=0;i<hyppo_symbol_count;i++) {
    // Check for exact address match
    if (addr==hyppo_symbols[i].addr) s=&hyppo_symbols[i];
    // Check for best approximate match
    if (s&&s->addr<hyppo_symbols[i].addr&&addr>hyppo_symbols[i].addr)
      s=&hyppo_symbols[i];
  }
  
  if (s) {
    if (s->addr==addr)  snprintf(addr_description,8192,"$%04X (first instruction in %s)",addr,s->name);
    else  snprintf(addr_description,8192,"$%04X (at %s+%d)",addr,s->name,addr-s->addr);
  } else 
    snprintf(addr_description,8192,"$%04X",addr);
  return addr_description;
}

char *describe_address_label28(struct cpu *cpu,unsigned int addr)
{
  struct hyppo_symbol *s=NULL;
  int exact=0;

  for(int i=0;i<hyppo_symbol_count;i++) {
    // Check for exact address match
    //    fprintf(stderr,"$%07x vs $%04x (%s)\n",addr,hyppo_symbols[i].addr,hyppo_symbols[i].name);
    if (addr==(hyppo_symbols[i].addr+0xfff0000)) { s=&hyppo_symbols[i]; exact=1; }
    // Check for best approximate match
    if (s&&s->addr<hyppo_symbols[i].addr&&addr>(hyppo_symbols[i].addr+0xfff0000))
      s=&hyppo_symbols[i];
    if ((!s)&&addr>(hyppo_symbols[i].addr+0xfff0000))
      s=&hyppo_symbols[i];
  }

  int nonhyppo=0;
  if (!exact) {
    for(int i=0;i<symbol_count;i++) {
      // Check for exact address match
      //      fprintf(stderr,"$%07x vs $%07x (%s)\n",addr,symbols[i].addr,symbols[i].name);
      if (addr==(symbols[i].addr)) s=&hyppo_symbols[i];
      // Check for best approximate match
      int delta=0;
      if (s) delta=addr-s->addr; else delta=addr;
      if (!nonhyppo) delta-=0xfff0000;
      if (s&&s->addr<symbols[i].addr&&addr>(symbols[i].addr)
	  &&((addr-symbols[i].addr)<delta)) {
	//fprintf(stderr,"$%07x vs $%07x (%s) (delta=$%07x)\n",addr,symbols[i].addr,symbols[i].name,
	//		addr-symbols[i].addr);
	nonhyppo=1;
	s=&symbols[i];
      }
      if ((!s)&&addr>(symbols[i].addr)) {
	nonhyppo=1;
	s=&symbols[i];
      }
    }
  }

  
  if (s) {
    if (nonhyppo&&(s->addr+0xfff0000)==addr)  snprintf(addr_description,8192,"%s",s->name);
    if ((!nonhyppo)&&(s->addr)==addr)  snprintf(addr_description,8192,"%s",s->name);
    else {
      if (nonhyppo) {
	snprintf(addr_description,8192,"%s+%d",s->name,addr-s->addr);
	if (addr-s->addr>0xff) snprintf(addr_description,8192,"%s+$%x",s->name,addr-s->addr);
      } else {
	snprintf(addr_description,8192,"%s+%d",s->name,addr-s->addr-0xfff0000);
	if (addr-s->addr>0xff000ff) snprintf(addr_description,8192,"%s+$%x",s->name,addr-s->addr-0xfff0000);
      }
    }
  } else 
    addr_description[0]=0;


  
  return addr_description;
}

char *describe_address_label(struct cpu *cpu,unsigned int addr)
{
  return describe_address_label28(cpu,addr_to_28bit(cpu,addr,1));
}


void cpu_log_reset(void)
{
  for(int i=0;i<cpulog_len;i++) free(cpulog[i]);
  cpulog_len=1;
  cpulog[0]=NULL;
}

void cpu_stash_ram(void)
{
  // Remember the RAM contents before calling a routine
  bcopy(chipram_expected,chipram,CHIPRAM_SIZE);
  bcopy(hypporam_expected,hypporam,HYPPORAM_SIZE);
}

unsigned int addr_to_28bit(struct cpu *cpu,unsigned int addr,int writeP)
{
  // XXX -- Royally stupid banking emulation for now
  unsigned int addr_in=addr;

  if (addr>0xffff) {
    fprintf(logfile,"ERROR: Asked to map %s of non-16 bit address $%x\n",writeP?"write":"read",addr);
    show_recent_instructions(logfile,"Instructions leading up to the request",
			     cpu,cpulog_len-6,6,cpu->regs.pc);
    cpu->term.error=1;
    return -1;
  }
  int lnc=chipram[1]&7;
  lnc|=(~(chipram[0]))&7;
  unsigned int bank=addr>>12;
  unsigned int zone=addr>>13;
  if (bank>15) bank=0;
  if (zone>7) zone=0;
  if (bank==13) {
    switch(lnc) {
    case 0: case 4:
      // RAM -- no mapping required
      break;
    case 1: case 2: case 3:
      // CharROM
      if (!writeP) {
	addr&=0xfff;
	addr|=0x2d000;
      }
      break;
    case 5: case 6: case 7:
      // IO bank
      addr&=0xfff;
      addr|=0xffd3000;
      break;
    }
  }
  if (!writeP) {
    // C64 BASIC ROM
    if (bank==10||bank==11) {
      if (lnc==3||lnc==7) {
	addr&=0x1fff;
	addr|=0x2a000;
      }
    }
    // C64 KERNAL ROM
    if (bank==14||bank==15) {
      switch(lnc){
      case 2: case 3: case 6: case 7:
	addr&=0x1fff;
	addr|=0x2e000;
	break;
      }
    }
  }

  // $D031 banking takes priority over C64 banking

  // MAP takes priority over all else
  if (zone<4) {
    if ((cpu->regs.maplo>>(12+zone))&1) {
      // This 8KB area is mapped
      addr=addr_in;
      addr+=(cpu->regs.maplo&0xfff)<<8;
      addr+=cpu->regs.maplomb<<20;
    }
  } else if (zone>3) {
    if ((cpu->regs.maphi>>(12+zone-4))&1) {
      // This 8KB area is mapped
      addr=addr_in;
      addr+=(cpu->regs.maphi&0xfff)<<8;
      addr+=cpu->regs.maphimb<<20;
    }
  }

  //  fprintf(stderr,"NOTE: Address $%04x mapped to $%07x (lnc=%d)\n",addr_in,addr,lnc);
  //  fprintf(stderr,"      chipram[0]=$%02x, chipram[1]=$%02x\n",chipram[0],chipram[1]);
  
  return addr;
}

unsigned char read_memory28(struct cpu *cpu,unsigned int addr)
{
  if (addr>=0xfff8000&&addr<0xfffc000)
  {
    // Hypervisor sits at $FFF8000-$FFFBFFF
    return hypporam[addr-0xfff8000];
  } else if (addr<CHIPRAM_SIZE) {
    // Chipram at base of address space
    return chipram[addr];
  } else if (addr>=0xff80000&&addr<(0xff80000+COLOURRAM_SIZE)) {
    // $FF8xxxx = colour RAM
    return colourram[addr-0xff80000];
  } else if ((addr&0xfff0000)==0xffd0000) {
    // $FFDxxxx IO space
    return ffdram[addr-0xffd0000];
  }
  // Otherwise unmapped RAM
  return 0xbd;
}

unsigned char read_memory(struct cpu *cpu,unsigned int addr16)
{
  unsigned int addr=addr_to_28bit(cpu,addr16,0);

  return read_memory28(cpu,addr);
}

unsigned int memory_blame(struct cpu *cpu,unsigned int addr16)
{
  unsigned int addr=addr_to_28bit(cpu,addr16,0);
  if (addr>=0xfff8000&&addr<0xfffc000)
  {
    // Hypervisor sits at $FFF8000-$FFFBFFF
    return hypporam_blame[addr-0xfff8000];
  } else if (addr<CHIPRAM_SIZE) {
    // Chipram at base of address space
    return chipram_blame[addr];
  } else if (addr>=0xff80000&&addr<(0xff80000+COLOURRAM_SIZE)) {
    // $FF8xxxx = colour RAM
    return colourram_blame[addr-0xff80000];
  } else if ((addr&0xfff0000)==0xffd0000) {
    // $FFDxxxx IO space
    return ffdram_blame[addr-0xffd0000];
  }
  // Otherwise unmapped RAM, no one to blame
  return 0;
}

int do_dma(struct cpu *cpu,int eDMA,unsigned int addr)
{
  int f011b=0;
  int with_transparency=0;
  int floppy_mode=0;
  int floppy_ignore_ff=0;
  int spiral_mode=0;
  int spiral_len=0;
  int spiral_len_remaining=0;
  int src_mb=0;
  int dst_mb=0;
  int src_skip=0;
  int dst_skip=0;
  int transparent_value=0;
  int x8_offset=0;
  int y8_offset=0;
  int slope=0;
  int slope_overflow_toggle=0;
  int slope_fraction_start=0;
  int line_mode=0;
  int line_x_or_y=0;
  int line_slope_negative=0;
  int dma_count=0;
  int s_x8_offset=0;
  int s_y8_offset=0;
  int s_slope=0;
  int s_slope_overflow_toggle=0;
  int s_slope_fraction_start=0;
  int s_line_mode=0;
  int s_line_x_or_y=0;
  int s_line_slope_negative=0;

  int spiral_phase=0;
  
  if (cpu->term.log_dma) {
    fprintf(logfile,"NOTE: %sDMA dispatched with list address $%07x\n",
	    eDMA?"E":"",addr);
    fprintf(logfile,"      DMA addr regs contain $%02X $%02X $%02X $%02X $%02X $%02X\n",
	    ffdram[0x3700],ffdram[0x3701],ffdram[0x3702],ffdram[0x3703],ffdram[0x3704],ffdram[0x3705]);
    show_recent_instructions(logfile,"Instructions leading up to the DMA request", cpu,cpulog_len-32,32,cpu->regs.pc);
  }

  int more_jobs=1;
  
  while(more_jobs) {
    more_jobs=0;

    dma_count=0;

    src_skip=0x0100;
    dst_skip=0x0100;

    
    if (eDMA) {
      // Read DMA option bytes
      while(read_memory28(cpu,addr)) {
	int option=read_memory28(cpu,addr++);
	int arg=0;
	if (option&0x80) arg=read_memory28(cpu,addr++);      
	if (cpu->term.log_dma) fprintf(logfile,"INFO: DMA option $%02X $%02X\n",option,arg);
	switch(option) {
	case 0x06: with_transparency=0; break;
	case 0x07: with_transparency=0; break;
	case 0x0a: f011b=0; break;
	case 0x0b: f011b=1; break;
	case 0x0d: floppy_mode=1;  break;
	case 0x0e: floppy_mode=1; floppy_ignore_ff=1; break;
	case 0x0f: floppy_mode=1; floppy_ignore_ff=0; break;
	case 0x53: spiral_mode=1; spiral_len=39; spiral_len_remaining=38; break;
	case 0x80: src_mb=arg; break;
	case 0x81: dst_mb=arg; break;
	case 0x82: src_skip|=arg; break;
	case 0x83: src_skip|=arg<<8; break;
	case 0x84: dst_skip|=arg; break;
	case 0x85: dst_skip|=arg<<8; break;
	case 0x86: transparent_value=arg; break;
	case 0x87: x8_offset|=arg; break;
	case 0x88: x8_offset|=arg<<8; break;
	case 0x89: y8_offset|=arg; break;
	case 0x8a: y8_offset|=arg<<8; break;
	case 0x8b: slope|=arg; break;
	case 0x8c: slope|=arg<<8; break;
	case 0x8d: slope_fraction_start|=arg; break;
	case 0x8e: slope_fraction_start|=arg<<8; break;
	case 0x8f:
	  line_mode=arg&0x80;
	  line_x_or_y=arg&0x40;
	  line_slope_negative=arg&0x20;
	  break;
	case 0x90: dma_count|=arg<<16; break;
	case 0x97: s_x8_offset|=arg; break;
	case 0x98: s_x8_offset|=arg<<8; break;
	case 0x99: s_y8_offset|=arg; break;
	case 0x9a: s_y8_offset|=arg<<8; break;
	case 0x9b: s_slope|=arg; break;
	case 0x9c: s_slope|=arg<<8; break;
	case 0x9d: s_slope_fraction_start|=arg; break;
	case 0x9e: s_slope_fraction_start|=arg<<8; break;
	case 0x9f:
	  s_line_mode=arg&0x80;
	  s_line_x_or_y=arg&0x40;
	  s_line_slope_negative=arg&0x20;
	  break;
	default:
	  fprintf(logfile,"ERROR: Unknown DMA option $%02X used.\n",option);
	  cpu->term.error=1;
	  break;
	}
      }
      addr++; // skip final $00 option byte
      if (cpu->term.log_dma)
	fprintf(logfile,"INFO: End of DMA Options found. DMA list proper begins at $%07X (%s)\n",
		addr,describe_address_label28(cpu,addr));
    } else {
      if (cpu->term.log_dma)
	fprintf(logfile,"INFO: Non-enhanced DMA list proper begins at $%07X (%s)\n",
		addr,describe_address_label28(cpu,addr));
    }
    
    // Read DMA list bytes
    int dma_cmd=read_memory28(cpu,addr++);
    dma_count|=read_memory28(cpu,addr++);
    dma_count|=read_memory28(cpu,addr++)<<8;
    unsigned int dma_src=read_memory28(cpu,addr++);
    dma_src|=read_memory28(cpu,addr++)<<8;
    dma_src|=read_memory28(cpu,addr++)<<16;
    unsigned int dma_dst=read_memory28(cpu,addr++);
    dma_dst|=read_memory28(cpu,addr++)<<8;
    dma_dst|=read_memory28(cpu,addr++)<<16;
    if (f011b) dma_cmd|=read_memory28(cpu,addr++)<<8;
    unsigned int dma_modulo=read_memory28(cpu,addr++);
    dma_modulo|=read_memory28(cpu,addr++)<<8;
    
    int src_direction,src_hold,src_modulo;
    int dest_direction,dest_hold,dest_modulo;
    if (f011b) {
      src_direction=(dma_cmd>>4)&1;
      src_hold=(dma_cmd>>9)&1;
      src_modulo=(dma_cmd>>8)&1;
      dest_direction=(dma_cmd>>5)&1;
      dest_hold=(dma_cmd>>11)&1;
      dest_modulo=(dma_cmd>>10)&1;
    } else {
      src_direction=(dma_src>>22)&1;
      src_modulo=(dma_src>>21)&1;
      src_hold=(dma_src>>20)&1;
      dest_direction=(dma_dst>>22)&1;
      dest_modulo=(dma_dst>>21)&1;
      dest_hold=(dma_dst>>20)&1;
    }
    int src_io=dma_src&0x800000;
    int dest_io=dma_dst&0x800000;
    dma_src&=0xfffff;
    unsigned long long src_addr=(dma_src<<8)|(((unsigned long long)src_mb)<<28);
    dma_dst&=0xfffff;
    unsigned long long dest_addr=(dma_dst<<8)|(((unsigned long long)dst_mb)<<28);
    
    // Is it chained?
    more_jobs=dma_cmd&4;

    if (cpu->term.log_dma)
      fprintf(logfile,"INFO: DMA cmd=$%04X, src=$%07X, dst=$%07X, count=$%06X, modulo=$%04X\n",
	      dma_cmd,dma_src,dma_dst,dma_count,dma_modulo);

    if (!dma_count) dma_count=0x10000;

    switch(dma_cmd&3) {
    case 0:
      /* Copy operation: Clone symbols from source region to destination region. */
      {
	int symbols_copied=0;
	int pre_symbol_count=symbol_count; // don't duplicate duplicates!
	for(int i=0;i<pre_symbol_count;i++) {
	  if (symbols[i].addr>=(src_addr>>8)&&symbols[i].addr<((src_addr>>8)+dma_count)) {
	    /*	    fprintf(stderr,"NOTE: Copying symbol #%d '%s' from $%07X to $%07X due to DMA copy.\n",
		    i,symbols[i].name,
		    symbols[i].addr,
		    dest_addr + (symbols[i].addr-src_addr)); */
	    symbols_copied++;
	    
	    if (symbol_count>=MAX_SYMBOLS) {
	      fprintf(logfile,"ERROR: Too many symbols. Increase MAX_SYMBOLS.\n");
	      cpu->term.error=1;
	      cpu->term.done=1;
	      return -1;
	    }
	    symbols[symbol_count].name=symbols[i].name;
	    symbols[symbol_count].addr=(dest_addr>>8) + (symbols[i].addr-(src_addr>>8));
	    if (((dest_addr>>8) + (symbols[i].addr-(src_addr>>8)))<CHIPRAM_SIZE) {
	      sym_by_addr[(dest_addr>>8) + (symbols[i].addr-(src_addr>>8))]=&symbols[symbol_count];
	    }
	    symbol_count++;
	  }
	}
	if (symbols_copied)
	  fprintf(logfile,"NOTE: Duplicated %d symbols due to DMA copy from $%07llX-$%07llX to $%07llX-$%07llX.\n",
		  symbols_copied,src_addr>>8,(src_addr>>8)+dma_count-1,dest_addr>>8,(dest_addr>>8)+dma_count-1);
      }
      break;
    case 3:
      /* Fill operation: Erase symbols from destination region */
      {
	int symbols_erased=0;
	for(int i=0;i<symbol_count;i++) {
	  if (symbols[i].addr>=(dest_addr>>8)&&symbols[i].addr<((dest_addr>>8)+dma_count)) {
	    symbols_erased++;
	    symbols[i].addr=symbols[symbol_count-1].addr;
	    free(symbols[i].name);
	    symbols[i].name=symbols[symbol_count-1].name;
	    symbol_count--;
	  }
	}
	if (symbols_erased)
	  fprintf(logfile,"NOTE: Erased %d symbols due to DMA fill from $%07llX to $%07llX.\n",
		  symbols_erased,dest_addr>>8,(dest_addr>>8)+dma_count-1);
      }
      break;
    }

    
    
    while(dma_count--)
      {

	// Do operation before updating addresses
	switch (dma_cmd&3) {
	case 0: // copy
	  {
	    // XXX - Doesn't simulate the 4 cycle DMA pipeline
	    int value=read_memory28(cpu,src_addr>>8);
	    MEM_WRITE28(cpu,dest_addr>>8,value);
	    //	    fprintf(stderr,"DEBUG: Copying $%02X from $%07X to $%07X\n",value,src_addr>>8,dest_addr>>8);
	  }
	  break;
	case 3: // fill
	  MEM_WRITE28(cpu,dest_addr>>8,(src_addr>>8)&0xff);
	  break;
	default:
	  fprintf(logfile,"ERROR: Unsupported DMA operation %d requested.\n",
		  dma_cmd&3);
	  cpu->term.error=1;
	  cpu->term.done=1;
	  return 0;
	}
	
	
	// Update source address
	{
	  if (!s_line_mode) {
	    // Normal fill / copy
	    if (!src_hold) {
	      if (!src_direction) src_addr += src_skip;
	      else src_addr -= src_skip;
	    }
	  } else {
	    // We are in line mode.
	    
	    // Add fractional position
	    s_slope_fraction_start += s_slope;
	    // Check if we have accumulated a whole pixel of movement?
	    int line_x_move = 0;
	    int line_x_move_negative = 0;
	    int line_y_move = 0;
	    int line_y_move_negative = 0;
	    if (s_slope_overflow_toggle /= (s_slope_fraction_start&0x10000)) {
	      s_slope_overflow_toggle = (s_slope_fraction_start&0x10000);
	      // Yes: Advance in minor axis
	      if (!s_line_x_or_y) {
		line_y_move = 1;
		line_y_move_negative = s_line_slope_negative;
	      } else {
		line_x_move = 1;
		line_x_move_negative = s_line_slope_negative;
	      }
	    }
	    // Also move major axis (which is always in the forward direction)
	    if (!s_line_x_or_y) line_x_move = 1; else line_y_move=1;
	    if ((!line_x_move)&&line_y_move&&(!line_y_move_negative)) {
	      // Y = Y + 1
	      if (((src_addr>>11)&7)==7) {
		// Will overflow between Y cards
		src_addr |= (256*8) + (s_y8_offset<<8);
	      } else {
		// No overflow, so just add 8 bytes (with 8-bit pixel resolution)
		src_addr |= (256*8);
	      }
	    } else if ((!line_x_move)&&line_y_move&&line_y_move_negative) {
	      // Y = Y - 1
	      if (((src_addr>>11)&7)==0) {
		// Will overflow between X cards
		src_addr  -= (256*8) + (s_y8_offset<<8);
	      } else {
		// No overflow, so just subtract 8 bytes (with 8-bit pixel resolution)
		src_addr  -= (256*8);
	      }
	    } else if (line_x_move&&(!line_x_move_negative)&&(!line_y_move)) {
	      // X = X + 1
	      if (((src_addr>>8)&7)==7) {
		// Will overflow between X cards
		src_addr += 256 + (s_x8_offset<<8);
	      } else {
		// No overflow, so just add 1 pixel (with 8-bit pixel resolution)
		src_addr += 256;
	      }
	    } else if (line_x_move&&line_x_move_negative&&(!line_y_move)) {
	      // X = X - 1 
	      if (((src_addr>>8)&7)==0) {
		// Will overflow between X cards
		src_addr -= 256 + (s_x8_offset<<8);
	      } else {
		// No overflow, so just subtract 1 pixel (with 8-bit pixel resolution)
		src_addr -= 256;
	      }
	    } else if (line_x_move&&(!line_x_move_negative)&&line_y_move&&(!line_y_move_negative)) {
	      // X = X + 1, Y = Y + 1
	      if (((src_addr>>8)&0x3f)==0x3f) {
		// positive overflow on both
		src_addr  += (256*9) + (s_x8_offset<<8) + (s_y8_offset<<8);
	      } else if (((src_addr>>8)&0x3f)==0x38) {
		// positive card overflow on Y only
		src_addr  += (256*9) + (s_y8_offset<<8);
	      } else if (((src_addr>>8)&0x3f)==0x07) {
		// positive card overflow on X only
		src_addr  += (256*9) + (s_x8_offset<<8);
	      } else {
		// no card overflow
		src_addr  += (256*9);
	      } 
	    } else if (line_x_move&&(!line_x_move_negative)&&line_y_move&&line_y_move_negative) {
	      // X = X + 1, Y = Y - 1
	      if (((src_addr>>8)&0x3f)==0x07) {
		// positive card overflow on X, negative on Y 
		src_addr  += (256*1) - (256*8) + (s_x8_offset<<8) - (s_y8_offset<<8);
	      } else if (((src_addr>>8)&0x3f)<0x08) {
		// negative card overflow on Y only
		src_addr  += (256*1) - (256*8) - (s_y8_offset<<8);
	      } if (((src_addr>>8)&0x07)==0x07) {
		// positive overflow on X only
		src_addr  += (256*1) - (256*8) + (s_x8_offset<<8);
	      } else {
		src_addr  += (256*1) - (256*8);
	      }
	    } else if (line_x_move&&line_x_move_negative&&line_y_move&&(!line_y_move_negative)) {
	      // X = X - 1, Y = Y + 1
	      if (((src_addr>>8)&0x3f)==0x38) {
		// negative card overflow on X, positive on Y 
		src_addr  +=  - (256*1) + (256*8) - (s_x8_offset<<8) + (s_y8_offset<<8);
	      } else if (((src_addr>>11)&0x07)==0x07) {
		// positive card overflow on Y only
		src_addr  +=  - (256*1) + (256*8) + (s_y8_offset<<8);
	      } else if (((src_addr>>8)&7)==0) {
		// negative overflow on X only
		src_addr  +=  - (256*1) + (256*8) - (s_x8_offset<<8);
	      } else {
		src_addr  +=  - (256*1) + (256*8);
	      }
	    } else if (line_x_move&&line_x_move_negative&&line_y_move&&line_y_move_negative) {
	      // X = X - 1, Y = Y - 1
	      if (((src_addr>>8)&0x3f)==0x00) {
		// negative card overflow on X, negative on Y 
		src_addr  +=  - (256*1) - (256*8) - (s_x8_offset<<8) - (s_y8_offset<<8);
	      } else if (((src_addr>>11)&0x7)==0x00) { 
		// negative card overflow on Y only
		src_addr  +=  - (256*1) - (256*8) - (s_y8_offset<<8);
	      } else if (((src_addr>>8)&0x7)==0x00) {
		// negative overflow on X only
		src_addr  +=  - (256*1) - (256*8) - (s_x8_offset<<8);
	      } else {
		src_addr  +=  - (256*1) - (256*8);
	      }
	    }
	  }	
	}
	
	
	// Update destination address
	{
	  if (spiral_mode) {
	    // Draw the dreaded Shallan Spriral
	    switch(spiral_phase) {
	    case 0: dest_addr=dest_addr+0x100; break;
	    case 1: dest_addr=dest_addr+0x2800; break;
	    case 2: dest_addr=dest_addr-0x100; break;
	    case 3: dest_addr=dest_addr-0x2800; break;
	    }
	    if (spiral_len_remaining) spiral_len_remaining-=1;
	    else {
	      // Calculate details for next phase of the spiral
	      if (!(spiral_phase&1)) {
		// Next phase is vertical, so reduce spiral length by 40 - 24 = 17
		spiral_len_remaining = spiral_len - 16;
	      } else {
		spiral_len_remaining = spiral_len;
	      }
	      if (spiral_len) spiral_len--;
	    }
	    spiral_phase++; spiral_phase&=3;
	  } else if (!line_mode) {
	    // Normal fill / copy
	    if (!dest_hold) {
	      if (!dest_direction) dest_addr += dst_skip;
	      else dest_addr -= dst_skip;
	    }
	  } else {
	    // We are in line mode.
	    
	    // Add fractional position
	    slope_fraction_start += slope;
	    // Check if we have accumulated a whole pixel of movement?
	    int line_x_move = 0;
	    int line_x_move_negative = 0;
	    int line_y_move = 0;
	    int line_y_move_negative = 0;
	    if (slope_overflow_toggle /= (slope_fraction_start&0x10000)) {
	      slope_overflow_toggle = (slope_fraction_start&0x10000);
	      // Yes: Advance in minor axis
	      if (!line_x_or_y) {
		line_y_move = 1;
		line_y_move_negative = line_slope_negative;
	      } else {
		line_x_move = 1;
		line_x_move_negative = line_slope_negative;
	      }
	    }
	    // Also move major axis (which is always in the forward direction)
	    if (!line_x_or_y) line_x_move = 1; else line_y_move=1;
	    if ((!line_x_move)&&line_y_move&&(!line_y_move_negative)) {
	      // Y = Y + 1
	      if (((dest_addr>>11)&7)==7) {
		// Will overflow between Y cards
		dest_addr |= (256*8) + (y8_offset<<8);
	      } else {
		// No overflow, so just add 8 bytes (with 8-bit pixel resolution)
		dest_addr |= (256*8);
	      }
	    } else if ((!line_x_move)&&line_y_move&&line_y_move_negative) {
	      // Y = Y - 1
	      if (((dest_addr>>11)&7)==0) {
		// Will overflow between X cards
		dest_addr  -= (256*8) + (y8_offset<<8);
	      } else {
		// No overflow, so just subtract 8 bytes (with 8-bit pixel resolution)
		dest_addr  -= (256*8);
	      }
	    } else if (line_x_move&&(!line_x_move_negative)&&(!line_y_move)) {
	      // X = X + 1
	      if (((dest_addr>>8)&7)==7) {
		// Will overflow between X cards
		dest_addr += 256 + (x8_offset<<8);
	      } else {
		// No overflow, so just add 1 pixel (with 8-bit pixel resolution)
		dest_addr += 256;
	      }
	    } else if (line_x_move&&line_x_move_negative&&(!line_y_move)) {
	      // X = X - 1 
	      if (((dest_addr>>8)&7)==0) {
		// Will overflow between X cards
		dest_addr -= 256 + (x8_offset<<8);
	      } else {
		// No overflow, so just subtract 1 pixel (with 8-bit pixel resolution)
		dest_addr -= 256;
	      }
	    } else if (line_x_move&&(!line_x_move_negative)&&line_y_move&&(!line_y_move_negative)) {
	      // X = X + 1, Y = Y + 1
	      if (((dest_addr>>8)&0x3f)==0x3f) {
		// positive overflow on both
		dest_addr  += (256*9) + (x8_offset<<8) + (y8_offset<<8);
	      } else if (((dest_addr>>8)&0x3f)==0x38) {
		// positive card overflow on Y only
		dest_addr  += (256*9) + (y8_offset<<8);
	      } else if (((dest_addr>>8)&0x3f)==0x07) {
		// positive card overflow on X only
		dest_addr  += (256*9) + (x8_offset<<8);
	      } else {
		// no card overflow
		dest_addr  += (256*9);
	      } 
	    } else if (line_x_move&&(!line_x_move_negative)&&line_y_move&&line_y_move_negative) {
	      // X = X + 1, Y = Y - 1
	      if (((dest_addr>>8)&0x3f)==0x07) {
		// positive card overflow on X, negative on Y 
		dest_addr  += (256*1) - (256*8) + (x8_offset<<8) - (y8_offset<<8);
	      } else if (((dest_addr>>8)&0x3f)<0x08) {
		// negative card overflow on Y only
		dest_addr  += (256*1) - (256*8) - (y8_offset<<8);
	      } if (((dest_addr>>8)&0x07)==0x07) {
		// positive overflow on X only
		dest_addr  += (256*1) - (256*8) + (x8_offset<<8);
	      } else {
		dest_addr  += (256*1) - (256*8);
	      }
	    } else if (line_x_move&&line_x_move_negative&&line_y_move&&(!line_y_move_negative)) {
	      // X = X - 1, Y = Y + 1
	      if (((dest_addr>>8)&0x3f)==0x38) {
		// negative card overflow on X, positive on Y 
		dest_addr  +=  - (256*1) + (256*8) - (x8_offset<<8) + (y8_offset<<8);
	      } else if (((dest_addr>>11)&0x07)==0x07) {
		// positive card overflow on Y only
		dest_addr  +=  - (256*1) + (256*8) + (y8_offset<<8);
	      } else if (((dest_addr>>8)&7)==0) {
		// negative overflow on X only
		dest_addr  +=  - (256*1) + (256*8) - (x8_offset<<8);
	      } else {
		dest_addr  +=  - (256*1) + (256*8);
	      }
	    } else if (line_x_move&&line_x_move_negative&&line_y_move&&line_y_move_negative) {
	      // X = X - 1, Y = Y - 1
	      if (((dest_addr>>8)&0x3f)==0x00) {
		// negative card overflow on X, negative on Y 
		dest_addr  +=  - (256*1) - (256*8) - (x8_offset<<8) - (y8_offset<<8);
	      } else if (((dest_addr>>11)&0x7)==0x00) { 
		// negative card overflow on Y only
		dest_addr  +=  - (256*1) - (256*8) - (y8_offset<<8);
	      } else if (((dest_addr>>8)&0x7)==0x00) {
		// negative overflow on X only
		dest_addr  +=  - (256*1) - (256*8) - (x8_offset<<8);
	      } else {
		dest_addr  +=  - (256*1) - (256*8);
	      }
	    }
	  }	
	}
      }
  }
  return 0;
}

int write_mem28(struct cpu *cpu, unsigned int addr,unsigned char value)
{
  unsigned int dma_addr;
  
  if (addr>=0xfff8000&&addr<0xfffc000)
  {
    // Hypervisor sits at $FFF8000-$FFFBFFF
    hypporam_blame[addr-0xfff8000]=cpu->instruction_count;
    hypporam[addr-0xfff8000]=value;
  } else if (addr<CHIPRAM_SIZE) {
    // Chipram at base of address space
    if (addr==0&&value==0x41) {
      // Set fast CPU
    } else if (addr==0&&value==0x40) {
      // Clear fast CPU
    } else {
      chipram_blame[addr]=cpu->instruction_count;
      chipram[addr]=value;
    }
  } else if (addr>=0xff80000&&addr<(0xff80000+COLOURRAM_SIZE)) {
    colourram_blame[addr-0xff80000]=cpu->instruction_count;
    colourram[addr-0xff80000]=value;
  } else if ((addr&0xfff0000)==0xffd0000) {
    // $FFDxxxx IO space
    ffdram[addr-0xffd0000]=value;
    ffdram_blame[addr-0xffd0000]=cpu->instruction_count;
    
    // Now check for special address actions
    switch(addr) {
    case 0xffd3700: // Trigger DMA
      if (cpu->term.log_dma)
	fprintf(logfile,"NOTE: DMA triggered via write to $%07x at instruction #%d\n",
		addr,cpulog_len);
      ffdram[0x3705]=value;
      ffdram_blame[0x3705]=cpu->instruction_count;
      dma_addr=(ffdram[0x3700]+(ffdram[0x3701]<<8)+((ffdram[0x3702]&0x7f)<<16))|(ffdram[0x3704]<<20);
      do_dma(cpu,0,dma_addr);
      break;
    case 0xffd3702: // Set bits 22 to 16 of DMA address
      ffdram[0x3704]&=0xf1;
      ffdram[0x3704]|=(value>>4)&7;
      ffdram_blame[0x3704]=cpu->instruction_count;
      break;
    case 0xffd3705: // Trigger EDMA
      if (cpu->term.log_dma)
	fprintf(logfile,"NOTE: DMA triggered via write to $%07x at instruction #%d\n",
		addr,cpulog_len);
      ffdram[0x3700]=value;
      ffdram_blame[0x3700]=cpu->instruction_count;
      dma_addr=(ffdram[0x3700]+(ffdram[0x3701]<<8)+((ffdram[0x3702]&0x7f)<<16))|(ffdram[0x3704]<<20);
      do_dma(cpu,1,dma_addr);
      break;
    }
    if (!cpu->regs.in_hyper) {
      if (addr>=0xffd3640&&addr<=0xffd367f) {
	// Enter hypervisor
	fprintf(logfile,"NOTE: CPU Entered Hypervisor via write to $%07x at instruction #%d\n",
		addr,cpulog_len);
      }
    } else {
      if (addr==0xffd367f) {
	// Exit hypervisor
	fprintf(logfile,"NOTE: CPU Exited Hypervisor via write to $%07x at instruction #%d\n",
		addr,cpulog_len);
      }
    }
    
  } else {
  // Otherwise unmapped RAM
    fprintf(logfile,"ERROR: Writing to unmapped address $%07x\n",addr);
    show_recent_instructions(logfile,"Instructions leading up to the request", cpu,cpulog_len-6,6,cpu->regs.pc);
    cpu->term.error=1;
  }

  return 0;
}

int write_mem16(struct cpu *cpu, unsigned int addr16,unsigned char value)
{
  unsigned int addr=addr_to_28bit(cpu,addr16,1);
  return write_mem28(cpu,addr,value);
}

int write_mem_expected28(unsigned int addr,unsigned char value)
{
  if (addr>=0xfff8000&&addr<0xfffc000)
  {
    // Hypervisor sits at $FFF8000-$FFFBFFF
    hypporam_expected[addr-0xfff8000]=value;
    fprintf(logfile,"NOTE: Writing to hypervisor RAM @ $%07x\n",addr);
  } else if (addr<CHIPRAM_SIZE) {
    // Chipram at base of address space
    chipram_expected[addr]=value;
  } else if (addr>=0xff80000&&addr<(0xff80000+COLOURRAM_SIZE)) {
    colourram_expected[addr-0xff80000]=value;
  } else if ((addr&0xfff0000)==0xffd0000) {
    // $FFDxxxx IO space
    ffdram_expected[addr-0xffd0000]=value;
  } else {
  // Otherwise unmapped RAM
    fprintf(logfile,"ERROR: Writing to unmapped address $%07x\n",addr);
  }
  return 0;
}

unsigned int addr_abs(struct instruction_log *log)
{
  return log->bytes[1]+(log->bytes[2]<<8);
}

unsigned int addr_zp(struct cpu *cpu,struct instruction_log *log)
{
  return log->bytes[1]+(log->regs.b<<8);
}

unsigned int addr_zpx(struct cpu *cpu,struct instruction_log *log)
{
  return (log->bytes[1]+(log->regs.b<<8)+cpu->regs.x)&0xffff;
}

unsigned int addr_zpy(struct cpu *cpu,struct instruction_log *log)
{
  return (log->bytes[1]+(log->regs.b<<8)+cpu->regs.y)&0xffff;
}

unsigned int addr_izpy(struct cpu *cpu,struct instruction_log *log)
{
  log->zp_pointer=(log->bytes[1]+(log->regs.b<<8));
  log->zp_pointer_addr= (read_memory(cpu,log->zp_pointer+0)
			 +(read_memory(cpu,log->zp_pointer+1)<<8)
			 +cpu->regs.y)&0xffff;
  return log->zp_pointer_addr;
}

unsigned int addr_izpx(struct cpu *cpu,struct instruction_log *log)
{
  // Note that we allow the pointer to cross ZP boundary, i.e.,
  // "The ($xx,X) bug" is purposely not fixed in the MEGA65 for
  // backwards compatibility.
  log->zp_pointer=((log->bytes[1]+cpu->regs.x)&0xff)+(log->regs.b<<8);		   
  log->zp_pointer_addr= (read_memory(cpu,log->zp_pointer+0)
			 +(read_memory(cpu,log->zp_pointer+1)<<8)
			 )&0xffff;
  return log->zp_pointer_addr;
}

unsigned int addr_deref16(struct cpu *cpu,struct instruction_log *log)
{
  log->zp_pointer=(log->bytes[1]+(log->bytes[2]<<8));
  log->zp_pointer_addr= (read_memory(cpu,log->zp_pointer+0)
			 +(read_memory(cpu,log->zp_pointer+1)<<8)
			 )&0xffff;
  return log->zp_pointer_addr;
}

unsigned int addr_izpz(struct cpu *cpu,struct instruction_log *log)
{
  log->zp_pointer=(log->bytes[1]+(log->regs.b<<8));
  log->zp_pointer_addr= (read_memory(cpu,log->zp_pointer+0)
			 +(read_memory(cpu,log->zp_pointer+1)<<8)
			 +cpu->regs.z)&0xffff;
  return log->zp_pointer_addr;
}

unsigned int addr_izpz32(struct cpu *cpu,struct instruction_log *log)
{
  log->zp_pointer=(log->bytes[1]+(log->regs.b<<8));
  log->zp_pointer_addr= (read_memory(cpu,log->zp_pointer+0)
			 +(read_memory(cpu,log->zp_pointer+1)<<8)
			 +(read_memory(cpu,log->zp_pointer+2)<<16)
			 +(read_memory(cpu,log->zp_pointer+3)<<24)
			 +cpu->regs.z)&0xffff;
  return log->zp_pointer_addr;
}


unsigned int addr_absx(struct cpu *cpu,struct instruction_log *log)
{
  return (log->bytes[1]+(log->bytes[2]<<8)+cpu->regs.x)&0xffff;
}

unsigned int addr_absy(struct cpu *cpu,struct instruction_log *log)
{
  return (log->bytes[1]+(log->bytes[2]<<8)+cpu->regs.y)&0xffff;
}


void update_nz(unsigned char v)
{
  if (!v) { cpu.regs.flags|=FLAG_Z; }
  else cpu.regs.flags&=~FLAG_Z;
  cpu.regs.flags&=~FLAG_N;
  cpu.regs.flags|=v&FLAG_N;
  
}

void update_nvzc(int v)
{
  update_nz(v);
  cpu.regs.flags&=~(FLAG_C+FLAG_V);
  if (v>0xff) cpu.regs.flags|=FLAG_C;
  // XXX - Do V calculation as well
}


unsigned char stack_pop(struct cpu *cpu,struct instruction_log *log)
{
  int addr=(cpu->regs.sph<<8)+cpu->regs.spl;
  addr++;
  cpu->regs.spl++;
  unsigned char c=read_memory(cpu,addr);
  if (!(addr&0xff)) {
    if (!(cpu->regs.flags&FLAG_E))
      cpu->regs.sph++;
    else
      cpu->stack_underflow=1;
    if (!addr) cpu->stack_underflow=1;
  }
  log->pop_blame[log->pops++]=memory_blame(cpu,addr);
  return c;
}

int stack_push(struct cpu *cpu,unsigned char v)
{
  //  fprintf(logfile,"NOTE: Pushing $%02X onto the stack\n",v);
  int addr=(cpu->regs.sph<<8)+cpu->regs.spl;
  MEM_WRITE16(cpu,addr,v);
  cpu->regs.spl--;
  if ((addr&0xff)==0x00) {
    if (!(cpu->regs.flags&FLAG_E))
      cpu->regs.sph--;
    else
      cpu->stack_overflow=1;
    if (addr==0xffff) cpu->stack_overflow=1;
  }
  return 0;
}

int execute_instruction(struct cpu *cpu,struct instruction_log *log)
{
  int v;

  if (breakpoints[cpu->regs.pc]) {
    fprintf(logfile,"INFO: Breakpoint at %s ($%04X) triggered.\n",
	    describe_address_label(cpu,cpu->regs.pc),
	    cpu->regs.pc);
    cpu->term.done=1;
    return 0;
  }
  
  for(int i=0;i<6;i++) {
    log->bytes[i]=read_memory(cpu,cpu->regs.pc+i);
  }
  switch(log->bytes[0]) {
  case 0x00: // BRK
    log->len=2;
    cpu->term.error=1;
    cpu->term.brk=1;
    cpu->term.done=1;
    break;
  case 0x03: // SEE
    cpu->regs.flags|=FLAG_E;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x05: // ORA $xx
    log->len=2;
    cpu->regs.pc+=2;
    v=read_memory(cpu,addr_zp(cpu,log));
    cpu->regs.a|=v;
    update_nz(cpu->regs.a);
    break;
  case 0x06: // ASL $nn
    v=read_memory(cpu,addr_zp(cpu,log))<<1;
    if (cpu->regs.flags&FLAG_C) v|=0x1;
    v&=0xff;
    update_nz(v);
    MEM_WRITE16(cpu,addr_zp(cpu,log),v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x08: // PHP
    stack_push(cpu,cpu->regs.flags);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x09: // ORA #$nn
    cpu->regs.a|=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x0A: // ASL A
    v=cpu->regs.a<<1;
    if (cpu->regs.flags&FLAG_C) v|=0x1;
    v&=0xff;
    update_nz(v);
    cpu->regs.a=v;
    log->len=1;
    cpu->regs.pc+=1;
    break;
  case 0x0c: // TSB $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    v|=cpu->regs.a;
    MEM_WRITE16(cpu,addr_abs(log),v);
    update_nz(v);
    break;
  case 0x0d: // ORA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    cpu->regs.a|=v;
    update_nz(cpu->regs.a);
    break;
  case 0x10: // BPL $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_N)
      cpu->regs.pc+=2;
    else
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    break;
  case 0x13: // BPL $rrrr
    log->len=3;
    if (cpu->regs.flags&FLAG_N)
      cpu->regs.pc+=3;
    else
      cpu->regs.pc+=2+rel16_delta(log->bytes[1]);
    break;
  case 0x18: // CLC
    cpu->regs.flags&=~FLAG_C;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x1A: // INC A
    cpu->regs.a++;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x1B: // INZ
    cpu->regs.z++;
    update_nz(cpu->regs.z);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x1c: // TRB $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    v&=~cpu->regs.a;
    MEM_WRITE16(cpu,addr_abs(log),v);
    update_nz(v);
    break;
  case 0x20: // JSR $nnnn
    stack_push(cpu,(cpu->regs.pc+2)>>8);
    stack_push(cpu,cpu->regs.pc+2);
    cpu->regs.pc=addr_abs(log);
    log->len=3;
    break;
  case 0x22: // JSR ($nnnn)
    stack_push(cpu,(cpu->regs.pc+2)>>8);
    stack_push(cpu,cpu->regs.pc+2);
    cpu->regs.pc=addr_deref16(cpu,log);
    log->len=3;
    break;
  case 0x26: // ROL $nn
    v=read_memory(cpu,addr_zp(cpu,log))<<1;
    if (cpu->regs.flags&FLAG_C) v|=0x1;
    cpu->regs.flags&=~FLAG_C;
    if (v&0x100) cpu->regs.flags|=FLAG_C;
    v&=0xff;
    update_nz(v);
    MEM_WRITE16(cpu,addr_zp(cpu,log),v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x28: // PLP
    // E flag cannot be set via PLP
    cpu->regs.flags&=FLAG_E;
    cpu->regs.flags|=(stack_pop(cpu,log)&(~FLAG_E));
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x29: // AND #$nn
    cpu->regs.a&=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x2A: // ROL A
    v=cpu->regs.a<<1;
    if (cpu->regs.flags&FLAG_C) v|=0x1;
    cpu->regs.flags&=~FLAG_C;
    if (v&0x100) cpu->regs.flags|=FLAG_C;
    v&=0xff;
    update_nz(v);
    cpu->regs.a=v;
    log->len=1;
    cpu->regs.pc+=1;
    break;
  case 0x2b: // TYS
    cpu->regs.sph=cpu->regs.y;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x2C: // BIT $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    cpu->regs.flags&=~(FLAG_N|FLAG_V|FLAG_Z);
    cpu->regs.flags|=v&(FLAG_N|FLAG_V);
    v&=cpu->regs.a;
    if (!v) cpu->regs.flags|=FLAG_Z;
    break;
  case 0x30: // BMI $rr
    log->len=2;
    if (!(cpu->regs.flags&FLAG_N))
      cpu->regs.pc+=2;
    else
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    break;
  case 0x31: // AND ($nn),Y
    cpu->regs.a&=addr_izpy(cpu,log);
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x33: // BMI $rrrr
    log->len=3;
    if (!(cpu->regs.flags&FLAG_N))
      cpu->regs.pc+=3;
    else
      cpu->regs.pc+=2+rel16_delta(log->bytes[1]);
    break;
  case 0x38: // SEC
    cpu->regs.flags|=FLAG_C;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x3A: // DEC A
    cpu->regs.a--;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x46: // LSR $nn
    v=addr_zp(cpu,log);
    cpu->regs.flags&=~FLAG_C;
    if (v&1) cpu->regs.flags|=FLAG_C;
    v=v>>1;
    update_nz(v);
    MEM_WRITE16(cpu,addr_zp(cpu,log),v);    
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x48: // PHA
    stack_push(cpu,cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x49: // EOR #$nn
    cpu->regs.a^=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x4B: // TAZ
    cpu->regs.z=cpu->regs.a;
    update_nz(cpu->regs.z);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x4c: // JMP $nnnn
    cpu->regs.pc=addr_abs(log);
    log->len=3;
    break;
  case 0x58: // CLI
    cpu->regs.flags&=~FLAG_I;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x5A: // PHY
    stack_push(cpu,cpu->regs.y);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x5b: // TAB
    cpu->regs.b=cpu->regs.a;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x5c: // MAP
    cpu->regs.pc++;

    if (cpu->regs.x==0x0f) cpu->regs.maplomb=cpu->regs.a;
     else cpu->regs.maplo=cpu->regs.a+(cpu->regs.x<<8);
    if (!cpu->regs.in_hyper) {
      if (cpu->regs.z==0x0f) cpu->regs.maphimb=cpu->regs.y;
      else cpu->regs.maplo=cpu->regs.y+(cpu->regs.z<<8);
    }
    cpu->regs.map_irq_inhibit=1;
    log->len=1;
    break;
  case 0x60: // RTS
    log->len=1;
    if (cpu->term.rts) {
      cpu->term.rts--;
      if (!cpu->term.rts) {
	fprintf(logfile,"INFO: Terminating via RTS\n");
	cpu->term.done=1;
      }
    }
    cpu->regs.pc=stack_pop(cpu,log);
    cpu->regs.pc|=stack_pop(cpu,log)<<8;
    cpu->regs.pc++;
    break;
  case 0x65: // ADC $nn
    // XXX - Ignores decimal mode!
    v=cpu->regs.a+addr_zp(cpu,log);
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    cpu->regs.a=v;
    cpu->regs.a&=0xff;
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x66: // ROR $nn
    v=addr_zp(cpu,log);
    if (cpu->regs.flags&FLAG_C) v|=0x100;
    cpu->regs.flags&=~FLAG_C;
    if (v&1) cpu->regs.flags|=FLAG_C;
    v=v>>1;
    update_nz(v);
    MEM_WRITE16(cpu,addr_zp(cpu,log),v);    
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x68: // PLA
    // XXX -- Not implemented
    cpu->regs.pc++;
    log->len=1;
    cpu->regs.a=stack_pop(cpu,log);
    update_nz(cpu->regs.a);
    break;
  case 0x69: // ADC #$nn
    // XXX - Ignores decimal mode!
    v=cpu->regs.a+log->bytes[1];
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    cpu->regs.a=v;
    cpu->regs.a&=0xff;
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x6A: // ROR A
    v=cpu->regs.a;
    if (cpu->regs.flags&FLAG_C) v|=0x100;
    cpu->regs.flags&=~FLAG_C;
    if (v&1) cpu->regs.flags|=FLAG_C;
    v=v>>1;
    update_nz(v);
    cpu->regs.a=v;
    log->len=1;
    cpu->regs.pc+=1;
    break;
  case 0x6B: // TZA
    cpu->regs.a=cpu->regs.z;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x6C: // JMP ($nnnn)
    cpu->regs.pc=addr_deref16(cpu,log);
    log->len=3;
    break;
  case 0x6D: // ADC $nnnn
    // XXX - Ignores decimal mode!
    v=cpu->regs.a+addr_abs(log);
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    cpu->regs.a=v;
    cpu->regs.a&=0xff;
    log->len=3;
    cpu->regs.pc+=3;
    break;
  case 0x78: // SEI
    cpu->regs.flags|=FLAG_I;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x7a: // PLY
    cpu->regs.pc++;
    log->len=1;
    cpu->regs.y=stack_pop(cpu,log);
    update_nz(cpu->regs.y);
    break;
  case 0x7b: // TBA
    cpu->regs.a=cpu->regs.b;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x80: // BRA $rr
    log->len=2;
    cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    break;
  case 0x83: // BRA $rrrr
    log->len=3;
    cpu->regs.pc+=2+rel16_delta(log->bytes[1]);
    break;
  case 0x84: // STY $xx
    log->len=2;
    cpu->regs.pc+=2;
    MEM_WRITE16(cpu,addr_zp(cpu,log),cpu->regs.y);
    break;
  case 0x85: // STA $xx
    log->len=2;
    cpu->regs.pc+=2;
    MEM_WRITE16(cpu,addr_zp(cpu,log),cpu->regs.a);
    break;
  case 0x86: // STX $xx
    log->len=2;
    cpu->regs.pc+=2;
    MEM_WRITE16(cpu,addr_zp(cpu,log),cpu->regs.x);
    break;
  case 0x88: // DEY
    cpu->regs.y--;
    update_nz(cpu->regs.y);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x89: // BIT #$xx
    log->len=2;
    cpu->regs.pc+=2;
    v=log->bytes[1];
    cpu->regs.flags&=~(FLAG_N|FLAG_V|FLAG_Z);
    cpu->regs.flags|=v&(FLAG_N|FLAG_V);
    v&=cpu->regs.a;
    if (!v) cpu->regs.flags|=FLAG_Z;
    break;
  case 0x8a: // TXA
    cpu->regs.a=cpu->regs.x;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x8c: // STY $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE16(cpu,addr_abs(log),cpu->regs.y);
    break;
  case 0x8d: // STA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE16(cpu,addr_abs(log),cpu->regs.a);
    break;
  case 0x8e: // STX $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE16(cpu,addr_abs(log),cpu->regs.x);
    break;
  case 0x90: // BCC $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_C)
      cpu->regs.pc+=2;
    else
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    break;
  case 0x91: // STA ($xx),Y
    log->len=2;
    cpu->regs.pc+=2;
    log->zp16=1;
    MEM_WRITE16(cpu,addr_izpy(cpu,log),cpu->regs.a);
    break;
  case 0x92: // STA ($xx),Z
    log->len=2;
    cpu->regs.pc+=2;
    if ((cpulog_len>1)&&cpulog[cpulog_len-2]->bytes[0]==0xEA) {
      // NOP prefix means 32-bit ZP pointer
      fprintf(logfile,"ZP32 address = $%07x\n",addr_izpz32(cpu,log));
      log->zp32=1;
      MEM_WRITE28(cpu,addr_izpz32(cpu,log),cpu->regs.a);
    } else
      // Normal 16-bit ZP pointer
      log->zp16=1;
      MEM_WRITE16(cpu,addr_izpz(cpu,log),cpu->regs.a);
    break;
  case 0x93: // BCC $rrrr
    log->len=3;
    if (cpu->regs.flags&FLAG_C)
      cpu->regs.pc+=3;
    else
      cpu->regs.pc+=3+rel16_delta(log->bytes[1]+(log->bytes[2]<<8));
    break;
  case 0x95: // STA $xx,X
    log->len=2;
    cpu->regs.pc+=2;
    MEM_WRITE16(cpu,addr_zpx(cpu,log),cpu->regs.a);
    break;
  case 0x98: // TYA
    cpu->regs.a=cpu->regs.y;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x99: // STA $xxxx,Y
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE16(cpu,addr_absy(cpu,log),cpu->regs.a);
    break;
  case 0x9a: // TXS
    cpu->regs.spl=cpu->regs.x;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x9c: // STZ $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE16(cpu,addr_abs(log),cpu->regs.z);
    break;
  case 0x9d: // STA $xxxx,X
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE16(cpu,addr_absx(cpu,log),cpu->regs.a);
    break;
  case 0xa0: // LDY #$nn
    cpu->regs.y=log->bytes[1];
    update_nz(cpu->regs.y);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xA1: // LDA ($xx,X)
    log->len=2;
    cpu->regs.pc+=2;
    log->zp16=1;
    cpu->regs.a=read_memory(cpu,addr_izpx(cpu,log));
    update_nz(cpu->regs.a);
    break;
  case 0xa2: // LDX #$nn
    cpu->regs.x=log->bytes[1];
    update_nz(cpu->regs.x);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xa3: // LDZ #$nn
    cpu->regs.z=log->bytes[1];
    update_nz(cpu->regs.z);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xa4: // LDY $xx
    log->len=2;
    cpu->regs.pc+=2;
    cpu->regs.y=read_memory(cpu,addr_zp(cpu,log));
    update_nz(cpu->regs.y);
    break;
  case 0xa5: // LDA $xx
    log->len=2;
    cpu->regs.pc+=2;
    cpu->regs.a=read_memory(cpu,addr_zp(cpu,log));
    update_nz(cpu->regs.a);
    break;
  case 0xa6: // LDX $xx
    log->len=2;
    cpu->regs.pc+=2;
    cpu->regs.x=read_memory(cpu,addr_zp(cpu,log));
    update_nz(cpu->regs.x);
    break;
  case 0xa8: // TAY
    cpu->regs.y=cpu->regs.a;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xa9: // LDA #$nn
    cpu->regs.a=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xaa: // TAX
    cpu->regs.x=cpu->regs.a;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xac: // LDY $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.y=read_memory(cpu,addr_abs(log));
    update_nz(cpu->regs.y);
    break;
  case 0xad: // LDA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.a=read_memory(cpu,addr_abs(log));
    update_nz(cpu->regs.a);
    break;
  case 0xae: // LDX $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.x=read_memory(cpu,addr_abs(log));
    update_nz(cpu->regs.x);
    break;
  case 0xB0: // BCS $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_C)
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    else
      cpu->regs.pc+=2;
    break;
  case 0xb1: // LDA ($xx),Y
    log->len=2;
    cpu->regs.pc+=2;
    log->zp16=1;
    cpu->regs.a=read_memory(cpu,addr_izpy(cpu,log));
    update_nz(cpu->regs.a);
    break;
  case 0xb5: // LDA $xx,X
    log->len=2;
    cpu->regs.pc+=2;
    cpu->regs.a=read_memory(cpu,addr_zpx(cpu,log));
    update_nz(cpu->regs.a);
    break;
  case 0xb9: // LDA $xxxx,Y
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.a=read_memory(cpu,addr_absy(cpu,log));
    update_nz(cpu->regs.a);
    break;
  case 0xba: // TSX
    log->len=1;
    cpu->regs.pc+=1;
    cpu->regs.x=cpu->regs.spl;
    update_nz(cpu->regs.x);
    break;
  case 0xbd: // LDA $xxxx,X
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.a=read_memory(cpu,addr_absx(cpu,log));
    update_nz(cpu->regs.a);
    break;
  case 0xC0: // CPY #$nn
    v=cpu->regs.y+log->bytes[1];
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xC5: // CMP $nn
    v=cpu->regs.a+addr_zp(cpu,log);
    update_nvzc(v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xC6: // DEC $xx
    log->len=2;
    cpu->regs.pc+=2;
    v=read_memory(cpu,addr_zp(cpu,log));
    v--; v&=0xff;
    MEM_WRITE16(cpu,addr_zp(cpu,log),v);
    update_nz(v);
    break;
  case 0xC8: // INY
    cpu->regs.y++;
    update_nz(cpu->regs.y);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xC9: // CMP #$nn
    v=cpu->regs.a+log->bytes[1];
    update_nvzc(v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xCA: // DEX
    cpu->regs.x--;
    update_nz(cpu->regs.x);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xCC: // CPY $nnnn
    v=cpu->regs.y+addr_abs(log);
    update_nvzc(v);
    log->len=3;
    cpu->regs.pc+=3;
    break;
  case 0xCD: // CMP $nnnn
    v=cpu->regs.a+addr_abs(log);
    update_nvzc(v);
    log->len=3;
    cpu->regs.pc+=3;
    break;
  case 0xCE: // DEC $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    v--; v&=0xff;
    MEM_WRITE16(cpu,addr_abs(log),v);
    update_nz(v);
    break;
  case 0xd0: // BNE $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_Z)
      cpu->regs.pc+=2;
    else
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    break;
  case 0xD8: // CLD
    cpu->regs.flags&=~FLAG_D;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xDA: // PHX
    stack_push(cpu,cpu->regs.x);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xDB: // PHZ
    stack_push(cpu,cpu->regs.z);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xE0: // CPX #$nn
    v=cpu->regs.x+log->bytes[1];
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xe5: // SBC $nn
    // XXX - Ignores decimal mode!
    v=cpu->regs.a-addr_zp(cpu,log)-1;
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    cpu->regs.a=v;
    cpu->regs.a&=0xff;
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xE6: // INC $xx
    log->len=2;
    cpu->regs.pc+=2;
    v=read_memory(cpu,addr_zp(cpu,log));
    v++; v&=0xff;
    MEM_WRITE16(cpu,addr_zp(cpu,log),v);
    update_nz(v);
    break;
  case 0xE8: // INX
    cpu->regs.x++;
    update_nz(cpu->regs.x);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xe9: // SBC #$nn
    // XXX - Ignores decimal mode!
    v=cpu->regs.a-log->bytes[1]-1;
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    cpu->regs.a=v;
    cpu->regs.a&=0xff;
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xea: // EOM / NOP
    cpu->regs.pc++;
    cpu->regs.map_irq_inhibit=0;
    log->len=1;
    break;
  case 0xEC: // CPX $nnnn
    v=cpu->regs.x+read_memory(cpu,addr_abs(log));
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    log->len=3;
    cpu->regs.pc+=3;
    break;
  case 0xed: // SBC $nnnn
    // XXX - Ignores decimal mode!
    v=cpu->regs.a-addr_abs(log)-1;
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    cpu->regs.a=v;
    cpu->regs.a&=0xff;
    log->len=3;
    cpu->regs.pc+=3;
    break;
  case 0xEE: // INC $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    v++; v&=0xff;
    MEM_WRITE16(cpu,addr_abs(log),v);
    update_nz(v);
    break;
  case 0xf0: // BEQ $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_Z)
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    else
      cpu->regs.pc+=2;
    break;
  case 0xf3: // BEQ $rrrr
    log->len=3;
    if (cpu->regs.flags&FLAG_Z)
      cpu->regs.pc+=3+rel16_delta(log->bytes[1]);
    else
      cpu->regs.pc+=3;
    break;
  case 0xf6: // INC $xx,X
    log->len=2;
    cpu->regs.pc+=2;
    v=read_memory(cpu,addr_zpx(cpu,log));
    v++; v&=0xff;
    MEM_WRITE16(cpu,addr_zpx(cpu,log),v);
    update_nz(v);
    break;
  case 0xFA: // PLX
    cpu->regs.x=stack_pop(cpu,log);
    update_nz(cpu->regs.x);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xFB: // PLZ
    cpu->regs.z=stack_pop(cpu,log);
    update_nz(cpu->regs.z);
    cpu->regs.pc++;
    log->len=1;
    break;
  default:
    fprintf(stderr,"ERROR: Unimplemented opcode $%02X\n",log->bytes[0]);
    log->len=6;
    return -1;
  }

  // Ignore stack underflows/overflows if execution is complete, so that
  // terminal RTS doesn't cause a stack underflow error
  if (cpu->term.done) return 0;
  
  if (cpu->stack_underflow) {
    fprintf(stderr,"ERROR: Stack underflow detected.\n");
    return -1;
  }
  if (cpu->stack_overflow) {
    fprintf(stderr,"ERROR: Stack overflow detected.\n");
    return -1;
  }
  
  return 0;
}

int cpu_call_routine(FILE *f,unsigned int addr)
{
  cpu.regs.spl=0xff;
  
  // Is routine in hypervisor or in userland? Set stack pointer accordingly.
  if (addr>=0x8000&&addr<0xc000) {
    cpu.regs.sph=0xbe;
    cpu.regs.in_hyper=1;
  }
  else {
    cpu.regs.sph=0x01;
    cpu.regs.in_hyper=0;
  }

  fprintf(f,">>> Calling routine %s @ $%04x\n",describe_address_label(&cpu,addr),addr);

  // Remember the initial CPU state
  cpu_stash_ram();
  cpu_expected=cpu;

  // Reset the CPU instruction log
  cpu_log_reset();

  cpu.regs.pc=addr;
  
  // Now execute instructions until we empty the stack or hit a BRK
  // or various other nasty situations that we might allow, including
  // filling the CPU instruction log
  while(cpulog_len<MAX_LOG_LENGTH) {

    // Stop once the termination condition has been reached.
    if (cpu.term.done) break;
    
    struct instruction_log *log=calloc(sizeof(instruction_log),1);
    log->regs=cpu.regs;
    log->pc=cpu.regs.pc;
    log->len=0; // byte count of instruction
    log->count=1;
    log->dup=0;

    // Add instruction to the log
    cpu.instruction_count=cpulog_len;
    cpulog[cpulog_len++]=log;
    
    if (execute_instruction(&cpu,log)) {
      cpu.term.error=1;
      fprintf(f,"ERROR: Exception occurred executing instruction at %s\n       Aborted.\n",
	      describe_address(cpu.regs.pc));
      show_recent_instructions(f,"Instructions leading up to the exception",
			       &cpu,cpulog_len-16,16,cpu.regs.pc);
      return -1;
    }

    cpu.instruction_count=cpulog_len;
    
    // And to most recent instruction at this address, but only if the last instruction
    // there was not identical on all registers and instruction to this one
    if (lastataddr[cpu.regs.pc]&&identical_cpustates(lastataddr[cpu.regs.pc],log)) {
      // If identical, increase the count, so that we can keep track of infinite loops
      lastataddr[cpu.regs.pc]->count++;
      log->dup=1;
      if (lastataddr[cpu.regs.pc]->count>INFINITE_LOOP_THRESHOLD) {
	cpu.term.error=1;
	fprintf(stderr,"ERROR: Infinite loop detected at %s.\n       Aborted after %d iterations.\n",
		describe_address(cpu.regs.pc),lastataddr[cpu.regs.pc]->count);
	// Show upto 32 instructions prior to the infinite loop
	show_recent_instructions(stderr,"Instructions leading into the infinite loop for the first time",
				 &cpu,cpulog_len-lastataddr[cpu.regs.pc]->count-30,32,addr);
	return -1;
      }
    } else lastataddr[cpu.regs.pc]=log;
    
  }
  if (cpulog_len==MAX_LOG_LENGTH) {
    cpu.term.error=1;   
    fprintf(logfile,"ERROR: CPU instruction log filled.  Maybe a problem with the called routine?\n");
    return -1;
  }
  if (cpu.term.brk) {
    fprintf(logfile,"ERROR: BRK instruction encountered.\n");
    // Show upto 32 instructions prior to the infinite loop
    show_recent_instructions(logfile,"Instructions leading to the BRK instruction",
			     &cpu,cpulog_len-30,32,addr);
    int blame=memory_blame(&cpu,cpu.regs.pc);
    if (blame) {
      show_recent_instructions(logfile,"Instructions leading to the BRK instruction being written",
			       &cpu,blame-16,17,cpu.regs.pc);
    }
    return -1;    
  }
  if (cpu.term.done) {
    fprintf(logfile,"NOTE: Execution ended.\n");
  }
  
  return 0;
}

#define COMPARE_REG(REG,Reg) if (cpu->regs.Reg!=cpu_expected.regs.Reg) { fprintf(f,"ERROR: Register "REG" contains $%02X instead of $%02X\n",cpu->regs.Reg,cpu_expected.regs.Reg); cpu->term.error=1; /* XXX show instruction that set it */ }

#define COMPARE_REG16(REG,Reg) if (cpu->regs.Reg!=cpu_expected.regs.Reg) { fprintf(f,"ERROR: Register "REG" contains %s ($%04X) instead of",describe_address_label(cpu,cpu->regs.Reg),cpu->regs.Reg); fprintf(f," %s ($%04X)\n",describe_address_label(cpu,cpu_expected.regs.Reg),cpu_expected.regs.Reg); cpu->term.error=1; /* XXX show instruction that set it */ }

int compare_register_contents(FILE *f, struct cpu *cpu)
{
  COMPARE_REG("A",a);
  COMPARE_REG("X",x);
  COMPARE_REG("Y",y);
  COMPARE_REG("Z",z);
  COMPARE_REG("B",b);
  COMPARE_REG("SPL",spl);
  COMPARE_REG("SPH",sph);
  COMPARE_REG16("PC",pc);

  return cpu->term.error;
}

int ignore_ram_changes(unsigned int low, unsigned int high)
{
  for(int i=low;i<=high;i++) {
    if (i<CHIPRAM_SIZE) {
      //      if (chipram_expected[i]!=chipram[i]) fprintf(logfile,"NOTE: Ignoring mutated value at $%x\n",i);
      chipram_expected[i]=chipram[i];
    }
    if (i>=0xfff8000&&i<0xfffc000) hypporam_expected[i-0xfff8000]=hypporam[i-0xfff8000];
  }
  return 0;
}

int compare_ram_contents(FILE *f, struct cpu *cpu)
{
  int errors=0;
  
  for(int i=0;i<CHIPRAM_SIZE;i++) {
    if (chipram[i]!=chipram_expected[i]) {
      errors++;
    }
  }
  for(int i=0;i<HYPPORAM_SIZE;i++) {
    if (hypporam[i]!=hypporam_expected[i]) {
      errors++;
    }
  }
  for(int i=0;i<COLOURRAM_SIZE;i++) {
    if (colourram[i]!=colourram_expected[i]) {
      errors++;
    }
  }
  for(int i=0;i<65536;i++) {
    if (ffdram[i]!=ffdram_expected[i]) {
      errors++;
    }
  }

  if (errors) {
    fprintf(f,"ERROR: %d memory locations contained unexpected values.\n",errors);
    cpu->term.error=1;
    
    int displayed=0;
    
    for(int i=0;i<CHIPRAM_SIZE;i++) {
      if (chipram[i]!=chipram_expected[i]) {
	fprintf(f,"ERROR: Saw $%02X at $%07x (%s), but expected to see $%02X\n",
		chipram[i],i,describe_address_label28(cpu,i),chipram_expected[i]);
	int first_instruction=chipram_blame[i]-3;
	if (first_instruction<0) first_instruction=0;
	show_recent_instructions(f,"Instructions leading to this value being written",
				 cpu,first_instruction,4,-1);
	displayed++;
      }
      if (displayed>=100) break;
    }
    for(int i=0;i<HYPPORAM_SIZE;i++) {
      if (hypporam[i]!=hypporam_expected[i]) {
	fprintf(f,"ERROR: Saw $%02X at $%07x (%s), but expected to see $%02x\n",
		hypporam[i],i+0xfff8000,describe_address_label28(cpu,i+0xfff8000),hypporam_expected[i]);
	int first_instruction=hypporam_blame[i]-3;
	if (first_instruction<0) first_instruction=0;
	show_recent_instructions(f,"Instructions leading to this value being written",
				 cpu,first_instruction,4,-1);      
      }
      if (displayed>=100) break;	
    }
    for(int i=0;i<COLOURRAM_SIZE;i++) {
      if (colourram[i]!=colourram_expected[i]) {
	fprintf(f,"ERROR: Saw $%02X at $%07x (%s), but expected to see $%02X\n",
	        colourram[i],i+0xff80000,describe_address_label28(cpu,i+0xff80000),colourram_expected[i]);
	int first_instruction=colourram_blame[i]-3;
	if (first_instruction<0) first_instruction=0;
	show_recent_instructions(f,"Instructions leading to this value being written",
				 cpu,first_instruction,4,-1);
	displayed++;
      }
      if (displayed>=100) break;
    }
    for(int i=0;i<65536;i++) {
      if (ffdram[i]!=ffdram_expected[i]) {
	fprintf(f,"ERROR: Saw $%02X at $%07x (%s), but expected to see $%02X\n",
		ffdram[i],i+0xffd0000,describe_address_label28(cpu,i+0xffd0000),ffdram_expected[i]);
	int first_instruction=ffdram_blame[i]-3;
	if (first_instruction<0) first_instruction=0;
	show_recent_instructions(f,"Instructions leading to this value being written",
				 cpu,first_instruction,4,-1);
	displayed++;
      }
      if (displayed>=100) break;
    }
    if (displayed>100) {
      fprintf(f,"WARNING: Displayed only the first 100 incorrect memory contents. %d more suppressed.\n",
	      errors-100);
    }
    
    
  }
  return errors;
}

unsigned char viciv_regs[0x80]=
  {
   0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
   0x00,0x9B,0x37,0x00,0x00,0x00,0xC8,0x00,0x14,0x71,0xE0,0x00,0x00,0x00,0x00,0x00,
   0x0E,0x06,0x01,0x02,0x03,0x04,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x0C,0x00,
   0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
   0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0x68,0x00,0xF8,0x01,0x50,0x00,0x68,0x00,
   0x0C,0x83,0xE9,0x81,0x05,0x00,0x00,0x00,  80,   0,0x78,0x01,0x50,0xC0,0x28,0x00,
   0x00,0xb8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x90,0x00,0x00,0xF8,0x07,0x00,0x00,
   0xFF,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x37,0x81,0x18,0xC2,0x00,0x00,0x7F   
  };

void machine_init(struct cpu *cpu)
{
  // Initialise CPU staet
  bzero(cpu,sizeof(struct cpu));
  cpu->regs.flags=FLAG_E|FLAG_I;
  cpu->regs.b=0xbf;

  // We start in hypervisor mode
  cpu->regs.in_hyper=1;
  // Map in hypervisor
  cpu->regs.maphimb=0xff;
  cpu->regs.maphi=0x3f00; 
  
  bzero(breakpoints,sizeof(breakpoints));
  
  bzero(&cpu_expected,sizeof(struct cpu));
  cpu_expected.regs.flags=FLAG_E|FLAG_I;
  
  // Clear chip RAM
  bzero(chipram_expected,CHIPRAM_SIZE);
  // Clear Hypervisor RAM
  bzero(hypporam_expected,HYPPORAM_SIZE);
  bzero(colourram_expected,COLOURRAM_SIZE);
  bzero(ffdram_expected,65536);

  // Setup default VIC-IV register values
  for(int i=0;i<0x80;i++) {
    ffdram[0x3000+i]=viciv_regs[i];
    ffdram_expected[0x3000+i]=viciv_regs[i];
  }
  
  // Set CPU IO port $01
  chipram_expected[0]=0x3f;
  chipram_expected[1]=0x27;
  chipram[0]=0x3f;
  chipram[1]=0x27;
  
  // Reset blame for contents of memory
  bzero(chipram_blame,sizeof(chipram_blame));
  bzero(hypporam_blame,sizeof(hypporam_blame));

  // Reset loaded symbols
  for(int i=0;i<hyppo_symbol_count;i++) {
    free(hyppo_symbols[i].name);
  }
  hyppo_symbol_count=0;
  
  // Reset instruction logs
  for(int i=0;i<cpulog_len;i++) {
    free(cpulog[i]);
  }
  cpulog_len=0;
  bzero(lastataddr,sizeof(lastataddr));
}

void test_init(struct cpu *cpu)
{

  machine_init(cpu);

  log_on_failure=0;
  
  // Log to temporary file, so that we can rename it to PASS.* or FAIL.*
  // after.
  unlink(TESTLOGFILE);
  logfile=fopen(TESTLOGFILE,"w");
  if (!logfile) {
    fprintf(stderr,"ERROR: Could not write to '%s'\n",TESTLOGFILE);
    exit(-2);
  }

  {
    for(int i=0;test_name[i];i++) {
      if ((test_name[i]>='a'&&test_name[i]<='z')
	  ||(test_name[i]>='A'&&test_name[i]<='Z')
	  ||(test_name[i]>='0'&&test_name[i]<='9'))
	safe_name[i]=test_name[i];
      else safe_name[i]='_';
    }
    safe_name[strlen(test_name)]=0;
  }

  
  // Show starting of test
  printf("[    ] %s",test_name);
  
}

void test_conclude(struct cpu *cpu)
{
  char cmd[8192];
  
  // Report test status
  snprintf(cmd,8192,"FAIL.%s",safe_name); unlink(cmd);
  snprintf(cmd,8192,"PASS.%s",safe_name); unlink(cmd);
  
  if (cpu->term.error) {
    snprintf(cmd,8192,"mv %s FAIL.%s",TESTLOGFILE,safe_name);
    test_fails++;
    if (log_on_failure) {
      if (cpulog_len<500000) 
	show_recent_instructions(logfile,"Complete instruction log follows",cpu,1,cpulog_len,-1);
      else
	show_recent_instructions(logfile,"Log of last 500,000 instructions follows ",cpu,cpulog_len-500000,cpulog_len,-1);
    }
    fprintf(logfile,"NOTE: MEGA65 screen at end of test:\n");
    do_screen_shot_ascii(logfile);
    fprintf(logfile,"FAIL: Test failed.\n");
    printf("\r[FAIL] %s\n",test_name);
  } else {
    snprintf(cmd,8192,"mv %s PASS.%s",TESTLOGFILE,safe_name);
    test_passes++;

    //    show_recent_instructions(logfile,"Complete instruction log follows",cpu,1,cpulog_len,-1);
    fprintf(logfile,"PASS: Test passed.\n");
    printf("\r[PASS] %s\n",test_name);    
  }

  if (logfile!=stderr) {
    fclose(logfile);
    system(cmd);
  }

  logfile=stderr;
}

int load_hyppo(char *filename)
{
  FILE *f=fopen(filename,"rb");
  if (!f) {
    fprintf(logfile,"ERROR: Could not read HICKUP file from '%s'\n",filename);
    return -1;
  }
  int b=fread(hypporam_expected,1,HYPPORAM_SIZE,f);
  if (b!=HYPPORAM_SIZE) {
    fprintf(logfile,"ERROR: Read only %d of %d bytes from HICKUP file.\n",b,HYPPORAM_SIZE);
    return -1;
  }
  fclose(f);
  return 0;
}

unsigned char buffer[8192*1024];
int load_file(char *filename,unsigned int location)
{
  FILE *f=fopen(filename,"rb");
  if (!f) {
    fprintf(logfile,"ERROR: Could not read binary file from '%s'\n",filename);
    return -1;
  }
  int b=fread(buffer,1,8192*1024,f);
  fprintf(logfile,"NOTE: Loading %d bytes at $%07x from %s\n",b,location,filename);
  for(int i=0;i<b;i++) {
    write_mem_expected28(i+location,buffer[i]);  
  }  
  
  fclose(f);
  return 0;
}


int load_hyppo_symbols(char *filename)
{
  FILE *f=fopen(filename,"r");
  if (!f) {
    fprintf(logfile,"ERROR: Could not read HICKUP symbol list from '%s'\n",filename);
    return -1;
  }
  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    char sym[1024];
    int addr;
    if(sscanf(line," %s = $%x",sym,&addr)==2) {
      if (hyppo_symbol_count>=MAX_HYPPO_SYMBOLS) {
	fprintf(logfile,"ERROR: Too many symbols. Increase MAX_HYPPO_SYMBOLS.\n");
	return -1;
      }
      hyppo_symbols[hyppo_symbol_count].name=strdup(sym);
      hyppo_symbols[hyppo_symbol_count].addr=addr;
      sym_by_addr[addr]=&hyppo_symbols[hyppo_symbol_count];
      hyppo_symbol_count++;
    }
    line[0]=0; fgets(line,1024,f);
  }
  fclose(f);
  fprintf(logfile,"INFO: Read %d HYPPO symbols.\n",hyppo_symbol_count);
  return 0;
}

int load_symbols(char *filename, unsigned int offset)
{
  FILE *f=fopen(filename,"r");
  if (!f) {
    fprintf(logfile,"ERROR: Could not read symbol list from '%s'\n",filename);
    return -1;
  }
  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    char sym[1024];
    int addr;
    if(sscanf(line," %s = $%x",sym,&addr)==2) {
      if (symbol_count>=MAX_SYMBOLS) {
	fprintf(logfile,"ERROR: Too many symbols. Increase MAX_SYMBOLS.\n");
	return -1;
      }
      symbols[symbol_count].name=strdup(sym);
      symbols[symbol_count].addr=addr+offset;
      if (addr+offset<CHIPRAM_SIZE) {
	sym_by_addr[addr+offset]=&symbols[symbol_count];
      }
      symbol_count++;
    } else if (sscanf(line,"al %x %s",&addr,sym)==2) {
      // VICE symbol list format (eg from CC65)
      if (symbol_count>=MAX_SYMBOLS) {
	fprintf(logfile,"ERROR: Too many symbols. Increase MAX_SYMBOLS.\n");
	return -1;
      }
      symbols[symbol_count].name=strdup(sym);
      symbols[symbol_count].addr=addr+offset;
      if (addr+offset<CHIPRAM_SIZE) {
	sym_by_addr[addr+offset]=&symbols[symbol_count];
      }
      symbol_count++;
    }
    line[0]=0; fgets(line,1024,f);
  }
  fclose(f);
  fprintf(logfile,"INFO: Read %d symbols.\n",symbol_count);
  return 0;
}


int resolve_value32(char *in)
{
  int v;
  char label[1024];
  int delta=0;
  
  // Hex is the easy case
  if (sscanf(in,"$%x",&v)==1) return v;

  // Check for label with optional +delta
  if (sscanf(in,"%[^+]+%d",label,&delta)==2) ;
  else if (sscanf(in,"%[^-]-%d",label,&delta)==2) ;
  else if (sscanf(in,"%[^+]+$%x",label,&delta)==2) ;
  else if (sscanf(in,"%[^-]-$%x",label,&delta)==2) ;
  else if (sscanf(in,"%s",label)==1) ;
  else {
    fprintf(stderr,"ERROR: Could not parse address or value specification '%s'.\n",in);
    if (logfile!=stderr)
      fprintf(logfile,"ERROR: Could not parse address or value specification '%s'.\n",in);
    cpu.term.error=1;
    return 0;
  }

  int i;
  for(i=0;i<hyppo_symbol_count;i++) {
    if (!strcmp(label,hyppo_symbols[i].name)) break;
  }
  if (i==hyppo_symbol_count) {

    // Now look for non-hyppo symbols
    for(i=0;i<symbol_count;i++) {
      if (!strcmp(label,symbols[i].name)) break;
    }
    if (i==symbol_count) {
      fprintf(logfile,"ERROR: Cannot call find non-existent symbol '%s'\n",label);
      cpu.term.error=1;
      return 0;
    } else {
      // Return symbol address
      v=symbols[i].addr+delta;
      return v;
    }
  } else {
    // Add HYPPO base address to HYPPO symbols
    v=0xfff0000+hyppo_symbols[i].addr+delta;
    return v;
  }
}

int resolve_value8(char *in)
{
  return resolve_value32(in)&0xff;
}

int resolve_value16(char *in)
{
  return resolve_value32(in)&0xffff;
}

int main(int argc,char **argv)
{
  if (argc!=2) {
    fprintf(stderr,"usage: hypertest <test script>\n");
    exit(-2);
  }

  // Setup for anonymous tests, if user doesn't supply any test directives
  machine_init(&cpu);
  logfile=stderr;

  // Open test script, and start interpreting it 
  FILE *f=fopen(argv[1],"r");
  if (!f) {
    fprintf(stderr,"ERROR: Could not read test procedure from '%s'\n",argv[3]);
    exit(-2);
  }
  char line[1024];
  while(!feof(f)) {
    line[0]=0; fgets(line,1024,f);
    char routine[1024];
    char value[1024];
    char location[1024];
    char start[1024];
    char end[1024];
    unsigned int addr,addr2,first,last;
    if (!line[0]) continue;
    if (line[0]=='#') continue;
    if (line[0]=='\r') continue;
    if (line[0]=='\n') continue;
    if (sscanf(line,"jsr %s",routine)==1) {
      int i;
      for(i=0;i<hyppo_symbol_count;i++) {
	if (!strcmp(routine,hyppo_symbols[i].name)) break;
      }
      if (i==hyppo_symbol_count) {
	fprintf(logfile,"ERROR: Cannot call non-existent routine '%s'\n",routine);
	cpu.term.error=1;
      } else {
	int log_dma=cpu.term.log_dma;
	bzero(&cpu.term,sizeof(cpu.term));
	cpu.term.log_dma=log_dma;
	cpu.term.rts=1; // Terminate on net RTS from routine
	cpu_call_routine(logfile,hyppo_symbols[i].addr);
      }
    } else if (sscanf(line,"dump instructions %d to %d",&first,&last)==2) {
      show_recent_instructions(logfile,line,&cpu,first,last-first+1,-1);
    } else if (!strncasecmp(line,"log dma off",strlen("log dma off"))) {
      cpu.term.log_dma=0;
      fprintf(logfile,"NOTE: DMA jobs will not be reported\n");
    } else if (!strncasecmp(line,"log dma",strlen("log dma"))) {
      cpu.term.log_dma=1;
      fprintf(logfile,"NOTE: DMA jobs will be reported\n");
    } else if (!strncasecmp(line,"log on failure",strlen("log on failure"))) {
      // Dump all instructions on test failure
      log_on_failure=1;      
    } else if (sscanf(line,"jsr $%x",&addr)==1) {
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.rts=1; // Terminate on net RTS from routine
      cpu_call_routine(logfile,addr);
    } else if (sscanf(line,"jmp %s",routine)==1) {
      int i;
      int log_dma=cpu.term.log_dma;
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.log_dma=log_dma;
      cpu.term.rts=0;
      for(i=0;i<hyppo_symbol_count;i++) {
	if (!strcmp(routine,hyppo_symbols[i].name)) break;
      }
      if (i==hyppo_symbol_count) {
	fprintf(logfile,"ERROR: Cannot call non-existent routine '%s'\n",routine);
	cpu.term.error=1;
      } else {
	int log_dma=cpu.term.log_dma;
	bzero(&cpu.term,sizeof(cpu.term));
	cpu.term.log_dma=log_dma;
	cpu_call_routine(logfile,hyppo_symbols[i].addr);
      }
    }
    else if (sscanf(line,"jmp $%x",&addr)==1) {
      int log_dma=cpu.term.log_dma;
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.log_dma=log_dma;
      cpu.term.rts=0;
      cpu_call_routine(logfile,addr);
    }  else if (!strncasecmp(line,"check registers",strlen("check registers"))) {
      // Check registers for changes
      compare_register_contents(logfile,&cpu);
    } else if (sscanf(line,"ignore from %s to %s",start,end)==2) {
      int low=resolve_value32(start);
      int high=resolve_value32(end);
      ignore_ram_changes(low,high);
    } else if (sscanf(line,"ignore %s",start)==1) {
      int low=resolve_value32(start);
      ignore_ram_changes(low,low);
    }  else if (!strncasecmp(line,"check ram",strlen("check ram"))) {
      // Check RAM for changes
      compare_ram_contents(logfile,&cpu);
    }  else if (sscanf(line,"test \"%[^\"]\"",test_name)==1) {
      // Set test name
      test_init(&cpu);
      
      fflush(stdout);
      
    } else if (!strncasecmp(line,"test end",strlen("test end"))) {
      test_conclude(&cpu);	
    } else if (sscanf(line,"loadhypposymbols %s",routine)==1) {
      if (load_hyppo_symbols(routine)) cpu.term.error=1;
    } else if (sscanf(line,"loadhyppo %s",routine)==1) {
      if (load_hyppo(routine)) cpu.term.error=1;
    } else if (sscanf(line,"load %s at $%x",routine,&addr)==2) {
      if (load_file(routine,addr)) cpu.term.error=1;
    } else if (sscanf(line,"loadsymbols %s at $%x-$%x",routine,&addr,&addr2)==3) {
      if (load_symbols(routine,addr-addr2)) cpu.term.error=1;
    } else if (sscanf(line,"loadsymbols %s at $%x+$%x",routine,&addr,&addr2)==3) {
      if (load_symbols(routine,addr+addr2)) cpu.term.error=1;
    } else if (sscanf(line,"loadsymbols %s at $%x",routine,&addr)==2) {
      if (load_symbols(routine,addr)) cpu.term.error=1;
    } else if (sscanf(line,"breakpoint %s",routine)==1) {
      int addr32=resolve_value32(routine);
	int addr16=addr32;
      if (addr32&0xffff0000) {
	addr16=addr32&0xffff;
      } 
      fprintf(logfile,"INFO: Breakpoint set at %s ($%04x)\n",routine,addr16);
      breakpoints[addr16]=1;
    } else if (sscanf(line,"expect %s = %s",location,value)==2) {
      // Set expected register value
      if (!strcasecmp(location,"a")) cpu_expected.regs.a=resolve_value8(value);
      else if (!strcasecmp(location,"a")) cpu_expected.regs.a=resolve_value8(value);
      else if (!strcasecmp(location,"x")) cpu_expected.regs.x=resolve_value8(value);
      else if (!strcasecmp(location,"y")) cpu_expected.regs.y=resolve_value8(value);
      else if (!strcasecmp(location,"z")) cpu_expected.regs.z=resolve_value8(value);
      else if (!strcasecmp(location,"b")) cpu_expected.regs.b=resolve_value8(value);
      else if (!strcasecmp(location,"spl")) cpu_expected.regs.spl=resolve_value8(value);
      else if (!strcasecmp(location,"sph")) cpu_expected.regs.sph=resolve_value8(value);
      else if (!strcasecmp(location,"pc")) cpu_expected.regs.pc=resolve_value16(value);
      else {
	fprintf(logfile,"ERROR: Unknown register '%s'\n",location);
	cpu.term.error=1;
      }
    } else if (sscanf(line,"expect %s at %s",value,location)==2) {
      // Update *_expected[] memories to indicate the value we expect where.
      // Resolve labels and label+offset and $nn in each of the fields.
      int v=resolve_value8(value);
      int l=resolve_value32(location);
      write_mem_expected28(l,v);
    } else {
      fprintf(logfile,"ERROR: Unrecognised test directive:\n       %s\n",line);
      cpu.term.error=1;
    }
  }
  if (logfile!=stderr) test_conclude(&cpu);
  fclose(f);
}

/* ----------------------------------------------------------------------------------------------------------
   Screen shot code follows 
   ----------------------------------------------------------------------------------------------------------
*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <strings.h>
#include <string.h>
#include <ctype.h>
#include <sys/time.h>
#include <errno.h>
#include <getopt.h>
#include <inttypes.h>
#include <pthread.h>

#define PNG_DEBUG 3
#include <png.h>

#ifdef WINDOWS
#include <windows.h>
#else
#include <termios.h>
#endif

#define SCREEN_POSITION ((800 - 720) / 2)

int fetch_ram(unsigned long address, unsigned int count, unsigned char* buffer)
{
  for(int i=0;i<count;i++)
    buffer[i]=read_memory28(NULL,address+i);
  return 0;
}

#ifdef WINDOWS
#define bzero(b, len) (memset((b), '\0', (len)), (void)0)
#define bcopy(b1, b2, len) (memmove((b2), (b1), (len)), (void)0)
#endif

unsigned char bitmap_multi_colour;
unsigned int current_physical_raster;
extern unsigned int screen_address;
unsigned int charset_address;
extern unsigned int screen_line_step;
unsigned int colour_address;
extern unsigned int screen_width;
unsigned int upper_case;
unsigned int screen_rows;
unsigned int sixteenbit_mode;
unsigned int screen_size;
unsigned int charset_size;
unsigned int extended_background_mode;
unsigned int multicolour_mode;
int bitmap_mode;
unsigned int screen_line_step=0;
unsigned int screen_width=0;
unsigned int screen_address=0;

int border_colour;
int background_colour;

unsigned int y_scale;
unsigned int h640;
unsigned int v400;
unsigned int viciii_attribs;
unsigned int chargen_x;
unsigned int chargen_y;

unsigned int top_border_y;
unsigned int bottom_border_y;
unsigned int side_border_width;
unsigned int left_border;
unsigned int right_border;
unsigned int x_scale_120;
float x_step;

unsigned char vic_regs[0x400];
#define MAX_SCREEN_SIZE (128 * 1024)
unsigned char screen_data[MAX_SCREEN_SIZE];
unsigned char colour_data[MAX_SCREEN_SIZE];
unsigned char char_data[8192 * 8];

unsigned char mega65_rgb(int colour, int rgb)
{
  return ((vic_regs[0x0100 + (0x100 * rgb) + colour] & 0xf) << 4)
       + ((vic_regs[0x0100 + (0x100 * rgb) + colour] & 0xf0) >> 4);
}

png_structp png_ptr = NULL;
png_bytep png_rows[576];
int is_pal_mode = 0;

int min_y = 0;
int max_y = 999;

int set_pixel(int x, int y, int r, int g, int b)
{
  if (y < min_y || y > max_y)
    return 0;
  if (y < 0 || y > (is_pal_mode ? 575 : 479)) {
    //    fprintf(stderr,"ERROR: Impossible y value %d\n",y);
    //    exit(-1);
    return 1;
  }
  if (x < 0 || x > 719) {
    fprintf(stderr, "ERROR: Impossible x value %d\n", x);
    exit(-1);
  }

  //  printf("Setting pixel at %d,%d to #%02x%02x%02x\n",x,y,b,g,r);
  ((unsigned char*)png_rows[y])[x * 3 + 0] = r;
  ((unsigned char*)png_rows[y])[x * 3 + 1] = g;
  ((unsigned char*)png_rows[y])[x * 3 + 2] = b;

  return 0;
}

typedef struct {
  char mask;       /* char data will be bitwise AND with this */
  char lead;       /* start bytes of current char in utf-8 encoded character */
  uint32_t beg;    /* beginning of codepoint range */
  uint32_t end;    /* end of codepoint range */
  int bits_stored; /* the number of bits from the codepoint that fits in char */
} utf_t;

utf_t* utf[] = {
  /*             mask        lead        beg      end       bits */
  [0] = &(utf_t) { 0b00111111, 0b10000000, 0, 0, 6 },
  [1] = &(utf_t) { 0b01111111, 0b00000000, 0000, 0177, 7 },
  [2] = &(utf_t) { 0b00011111, 0b11000000, 0200, 03777, 5 },
  [3] = &(utf_t) { 0b00001111, 0b11100000, 04000, 0177777, 4 },
  [4] = &(utf_t) { 0b00000111, 0b11110000, 0200000, 04177777, 3 },
  &(utf_t) { 0 },
};

// UTF-8 from https://rosettacode.org/wiki/UTF-8_encode_and_decode#C

/* All lengths are in bytes */
int codepoint_len(const uint32_t cp); /* len of associated utf-8 char */
int utf8_len(const char ch);          /* len of utf-8 encoded char */

char* to_utf8(const uint32_t cp);
uint32_t to_cp(const char chr[4]);

int codepoint_len(const uint32_t cp)
{
  int len = 0;
  for (utf_t** u = utf; *u; ++u) {
    if ((cp >= (*u)->beg) && (cp <= (*u)->end)) {
      break;
    }
    ++len;
  }
  if (len > 4) /* Out of bounds */
    exit(1);

  return len;
}

int utf8_len(const char ch)
{
  int len = 0;
  for (utf_t** u = utf; *u; ++u) {
    if ((ch & ~(*u)->mask) == (*u)->lead) {
      break;
    }
    ++len;
  }
  if (len > 4) { /* Malformed leading byte */
    exit(1);
  }
  return len;
}

char* to_utf8(const uint32_t cp)
{
  static char ret[5];
  const int bytes = codepoint_len(cp);

  int shift = utf[0]->bits_stored * (bytes - 1);
  ret[0] = (cp >> shift & utf[bytes]->mask) | utf[bytes]->lead;
  shift -= utf[0]->bits_stored;
  for (int i = 1; i < bytes; ++i) {
    ret[i] = (cp >> shift & utf[0]->mask) | utf[0]->lead;
    shift -= utf[0]->bits_stored;
  }
  ret[bytes] = '\0';
  return ret;
}

void print_screencode(FILE *f,unsigned char c, int upper_case)
{
  int rev = 0;
  if (c & 0x80) {
    rev = 1;
    c &= 0x7f;
    // Now swap foreground/background
    fprintf(f,"%c[7m", 27);
  }
  if (c >= '0' && c <= '9')
    fprintf(f,"%c", c);
  else if (c >= 0x00 && c <= 0x1f) {
    if (upper_case)
      fprintf(f,"%c", c + 0x40);
    else
      fprintf(f,"%c", c + 0x60);
  }
  else if (c >= 0x20 && c < 0x40)
    fprintf(f,"%c", c);
  else if ((c >= 0x40 && c <= 0x5f) && (!upper_case))
    fprintf(f,"%c", c);

  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x61)
    fprintf(f,"%s", to_utf8(0x258c));
  else if (c == 0x62)
    fprintf(f,"%s", to_utf8(0x2584));
  else if (c == 0x63)
    fprintf(f,"%s", to_utf8(0x2594));
  else if (c == 0x64)
    fprintf(f,"%s", to_utf8(0x2581));
  else if (c == 0x65)
    fprintf(f,"%s", to_utf8(0x258e));
  else if (c == 0x66)
    fprintf(f,"%s", to_utf8(0x2592));
  else if (c == 0x67)
    fprintf(f,"%s", to_utf8(0x258a));
  else if (c == 0x68)
    fprintf(f,"%s", to_utf8(0x7f)); // No Unicode equivalent
  else if (c == 0x69)
    fprintf(f,"%s", to_utf8(0x25e4));
  else if (c == 0x6A)
    fprintf(f,"%s", to_utf8(0x258a));
  else if (c == 0x6B)
    fprintf(f,"%s", to_utf8(0x2523));
  else if (c == 0x6C)
    fprintf(f,"%s", to_utf8(0x2597));
  else if (c == 0x6D)
    fprintf(f,"%s", to_utf8(0x2517));
  else if (c == 0x6E)
    fprintf(f,"%s", to_utf8(0x2513));
  else if (c == 0x6F)
    fprintf(f,"%s", to_utf8(0x2582));

  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));
  else if (c == 0x60)
    fprintf(f,"%s", to_utf8(0xA0));

  else
    fprintf(f,"?");

  if (rev) {
    // Reverse off again
    fprintf(f,"%c[0m", 27);
  }
}

int do_screen_shot_ascii(FILE *f)
{
  //  dump_bytes(0,"screen data",screen_data,screen_size);
  get_video_state();
  fprintf(f,"INFO: Screen RAM address = $%07X, Colours=$%02X,$%02X\n",
	  screen_address,vic_regs[0x020],vic_regs[0x021]);
  fprintf(f,"INFO: Screen RAM contents:\n");
  for(int i=0;i<screen_size;i++) {
    if (!(i&0x0f)) fprintf(f,"      $%07X :",screen_address+i);
    fprintf(f," %02X",screen_data[i]);
    if ((i&0xf)==0xf) fprintf(f,"\n");
  }
  if (screen_size&0xf) fprintf(f,"\n");
  fprintf(f,"INFO: VIC-IV Registers:\n");
  for(int i=0;i<0x0400;i++) {
    if (!(i&0x0f)) fprintf(f,"      $%04X :",0xd000+i);
    fprintf(f," %02X",vic_regs[i]);
    if ((i&0xf)==0xf) fprintf(f,"\n");
  }

#ifndef WINDOWS
  // Display a thin border
  fprintf(f,"%c[48;2;%d;%d;%dm", 27,
      ((vic_regs[0x0100 + border_colour] & 0xf) << 4) + ((vic_regs[0x0100 + border_colour] & 0xf0) >> 4),
      ((vic_regs[0x0200 + border_colour] & 0xf) << 4) + ((vic_regs[0x0200 + border_colour] & 0xf0) >> 4),
      ((vic_regs[0x0300 + border_colour] & 0xf) << 4) + ((vic_regs[0x0300 + border_colour] & 0xf0) >> 4));
  for (int x = 0; x < (1 + screen_width + 1); x++)
    fprintf(f," ");
  fprintf(f,"%c[0m\n", 27);

  for (int y = 0; y < screen_rows; y++) {
    //    dump_bytes(0,"row data",&screen_data[y*screen_line_step],screen_width*(1+sixteenbit_mode));

    fprintf(f,"%c[48;2;%d;%d;%dm ", 27,
        ((vic_regs[0x0100 + border_colour] & 0xf) << 4) + ((vic_regs[0x0100 + border_colour] & 0xf0) >> 4),
        ((vic_regs[0x0200 + border_colour] & 0xf) << 4) + ((vic_regs[0x0200 + border_colour] & 0xf0) >> 4),
        ((vic_regs[0x0300 + border_colour] & 0xf) << 4) + ((vic_regs[0x0300 + border_colour] & 0xf0) >> 4));

    for (int x = 0; x < screen_width; x++) {

      int char_background_colour;
      int char_id = 0;
      int char_value = screen_data[y * screen_line_step + x * (1 + sixteenbit_mode)];
      if (sixteenbit_mode)
        char_value |= (screen_data[y * screen_line_step + x * (1 + sixteenbit_mode) + 1] << 8);
      int colour_value = colour_data[y * screen_line_step + x * (1 + sixteenbit_mode)];
      if (sixteenbit_mode)
        colour_value |= (colour_data[y * screen_line_step + x * (1 + sixteenbit_mode) + 1] << 8);
      if (extended_background_mode) {
        char_id = char_value &= 0x3f;
        char_background_colour = vic_regs[0x21 + ((char_value >> 6) & 3)];
      }
      else {
        char_id = char_value & 0x1fff;
        char_background_colour = background_colour;
      }
      int glyph_width_deduct = char_value >> 13;

      // Set foreground and background colours
      int foreground_colour = colour_value & 0xff;
      //      int glyph_flip_vertical=colour_value&0x8000;
      //      int glyph_flip_horizontal=colour_value&0x4000;
      //      int glyph_with_alpha=colour_value&0x2000;
      //      int glyph_goto=colour_value&0x1000;
      int glyph_full_colour = 0;
      //      int glyph_blink=0;
      //      int glyph_underline=0;
      int glyph_bold = 0;
      int glyph_reverse = 0;
      if (viciii_attribs && (!multicolour_mode)) {
        //	glyph_blink=colour_value&0x0010;
        glyph_reverse = colour_value & 0x0020;
        glyph_bold = colour_value & 0x0040;
        //	glyph_underline=colour_value&0x0080;
        if (glyph_bold)
          foreground_colour |= 0x10;
      }
      if (vic_regs[0x54] & 2)
        if (char_id < 0x100)
          glyph_full_colour = 1;
      if (vic_regs[0x54] & 4)
        if (char_id > 0x0FF)
          glyph_full_colour = 1;
      int glyph_4bit = colour_value & 0x0800;
      if (glyph_4bit)
        glyph_full_colour = 1;
      if (colour_value & 0x0400)
        glyph_width_deduct += 8;

      int fg = foreground_colour;
      int bg = char_background_colour;
      if (glyph_reverse) {
        bg = foreground_colour;
        fg = char_background_colour;
      }
      fprintf(f,"%c[48;2;%d;%d;%dm%c[38;2;%d;%d;%dm", 27,
          ((vic_regs[0x0100 + bg] & 0xf) << 4) + ((vic_regs[0x0100 + bg] & 0xf0) >> 4),
          ((vic_regs[0x0200 + bg] & 0xf) << 4) + ((vic_regs[0x0200 + bg] & 0xf0) >> 4),
          ((vic_regs[0x0300 + bg] & 0xf) << 4) + ((vic_regs[0x0300 + bg] & 0xf0) >> 4), 27,
          ((vic_regs[0x0100 + fg] & 0xf) << 4) + ((vic_regs[0x0100 + fg] & 0xf0) >> 4),
          ((vic_regs[0x0200 + fg] & 0xf) << 4) + ((vic_regs[0x0200 + fg] & 0xf0) >> 4),
          ((vic_regs[0x0300 + fg] & 0xf) << 4) + ((vic_regs[0x0300 + fg] & 0xf0) >> 4));

      // Xterm can't display arbitrary graphics, so just mark full-colour chars
      if (glyph_full_colour) {
        fprintf(f,"?");
        if (glyph_4bit)
          fprintf(f,"?");
      }
      else
        print_screencode(f,char_id & 0xff, upper_case);
    }

    fprintf(f,"%c[48;2;%d;%d;%dm ", 27,
        ((vic_regs[0x0100 + border_colour] & 0xf) << 4) + ((vic_regs[0x0100 + border_colour] & 0xf0) >> 4),
        ((vic_regs[0x0200 + border_colour] & 0xf) << 4) + ((vic_regs[0x0200 + border_colour] & 0xf0) >> 4),
        ((vic_regs[0x0300 + border_colour] & 0xf) << 4) + ((vic_regs[0x0300 + border_colour] & 0xf0) >> 4));

    // Set foreground and background colours back to normal at end of each line, before newline
    fprintf(f,"%c[0m\n", 27);
  }
  fprintf(f,"%c[48;2;%d;%d;%dm", 27,
      ((vic_regs[0x0100 + border_colour] & 0xf) << 4) + ((vic_regs[0x0100 + border_colour] & 0xf0) >> 4),
      ((vic_regs[0x0200 + border_colour] & 0xf) << 4) + ((vic_regs[0x0200 + border_colour] & 0xf0) >> 4),
      ((vic_regs[0x0300 + border_colour] & 0xf) << 4) + ((vic_regs[0x0300 + border_colour] & 0xf0) >> 4));
  for (int x = 0; x < (1 + screen_width + 1); x++)
    fprintf(f," ");
  fprintf(f,"%c[0m", 27);

#endif

  fprintf(f,"\n");

  return 0;
}

void get_video_state(void)
{

  //  printf("Calling fetch_ram\n");
  fetch_ram(0xffd3000, 0x0400, vic_regs);
  // printf("Got video regs\n");

  screen_address = vic_regs[0x60] + (vic_regs[0x61] << 8) + (vic_regs[0x62] << 16);
  charset_address = vic_regs[0x68] + (vic_regs[0x69] << 8) + (vic_regs[0x6A] << 16);
  if (charset_address == 0x1000)
    charset_address = 0x2D000;
  if (charset_address == 0x9000)
    charset_address = 0x29000;
  if (charset_address == 0x1800)
    charset_address = 0x2D800;
  if (charset_address == 0x9800)
    charset_address = 0x29800;

  is_pal_mode = (vic_regs[0x6f] & 0x80) ^ 0x80;
  screen_line_step = vic_regs[0x58] + (vic_regs[0x59] << 8);
  colour_address = vic_regs[0x64] + (vic_regs[0x65] << 8);
  screen_width = vic_regs[0x5e];
  upper_case = 2 - (vic_regs[0x18] & 2);
  screen_rows = 1 + vic_regs[0x7B];
  sixteenbit_mode = vic_regs[0x54] & 1;
  screen_size = screen_line_step * screen_rows * (1 + sixteenbit_mode);
  charset_size = 2048;
  extended_background_mode = vic_regs[0x11] & 0x40;
  multicolour_mode = vic_regs[0x16] & 0x10;
  bitmap_mode = vic_regs[0x11] & 0x20;

  if (0) printf("bitmap_mode=%d, multicolour_mode=%d, extended_background_mode=%d\n", bitmap_mode, multicolour_mode,
      extended_background_mode);

  border_colour = vic_regs[0x20];
  background_colour = vic_regs[0x21];

  current_physical_raster = vic_regs[0x52] + ((vic_regs[0x53] & 0x3) << 8);
  //  next_raster_interrupt = vic_regs[0x79] + ((vic_regs[0x7A] & 0x3) << 8);
  if (!(vic_regs[0x53] & 0x80)) {
    // Raster compare is VIC-II raster, not physical, so double it
    current_physical_raster *= 2;
  }
  if (!(vic_regs[0x7A] & 0x80)) {
    // Raster compare is VIC-II raster, not physical, so double it
    //    next_raster_interrupt *= 2;
  }
  //  raster_interrupt_enabled = vic_regs[0x1a] & 1;

  y_scale = vic_regs[0x5B];
  h640 = vic_regs[0x31] & 0x80;
  v400 = vic_regs[0x31] & 0x08;
  viciii_attribs = vic_regs[0x31] & 0x20;
  chargen_x = (vic_regs[0x4c] + (vic_regs[0x4d] << 8)) & 0xfff;
  chargen_x -= SCREEN_POSITION; // adjust for pipeline delay
  chargen_y = (vic_regs[0x4e] + (vic_regs[0x4f] << 8)) & 0xfff;

  top_border_y = (vic_regs[0x48] + (vic_regs[0x49] << 8)) & 0xfff;
  bottom_border_y = (vic_regs[0x4A] + (vic_regs[0x4B] << 8)) & 0xfff;
  // side border width is measured in pixelclock ticks, so divide by 3
  side_border_width = ((vic_regs[0x5C] + (vic_regs[0x5D] << 8)) & 0xfff);
  left_border = side_border_width - SCREEN_POSITION; // Adjust for screen position
  right_border = 800 - side_border_width - SCREEN_POSITION;
  x_scale_120 = vic_regs[0x5A];
  // x_scale is actually in 120ths of a pixel.
  // so 120 = 1 pixel wide
  // 60 = 2 pixels wide
  x_step = x_scale_120 / 120.0;
  if (!h640)
    x_step /= 2;
  //  printf("x_scale_120=$%02x\n", x_scale_120);

  // Check if we are in 16-bit text mode, without full-colour chars for char IDs > 255
  if (sixteenbit_mode && (!(vic_regs[0x54] & 4))) {
    charset_size = 8192 * 8;
  }

  if (screen_size > MAX_SCREEN_SIZE) {
    fprintf(stderr, "ERROR: Implausibly large screen size of %d bytes: %d rows, %d columns\n", screen_size, screen_line_step,
        screen_rows);
    exit(-1);
  }

  if (0) {
    fprintf(stderr, "Screen is at $%07x, width= %d chars, height= %d rows, size=%d bytes, uppercase=%d, line_step= %d\n",
	    screen_address, screen_width, screen_rows, screen_size, upper_case, screen_line_step);
    fprintf(stderr, "charset_address=$%x\n", charset_address);
  }

  //  fprintf(stderr, "Fetching screen data,");
  fflush(stderr);
  fetch_ram(screen_address, screen_size, screen_data);
  //  fprintf(stderr, "colour data,");
  fflush(stderr);
  fetch_ram(0xff80000 + colour_address, screen_size, colour_data);

  //  fprintf(stderr, "charset");
  fflush(stderr);
  fetch_ram(charset_address, charset_size, char_data);

  //  fprintf(stderr, "\nDone\n");

  return;
}

void paint_screen_shot(void)
{
  printf("Painting rasters %d -- %d\n", min_y, max_y);

  // Now render the text display
  int y_position = chargen_y;
  for (int cy = 0; cy < screen_rows; cy++) {
    if (y_position >= (is_pal_mode ? 576 : 480))
      break;

    int x_position = chargen_x;

    int xc = 0;

    int is_foreground = 0;
    int transparent_background = 0;

    for (int cx = 0; cx < screen_width; cx++) {

      // printf("Rendering char (%d,%d) at (%d,%d)\n",cx,cy,x_position,y_position);
      //      int char_background_colour;
      int char_id = 0;
      int char_value = screen_data[cy * screen_line_step + cx * (1 + sixteenbit_mode)];
      if (sixteenbit_mode)
        char_value |= (screen_data[cy * screen_line_step + cx * (1 + sixteenbit_mode) + 1] << 8);
      int colour_value = colour_data[cy * screen_line_step + cx * (1 + sixteenbit_mode)];
      if (sixteenbit_mode) {
        colour_value = colour_value << 8;
        colour_value |= (colour_data[cy * screen_line_step + cx * (1 + sixteenbit_mode) + 1]);
      }
      if (extended_background_mode) {
        char_id = char_value &= 0x3f;
        //	char_background_colour=vic_regs[0x21+((char_value>>6)&3)];
      }
      else {
        char_id = char_value & 0x1fff;
        //	char_background_colour=background_colour;
      }
      int glyph_width_deduct = char_value >> 13;

      // Set foreground and background colours
      int foreground_colour = colour_value & 0x0f;
      int glyph_flip_vertical = colour_value & 0x8000;
      int glyph_flip_horizontal = colour_value & 0x4000;
      int glyph_with_alpha = colour_value & 0x2000;
      int glyph_goto = colour_value & 0x1000;
      int glyph_full_colour = 0;
      // int glyph_blink=0;
      int glyph_underline = 0;
      int glyph_bold = 0;
      int glyph_reverse = 0;
      if (viciii_attribs && (!multicolour_mode)) {
        // glyph_blink=colour_value&0x0010;
        glyph_reverse = colour_value & 0x0020;
        glyph_bold = colour_value & 0x0040;
        glyph_underline = colour_value & 0x0080;
        if (glyph_bold)
          foreground_colour |= 0x10;
      }
      if (multicolour_mode)
        foreground_colour = colour_value & 0xff;

      if (bitmap_mode) {
        char_value = screen_data[cy * screen_line_step + cx * (1 + sixteenbit_mode)];
        foreground_colour = char_value & 0xf;
        background_colour = char_value >> 4;
        bitmap_multi_colour = colour_data[cy * screen_line_step + cx * (1 + sixteenbit_mode)];
        if (0)
          printf("Bitmap fore/background colours are $%x / $%x\n", foreground_colour, background_colour);
      }

      if (vic_regs[0x54] & 2)
        if (char_id < 0x100)
          glyph_full_colour = 1;
      if (vic_regs[0x54] & 4)
        if (char_id > 0x0FF)
          glyph_full_colour = 1;
      int glyph_4bit = colour_value & 0x0800;
      if (colour_value & 0x0400)
        glyph_width_deduct += 8;

      // Lookup the char data, and work out how many pixels we need to paint
      int glyph_width = 8;
      if (glyph_4bit)
        glyph_width = 16;
      glyph_width -= glyph_width_deduct;

      // For each row of the glyph
      for (int yy = 0; yy < 8; yy++) {
        int glyph_row = yy;
        if (glyph_flip_vertical)
          glyph_row = 7 - glyph_row;

        unsigned char glyph_data[8];

        if (glyph_full_colour) {
          // Get 8 bytes of data
          fetch_ram(char_id * 64 + glyph_row * 8, 8, glyph_data);
        }
        else {
          // Use existing char data we have already fetched
          // printf("Chardata for char $%03x = $%02x\n",char_id,char_data[char_id*8+glyph_row]);
          if (!bitmap_mode) {
            for (int i = 0; i < 8; i++)
              if ((char_data[char_id * 8 + glyph_row] >> i) & 1)
                glyph_data[i] = 0xff;
              else
                glyph_data[i] = 0;
          }
          else {
            int addr = charset_address & 0xfe000;
            addr += cx * 8 + cy * 320 + glyph_row;
            if (h640) {
              addr = charset_address & 0xfc000;
              addr += cx * 8 + cy * 640 + glyph_row;
            }
            unsigned char pixels;
            fetch_ram(addr, 1, &pixels);
            if (0)
              printf("Reading bitmap data from $%x = $%02x, charset_address=$%x\n", addr, pixels, charset_address);
            for (int i = 0; i < 8; i++)
              if ((pixels >> i) & 1)
                glyph_data[i] = 0xff;
              else
                glyph_data[i] = 0;
          }
        }

        if (glyph_flip_horizontal) {
          unsigned char b[8];
          for (int i = 0; i < 8; i++)
            b[i] = glyph_data[i];
          for (int i = 0; i < 8; i++)
            glyph_data[i] = b[7 - i];
        }

        if (glyph_reverse) {
          for (int i = 0; i < 8; i++)
            glyph_data[i] = 0xff - glyph_data[i];
        }

        // XXX Do blink with PNG animation?

        if (glyph_underline && (yy == 7)) {
          for (int i = 0; i < 8; i++)
            glyph_data[i] = 0xff;
        }

        xc = 0;
        if (glyph_goto) {
          x_position = chargen_x + (char_value & 0x3ff);
          transparent_background = colour_value & 0x8000;
        }
        else
          for (float xx = 0; xx < glyph_width; xx += x_step) {
            int r = mega65_rgb(background_colour, 0);
            int g = mega65_rgb(background_colour, 1);
            int b = mega65_rgb(background_colour, 2);

            is_foreground = 0;

            if (glyph_4bit) {
              // 16-colour 4 bits per pixel
              int c = glyph_data[((int)xx) / 2];
              if (((int)xx) & 1)
                c = c >> 4;
              else
                c = c & 0xf;
              if (glyph_with_alpha) {
                // Alpha blended pixels:
                // Here we blend the foreground and background colours we already know
                // according to the alpha value
                int a = c;
                r = (mega65_rgb(foreground_colour, 0) * a + mega65_rgb(background_colour, 0) * (15 - a)) >> 8;
                g = (mega65_rgb(foreground_colour, 1) * a + mega65_rgb(background_colour, 1) * (15 - a)) >> 8;
                b = (mega65_rgb(foreground_colour, 2) * a + mega65_rgb(background_colour, 2) * (15 - a)) >> 8;
              }
              else {
                r = mega65_rgb(c, 0);
                g = mega65_rgb(c, 1);
                b = mega65_rgb(c, 2);
              }
              if (c)
                is_foreground = 1;
            }
            else if (glyph_full_colour) {
              // 256-colour 8 bits per pixel
              if (glyph_with_alpha) {
                // Alpha blended pixels:
                // Here we blend the foreground and background colours we already know
                // according to the alpha value
                int a = glyph_data[(int)xx];
                r = (mega65_rgb(foreground_colour, 0) * a + mega65_rgb(background_colour, 0) * (255 - a)) >> 8;
                g = (mega65_rgb(foreground_colour, 1) * a + mega65_rgb(background_colour, 1) * (255 - a)) >> 8;
                b = (mega65_rgb(foreground_colour, 2) * a + mega65_rgb(background_colour, 2) * (255 - a)) >> 8;
                if (foreground_colour)
                  is_foreground = 1;
              }
              else {
                r = mega65_rgb(glyph_data[(int)xx], 0);
                g = mega65_rgb(glyph_data[(int)xx], 1);
                b = mega65_rgb(glyph_data[(int)xx], 2);
              }
            }
            else if (multicolour_mode && ((foreground_colour & 8) || bitmap_mode)) {
              // Multi-colour normal char
              int bits = 0;
              if (glyph_data[6 - (((int)xx) & 0x6)])
                bits |= 1;
              if (glyph_data[7 - (((int)xx) & 0x6)])
                bits |= 2;
              int colour;
              if (!bitmap_mode) {
                switch (bits) {
                case 0:
                  colour = vic_regs[0x21];
                  break; // background colour
                case 1:
                  is_foreground = 1;
                  colour = vic_regs[0x22];
                  break; // multi colour 1
                case 2:
                  is_foreground = 1;
                  colour = vic_regs[0x23];
                  break; // multi colour 2
                case 3:
                  is_foreground = 1;
                  colour = foreground_colour & 7;
                  break; // foreground colour
                }
              }
              else {
                switch (bits) {
                case 0:
                  is_foreground = 1;
                  colour = vic_regs[0x21];
                  break;
                case 1:
                  colour = background_colour;
                  break;
                case 2:
                  is_foreground = 1;
                  colour = foreground_colour;
                  break;
                case 3:
                  is_foreground = 1;
                  colour = bitmap_multi_colour & 0xf;
                  break;
                }
              }
              r = mega65_rgb(colour, 0);
              g = mega65_rgb(colour, 1);
              b = mega65_rgb(colour, 2);
            }
            else {
              // Mono normal char
              if (glyph_data[7 - (int)xx]) {
                r = mega65_rgb(foreground_colour, 0);
                g = mega65_rgb(foreground_colour, 1);
                b = mega65_rgb(foreground_colour, 2);
                //	      printf("Foreground pixel. colour = $%02x = #%02x%02x%02x\n",
                //		     foreground_colour,b,g,r);
                is_foreground = 1;
              }
            }

            // Actually draw the pixels
            for (int yc = 0; yc <= y_scale; yc++) {
              if (((y_position + yc) < bottom_border_y) && ((y_position + yc) >= top_border_y)
                  && ((x_position + xc) < right_border) && ((x_position + xc) >= left_border))
                if (is_foreground || (!transparent_background)) {
                  set_pixel(x_position + xc, y_position + yc + yy * (1 + y_scale), r, g, b);
                }
            }

            xc++;
          }
      }

      // Advance for width of the glyph
      //      printf("Char was %d pixels wide.\n",xc);
      x_position += xc;
    }
    y_position += 8 * (1 + y_scale);
  }

  return;
}

int do_screen_shot(char *filename)
{

  get_video_state();

  //  printf("Got video state.\n");

  //  printf("Got ASCII screenshot.\n");

  FILE* f = NULL;
  f = fopen(filename, "wb");
  if (!f) {
    fprintf(stderr, "ERROR: Could not open '%s' for writing.\n",filename);
    return -1;
  }
  // printf("Rendering pixel-exact version to %s...\n", filename);

  png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
  if (!png_ptr) {
    fprintf(stderr, "ERROR: Could not creat PNG structure.\n");
    return -1;
  }

  png_infop info_ptr = png_create_info_struct(png_ptr);
  if (!info_ptr) {
    fprintf(stderr, "ERROR: Could not creat PNG info structure.\n");
    return -1;
  }

  png_init_io(png_ptr, f);

  // Set image size based on PAL or NTSC video mode
  png_set_IHDR(png_ptr, info_ptr, 720, is_pal_mode ? 576 : 480, 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
      PNG_COMPRESSION_TYPE_BASE, PNG_FILTER_TYPE_BASE);

  png_write_info(png_ptr, info_ptr);

  // Allocate frame buffer for image, and set all pixels to the border colour by default
  // printf("Allocating PNG frame buffer...\n");
  for (int y = 0; y < (is_pal_mode ? 576 : 480); y++) {
    png_rows[y] = (png_bytep)malloc(3 * 720 * sizeof(png_byte));
    if (!png_rows[y]) {
      perror("malloc()");
      return -1;
    }
    // Set all pixels to border colour
    for (int x = 0; x < 720; x++) {
      ((unsigned char*)png_rows[y])[x * 3 + 0] = mega65_rgb(border_colour, 0);
      ((unsigned char*)png_rows[y])[x * 3 + 1] = mega65_rgb(border_colour, 1);
      ((unsigned char*)png_rows[y])[x * 3 + 2] = mega65_rgb(border_colour, 2);
    }
  }

  printf("Rendering screen...\n");

  // Start by drawing the non-border area
  for (int y = top_border_y; y < bottom_border_y && (y < (is_pal_mode ? 576 : 480)); y++) {
    for (int x = left_border; x < right_border; x++) {
      ((unsigned char*)png_rows[y])[x * 3 + 0] = mega65_rgb(background_colour, 0);
      ((unsigned char*)png_rows[y])[x * 3 + 1] = mega65_rgb(background_colour, 1);
      ((unsigned char*)png_rows[y])[x * 3 + 2] = mega65_rgb(background_colour, 2);
    }
  }

 {
    //     printf("Video mode does not use raster splits. Drawing normally.\n");
    min_y = 0;
    max_y = is_pal_mode ? 576 : 480;
    paint_screen_shot();
  }

  //  printf("Writing out PNG frame buffer...\n");
  // Write out each row of the PNG
  for (int y = 0; y < (is_pal_mode ? 576 : 480); y++)
    png_write_row(png_ptr, png_rows[y]);

  png_write_end(png_ptr, NULL);

  fclose(f);

  printf("Wrote screen capture to %s...\n", filename);
  // start_cpu();
  // exit(0);

  return 0;
}
