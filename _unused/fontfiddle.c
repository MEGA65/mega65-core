#include <stdio.h>
#include <string.h>

int main(int argc,char **argv)
{
  char line[1024];
  unsigned int b[8];
  
  line[0]=0; fgets(line,1024,stdin);
  while(line[0]) {
    if (sscanf(line,"  x\"%x\", x\"%x\", x\"%x\", x\"%x\", x\"%x\", x\"%x\", x\"%x\", x\"%x\"",
	       &b[0],&b[1],&b[2],&b[3],&b[4],&b[5],&b[6],&b[7])==8) {
      for(int i=0;i<8;i++) {
	printf("  -- PIXELS: %c%c%c%c%c%c%c%c\n",
	       b[i]&0x80?'*':' ',
	       b[i]&0x40?'*':' ',
	       b[i]&0x20?'*':' ',
	       b[i]&0x10?'*':' ',
	       b[i]&0x08?'*':' ',
	       b[i]&0x04?'*':' ',
	       b[i]&0x02?'*':' ',
	       b[i]&0x01?'*':' ');
      }
      printf("  x\"%02x\", x\"%02x\", x\"%02x\", x\"%02x\", "
	     "x\"%02x\", x\"%02x\", x\"%02x\", x\"%02x\",\n",
	     b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7]);
    } else {
      if (strncmp(line,"  -- PIXELS:",12))
	printf("%s",line); }
    line[0]=0; fgets(line,1024,stdin);
  }
}
