#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <stdlib.h>

char *describe_address(unsigned int addr);
char *describe_address_label(unsigned int addr);

// By default we log to stderr
FILE *logfile=NULL;
char logfilename[8192]="";
#define TESTLOGFILE "/tmp/hyppotest.tmp"

int test_passes=0;
int test_fails=0;
char test_name[1024]="unnamed test";
char safe_name[1024]="unnamed_test";

unsigned char breakpoints[65536];

#define CHIPRAM_SIZE (384*1024)
#define HYPPORAM_SIZE (16*1024)

// Current memory state
unsigned char chipram[CHIPRAM_SIZE];
unsigned char hypporam[HYPPORAM_SIZE];

// Memory state before
unsigned char chipram_before[CHIPRAM_SIZE];
unsigned char hypporam_before[HYPPORAM_SIZE];

// Expected memory state
unsigned char chipram_expected[CHIPRAM_SIZE];
unsigned char hypporam_expected[HYPPORAM_SIZE];

// Instructions which modified the memory location last
unsigned int chipram_blame[CHIPRAM_SIZE];
unsigned int hypporam_blame[HYPPORAM_SIZE];

#define MAX_HYPPO_SYMBOLS HYPPORAM_SIZE
typedef struct hyppo_symbol {
  char *name;
  unsigned int addr;
} hyppo_symbol;
hyppo_symbol *sym_by_addr[65536]={NULL};
hyppo_symbol hyppo_symbols[MAX_HYPPO_SYMBOLS];
int hyppo_symbol_count=0;  

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
};

struct termination_conditions {
  // Indicates that execution has terminated
  int done;

  // Indicates that an error was detected
  int error;
  
