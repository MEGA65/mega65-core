#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <stdlib.h>

char *opnames[256]={NULL};
char *modes[256]={NULL};

int main(int argc,char **argv)
{
  char *headings[65536]={0};
  char *annotations[65536]={0};
  char is_data[65536]={0};

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

  if (argc<3||argc>4) {
    fprintf(stderr,"usage: dis4510 <binary file> <load address (hex)> [address annotations]\n");
    return -1;
  }

  if (argv[3]) {
    f=fopen(argv[3],"r");
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
	    printf("Data from %x - %x\n",address,addresshi);
	  }
	else if (sscanf(line,"word %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=2;
	    printf("Words from %x - %x\n",address,addresshi);
	  }
	else if (sscanf(line,"text %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=3;
	    printf("Text from %x - %x\n",address,addresshi);
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
      
      
      if (is_data[load_address+i-1]==1) {
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
      }

      // printf("op=%02X, mode=%s\n",opcode,modes[opcode]);

      // blank line before and after data block
      if (is_data[load_address+i-1]!=is_data[load_address+i-1-1])
	printf("\n");

      // Print address and opcode byte
      if (headings[load_address+i]) {
	printf("; %s\n",headings[load_address+i]);
      }
      int instruction_address=load_address+i;
      printf("%04X  %02X",load_address+i,mem[i]);
      i++;

      int value;
      int annotation_address=-1;
      int j,digits;

      if (is_data[load_address+i-1]==1) {
	printf("         .BY $%02X",mem[i-1]);	
      } else if (is_data[load_address+i-1]==2) {
	printf(" %02X      .W  $%04X",mem[i],mem[i-1]|(mem[i]<<8));
	annotation_address=mem[i-1]|(mem[i]<<8);
	i++;
      } else if (is_data[load_address+i-1]==3) {
	printf("         .text ");
	i--;
	j=i;
	while(is_data[load_address+i]==3&&(i-j<8)) {
	  printf("%02X ",mem[i++]);
	}
	printf(" '");
	i=j;
	while(is_data[load_address+i]==3&&(i-j<8)) {
	  if (mem[i]>=' '&&mem[i]<=0x7c)
	    printf("%c",mem[i++]);
	  else
	    printf("<%02X>",mem[i++]);
	}
	printf("'");
      } else {
	int immediate=0;
	for(j=0;modes[opcode][j];) {
	  args[o]=0;
	  // printf("j=%d, args=[%s], template=[%s]\n",j,args,modes[opcode]);
	  switch(modes[opcode][j]) {
	  case 'n': // normal argument
	    digits=0;
	    if (j<2||modes[opcode][j-2]!='#') immediate=0; else immediate=1;
	    while (modes[opcode][j++]=='n') digits++; j--;
	    if (digits==2) {
	      value=mem[i];
	      if (!immediate) annotation_address=value;
	      printf(" %02X",mem[i++]);
	      sprintf(&args[o],"%02X",value); o+=2;
	      c+=3;
	    }
	    if (digits==4) {
	      value=mem[i]+(mem[i+1]<<8);
	      if (!immediate) annotation_address=value;
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
	      annotation_address=value;
	      c+=3;
	    }
	    if (digits==4) {
	      value=mem[i]+(mem[i+1]<<8);
	      if (value&0x8000) value-=0x10000;
	      printf(" %02X",mem[i++]);
	      // 16 bit branches are still relative to the same point as 8-bit ones,
	      // i.e., after the 2nd of the 3 bytes
	      value+=load_address+i; 	    
	      annotation_address=value;
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
	printf("%s %s",opnames[opcode],args);      
	c+=strlen(opnames[opcode])+1+strlen(args);
      } 
      if (annotation_address>65536) annotation_address&=0xffff;
      if (annotation_address<0) annotation_address&=0xffff;
      if (annotations[instruction_address]) {
	while(c<40) { printf(" "); c++; }
	printf("; %s\n",annotations[instruction_address]);
      } else if (annotation_address!=-1&&annotations[annotation_address]) {
	while(c<40) { printf(" "); c++; }
	printf("; %s\n",annotations[annotation_address]);
      } else if (annotation_address!=-1&&headings[annotation_address]) {
	while(c<40) { printf(" "); c++; }
	printf("; %s\n",headings[annotation_address]);
      } else printf("\n");
      if (!is_data[load_address+i-1]) {
	if (!strcasecmp(opnames[opcode],"RTI")) printf("\n");
	if (!strcasecmp(opnames[opcode],"RTS")) printf("\n");
	if (!strcasecmp(opnames[opcode],"JMP")) printf("\n");
	if (!strcasecmp(opnames[opcode],"BRA")) printf("\n");
      }

      fflush(stdout);
    }

  return 0;
}
