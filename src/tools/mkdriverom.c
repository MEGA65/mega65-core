#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

char *top="library IEEE;\n"
"use IEEE.STD_LOGIC_1164.ALL;\n"
"use ieee.numeric_std.all;\n"
"\n"
"--\n"
"entity driverom is\n"
"  port (ClkA : in std_logic;\n"
"        addressa : in integer; -- range 0 to 16383;\n"
"        wea : in std_logic;\n"
"        csa : in std_logic;\n"
"        dia : in unsigned(7 downto 0);\n"
"        writes : out unsigned(7 downto 0);\n"
"        no_writes : out unsigned(7 downto 0);\n"
"        doa : out unsigned(7 downto 0);\n"
"        ClkB : in std_logic;\n"
"        addressb : in integer;\n"
"        dob : out unsigned(7 downto 0)\n"
"        );\n"
"end driverom;\n"
"\n"
"architecture Behavioral of driverom is\n"
"\n"
"  signal write_count : unsigned(7 downto 0) := x\"00\";\n"
"  signal no_write_count : unsigned(7 downto 0) := x\"00\";\n"
"  \n"
"  type ram_t is array (0 to 16383) of unsigned(7 downto 0);\n"
"  shared variable ram : ram_t := (\n"
;

char *bottom=
"  )\n"
"    ;\n"
"begin\n"
"\n"
"  writes <= write_count;\n"
"  no_writes <= no_write_count;\n"
"--process for read and write operation.\n"
"  PROCESS(ClkA,csa,addressa)\n"
"  BEGIN\n"
"    if(rising_edge(ClkA)) then \n"
"      if wea /= '0' and csa='1' then\n"
"        write_count <= write_count + 1;        \n"
"          ram(addressa) := dia;\n"
"      else\n"
"        no_write_count <= no_write_count + 1;        \n"
"      end if;\n"
"    end if;\n"
"    if csa='1' then\n"
"      doa <= ram(addressa);\n"
"    else\n"
"      doa <= (others => 'Z');\n"
"    end if;\n"
"  END PROCESS;\n"
"PROCESS(ClkB)\n"
"BEGIN\n"
"  if(rising_edge(ClkB)) then\n"
"      dob <= ram(addressb);\n"
"  end if;\n"
"END PROCESS;\n"
"\n"
"end Behavioral;\n"
  ;

int main(int argc,char **argv)
{
  if (argc!=3) {
    fprintf(stderr,"usage: mkdriverom <$C000 ROM> <$E000 ROM>\n");
    exit(-1);
  }

  unsigned char lorom[8192];
  unsigned char hirom[8192];

  FILE *f=fopen(argv[1],"rb");
  if (!f) {
    fprintf(stderr,"ERROR: Failed to read $C000 ROM from '%s'\n",
	    argv[1]);
    exit(-1);
  }
  int n=fread(lorom,8192,1,f);
  if (n!=1) {
    fprintf(stderr,"ERROR: Failed to read 8KB from '%s'\n",
	    argv[1]);
    exit(-1);
  }
  fclose(f);

  f=fopen(argv[2],"rb");
  if (!f) {
    fprintf(stderr,"ERROR: Failed to read $E000 ROM from '%s'\n",
	    argv[1]);
    exit(-1);
  }
  n=fread(hirom,8192,1,f);
  if (n!=1) {
    fprintf(stderr,"ERROR: Failed to read 8KB from '%s'\n",
	    argv[1]);
    exit(-1);
  }
  fclose(f);  

  // Mask out RAM/ROM tests on startup to speed it up
  for(int i=0xEAA7;i<=0xEB21;i++) {
    hirom[i-0xe000]=0xea;
  }
  
  fprintf(stdout,"%s",top);
  for(int i=0;i<8192;i++) printf(" %d => x\"%02x\",\n",i,lorom[i]);
  for(int i=0;i<8191;i++)
    printf(" %d => x\"%02x\",\n",i+8192,hirom[i]);
  printf(" %d => x\"%02x\"\n",8191+8192,hirom[8191]);
  fprintf(stdout,"%s",bottom);
  
  return 0;
  
}
