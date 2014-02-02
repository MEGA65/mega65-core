#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <stdlib.h>

char *opnames[256]={NULL};
char *modes[256]={NULL};

int main(int argc,char **argv)
{
  FILE *f=fopen("64net.opc","r");
  if (!f) {
    perror("Could not open 64net.opc");
    return -1;
  }
  int i;
  for(i=0;i<256;i++) {
    char line[1024];    
    int n;
    char opcode[1024];
    char mode[1024];
    
    line[0]=0; fgets(line,1024,f);
    int r=sscanf(line,"%02x   %s %s",&n,opcode,mode);
    if (n==i) {
      if (r==3) {
	opnames[i] = strdup(opcode);
	modes[i]=strdup(mode);
      } else if (r==2) {
	opnames[i] = strdup(opcode);
	modes[i]="";
      }
    }
  }

  if (argc!=3) {
    fprintf(stderr,"usage: dis4510 <binary file> <load address (hex)>\n");
    return -1;
  }

  f=fopen(argv[1],"r");
  if (!f) {
    perror("Could not read file to disassemble");
    return -1;
  }
  int load_address=strtoll(argv[2],NULL,16);

  unsigned char mem[65536];
  int bytes=fread(mem,1,65536,f); 

  printf("; Disassembly of $%04X -- $%04X\n",load_address,load_address+bytes-1);

  for(i=0;i<bytes;)
    {
      int o=0;
      char args[1024];
      int opcode=mem[i];
      int c=0;

      if (mem[i]==mem[i+1]&&mem[i]==mem[i+2]&&mem[i]==mem[i+3]) {
	// run of identical bytes, assume data.
	int j=i;
	for(j=i;mem[j]==mem[i];j++) continue;
	j-=1;
	printf("%04X - %04X .BY $%02X ; repeated byte\n\n",
	       load_address+i,load_address+j,mem[i]);

	i=j+1;
	continue;
      }

      // printf("op=%02X, mode=%s\n",opcode,modes[opcode]);

      // Print address and opcode byte
      printf("%04X  %02X",load_address+i,mem[i]);
      i++;
      int value;
      int j,digits;
      for(j=0;modes[opcode][j];) {
	args[o]=0;
	// printf("j=%d, args=[%s], template=[%s]\n",j,args,modes[opcode]);
	switch(modes[opcode][j]) {
	case 'n': // normal argument
	  digits=0;
	  while (modes[opcode][j++]=='n') digits++; j--;
	  if (digits==2) {
	    value=mem[i];
	    printf(" %02X",mem[i++]);
	    sprintf(&args[o],"%02X",value); o+=2;
	    c+=3;
	  }
	  if (digits==4) {
	    value=mem[i]+(mem[i+1]<<8);
	    printf(" %02X",mem[i++]);
	    printf(" %02X",mem[i++]);
	    sprintf(&args[o],"%04X",value); o+=4;
	    c+=6;
	  }
	  break;
	case 'r': // relative argument
	  digits=0;
	  while (modes[opcode][j++]=='r') digits++; j--;
	  if (digits==2) {
	    value=mem[i];
	    if (value&0x80) value-=0x100;
	    printf(" %02X",mem[i++]);
	    value+=load_address+i;
	    sprintf(&args[o],"%04X",value); o+=4;
	    c+=3;
	  }
	  if (digits==4) {
	    value=mem[i]+(mem[i+1]<<8);
	    if (value&0x8000) value-=0x10000;
	    printf(" %02X",mem[i++]);
	    // 16 bit branches are still relative to the same point as 8-bit ones,
	    // i.e., after the 2nd of the 3 bytes
	    value+=load_address+i; 	    
	    printf(" %02X",mem[i++]);
	    sprintf(&args[o],"%04X",value); o+=4;
	    c+=6;
	  }
	  break;
	default: 
	  args[o++]=modes[opcode][j++];
	  break;
	}
	args[o]=0;
	// printf("[%s]\n",args);
      }
      args[o]=0;
      while(c<9) { printf(" "); c++; }
      printf("%s %s\n",opnames[opcode],args);
      if (!strcasecmp(opnames[opcode],"RTS")) printf("\n");
      if (!strcasecmp(opnames[opcode],"JMP")) printf("\n");
      if (!strcasecmp(opnames[opcode],"BRA")) printf("\n");
      fflush(stdout);
    }

  return 0;
}
