#include <stdio.h>
#include <string.h>
#include <stdlib.h>

char *matrix[]={
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+               |",
  "| R0  |<----| INS |  #  |  %  |  '  |  )  |     | �   |  !  | NO  |               |",
  "|PIN12|     | DEL |  3  |  5  |  7  |  9  |  +  |     |  1  | SCRL|               |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+               |",
  "| R1  |<----| RET |  W  |  R  |  Y  |  I  |  P  |  *  |  ~  | TAB |               |",
  "|PIN11|     |     |     |     |     |     |     |     |  _  |     |               |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+               |",
  "| R2  |<----| HORZ|  A  |  D  |  G  |  J  |  L  |  ]  | CTRL| ALT |               |",
  "|PIN10|     | CRSR|     |     |     |     |     |  ;  |     |     +----------+    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R3  |<----| F8  |  $  |  &  |  {  |  {  |     | CLR |  \"  | HELP|          |    |",
  "|PIN-9|     | F7  |  4  |  6  |  8  |  0  |  -  | HOM |  2  |     |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R4  |<----| F2  |  Z  |  C  |  B  |  M  |  >  |RIGHT|SPACE| F10 |          |    |",
  "|PIN-8|     | F1  |     |     |     |     |  .  |SHIFT| BAR | F9  |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R5  |<----| F4  |  S  |  F  |  H  |  K  |  [  |  }  | C=  | F12 |          |    |",
  "|PIN-7|     | F3  |     |     |     |     |  :  |  =  |     | F11 |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R6  |<----| F6  |  E  |  T  |  U  |  O  |     |  �  |  Q  | F14 |          |    |",
  "|PIN-6|     | F5  |     |     |     |     |  @  |  ^  |     | F13 |          |    |",
  "+-----+     +-----+-----+-----+-----+-----+-----+-----+-----+-----+          |    |",
  "| R7  |<----| VERT|LEFT |  X  |  V  |  N  |  <  |  ?  | RUN | ESC +------+   |    |",
  "|PIN-5|     | CRSR|SHIFT|     |     |     |  ,  |  /  | STOP|     +--+   |   |    |",
  "+-----+     +--+--+--+--+-----+-----+-----+-----+--+--+-----+-----+  |   |  "
};

unsigned int colour_codes[16]={
  0x00,0x05,0x1c,0x9f,0x9c,0x1e,0x1f,0x9e,
  0x81,0x95,0x96,0x97,0x98,0x9a,0x9b,0x9c};

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
  // Unshifted keys
  printf("  signal matrix_normal : key_matix_t := (\n");
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
	  r2[0]|=0x20;
	}
      }
      unsigned int ascii=r2[0];
      if (strlen(r1)>1) ascii=0;
      if ((r1[0]=='F')&&(!ascii)) {
	// Function key
	ascii=0xF0+atoi(&r1[1]);
      }
      if (!strcmp("SPACE",r1)) ascii=' ';
      if (!strcmp("CLR",r1)) ascii=0x13;
      if (!strcmp("ESC",r1)) ascii=0x1b;
      if (!strcmp("INS",r1)) ascii=0x14;
      if (!strcmp("HORZ",r1)) ascii=0x1d;
      if (!strcmp("VERT",r1)) ascii=0x11;
      if (!strcmp("RUN",r1)) ascii=0x03;
      if (!strcmp("TAB",r1)) ascii=0x09;
      
      printf("    %d => x\"%02x\", -- %s/%s\n",key,ascii&0xff,r1,r2);
    }
  printf("\n    others => x\"00\"\n    );\n");


  // shifted
  printf("\n  signal matrix_shift : key_matix_t := (\n");
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
	  r2[0]|=0x20;
	}
      }
      unsigned int ascii=r1[0];
      if (strlen(r1)>1) ascii=0;
      if ((r1[0]=='F')&&(!ascii)) {
	// Function key
	ascii=0xF0+atoi(&r2[1]);
      }
      if (!strcmp("SPACE",r1)) ascii=0x20;
      if (!strcmp("CLR",r1)) ascii=0x93;
      if (!strcmp("ESC",r1)) ascii=0x1b;
      if (!strcmp("INS",r1)) ascii=0x94;
      if (!strcmp("HORZ",r1)) ascii=0x9d;
      if (!strcmp("VERT",r1)) ascii=0x91;
      if (!strcmp("RUN",r1)) ascii=0xa3;  // slightly random assignment
      if (!strcmp("TAB",r1)) ascii=0x0f;
      
      printf("    %d => x\"%02x\", -- %s/%s\n",key,ascii&0xff,r1,r2);
    }
  printf("\n    others => x\"00\"\n    );\n");

  // control
  printf("\n  signal matrix_control : key_matix_t := (\n");
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
	  r2[0]&=0x1f;  // get control codes
	}
      }
      if ((r2[0]>='0')&&(r2[0]<='9')) {
	// control-number = colour codes
	r2[0]=colour_codes[r2[0]-'0'+0];
      }
      unsigned int ascii=r2[0];
      if (strlen(r1)>1) ascii=0;
      if ((r1[0]=='F')&&(!ascii)) {
	// Function key
	ascii=0xF0+atoi(&r1[1]);
      }
      if (!strcmp("SPACE",r1)) ascii=0x20;
      if (!strcmp("CLR",r1)) ascii=0x93;
      if (!strcmp("ESC",r1)) ascii=0x1b;
      if (!strcmp("INS",r1)) ascii=0x94;
      if (!strcmp("HORZ",r1)) ascii=0x9d;
      if (!strcmp("VERT",r1)) ascii=0x91;
      if (!strcmp("RUN",r1)) ascii=0xa3;  // slightly random assignment
      if (!strcmp("TAB",r1)) ascii=0x0f;
      
      printf("    %d => x\"%02x\", -- %s/%s\n",key,ascii&0xff,r1,r2);
    }
  printf("\n    others => x\"00\"\n    );\n");
  
  // control
  printf("\n  signal matrix_cbm : key_matrix_t := (\n");
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
	  r2[0]|=0xC0;  // get graphic symbols
	  r2[0]&=0xDF;
	}
      }
      if ((r2[0]>='0')&&(r2[0]<='9')) {
	// C=+number = colour codes
	r2[0]=colour_codes[r2[0]-'0'+8];
      }
      unsigned int ascii=r2[0];
      if (strlen(r1)>1) ascii=0;
      if ((r1[0]=='F')&&(!ascii)) {
	// Function key
	ascii=0xF0+atoi(&r1[1]);
      }
      if (!strcmp("SPACE",r1)) ascii=0x20;
      if (!strcmp("CLR",r1)) ascii=0x93;
      if (!strcmp("ESC",r1)) ascii=0x1b;
      if (!strcmp("INS",r1)) ascii=0x94;
      if (!strcmp("HORZ",r1)) ascii=0x9d;
      if (!strcmp("VERT",r1)) ascii=0x91;
      if (!strcmp("RUN",r1)) ascii=0xa3;  // slightly random assignment
      if (!strcmp("TAB",r1)) ascii=0xef;  // C=+TAB = Matrix Mode trap
      
      printf("    %d => x\"%02x\", -- %s/%s\n",key,ascii&0xff,r1,r2);
    }
  printf("\n    others => x\"00\"\n    );\n");
  
  
  return 0;
}
