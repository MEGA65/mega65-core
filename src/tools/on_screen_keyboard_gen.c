#include <stdio.h>
#include <string.h>

int main(int argc,char **argv)
{
  FILE *f=fopen("keyboard.txt","r");


  int n=0;
  char line[1024];
  char out[1024];
  char packed[1024];
  
  for(n=0;n<19;n++) {
    line[0]=0; fgets(line,1024,f);

    // Remove boxes around characters
    for(int x=0;line[x];x++) {
      if (line[x]=='|'
	  ||(line[x]=='+'&&(line[x-1]=='-'||line[x+1]=='-'))
	  ||(line[x]=='-'&&(line[x-1]=='-'||line[x+1]=='-'))
	  ||(line[x]=='-'&&(line[x-1]=='+'||line[x+1]=='+')))
	out[x]=' ';
      else
	out[x]=line[x];
    }

    // Trim CR/LF from end
    out[strlen(out)-1]=0;

    // Trim spaces from end
    while(out[0]&&out[strlen(out)-1]==' ') out[strlen(out)-1]=0;

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
    
    printf("%s\n",packed);


  }

  fclose(f);
  
  
}
