/*
  Memory packer: Takes a list of files to load at particular addresses, and generates
  the combined memory file and VHDL source for the pre-initialised memory.x

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
	  "                 [-n name of VHDL entity] <file.prg@offset [...]>\n");
  exit(-1);
}

int main(int argc,char **argv)
{
  if (argc<3) {
    usage();
  }

  char *outfile=NULL;
  
  int bytes=128*1024-1;
  char name[1024]="shadowram";
  
  int ar_size=128*1024;
  unsigned char archive[ar_size];

  // Start with empty memory
  bzero(archive,ar_size);

  int opt;
  while ((opt = getopt(argc, argv, "f:n:s:")) != -1) {
    switch (opt) {
    case 'f': outfile=strdup(optarg); break;
    case 'n': strcpy(name,optarg); break;
    case 's': bytes=atoi(optarg); break;
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
    fprintf(stderr,"Could not open '%s' to write VHDL source file.\n",outfile);
    exit(-1);
  }

  fprintf(o,"library IEEE;\n"
	  "use IEEE.STD_LOGIC_1164.ALL;\n"
	  "use ieee.numeric_std.all;\n"
	  "\n"
	  "--\n"
	  "entity %s is\n"
	  "  port (Clk : in std_logic;\n"
	  "        address : in integer range 0 to %d;\n"
	  "        we : in std_logic;\n"
	  "        data_i : in unsigned(7 downto 0);\n"
	  "        data_o : out unsigned(7 downto 0);\n"
	  "        writes : out unsigned(7 downto 0);\n"
	  "        no_writes : out unsigned(7 downto 0)\n"
	  "        );\n"
	  "end %s;\n"
	  "\n"
	  "architecture Behavioral of %s is\n"
	  "\n"
	  "  signal write_count : unsigned(7 downto 0) := x\"00\";\n"
	  "  signal no_write_count : unsigned(7 downto 0) := x\"00\";\n"
	  "  \n"
	  "  type ram_t is array (0 to %d) of unsigned(7 downto 0);\n"
	  "  signal ram : ram_t := (\n",
	  name,bytes,name,name,bytes);

  for(i=0;i<bytes;i++)
    if (archive[i]) fprintf(o,"          %d => x\"%02x\", -- $%05x\n",i,archive[i],i);
  
  fprintf(o,"          others => x\"00\");\n" 
	  "begin\n"
	  "\n"
	  "--process for read and write operation.\n"
	  "  PROCESS(Clk,ram,address)\n"
	  "  BEGIN\n"
	  "    data_o <= ram(address);\n"
	  "    writes <= write_count;\n"
	  "    no_writes <= no_write_count;\n"
	  "    if(rising_edge(Clk)) then \n"
	  "      if we /= '0' then\n"
	  "        write_count <= write_count + 1;        \n"
	  "        ram(address) <= data_i;\n"
	  "      else\n"
	  "        no_write_count <= no_write_count + 1;        \n"
	  "      end if;\n"
	  "    end if;\n"
	  "  END PROCESS;\n"
	  "\n"
	  "end Behavioral;\n"
	  );
  
  fclose(o);
  fprintf(stderr,"%d bytes written\n",bytes);
  
}
