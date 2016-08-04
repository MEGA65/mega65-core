#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <stdlib.h>

int opcount=0;
char *opnames[256]={NULL};

char *addressing_modes[]={"","($nn,X)","$nn","#$nn","A",
			  "$nnnn","$nn,$rr","$rr","($nn),Y",
			  "($nn),Z","$rrrr","$nn,X","$nnnn,Y",
			  "$nnnn,X","($nnnn)","($nnnn,X)","($nn,SP),Y",
			  "$nn,Y","#$nnnn",NULL};

#define M_impl 0
#define M_InnX 1
#define M_nn 2
#define M_immnn 3
#define M_A 4
#define M_nnnn 5
#define M_nnrr 6
#define M_rr 7
#define M_InnY 8
#define M_InnZ 9
#define M_rrrr 10
#define M_nnX 11
#define M_nnnnY 12
#define M_nnnnX 13
#define M_Innnn 14
#define M_InnnnX 15
#define M_InnSPY 16
#define M_nnY 17
#define M_immnnnn 18

int modes[256];

struct ctx4510 {
  unsigned char flag_c;
  unsigned char flag_d;
  unsigned char flag_i;
  unsigned char flag_z;
  unsigned char flag_e;
  unsigned char flag_n;
  unsigned char flag_v;

  unsigned char a;
  unsigned char b;
  unsigned char x;
  unsigned char y;
  unsigned char z;
  unsigned short sp;
  unsigned short pc;
  unsigned int map_offset_low;
  unsigned char map_enable_low;
  unsigned int map_offset_high;
  unsigned char map_enable_high;
  
  unsigned char *rom;
  unsigned char ram[65536*2];
};

