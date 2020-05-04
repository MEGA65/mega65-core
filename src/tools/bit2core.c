#include <stdio.h>
#include <stdlib.h>
#include <strings.h>

unsigned char bitstream[4*1048576];

int main(int argc,char **argv)
{
  if (argc!=5) {
    fprintf(stderr,"MEGA65 bitstream to core file converter v0.0.1.\n");
    fprintf(stderr,"usage: <foo.bit> <core name> <core version> <out.cor>\n");
    exit(-1);
  }

  FILE *bf=fopen(argv[1],"rb");
  if (!bf) {
    fprintf(stderr,"ERROR: Could not read bitstream file '%s'\n",argv[1]);
    exit(-3);
  }
  int bit_size=fread(bitstream,1,4*1048576,bf);
  fclose(bf);

  printf("Bitstream file is %d bytes long.\n",bit_size);
  if (bit_size<1024||bit_size>(4*1048576-4096)) {
    fprintf(stderr,"ERROR: Bitstream file must be >1K and no bigger than (4MB - 4K)\n");
    exit(-2);
  }

  FILE *of=fopen(argv[4],"wb");
  if (!of) {
    fprintf(stderr,"ERROR: Could not create core file '%s'\n",argv[4]);
    exit(-3);
  }
  // Write magic bytes
  fprintf(of,"MEGA65BITSTREAM0");
  // Write core file name and version
  char header_block[4096-16];
  bzero(header_block,4096-16);
  for(int i=0;(i<32)&&argv[2][i];i++) header_block[i]=argv[2][i];
  for(int i=0;(i<32)&&argv[3][i];i++) header_block[32+i]=argv[3][i];
  fwrite(header_block,4096-16,1,of);
  fwrite(&bitstream[120],bit_size-120,1,of);
  fclose(of);

  printf("Core file written.\n");
  return 0;
} 
