#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

// 5 rows of 50 chars
unsigned char bannertext[50*5+1];

int main(int argc,char **argv)
{
  if ((!argv[1])||(!argv[2]))
    {
      fprintf(stderr,"Usage: %s <input file> <output file>\n",argv[0]);
      exit(-1);
    }
  FILE *f=fopen(argv[1],"r");
  FILE *o=fopen(argv[2],"w");
  if ((!f)||(!o))
    {
      fprintf(stderr,"Could not open input and/or output files.\n");
      exit(-1);
    }
  for(int i=0;i<5*50;i++) bannertext[i]=' ';
  bannertext[5*50]=0;

  for (int i=0;i<5;i++) {
    char line[1024]; line[0]=0;
    fgets(line,1024,f);
    printf("Processing line #%d : [%s]\n",i,line);
    for(int j=0;(j<50)&&(line[j]>=' ');j++)
      { bannertext[i*50+j]=line[j]; printf("."); }
    printf("\n");
  }
  fprintf(o,"%s",bannertext);
  return 0;
}
