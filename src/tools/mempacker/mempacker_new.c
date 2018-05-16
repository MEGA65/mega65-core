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
  
  int bytes=1024*1024-1;
  char name[1024]="shadowram";
  
  int ar_size=1024*1024;
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
	  "  port (ClkA : in std_logic;\n"
	  "        addressa : in integer range 0 to 1048575;\n"
	  "        wea : in std_logic;\n"
	  "        dia : in unsigned(7 downto 0);\n"
	  "        writes : out unsigned(7 downto 0);\n"
	  "        no_writes : out unsigned(7 downto 0);\n"
	  "        doa : out unsigned(7 downto 0);\n"
	  "        ClkB : in std_logic;\n"
          "        addressb : in unsigned(19 downto 0);\n"
          "        dob : out unsigned(7 downto 0)\n"
	  "        );\n"
	  "end %s;\n"
	  "\n"
	  "architecture Behavioral of %s is\n"
	  "\n"
	  "  signal write_count : unsigned(7 downto 0) := x\"00\";\n"
	  "  signal no_write_count : unsigned(7 downto 0) := x\"00\";\n"
	  "  \n"
	  "  type ram_t is array (0 to %d) of unsigned(7 downto 0);\n"
	  "  shared variable ram : ram_t := (\n",
	  name,name,name,bytes);

  for(i=0;i<bytes;i++)
//    if (archive[i])
    fprintf(o,"          %d => x\"%02x\", -- $%05x\n",i,archive[i],i);
  fprintf(o,"          %d => x\"%02x\"); -- $%05x\n",i,archive[i],i);
  
  // fprintf(o,"          others => x\"00\");\n" 
  fprintf(o,
	  "begin\n"
	  "\n"
	  "  writes <= write_count;\n"
	  "  no_writes <= no_write_count;\n"
	  "--process for read and write operation.\n"
	  "  PROCESS(ClkA)\n"
	  "  BEGIN\n"
	  "    if(rising_edge(ClkA)) then \n"
	  "      if wea /= '0' then\n"
	  "        write_count <= write_count + 1;        \n"
	  //	  "        if %d>addressa then\n"	  
	  "          ram(addressa) := dia;\n"
	  //	  "        end if;\n"
	  "      else\n"
	  "        no_write_count <= no_write_count + 1;        \n"
	  "      end if;\n"
	  //	  "      if %d>addressa then\n"	  
	  "        doa <= ram(addressa);\n"
	  //	  "      else\n"
	  //	  "        doa <= x\"BD\";\n"
	  //	  "      end if;\n"
	  "    end if;\n"
	  "  END PROCESS;\n"
          "PROCESS(ClkB)\n"
          "BEGIN\n"
          "  if(rising_edge(ClkB)) then\n"
	  // "    if %d>to_integer(addressb) then\n"
	  "      dob <= ram(to_integer(addressb));\n"
	  // "    else\n"
	  // "      dob <= x\"BD\";\n"
	  //          "    end if;\n"
          "  end if;\n"
          "END PROCESS;\n"
	  "\n"
	  "end Behavioral;\n",
	  bytes+1,bytes+1,bytes+1);
  
  fclose(o);
  fprintf(stderr,"%d bytes written\n",bytes);

  return 0;  
}
