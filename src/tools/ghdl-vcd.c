#include <stdio.h>
#include <stdlib.h>

int main(int argc,char **argv)
{
  char line[1024];
  int timepoint;
  int regnum;
  int active=10000;
  char sda,scl;
  unsigned char hr_cs0,hr_clk_p,hr_reset,hr_rwds;
  unsigned char hr_d[8];

  printf("$date\n"
	 "   Mon Feb 17 15:29:53 2020\n"
	 "\n"
	 "$end\n"
	 "$version\n"
	 "   MEGA65 monitor_load JTAG scan tool.\n"
	 "$end\n"
	 "$comment\n"
	 "   No comment.\n"
	 "$end\n"
	 "$timescale 1us $end\n"
	 "$scope module logic $end\n"
	 "$var wire 1 ! hr_cs0 $end\n"
	 "$var wire 1 \" hr_clk_p $end\n"
	 "$var wire 1 & hr_reset $end\n"
	 "$var wire 1 %% hr_rwds $end\n"
	 "$var wire 8 ^ hr_d $end\n"
	 "$upscope $end\n"
	 "$enddefinitions $end\n"
	 "$dumpvars\n"
	 "x!\n"
	 "x\"\n"
	 "x&\n"
	 "x%%\n"
	 "bxxxxxxxx ^\n"
	 "$end\n"
	 "\n");	
  
  line[0]=0; fgets(line,1024,stdin);
  while (line[0]) {
    if (sscanf(line,"%*[^@]@%dns:(report note): Writing to register $%x",
	       &timepoint,&regnum)==2) {
      active=1000;
    }
    if (active) {
      int n=sscanf(line,"%*[^@]@%dns:(report note): hr_cs0 = '%c', hr_clk_p = '%c', hr_reset = '%c', hr_rwds = '%c', hr_d = '%c''%c''%c''%c''%c''%c''%c''%c', ",
		   &timepoint,&hr_cs0,&hr_clk_p,&hr_reset,&hr_rwds,
		   &hr_d[0],
		   &hr_d[1],
		   &hr_d[2],
		   &hr_d[3],
		   &hr_d[4],
		   &hr_d[5],
		   &hr_d[6],
		   &hr_d[7]
		   );
      if (n==13) {
	printf("#%d\n%c!\n%c\"\n%c&\n%c%%\nb%c%c%c%c%c%c%c%c ^\n",
	       timepoint,(char)hr_cs0,(char)hr_clk_p,(char)hr_reset,(char)hr_rwds,
	       hr_d[7],hr_d[6],hr_d[5],hr_d[4],hr_d[3],hr_d[2],hr_d[1],hr_d[0]
	       );
	active--;
	if (!active) {
	  
	  exit(0);
	}
      }

	if (sscanf(line,"%*[^@]@%dns:(report note): SDA='%c', SCL='%c'",
		 &timepoint,&sda,&scl)==3) {
	printf("#%d\n%c!\n%c\"\n",timepoint,(char)sda,(char)scl);
	active--;
	if (!active) {
	  
	  exit(0);
	}
      }
    }
    
    line[0]=0; fgets(line,1024,stdin);
  }
}
