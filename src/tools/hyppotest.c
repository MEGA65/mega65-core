#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <stdlib.h>

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

#define MAX_HYPPO_SYMBOLS HYPPORAM_SIZE
typedef struct hyppo_symbol {
  char *name;
  unsigned int addr;
} hyppo_symbol;
hyppo_symbol *sym_by_addr[65536]={NULL};
hyppo_symbol hyppo_symbols[MAX_HYPPO_SYMBOLS];
int hyppo_symbol_count=0;  

struct regs {
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

struct cpu {
  struct regs regs;
};

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

int show_recent_instructions(char *title,int first_instruction, int count,
			     unsigned int highlight_address)
{
  int last_was_dup=0;
  if (first_instruction<0) first_instruction=0;
  for(int i=first_instruction;count>0&&i<cpulog_len;count--,i++) {
    if (cpulog[i]->dup&&(i>first_instruction)) {
      if (!last_was_dup) printf("                 ... duplicated instructions omitted ...\n");
      last_was_dup=1;
    } else {
      last_was_dup=0;
      printf("I-%-7d ",cpulog_len-i);
      if (cpulog[i]->pc==highlight_address)
	printf("  >>>  "); else printf("       ");
      if (cpulog[i]->count>1)
	printf("$%04X : x%-6d : ",cpulog[i]->pc,cpulog[i]->count);
      else
	printf("$%04X :         : ",cpulog[i]->pc);
      printf("A:%02X ",cpulog[i]->regs.a);
      printf("X:%02X ",cpulog[i]->regs.x);
      printf("Y:%02X ",cpulog[i]->regs.y);
      printf("Z:%02X ",cpulog[i]->regs.z);
      printf("F:%02X ",cpulog[i]->regs.flags);
      printf("SP:%02x%02x ",cpulog[i]->regs.sph,cpulog[i]->regs.spl);
      for(int j=0;j<6;j++) {
	if (j<cpulog[i]->len) printf("%02x ",cpulog[i]->bytes[j]);
	else printf("   ");
      }
      // XXX - Show instruction decode
      printf("\n");
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

int execute_instruction(unsigned int pc,struct instruction_log *log)
{
  return -1;
}

int cpu_call_routine(unsigned int addr)
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

  printf(">>> Calling routine @ $%04X",addr);
  if (sym_by_addr[addr]) {
    printf(" (%s)",sym_by_addr[addr]->name);
  }
  printf("\n");

  // Remember the initial CPU state
  cpu_stash_ram();
  cpu_before=cpu;

  // Reset the CPU instruction log
  cpu_log_reset();

  unsigned int pc=addr;
  
  // Now execute instructions until we empty the stack or hit a BRK
  // or various other nasty situations that we might allow, including
  // filling the CPU instruction log
  while(cpulog_len<MAX_LOG_LENGTH) {

    struct instruction_log *log=calloc(sizeof(instruction_log),1);
    log->regs=cpu.regs;
    log->pc=pc;
    log->len=0; // byte count of instruction
    log->count=1;
    log->dup=0;

    if (execute_instruction(pc,log)) {
      fprintf(stderr,"ERROR: Exception occurred execting instruction at %s\n       Aborted.\n",
	      describe_address(pc));
      show_recent_instructions("Instructions leading up to the exception",
			       cpulog_len-16,16,addr);
      return -1;
    }
    
    // Add instruction to the log
    cpulog[cpulog_len++]=log;

    // And to most recent instruction at this address, but only if the last instruction
    // there was not identical on all registers and instruction to this one
    if (lastataddr[pc]&&identical_cpustates(lastataddr[pc],log)) {
      // If identical, increase the count, so that we can keep track of infinite loops
      lastataddr[pc]->count++;
      log->dup=1;
      if (lastataddr[pc]->count>INFINITE_LOOP_THRESHOLD) {
	fprintf(stderr,"ERROR: Infinite loop detected at %s.\n       Aborted after %d iterations.\n",
		describe_address(pc),lastataddr[pc]->count);
	// Show upto 32 instructions prior to the infinite loop
	show_recent_instructions("Instructions leading into the infinite loop for the first time",
				 cpulog_len-lastataddr[pc]->count-30,32,addr);
	return -1;
      }
    } else lastataddr[pc]=log;
    
  }
  if (cpulog_len==MAX_LOG_LENGTH) {
    fprintf(stderr,"ERROR: CPU instruction log filled.  Maybe a problem with the called routine?\n");
    exit(-2);
  }
  
  return 0;
}

int main(int argc,char **argv)
{
  if (argc!=4) {
    fprintf(stderr,"usage: hypertest <HICKUP.M65> <HICKUP.sym> <test script>\n");
    exit(-2);
  }

  // Initialise CPU staet
  bzero(&cpu,sizeof(cpu));
  
  // Clear chip RAM
  bzero(chipram_before,CHIPRAM_SIZE);
  
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
	fprintf(stderr,"ERROR: Cannot call non-existent routine '%s'\n",routine);
	exit(-2);
      }
      cpu_call_routine(hyppo_symbols[i].addr);
    }
    else if (sscanf(line,"call $%x",&addr)==1) {
      cpu_call_routine(addr);
    } else {
      fprintf(stderr,"ERROR: Unrecognised test directive:\n       %s\n",line);
      exit(-2);
    }
  }
  fclose(f);
}
