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
"        addressa : in integer; -- range 0 to %d;\n"
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
"  type ram_t is array (0 to %d) of unsigned(7 downto 0);\n"
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
  if (argc<2) {
    fprintf(stderr,"usage: mkdriverom <ROM> [.. <ROM>]\n");
    exit(-1);
  }

#define MAX_ROM 65536
  unsigned char rom[MAX_ROM];

  int rom_size = 0;
  
  for(int i=1;i<argc;i++) {
  
    FILE *f=fopen(argv[i],"rb");
    if (!f) {
      fprintf(stderr,"ERROR: Failed to read ROM from '%s'\n",
	      argv[i]);
      exit(-1);
    }
    int n=fread(&rom[rom_size],1,MAX_ROM - rom_size,f);
    fprintf(stderr,"INFO: Read %d bytes from ROM file '%s'\n",
	    n,argv[i]);
    rom_size+=n;
    fclose(f);
  }

  fprintf(stderr,"INFO: Read %d total ROM bytes\n",rom_size);

  if (rom_size==16384) {
    // Mask out 1541 RAM/ROM tests on startup to speed it up
    fprintf(stderr,"INFO: Assuming 16KB ROM is for 1541, and masking out RAM/ROM startup tests\n");
    for(int i=0xEAA7;i<=0xEB21;i++) {
      rom[i-0xc000]=0xea;
    }
  }
  if (rom_size==32768) {
    // Mask out 1581 RAM/ROM tests on startup to speed it up
    fprintf(stderr,"INFO: Assuming 32KB ROM is for 1581, and masking out RAM/ROM startup tests\n");
    for(int i=0xAF4E;i<=0xAFBF;i++) {
      rom[i-0x8000]=0xea;
    }
    // Mask out BRK instruction that 1581 ROM uses on purpose (!!)
    // It is used to switch from DOS to FDC personalities, as best I can tell.
    // We'll just make it RTS instead at the start of the routine. This will mean
    // no jobs ever execute, but that should be okay for the test environment.
    // rom[0x95a1-0x8000]= 0x60; // was a BRK
    rom[0x959D-0x8000]= 0x60; // was first instruction of this job service routine
  }
  
  fprintf(stdout,top,rom_size-1,rom_size-1);
  for(int i=0;i<rom_size-1;i++) printf(" %d => x\"%02x\",\n",i,rom[i]);
  printf(" %d => x\"%02x\"\n",rom_size-1,rom[rom_size-1]);
  fprintf(stdout,"%s",bottom);
  
  return 0;
  
}
