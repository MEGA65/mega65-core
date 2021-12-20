#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <stdlib.h>

#define CHIPRAM_SIZE (384*1024)
unsigned char chipram[CHIPRAM_SIZE];
#define HYPPORAM_SIZE (16*1024)
unsigned char hypporam[HYPPORAM_SIZE];

#define MAX_HYPPO_SYMBOLS HYPPORAM_SIZE
typedef struct hyppo_symbol {
  char *name;
  unsigned int addr;
} hyppo_symbol;
hyppo_symbol *sym_by_addr[65536]={NULL};
hyppo_symbol hyppo_symbols[MAX_HYPPO_SYMBOLS];
int hyppo_symbol_count=0;  

int main(int argc,char **argv)
{
  if (argc!=4) {
    fprintf(stderr,"usage: hypertest <HICKUP.M65> <HICKUP.sym> <test script>\n");
    exit(-2);
  }

  FILE *f=fopen(argv[1],"rb");
  if (!f) {
    fprintf(stderr,"ERROR: Could not read HICKUP file from '%s'\n",argv[1]);
    exit(-2);
  }
  int b=fread(hypporam,1,HYPPORAM_SIZE,f);
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
  
}
