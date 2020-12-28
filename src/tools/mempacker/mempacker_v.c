/*
  Memory packer: Takes a list of files to load at particular addresses, and generates
  the combined memory file and Verilog source for the pre-initialised memory.x

*/

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <getopt.h>

int load_block(char *arg,unsigned char *archive,int ar_size)
{
  char filename[1024];
  int addr;

  if (sscanf(arg,"%[^@]@%x",filename,&addr)!=2) {
    fprintf(stderr,"Could not parse '%s', should be filename@hexaddr\n",arg);
    exit(-1);
  }
  FILE *f=fopen(filename,"r");
  if (!f) {
    fprintf(stderr,"Could not read file '%s'\n",filename);
  }
  int offset=addr;
  int bytes;
  while((bytes=fread(&archive[offset],1,ar_size-offset,f))>0) {
    if (offset>=ar_size) {
      fprintf(stderr,"WARNING: Input file '%s' would overflow memory.\n",filename);
    }
    offset+=bytes;
  }
  fclose(f);
  
  return 0;
}

int usage(void)
{
  fprintf(stderr,
	  "usage: mempacker [-f output.vhdl] [-s size of memory]"
	  "                 [-n name of Verilog entity] <file.prg@offset [...]>\n");
  exit(-1);
}

int main(int argc,char **argv)
{
  if (argc<3) {
    usage();
  }

  char *outfile=NULL;
  
  int bytes=1024*1024-1;
  char name[1024]="shadowram";
  int width=16;
  int ar_size=1024*1024;
  unsigned char archive[ar_size];

  // Start with empty memory
  // bzero(archive,ar_size);
  for(int i=0;i<ar_size;i++) archive[i]=0;

  int opt;
  while ((opt = getopt(argc, argv, "f:n:s:w:")) != -1) {
    switch (opt) {
    case 'f': outfile=strdup(optarg); break;
    case 'n': strcpy(name,optarg); break;
    case 's': bytes=atoi(optarg); break;
    case 'w': width=atoi(optarg); break;
    default:
      usage();
    }
  }
  if (!outfile) usage();

  int i;
  for(i=optind;i<argc;i++) {
    load_block(argv[i],archive,ar_size);
  }  
  
  FILE *o=fopen(outfile,"w");
  if (!o) {
    fprintf(stderr,"Could not open '%s' to write Verilog source file.\n",outfile);
    exit(-1);
  }

  fprintf(o,
  	"module %s(clk, we, addr, di, do);\n"
  	"input clk;\n"
  	"input we;\n"
  	"input [%d:0] addr;\n"
  	"input [7:0] di;\n"
  	"output [7:0] do;\n"
  	"reg [7:0] ram [0:%d];\n"
  	"reg [7:0] do;\n"
  	"\n"
  	"initial\n"
  	"begin\n"
  	,name,width-1,bytes-1);

  for(i=0;i<bytes;i++)
  {
		fprintf(o,"ram[16'h%04x] = 8'h%02x; ",i,archive[i]);
		if((i+1)%8 == 0)
			fprintf(o,"\n");
  }
	fprintf(o,"\n");
  
	fprintf(o,
		"end\n\n"
		"always @(posedge clk)\n"
		"begin\n"
		"    if(we)\n"
		"        ram[addr] <= di;\n"
		"    do <= ram[addr];\n"
		"end\n"
		"\n"
		"endmodule\n");
  
  fclose(o);
  fprintf(stderr,"%d bytes written\n",bytes);

  return 0;  
}
