#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <stdlib.h>

char *opnames[256]={NULL};
char *modes[256]={NULL};

char *modelist[256]={NULL};
int modecount=0;

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

  printf("  type instruction is (\n    -- 4510 opcodes\n    ");
  int j,icount=0;
  for(i=0;i<256;i++) {
    int dup=0;
    for(j=0;j<i;j++) if (!strncasecmp(opnames[i],opnames[j],3)) dup=1;
    if (!dup) {
      if (icount>0) printf(",");
      if ((icount&7)==7) printf("\n    ");
      printf("I_%c%c%c",opnames[i][0],opnames[i][1],opnames[i][2]);
      icount++;
    }
  }
  printf(");\n\n");

  printf("  type ilut8bit is array(0 to 255) of instruction;\n");
  printf("  constant instruction_lut : ilut8bit := (\n    ");
  for(i=0;i<256;i++) {
    printf("I_%c%c%c",opnames[i][0],opnames[i][1],opnames[i][2]);
    if (i<255) printf(","); else printf(");\n");
    if ((i&15)==15) printf("\n    ");
  }

  printf("\n  type mlut8bit is array(0 to 255) of addressingmode;\n  constant mode_lut : mlut8bit := (\n    ");
  for(i=0;i<256;i++) {
    char mode[1024]="M_";
    int o=2;
    for(j=0;modes[i][j];j++) {
      switch(modes[i][j]) {
      case '(': mode[o++]='I'; break;
      case '#': mode[o++]='i'; mode[o++]='m'; mode[o++]='m'; break;
      case 'n': case 'r': case 'X': case 'Y': case 'Z': case 'S': case 'P': case 'A':
	mode[o++]=modes[i][j]; break;
      }
    }
    mode[o]=0; if (o==2) strcpy(mode,"M_impl"); o=strlen(mode);
    int m;
    for(m=0;m<modecount;m++) if (!strcasecmp(mode,modelist[m])) break;
    if (m>=modecount) {
      modelist[modecount++]=strdup(mode);
    }

    printf("%s",mode);
    if (i<255) { printf(",");
      while(o<8) { printf(" "); o++; }

    }
    else printf(");\n");
    if ((i&7)==7) printf("\n    ");
  }

  printf("\n  type addressingmode is (\n    ");
  int m;
  for(m=0;m<modecount;m++) {
    if (m) printf(",");
    if ((m&7)==7) printf("\n    ");
    printf("%s",modelist[m]);
  }
  printf(");\n\n");

  printf("  type mode_list is array(addressingmode'low to addressingmode'high) of integer;\n  constant mode_bytes_lut : mode_list := (\n");
  for(m=0;m<modecount;m++) {
    int c=0;
    for(i=0;modelist[m][i];i++) {
      if (modelist[m][i]=='n'||modelist[m][i]=='r') c++;
    }
    if (m>0) printf(",\n");
    printf("    %s => %d",modelist[m],c/2);    
  }
  printf(");\n\n");

}
