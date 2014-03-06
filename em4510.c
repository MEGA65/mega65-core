#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <stdlib.h>

int opcount=0;
char *opnames[256]={NULL};

char *addressing_modes[]={"","($nn,X)","$nn","#$nn","A",
			  "$nnnn","$nn,$rr","$rr","($nn),Y",
			  "($nn),Z","$rrrr","$nn,X","$nnnn,Y",
			  "$nnnn,X","($nnnn)","($nnnn,X)","($nn,SP),Y",
			  "$nn,Y","#$nnnn",NULL};

#define M_impl 0
#define M_InnX 1
#define M_nn 2
#define M_immnn 3
#define M_A 4
#define M_nnnn 5
#define M_nnrr 6
#define M_rr 7
#define M_InnY 8
#define M_InnZ 9
#define M_rrrr 10
#define M_nnX 11
#define M_nnnnY 12
#define M_nnnnX 13
#define M_Innnn 14
#define M_InnnnX 15
#define M_InnSPY 16
#define M_nnY 17
#define M_immnnnn 18

int modes[256];

int main(int argc,char **argv)
{
  char *headings[65536]={0};
  char *annotations[65536]={0};
  char is_data[65536]={0};

  if (argc<2||argc>3) {
    fprintf(stderr,"em4510 <ROM file> <ROM annotations.txt>\n");
    exit(-1);
  }

  FILE *f=fopen("64net.opc","r");
  if (!f) {
    perror("Could not open 64net.opc");
    return -1;
  }
  int i,j;
  for(i=0;i<256;i++) {
    char line[1024];    
    int n;
    char opcode[1024];
    char mode[1024];
    
    line[0]=0; fgets(line,1024,f);
    int r=sscanf(line,"%02x   %s %s",&n,opcode,mode);
    if (n==i) {
      if (r<2) {
	fprintf(stderr,"Could not parse line %d of 64net.opc.\n> %s\n",
		i,line);
	exit(-3);
      }
      for(j=0;j<opcount;j++) if (opnames[j]==opcode) break;
      if (j==opcount) opnames[opcount++] = strdup(opcode);
      if (r==2) modes[i]=M_impl;
      else {
	for(j=0;addressing_modes[j];j++) {
	  if (!strcasecmp(addressing_modes[j],mode)) {
	    modes[i]=j; break;
	  }
	}
	if (!addressing_modes[j]) {
	  fprintf(stderr,"Illegal addressing mode '%s' in line %d of 64net.opc.\n> %s\n",
		  mode,i,line);
	  exit(-3);
	}
      }
    }
  }

  if (argv[2]) {
    f=fopen(argv[2],"r");
    if (f) {
      char line[1024];
      int address,addresshi;
      char note[1024];
      int count=0;
      line[0]=0; fgets(line,1024,f);
      while(line[0]) {
	if (sscanf(line,"data %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=1;
	  }
	else if (sscanf(line,"word %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=2;
	  }
	else if (sscanf(line,"text %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=3;
	  }
	else if (sscanf(line,"%x %[^\n\r]",&address,note)==2)
	  {
	    if (address>=0&&address<65536) {
	      if (note[0]=='@')
		annotations[address]=strdup(&note[1]);
	      else
		headings[address]=strdup(note);
	      count++;
	    }
	  }
	line[0]=0; fgets(line,1024,f);
      }
      fclose(f);
      fprintf(stderr,"Read %d annotations.\n",count);
    }
  }

  unsigned char rom[65536*2];
  f=fopen(argv[1],"rb");
  if (!f) {
    fprintf(stderr,"Could not read ROM file '%s'\n",argv[1]);
    exit(-3);
  }
  int b,o=0;
  while(o<65536*2) {
    b=fread(&rom[o],1,65536*2-o,f);
    if (b>0) o+=b;
  }
  printf("Read ROM file.\n");

  return 0;
}
  
