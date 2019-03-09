#include <stdio.h>

int main(int argc,char **argv)
{
  FILE *in=fopen(argv[1],"r");
  char *name=argv[2];
  FILE *out=fopen(argv[3],"w");

  unsigned char buffer[1024*1024];

  int size=fread(buffer,1,1024*1024,in);

  fprintf(out,"unsigned int %s_len=%d;\n",name,size);
  fprintf(out,"unsigned char %s[]={\n",name);
  for(int i=0;i<size;i++) {
    fprintf(out,"0x%02x",buffer[i]);
    if (i<(size-1)) fprintf(out,",");
    if ((i&0xf)==0x0f) fprintf(out,"\n");
  }
  fprintf(out,"};\n");

  fclose(in);
  fclose(out);
  return 0;
}
