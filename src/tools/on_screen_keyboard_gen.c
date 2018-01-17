#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <stdlib.h>

int main(int argc,char **argv)
{
  FILE *f=fopen(argv[1]?argv[1]:"keyboard.txt","r");

  char line[1024];
  int b[32];
  int i;

  unsigned char map[16*32];
  int offset=0;
  bzero(map,sizeof(map));
  
  int parse_mode=0;
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    if (!strcasecmp("Matrix Layout:\n",line)) {
      parse_mode=1;
      fprintf(stderr,"Found matrix layout section.\n");
    }
    if (!strcasecmp("Sticky/modifier keys:\n",line)) {
      if (parse_mode!=1) {
	fprintf(stderr,"'Matrix Layout:' section must come before 'Stick/modifier keys:' section\n");
	exit(2);
      }
      fprintf(stderr,"Found sticky/modifier key section.\n");
      parse_mode=2;
      offset=15*16;
    }
    if (parse_mode==1)
      if (sscanf(line,"%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x,%x",
		 &b[0],&b[1],&b[2],&b[3],
		 &b[4],&b[5],&b[6],&b[7],
		 &b[8],&b[9],&b[10],&b[11],
		 &b[12],&b[13],&b[14],&b[15]
		 )==16) {
	for(i=0;i<16;i++) {
	  map[offset+i]=b[i];
	}
	offset+=16;
	fprintf(stderr,"Read keyboard row %d\n",offset/32);
      }
    if (parse_mode==2) {
      if (sscanf(line,"%x",&b[0])==1) {
	// XXX - We are not doing this here any more
	//	map[8*16+b[0]]=0x01; // mark key as sticky
	fprintf(stderr,"Key %d is sticky.\n",b[0]);
      }
    }
    
    line[0]=0; fgets(line,1024,f);
  }
  if (parse_mode!=2) {
    fprintf(stderr,"Missing 'Matrix Layout:' or 'Sticky/modifier keys:' section\n");
    exit(-1);
  }

  // Write map out and sticky keys
  fwrite(map,16*16,1,stdout);
  
  int n=0;

  fclose(f); f=fopen(argv[1]?argv[1]:"keyboard.txt","r");
  
  char out[1024];
  char packed[1024];
  int alternate_keyboard_offset=0;
  int packed_len=0;
  
  for(n=0;n<(19+17);n++) {
    line[0]=0; fgets(line,1024,f);

    if (n==19) alternate_keyboard_offset=packed_len;
    
    // Remove boxes around characters
    int y=0;
    for(int x=0;line[x];x++) {
      if (line[x]=='|'
	  ||(line[x]=='+'&&(line[x-1]=='-'||line[x+1]=='-'))
	  ||(line[x]=='-'&&(line[x-1]=='-'||line[x+1]=='-'))
	  ||(line[x]=='-'&&(line[x-1]=='+'||line[x+1]=='+')))
	out[y++]=' ';
      else
	if (line[x]=='\\') {
	  // Hex escaped byte
	  char hex[3];
	  hex[0]=line[x+1];
	  hex[1]=line[x+2];
	  hex[2]=0;
	  out[y++]=strtoll(hex,NULL,16);
	  x+=2;
	} else
	  out[y++]=line[x];
    }
    out[y]=0;
    
    // Trim CR/LF from end
    if (out[0]) out[strlen(out)-1]=0;

    // Trim spaces from end
    while(out[0]&&out[strlen(out)-1]==' ') out[strlen(out)-1]=0;
    fprintf(stderr,"line [%s]\n",out);
  
    // Replace runs of spaces
    int pl=0;
    int space_count=0;
    for(int x=0;out[x];x++) {
      if (out[x]==' '&&(space_count<17)) space_count++;
      else {
	// RLE groups of upto 17 spaces as 0x90 + count
	if (space_count>1) packed[pl++]=0x90 + (space_count - 2);
	else if (space_count==1) packed[pl++]=' ';
	space_count=0;
	
	// And the current character (if not a space)
	if (out[x]!=' ') packed[pl++]=out[x];
	else {
	  // Must be a space
	  space_count=1;
	}
      }
    }
    // Ignore any banked up spaces, as we trim spaces at end of line
    
    packed[pl]=0;
    packed_len+=pl+1;
    
    printf("%s\n",packed);
  }

  fprintf(stderr,"Packed len = $%04x\n",packed_len);
  while(packed_len<(4095-2-2048-256)) {
    putc(0,stdout); packed_len++;
  }
  putc(alternate_keyboard_offset&0xff,stdout);
  putc(9+(alternate_keyboard_offset>>8),stdout);
    

  fclose(f);
  
  
}
