/*
  Memory packer: Takes a list of files to load at particular addresses, and generates
  the combined memory file and VHDL source for the pre-initialised memory.x

*/

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>

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

int main(int argc,char **argv)
{
  if (argc<3) {
    fprintf(stderr,"usage: mempacker <output.vhdl> <file.prg@offset [...]>\n");
    exit(-1);
  }
  
  int ar_size=128*1024;
  unsigned char archive[ar_size];

  // Start with empty memory
  bzero(archive,ar_size);

  for(int i=2;i<argc;i++) {
    load_block(argv[i],archive,ar_size);
  }  
  
  FILE *o=fopen(argv[1],"w");
  if (!o) {
    fprintf(stderr,"Could not open '%s' to write VHDL source file.\n",argv[1]);
    exit(-1);
  }

  fprintf(o,"library IEEE;\n"
	  "use IEEE.STD_LOGIC_1164.ALL;\n"
	  "use ieee.numeric_std.all;\n"
	  "\n"
	  "--\n"
	  "entity shadowram is\n"
	  "  port (Clk : in std_logic;\n"
	  "        address : in integer range 0 to 131071;\n"
	  "        we : in std_logic;\n"
	  "        data_i : in unsigned(7 downto 0);\n"
	  "        data_o : out unsigned(7 downto 0);\n"
	  "        writes : out unsigned(7 downto 0);\n"
	  "        no_writes : out unsigned(7 downto 0)\n"
	  "        );\n"
	  "end shadowram;\n"
	  "\n"
	  "architecture Behavioral of shadowram is\n"
	  "\n"
	  "  signal write_count : unsigned(7 downto 0) := x\"00\";\n"
	  "  signal no_write_count : unsigned(7 downto 0) := x\"00\";\n"
	  "  \n"
	  "--  type ram_t is array (0 to 262143) of std_logic_vector(7 downto 0);\n"
	  "  type ram_t is array (0 to 131071) of unsigned(7 downto 0);\n"
	  "  signal ram : ram_t := (\n");

  for(int i=0;i<ar_size;i++)
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
	  "        report \"wrote to shadow ram\" severity note;\n"
	  "      else\n"
	  "        no_write_count <= no_write_count + 1;        \n"
	  "      end if;\n"
	  "    end if;\n"
	  "  END PROCESS;\n"
	  "\n"
	  "end Behavioral;\n"
	  );
  
  fclose(o);
  fprintf(stderr,"%d bytes written\n",ar_size);
  
}
