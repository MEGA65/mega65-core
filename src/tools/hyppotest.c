#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <stdlib.h>

char *describe_address(unsigned int addr);
char *describe_address_label(unsigned int addr);


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

void disassemble_imm(FILE *f,struct instruction_log *log)
{
  fprintf(f,"#$%02X",log->bytes[1]);
}

void disassemble_abs(FILE *f,struct instruction_log *log)
{
  fprintf(f,"$%02X%02X",log->bytes[2],log->bytes[1]);
}


void disassemble_instruction(FILE *f,struct instruction_log *log)
{
  
  if (!log->len) return;
  switch(log->bytes[0]) {
  case 0x1c:
    fprintf(f,"TRB ");
    disassemble_abs(f,log);
    break;
  case 0x20:
    fprintf(f,"JSR ");
    disassemble_abs(f,log);
    break;
  case 0x29:
    fprintf(f,"AND ");
    disassemble_imm(f,log);
    break;
  case 0x40:
    fprintf(f,"RTI");
    break;
  case 0x60:
    fprintf(f,"RTS");
    break;
  case 0x8d:
    fprintf(f,"STA ");
    disassemble_abs(f,log);
    break;
  case 0xa9:
    fprintf(f,"LDA ");
    disassemble_imm(f,log);
    break;
  case 0xad:
    fprintf(f,"LDA ");
    disassemble_abs(f,log);
    break;
  }
  
}