int resolve_address_to_long(unsigned short short_address,int writeP,struct ctx4510 *cpu)
{
  int temp_address=0;
  int blocknum;
  int lhc;

  // Lower 8 address bits are never changed
  temp_address = (temp_address & 0xFFFFFF00) | (short_address & 0x000000FF);

  // -- Add the map offset if required
  blocknum = (short_address>>13)& 0x3;
  
  if (short_address&0x8000) {
    if ((map_enable_high>>blocknum)&1) {
      temp_address |= reg_mb_high<<20;
      temp_address |= ((reg_offset_high+(short_address>>8))<<8)&0xfff00;
    } else
      temp_address = short_address;
  } else {
    if ((map_enable_low>>blocknum)&1) {
      temp_address |= reg_mb_low<<20;
      temp_address |= ((reg_offset_low+(short_address>>8))<<8)&0xfff00;
    } else
      temp_address = short_address;
  }
    
  // -- Now apply $01 and $D030 lines to determine what is really going on.    
  blocknum = short_address(15 downto 12)>>12;
  lhc = cpu->cpuport_value&7;
  lhc |= ~cpu->cpuport_ddr;
    
  // -- IO
  if ((blocknum==13) && ((lhc&1) || (lhc&2)) && (lhc&4)) {
    temp_address &= 0x00000fff;
    temp_address |= 0xffd3000;
  }
  // -- CHARROM
  if ((blocknum==13) && (!(lhc&4)) && (!writeP)) {
    temp_address &= 0x00000fff;
    temp_address |= 0x002d000;
  }

  // -- Examination of the C65 interface ROM reveals that MAP instruction
  // -- takes precedence over $01 CPU port when MAP bit is set for a block of RAM.
  // -- C64 KERNEL
    if reg_map_high(3)='0' then
      if (blocknum=14) and (lhc(1)='1') and (writeP=false) then
        temp_address(27 downto 12) := x"002E";      
      end if;
      if (blocknum=15) and (lhc(1)='1') and (writeP=false) then
        temp_address(27 downto 12) := x"002F";      
      end if;
    end if;
    -- C64 BASIC
    if reg_map_high(1)='0' then
      if (blocknum=10) and (lhc(0)='1') and (writeP=false) then
        temp_address(27 downto 12) := x"002A";      
      end if;
      if (blocknum=11) and (lhc(0)='1') and (writeP=false) then
        temp_address(27 downto 12) := x"002B";      
      end if;
    end if;

    -- $D030 ROM select lines:
    if (blocknum=14 or blocknum=15) and rom_at_e000='1' then
      temp_address(27 downto 12) := x"003E";
      if blocknum=15 then temp_address(12):='1'; end if;
    end if;
    if (blocknum=12) and rom_at_c000='1' then
      temp_address(27 downto 12) := x"002C";
    end if;
    if (blocknum=10 or blocknum=11) and rom_at_a000='1' then
      temp_address(27 downto 12) := x"003A";
      if blocknum=11 then temp_address(12):='1'; end if;
    end if;
    if (blocknum=9) and rom_at_9000='1' then
      temp_address(27 downto 12) := x"0039";
    end if;
    if (blocknum=8) and rom_at_8000='1' then
      temp_address(27 downto 12) := x"0038";
    end if;
    
    -- Kickstart ROM (takes precedence over all else if enabled)
    if (blocknum=14) and (kickstart_en='1') and (writeP=false) then
      temp_address(27 downto 12) := x"FFFE";      
    end if;
    if (blocknum=15) and (kickstart_en='1') and (writeP=false) then
      temp_address(27 downto 12) := x"002F";      
      temp_address(27 downto 12) := x"FFFF";      
    end if;
    
    return temp_address;
  end resolve_address_to_long;


int cpu_step(struct ctx4510 *cpu)
{
  printf("PC=$%04x, A=$%02x, X=$%02x, Y=$%02x, Z=$%02x, B=$%02x, SP=$%04x, P=%c%c-%c%c%c%c%c\n",
	 cpu->pc,cpu->a,cpu->x,cpu->y,cpu->z,cpu->b,cpu->sp,
	 cpu->flag_n?'N':'n',
	 cpu->flag_v?'V':'v',
	 cpu->flag_e?'E':'e',
	 cpu->flag_d?'D':'d',
	 cpu->flag_i?'I':'i',
	 cpu->flag_z?'Z':'z',
	 cpu->flag_c?'C':'c');
  
  int instruction_address=cpu->pc;

  return 0;
}

int main(int argc,char **argv)
{
  char *headings[65536]={0};
  char *annotations[65536]={0};
  char is_data[65536]={0};

  if (argc<2||argc>3) {
    fprintf(stderr,"em4510 <ROM file> <ROM annotations.txt>\n");
    exit(-1);
  }

  FILE *f=fopen("64net.opc","r");
  if (!f) {
    perror("Could not open 64net.opc");
    return -1;
  }
  int i,j;
  for(i=0;i<256;i++) {
    char line[1024];    
    int n;
    char opcode[1024];
    char mode[1024];
    
    line[0]=0; fgets(line,1024,f);
    int r=sscanf(line,"%02x   %s %s",&n,opcode,mode);
    if (n==i) {
      if (r<2) {
	fprintf(stderr,"Could not parse line %d of 64net.opc.\n> %s\n",
		i,line);
	exit(-3);
      }
      for(j=0;j<opcount;j++) if (opnames[j]==opcode) break;
      if (j==opcount) opnames[opcount++] = strdup(opcode);
      if (r==2) modes[i]=M_impl;
      else {
	for(j=0;addressing_modes[j];j++) {
	  if (!strcasecmp(addressing_modes[j],mode)) {
	    modes[i]=j; break;
	  }
	}
	if (!addressing_modes[j]) {
	  fprintf(stderr,"Illegal addressing mode '%s' in line %d of 64net.opc.\n> %s\n",
		  mode,i,line);
	  exit(-3);
	}
      }
    }
  }

  if (argv[2]) {
    f=fopen(argv[2],"r");
    if (f) {
      char line[1024];
      int address,addresshi;
      char note[1024];
      int count=0;
      line[0]=0; fgets(line,1024,f);
      while(line[0]) {
	if (sscanf(line,"data %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=1;
	  }
	else if (sscanf(line,"word %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=2;
	  }
	else if (sscanf(line,"text %x %x",&address,&addresshi)==2)
	  {
	    int i;
	    for(i=address;i<=addresshi;i++) is_data[i]=3;
	  }
	else if (sscanf(line,"%x %[^\n\r]",&address,note)==2)
	  {
	    if (address>=0&&address<65536) {
	      if (note[0]=='@')
		annotations[address]=strdup(&note[1]);
	      else
		headings[address]=strdup(note);
	      count++;
	    }
	  }
	line[0]=0; fgets(line,1024,f);
      }
      fclose(f);
      fprintf(stderr,"Read %d annotations.\n",count);
    }
  }

  unsigned char rom[65536*2];
  f=fopen(argv[1],"rb");
  if (!f) {
    fprintf(stderr,"Could not read ROM file '%s'\n",argv[1]);
    exit(-3);
  }
  int b,o=0;
  while(o<65536*2) {
    b=fread(&rom[o],1,65536*2-o,f);
    if (b>0) o+=b;
  }
  printf("Read ROM file.\n");

  struct ctx4510 cpu;

  bzero(&cpu,sizeof(cpu));
  cpu.rom=rom;
  cpu.pc = cpu.rom[0xfffc]+(cpu.rom[0xfffd]<<8);
  while(1) {
    cpu_step(&cpu);
  }

  return 0;
}

  