  // Terminate when number of RTS (minus JSRs) is encountered
  int rts;
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

struct cpu cpu;
struct cpu cpu_before;

// Instruction log
typedef struct instruction_log {
  unsigned int pc;
  unsigned char bytes[6];
  unsigned char len;
  unsigned char dup;
  struct regs regs;
  unsigned int count;
} instruction_log;
#define MAX_LOG_LENGTH (1024*1024)
instruction_log *cpulog[MAX_LOG_LENGTH];
int cpulog_len=0;

#define INFINITE_LOOP_THRESHOLD 65536

instruction_log *lastataddr[65536]={NULL};

int rel8_delta(unsigned char c)
{
  if (c<0x80) return c;
  return c-0x100;
}

void disassemble_rel8(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%04X",log->pc+1+rel8_delta(log->bytes[1]));
}

void disassemble_imm(FILE *f,struct instruction_log *log)
{
  fprintf(f,"#$%02X",log->bytes[1]);
}

void disassemble_abs(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X",log->bytes[2],log->bytes[1]);
}

void disassemble_absx(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X,X",log->bytes[2],log->bytes[1]);
}

void disassemble_absy(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X,Y",log->bytes[2],log->bytes[1]);
}


void disassemble_instruction(FILE *f,struct instruction_log *log)
{
  
  if (!log->len) return;
  switch(log->bytes[0]) {
  case 0x03: fprintf(f,"SEE"); break;
  case 0x0c: fprintf(f,"TSB "); disassemble_abs(f,log); break;
  case 0x18: fprintf(f,"CLC"); break;
  case 0x1A: fprintf(f,"INC"); break;
  case 0x1c: fprintf(f,"TRB "); disassemble_abs(f,log); break;
  case 0x20: fprintf(f,"JSR "); disassemble_abs(f,log); break;
  case 0x29: fprintf(f,"AND "); disassemble_imm(f,log); break;
  case 0x2B: fprintf(f,"TYS"); break;
  case 0x38: fprintf(f,"SEC"); break;
  case 0x3A: fprintf(f,"DEC"); break;
  case 0x40: fprintf(f,"RTI"); break;
  case 0x4C: fprintf(f,"JMP "); disassemble_abs(f,log); break;
  case 0x5b: fprintf(f,"TAB"); break;
  case 0x5c: fprintf(f,"MAP"); break;
  case 0x60: fprintf(f,"RTS"); break;
  case 0x69: fprintf(f,"ADC "); disassemble_imm(f,log); break;
  case 0x78: fprintf(f,"SEI"); break;
  case 0x8A: fprintf(f,"TXA"); break;
  case 0x8d: fprintf(f,"STA "); disassemble_abs(f,log); break;
  case 0x8e: fprintf(f,"STX "); disassemble_abs(f,log); break;
  case 0x90: fprintf(f,"BCC "); disassemble_rel8(f,log); break;
  case 0x99: fprintf(f,"STA "); disassemble_absy(f,log); break;
  case 0x9A: fprintf(f,"TXS"); break;
  case 0x9d: fprintf(f,"STA "); disassemble_absx(f,log); break;
  case 0xa0: fprintf(f,"LDY "); disassemble_imm(f,log); break;
  case 0xa2: fprintf(f,"LDX "); disassemble_imm(f,log); break;
  case 0xa3: fprintf(f,"LDZ "); disassemble_imm(f,log); break;
  case 0xa9: fprintf(f,"LDA "); disassemble_imm(f,log); break;
  case 0xAA: fprintf(f,"TAX"); break;
  case 0xad: fprintf(f,"LDA "); disassemble_abs(f,log); break;
  case 0xB0: fprintf(f,"BCS "); disassemble_rel8(f,log); break;
  case 0xC0: fprintf(f,"CPY "); disassemble_imm(f,log); break;
  case 0xC8: fprintf(f,"INY"); break;
  case 0xC9: fprintf(f,"CMP "); disassemble_imm(f,log); break;
  case 0xd0: fprintf(f,"BNE "); disassemble_rel8(f,log); break;
  case 0xD8: fprintf(f,"CLD"); break;
  case 0xE8: fprintf(f,"INX"); break;
  case 0xea: fprintf(f,"EOM"); break;
  case 0xf0: fprintf(f,"BEQ "); disassemble_rel8(f,log); break;
  }
  
}

int show_recent_instructions(FILE *f,char *title,int first_instruction, int count,
			     unsigned int highlight_address)
{
  int last_was_dup=0;
  fprintf(f,"INFO: %s\n",title);
  if (first_instruction<0) first_instruction=0;
  for(int i=first_instruction;count>0&&i<cpulog_len;count--,i++) {
    if (cpulog[i]->dup&&(i>first_instruction)) {
      if (!last_was_dup) fprintf(f,"                 ... duplicated instructions omitted ...\n");
      last_was_dup=1;
    } else {
      last_was_dup=0;
      if (cpulog_len-i-1) fprintf(f,"I-%-7d ",cpulog_len-i-1);
      else fprintf(f,"  >>>     ");
      if (cpulog[i]->pc==highlight_address)
	fprintf(f,"  >>>  "); else fprintf(f,"       ");
      if (cpulog[i]->count>1)
	fprintf(f,"$%04X : x%-6d : ",cpulog[i]->pc,cpulog[i]->count);
      else
	fprintf(f,"$%04X :         : ",cpulog[i]->pc);
      fprintf(f,"A:%02X ",cpulog[i]->regs.a);
      fprintf(f,"X:%02X ",cpulog[i]->regs.x);
      fprintf(f,"Y:%02X ",cpulog[i]->regs.y);
      fprintf(f,"Z:%02X ",cpulog[i]->regs.z);
      fprintf(f,"SP:%02X%02X ",cpulog[i]->regs.sph,cpulog[i]->regs.spl);
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

      fprintf(f,"%32s : ",describe_address_label(cpulog[i]->regs.pc));

      for(int j=0;j<6;j++) {
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

char *describe_address_label(unsigned int addr)
{
  struct hyppo_symbol *s=NULL;
  
  for(int i=0;i<hyppo_symbol_count;i++) {
    // Check for exact address match
    if (addr==hyppo_symbols[i].addr) s=&hyppo_symbols[i];
    // Check for best approximate match
    if (s&&s->addr<hyppo_symbols[i].addr&&addr>hyppo_symbols[i].addr)
      s=&hyppo_symbols[i];
    if ((!s)&&addr>hyppo_symbols[i].addr)
      s=&hyppo_symbols[i];
  }
  
  if (s) {
    if (s->addr==addr)  snprintf(addr_description,8192,"%s",s->name);
    else  snprintf(addr_description,8192,"%s+%d",s->name,addr-s->addr);
  } else 
    addr_description[0]=0;
  return addr_description;
}

void cpu_log_reset(void)
{
  for(int i=0;i<cpulog_len;i++) free(cpulog[i]);
  cpulog_len=0;
}

void cpu_stash_ram(void)
{
  // Remember the RAM contents before calling a routine
  bcopy(chipram_before,chipram,CHIPRAM_SIZE);
  bcopy(hypporam_before,hypporam,HYPPORAM_SIZE);
}

unsigned char read_memory(struct cpu *cpu,unsigned int addr)
{
  // XXX Should support banking etc. For now it is _really_ stupid.
  if (addr>=0x8000&&addr<0xc000) {
    return hypporam[addr-0x8000];
  } else {
    return chipram[addr];
  }
  
}

int write_mem(struct cpu *cpu, unsigned int addr,unsigned char value)
{
  // XXX Should support banking etc. For now it is _really_ stupid.
  if (addr>=0x8000&&addr<0xc000) {
    hypporam[addr-0x8000]=value;
    hypporam_blame[addr-0x8000]=cpu->instruction_count;
  } else {
    chipram[addr]=value;
    chipram_blame[addr]=cpu->instruction_count;
  }
  return 0;
}

unsigned int addr_abs(struct instruction_log *log)
{
  return log->bytes[1]+(log->bytes[2]<<8);
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

#define MEM_WRITE(CPU,ADDR,VALUE) if (write_mem(CPU,ADDR,VALUE)) { fprintf(stderr,"ERROR: Memory write failed to %s.\n",describe_address(ADDR)); return -1; }

unsigned char stack_pop(struct cpu *cpu)
{
  int addr=(cpu->regs.sph<<8)+cpu->regs.spl;
  addr++;
  cpu->regs.spl++;
  unsigned char c=read_memory(cpu,addr);
  //  fprintf(logfile,"NOTE: Popping $%02X from the stack\n",c);
  if (!(addr&0xff)) {
    if (!(cpu->regs.flags&FLAG_E))
      cpu->regs.sph++;
    else
      cpu->stack_underflow=1;
    if (!addr) cpu->stack_underflow=1;
  }
  return c;
}

int stack_push(struct cpu *cpu,unsigned char v)
{
  //  fprintf(logfile,"NOTE: Pushing $%02X onto the stack\n",v);
  int addr=(cpu->regs.sph<<8)+cpu->regs.spl;
  MEM_WRITE(cpu,addr,v);
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
    fprintf(logfile,"INFO: Breakpoint at $%04x triggered.\n",cpu->regs.pc);
    cpu->term.done=1;
  }
  
  for(int i=0;i<6;i++) {
    log->bytes[i]=read_memory(cpu,cpu->regs.pc+i);
  }
  switch(log->bytes[0]) {
  case 0x03: // SEE
    cpu->regs.flags|=FLAG_E;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x0c: // TSB $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    v|=cpu->regs.a;
    MEM_WRITE(cpu,addr_abs(log),v);
    update_nz(v);
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
  case 0x1c: // TRB $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    v=read_memory(cpu,addr_abs(log));
    v&=~cpu->regs.a;
    MEM_WRITE(cpu,addr_abs(log),v);
    update_nz(v);
    break;
  case 0x20: // JSR $nnnn
    stack_push(cpu,(cpu->regs.pc+2)>>8);
    stack_push(cpu,cpu->regs.pc+2);
    cpu->regs.pc=addr_abs(log);
    log->len=3;
    break;
  case 0x29: // AND #$nn
    cpu->regs.a&=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x2b: // TYS
    cpu->regs.sph=cpu->regs.y;
    cpu->regs.pc++;
    log->len=1;
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
  case 0x4c: // JMP $nnnn
    cpu->regs.pc=addr_abs(log);
    log->len=3;
    break;
  case 0x5b: // TAB
    cpu->regs.b=cpu->regs.a;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x5c: // MAP
    // XXX -- Not implemented
    cpu->regs.pc++;
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
    cpu->regs.pc=stack_pop(cpu);
    cpu->regs.pc|=stack_pop(cpu)<<8;
    cpu->regs.pc++;
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
  case 0x78: // SEI
    cpu->regs.flags|=FLAG_I;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x8a: // TXA
    cpu->regs.a=cpu->regs.x;
    update_nz(cpu->regs.a);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x8d: // STA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE(cpu,addr_abs(log),cpu->regs.a);
    break;
  case 0x8e: // STX $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE(cpu,addr_abs(log),cpu->regs.x);
    break;
  case 0x90: // BCC $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_C)
      cpu->regs.pc+=2;
    else
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    break;
  case 0x99: // STA $xxxx,Y
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE(cpu,addr_absy(cpu,log),cpu->regs.a);
    break;
  case 0x9a: // TXS
    cpu->regs.spl=cpu->regs.x;
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0x9d: // STA $xxxx,X
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE(cpu,addr_absx(cpu,log),cpu->regs.a);
    break;
  case 0xa0: // LDY #$nn
    cpu->regs.y=log->bytes[1];
    update_nz(cpu->regs.y);
    log->len=2;
    cpu->regs.pc+=2;
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
  case 0xa9: // LDA #$nn
    cpu->regs.a=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xaa: // TAX
    cpu->regs.x=cpu->regs.a;
    update_nz(cpu->regs.x);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xad: // LDA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.a=read_memory(cpu,addr_abs(log));
    update_nz(cpu->regs.a);
    break;
  case 0xB0: // BCS $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_C)
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    else
      cpu->regs.pc+=2;
    break;
  case 0xC0: // CPY #$nn
    v=cpu->regs.y+log->bytes[1];
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xC8: // INY
    cpu->regs.y++;
    update_nz(cpu->regs.y);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xC9: // CMP #$nn
    v=cpu->regs.a+log->bytes[1];
    if (cpu->regs.flags&FLAG_C) v++;
    update_nvzc(v);
    log->len=2;
    cpu->regs.pc+=2;
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
  case 0xE8: // INX
    cpu->regs.x++;
    update_nz(cpu->regs.x);
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xea: // EOM / NOP
    cpu->regs.pc++;
    log->len=1;
    break;
  case 0xf0: // BEQ $rr
    log->len=2;
    if (cpu->regs.flags&FLAG_Z)
      cpu->regs.pc+=2+rel8_delta(log->bytes[1]);
    else
      cpu->regs.pc+=2;
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

  fprintf(f,">>> Calling routine @ $%04X",addr);
  if (sym_by_addr[addr]) {
    fprintf(f," (%s)",sym_by_addr[addr]->name);
  }
  fprintf(f,"\n");

  // Remember the initial CPU state
  cpu_stash_ram();
  cpu_before=cpu;

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
      fprintf(f,"ERROR: Exception occurred execting instruction at %s\n       Aborted.\n",
	      describe_address(cpu.regs.pc));
      show_recent_instructions(f,"Instructions leading up to the exception",
			       cpulog_len-16,16,cpu.regs.pc);
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
				 cpulog_len-lastataddr[cpu.regs.pc]->count-30,32,addr);
	return -1;
      }
    } else lastataddr[cpu.regs.pc]=log;
    
  }
  if (cpulog_len==MAX_LOG_LENGTH) {
    cpu.term.error=1;   
    fprintf(stderr,"ERROR: CPU instruction log filled.  Maybe a problem with the called routine?\n");
    return -1;
  }
  if (cpu.term.done) {
    fprintf(logfile,"NOTE: Execution ended.\n");
  }
  
  return 0;
}

#define COMPARE_REG(REG,Reg) if (cpu->regs.Reg!=cpu_before.regs.Reg) { fprintf(f,"ERROR: Register "REG" contains $%02X instead of $%02X\n",cpu->regs.Reg,cpu_before.regs.Reg); cpu->term.error=1; /* XXX show instruction that set it */ }

#define COMPARE_REG16(REG,Reg) if (cpu->regs.Reg!=cpu_before.regs.Reg) { fprintf(f,"ERROR: Register "REG" contains $%04X instead of $%04X\n",cpu->regs.Reg,cpu_before.regs.Reg); cpu->term.error=1; /* XXX show instruction that set it */ }

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

int compare_ram_contents(FILE *f, struct cpu *cpu)
{
  int errors=0;
  
  for(int i=0;i<CHIPRAM_SIZE;i++) {
    if (chipram[i]!=chipram_before[i]) {
      errors++;
    }
  }
  for(int i=0;i<HYPPORAM_SIZE;i++) {
    if (hypporam[i]!=hypporam_before[i]) {
      errors++;
    }
  }

  if (errors) {
    fprintf(f,"ERROR: %d memory locations contained unexpected values.\n",errors);
    cpu->term.error=1;
    
    int displayed=0;
    
    for(int i=0;i<CHIPRAM_SIZE;i++) {
      if (chipram[i]!=chipram_before[i]) {
	fprintf(f,"ERROR: Saw $%02X at %s, but expected to see $%02X\n",
		chipram[i],describe_address(i),chipram_before[i]);
	int first_instruction=chipram_blame[i]-3;
	if (first_instruction<0) first_instruction=0;
	show_recent_instructions(f,"Instructions leading to this value being written",
				 first_instruction,4,-1);
	displayed++;
      }
      if (displayed>=100) break;
    }
    for(int i=0;i<HYPPORAM_SIZE;i++) {
      if (hypporam[i]!=hypporam_before[i]) {
	fprintf(f,"ERROR: Saw $%02X at %s, but expected to see $%02x\n",
		hypporam[i],describe_address(i+0x8000),hypporam_before[i]);
	int first_instruction=hypporam_blame[i]-3;
	if (first_instruction<0) first_instruction=0;
	show_recent_instructions(f,"Instructions leading to this value being written",
				 first_instruction,4,-1);      
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

void machine_init(struct cpu *cpu)
{
  // Initialise CPU staet
  bzero(cpu,sizeof(struct cpu));
  cpu->regs.flags=FLAG_E|FLAG_I;

  bzero(breakpoints,sizeof(breakpoints));
  
  bzero(&cpu_before,sizeof(struct cpu));
  cpu_before.regs.flags=FLAG_E|FLAG_I;
  
  // Clear chip RAM
  bzero(chipram_before,CHIPRAM_SIZE);
  // Clear Hypervisor RAM
  bzero(hypporam_before,HYPPORAM_SIZE);

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
    show_recent_instructions(logfile,"Complete instruction log follows",0,cpulog_len,-1);
    fprintf(logfile,"FAIL: Test failed.\n");
    printf("\r[FAIL] %s\n",test_name);
  } else {
    snprintf(cmd,8192,"mv %s PASS.%s",TESTLOGFILE,safe_name);
    test_passes++;

    show_recent_instructions(logfile,"Complete instruction log follows",0,cpulog_len,-1);
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
  int b=fread(hypporam_before,1,HYPPORAM_SIZE,f);
  if (b!=HYPPORAM_SIZE) {
    fprintf(logfile,"ERROR: Read only %d of %d bytes from HICKUP file.\n",b,HYPPORAM_SIZE);
    return -1;
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

int resolve_value(char *in)
{
  int v;
  char label[1024];
  int delta=0;
  
  // Hex is the easy case
  if (sscanf(in,"$%x",&v)==1) return v;

  // Check for label with optional +delta
  if (sscanf(in,"%[^+]+%d",label,&delta)==2) ;
  else if (sscanf(in,"%[^-]-%d",label,&delta)==2) ;
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
    fprintf(logfile,"ERROR: Cannot call find non-existent symbol '%s'\n",label);
    cpu.term.error=1;
    return 0;
  } else {
    v=hyppo_symbols[i].addr+delta;
    return v;
  }
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
    unsigned int addr;
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
	bzero(&cpu.term,sizeof(cpu.term));
	cpu.term.rts=1; // Terminate on net RTS from routine
	cpu_call_routine(logfile,hyppo_symbols[i].addr);
      }
    }
    else if (sscanf(line,"jsr $%x",&addr)==1) {
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.rts=1; // Terminate on net RTS from routine
      cpu_call_routine(logfile,addr);
    } else if (sscanf(line,"jmp %s",routine)==1) {
      int i;
      cpu.term.rts=0;
      for(i=0;i<hyppo_symbol_count;i++) {
	if (!strcmp(routine,hyppo_symbols[i].name)) break;
      }
      if (i==hyppo_symbol_count) {
	fprintf(logfile,"ERROR: Cannot call non-existent routine '%s'\n",routine);
	cpu.term.error=1;
      } else {
	bzero(&cpu.term,sizeof(cpu.term));
	cpu_call_routine(logfile,hyppo_symbols[i].addr);
      }
    }
    else if (sscanf(line,"jmp $%x",&addr)==1) {
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.rts=0;
      cpu_call_routine(logfile,addr);
    }  else if (!strncasecmp(line,"check registers",strlen("check registers"))) {
      // Check registers for changes
      compare_register_contents(logfile,&cpu);
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
    } else if (sscanf(line,"breakpoint %s",routine)==1) {
      breakpoints[resolve_value(routine)]=1;
      fprintf(logfile,"INFO: Breakpoint set at %s ($%04x)\n",routine,resolve_value(routine));
    } else if (sscanf(line,"expect %s = %s",location,value)==2) {
      // Set expected register value
      if (!strcasecmp(location,"a")) cpu_before.regs.a=resolve_value(value);
      else if (!strcasecmp(location,"a")) cpu_before.regs.a=resolve_value(value);
      else if (!strcasecmp(location,"x")) cpu_before.regs.x=resolve_value(value);
      else if (!strcasecmp(location,"y")) cpu_before.regs.y=resolve_value(value);
      else if (!strcasecmp(location,"z")) cpu_before.regs.z=resolve_value(value);
      else if (!strcasecmp(location,"b")) cpu_before.regs.b=resolve_value(value);
      else if (!strcasecmp(location,"spl")) cpu_before.regs.spl=resolve_value(value);
      else if (!strcasecmp(location,"sph")) cpu_before.regs.sph=resolve_value(value);
      else if (!strcasecmp(location,"pc")) cpu_before.regs.pc=resolve_value(value);
      else {
	fprintf(logfile,"ERROR: Unknown register '%s'\n",location);
	cpu.term.error=1;
      }
    } else if (sscanf(line,"expect %s at %s",value,location)==2) {
      // Update *_before[] memories to indicate the value we expect where.
      // Resolve labels and label+offset and $nn in each of the fields.
      int v=resolve_value(value);
      int l=resolve_value(location);
      // XXX Horrible hack for hypervisor memory vs chip RAM.
      // We should eventually use 28-bit flat addresses,
      // or auto-detect if the symbol was in hypervisor or user land,
      // and make the decision that way.
      if (l<0x8000||l>0xbfff) {
	// Chip RAM
        chipram_before[l]=v;
      } else {
	// Hypervisor RAM
	hypporam_before[l-0x8000]=v;
      }
    } else {
      fprintf(logfile,"ERROR: Unrecognised test directive:\n       %s\n",line);
      cpu.term.error=1;
    }
  }
  if (logfile!=stderr) test_conclude(&cpu);
  fclose(f);
}