int show_recent_instructions(FILE *f,char *title,int first_instruction, int count,
			     unsigned int highlight_address)
{
  int last_was_dup=0;
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
  int addr=(cpu->regs.sph<<8)+cpu->regs.spl;
  MEM_WRITE(cpu,addr,v);
  cpu->regs.spl--;
  if ((addr&0xff)==0xff) {
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
  for(int i=0;i<6;i++) {
    log->bytes[i]=read_memory(cpu,cpu->regs.pc+i);
  }
  switch(log->bytes[0]) {
  case 0x1c: // TRB $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    int v=read_memory(cpu,addr_abs(log));
    v&=~cpu->regs.a;
    MEM_WRITE(cpu,addr_abs(log),v);
    update_nz(v);
    break;
  case 0x20: // JSR $nnnn
    stack_push(cpu,cpu->regs.pc+2);
    stack_push(cpu,(cpu->regs.pc+2)>>8);
    cpu->regs.pc=addr_abs(log);    
    break;
  case 0x29: // AND #$nn
    cpu->regs.a&=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0x60: // RTS
    log->len=1;
    if (cpu->term.rts) {
      cpu->term.rts--;
      if (!cpu->term.rts) {
	fprintf(stderr,"NOTE: Terminating via RTS\n");
	cpu->term.done=1;
      }
    }
    cpu->regs.pc=stack_pop(cpu);
    cpu->regs.pc|=stack_pop(cpu)<<8;
    cpu->regs.pc++;
    break;
  case 0x8d: // STA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    MEM_WRITE(cpu,addr_abs(log),cpu->regs.a);
    break;
  case 0xa9: // LDA #$nn
    cpu->regs.a=log->bytes[1];
    update_nz(cpu->regs.a);
    log->len=2;
    cpu->regs.pc+=2;
    break;
  case 0xad: // LDA $xxxx
    log->len=3;
    cpu->regs.pc+=3;
    cpu->regs.a=read_memory(cpu,addr_abs(log));
    update_nz(cpu->regs.a);
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
      fprintf(stderr,"ERROR: Exception occurred execting instruction at %s\n       Aborted.\n",
	      describe_address(cpu.regs.pc));
      show_recent_instructions(stderr,"Instructions leading up to the exception",
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
    exit(-2);
  }
  if (cpu.term.done) {
    fprintf(stderr,"NOTE: Execution ended.\n");
  }
  
  return 0;
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
	fprintf(f,"ERROR: Saw $%02x at %s, but expected to see $%02x\n",
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

// By default we log to stderr
FILE *logfile=NULL;
char logfilename[8192]="";
#define TESTLOGFILE "/tmp/hyppotest.tmp"

int test_passes=0;
int test_fails=0;
char test_name[1024]="unnamed test";
char safe_name[1024]="unnamed_test";

void machine_init(struct cpu *cpu)
{
  // Initialise CPU staet
  bzero(cpu,sizeof(struct cpu));
  cpu->regs.flags=FLAG_E|FLAG_I;
  
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
  if (logfile!=stderr) {
    fclose(logfile);
  }
  
  // Report test status
  if (cpu->term.error) {
    printf("\r[FAIL] %s\n",test_name);
    snprintf(cmd,8192,"mv %s FAIL.%s",TESTLOGFILE,safe_name);
    test_fails++;
  } else {
    printf("\r[PASS] %s\n",test_name);
    snprintf(cmd,8192,"mv %s PASS.%s",TESTLOGFILE,safe_name);
    test_passes++;
  }
  if (logfile!=stderr) system(cmd);

  logfile=stderr;
}


int main(int argc,char **argv)
{
  if (argc!=4) {
    fprintf(stderr,"usage: hypertest <HICKUP.M65> <HICKUP.sym> <test script>\n");
    exit(-2);
  }

  // Setup for anonymous tests, if user doesn't supply any test directives
  machine_init(&cpu);
  logfile=stderr;

  FILE *f=fopen(argv[1],"rb");
  if (!f) {
    fprintf(stderr,"ERROR: Could not read HICKUP file from '%s'\n",argv[1]);
    exit(-2);
  }
  int b=fread(hypporam_before,1,HYPPORAM_SIZE,f);
  if (b!=HYPPORAM_SIZE) {
    fprintf(stderr,"ERROR: Read only %d of %d bytes from HICKUP file.\n",b,HYPPORAM_SIZE);
    exit(-2);
  }
  fclose(f);

  f=fopen(argv[2],"r");
  if (!f) {
    fprintf(stderr,"ERROR: Could not read HICKUP symbol list from '%s'\n",argv[2]);
    exit(-2);
  }
  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    char sym[1024];
    int addr;
    if(sscanf(line," %s = $%x",sym,&addr)==2) {
      if (hyppo_symbol_count>=MAX_HYPPO_SYMBOLS) {
	fprintf(stderr,"ERROR: Too many symbols. Increase MAX_HYPPO_SYMBOLS.\n");
	exit(-2);
      }
      hyppo_symbols[hyppo_symbol_count].name=strdup(sym);
      hyppo_symbols[hyppo_symbol_count].addr=addr;
      sym_by_addr[addr]=&hyppo_symbols[hyppo_symbol_count];
      hyppo_symbol_count++;
    }
    line[0]=0; fgets(line,1024,f);
  }
  fclose(f);
  printf("Read %d symbols.\n",hyppo_symbol_count);

  // Open test script, and start interpreting it 
  f=fopen(argv[3],"r");
  if (!f) {
    fprintf(stderr,"ERROR: Could not read test procedure from '%s'\n",argv[3]);
    exit(-2);
  }
  while(!feof(f)) {
    line[0]=0; fgets(line,1024,f);
    char routine[1024];
    unsigned int addr;
    if (!line[0]) continue;
    if (line[0]=='#') continue;
    if (line[0]=='\r') continue;
    if (line[0]=='\n') continue;
    if (sscanf(line,"call %s",routine)==1) {
      int i;
      for(i=0;i<hyppo_symbol_count;i++) {
	if (!strcmp(routine,hyppo_symbols[i].name)) break;
      }
      if (i==hyppo_symbol_count) {
	fprintf(logfile,"ERROR: Cannot call non-existent routine '%s'\n",routine);
	exit(-2);
      }
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.rts=1; // Terminate on net RTS from routine
      cpu_call_routine(logfile,hyppo_symbols[i].addr);
    }
    else if (sscanf(line,"call $%x",&addr)==1) {
      bzero(&cpu.term,sizeof(cpu.term));
      cpu.term.rts=1; // Terminate on net RTS from routine
      cpu_call_routine(logfile,addr);
    }  else if (!strncasecmp(line,"check ram",strlen("check ram"))) {
      // Check RAM for changes
      compare_ram_contents(logfile,&cpu);
    }  else if (sscanf(line,"test \"%[^\"]\"",test_name)==1) {
      // Set test name
      test_init(&cpu);
      
      fflush(stdout);

      
    } else if (!strncasecmp(line,"test end",strlen("test end"))) {
      test_conclude(&cpu);	
    } else {
      fprintf(logfile,"ERROR: Unrecognised test directive:\n       %s\n",line);
      cpu.term.error=1;
    }
  }
  test_conclude(&cpu);
  fclose(f);
}
