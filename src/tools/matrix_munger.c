#include <stdio.h>
#include <string.h>
#include <stdlib.h>

char *matrix[]={
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+               |",
  "| R0  |<----| INS |  #  |  %  |  '  |  )  |  +  | �   |  !  | NO  |               |",
  "|PIN12|     | DEL |  3  |  5  |  7  |  9  |     |     |  1  | SCRL|               |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+               |",
  "| R1  |<----| RET |  W  |  R  |  Y  |  I  |  P  |  *  |  _  | TAB |               |",
  "|PIN11|     |     |     |     |     |     |     |     |     |     |               |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+               |",
  "| R2  |<----| HORZ|  A  |  D  |  G  |  J  |  L  |  ]  | CTRL| ALT |               |",
  "|PIN10|     | CRSR|     |     |     |     |     |  ;  |     |     +----------+    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R3  |<----| F8  |  $  |  &  |  {  |  0  |  -  | CLR |  \"  | HELP|          |    |",
  "|PIN-9|     | F7  |  4  |  6  |  8  |     |     | HOM |  2  |     |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R4  |<----| F2  |  Z  |  C  |  B  |  M  |  >  |RIGHT|SPACE| F10 |          |    |",
  "|PIN-8|     | F1  |     |     |     |     |  .  |SHIFT| BAR | F9  |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R5  |<----| F4  |  S  |  F  |  H  |  K  |  [  |  =  | C=  | F12 |          |    |",
  "|PIN-7|     | F3  |     |     |     |     |  :  |     |     | F11 |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R6  |<----| F6  |  E  |  T  |  U  |  O  |  @  |  �  |  Q  | F14 |          |    |",
  "|PIN-6|     | F5  |     |     |     |     |     |  ^  |     | F13 |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R7  |<----| VERT|LEFT |  X  |  V  |  N  |  <  |  ?  | RUN | ESC +------+   |    |",
  "|PIN-5|     | CRSR|SHIFT|     |     |     |  ,  |  /  | STOP|     +--+   |   |    |",
  "+-----+     +--+--+--+--+-----+-----+-----+-----+--+--+-----+-----+  |   |  "
};

int trim(char *s)
{
  char out[6];
  int o=0;
  for(int i=0;i<6;i++) if (s[i]!=' ') out[o++]=s[i];
  out[o]=0;
  strcpy(s,out);
  return 0;
}

int main(void)
{
  // Unshifted key
  for(int key=0;key<72;key++)
    {
      int row=key&7;
      int column=key/8;

      int trow=1+row*3;
      int tcol=3+column;

      int x1,x2;
      for(x1=0;tcol;x1++) if (matrix[trow][x1]=='|') tcol--;
      tcol=3+column;
      for(x2=0;tcol;x2++) if (matrix[trow+1][x2]=='|') tcol--;
      char r1[6],r2[6];
      for(int o=0;o<6;o++) {
	r1[o]=matrix[trow][x1+o];
	r2[o]=matrix[trow+1][x2+o];
      }
      r1[5]=0; r2[5]=0;
      trim(r1); trim(r2);
      if ((strlen(r1)==1)&&(r2[0]==0)) {
	if ((r1[0]>='A')&&(r1[0]<='Z')) {
	  // Alpha -- switch case for ASCII
	  r2[0]=r1[0]; r2[1]=0;
	  r1[0]|=0x20;
	}
	// Add some missing common ASCII keys
	if (r1[0]=='@') { r2[0]='{'; r2[1]=0; }
	if (r2[0]=='=') { r2[0]='}'; r2[1]=0; }
      }
      int ascii=r1[0];
      if (strlen(r1)>1) ascii=0;
      if ((r1[0]=='F')&&(!ascii)) {
	// Function key
	ascii=0x80+atoi(&r1[1]);
      }
      if (!strcmp("SPACE",r1)) ascii=' ';
      if (!strcmp("BAR",r1)) ascii=0xa0;
      if (!strcmp("ESC",r1)) ascii=0x1b;
      if (!strcmp("INS",r1)) ascii=0x08;
      if (!strcmp("HORZ",r1)) ascii=0x06;
      if (!strcmp("VERT",r1)) ascii=0x0e;
      if (!strcmp("RUN",r1)) ascii=0x03;
      if (!strcmp("TAB",r1)) ascii=0x09;
      
      
      printf(" %d => x\"%02x\", -- %s/%s\n",key,ascii,r1,r2);
    }
  return 0;
}
