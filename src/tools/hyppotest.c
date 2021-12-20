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
  struct regs regs;
} instruction_log;
#define MAX_LOG_LENGTH (1024*1024)
instruction_log *cpulog[MAX_LOG_LENGTH];
int cpulog_len=0;

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

  printf(">>> Calling routine @ $%04x",addr);
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

    // Add instruction to the log
    cpulog[cpulog_len++]=log;    
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
    fgets(line,1024,f);
    char routine[1024];
    unsigned int addr;
    if (line[0]=='#') continue;
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
