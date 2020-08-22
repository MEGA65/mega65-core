#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(int argc,char **argv)
{
  char line[1024];
  int timepoint;
  int regnum;
  int active=100000;
  char sda,scl;
  unsigned char hr_cs0,hr_clk_p,hr_reset,hr_rwds;
  unsigned char hr_d[8];
  unsigned char hr2_cs0,hr2_clk_p,hr2_reset,hr2_rwds;
  unsigned char hr2_d[8];
  unsigned char hr_sample,hr_return;

  time_t t=time(0);
  
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

	 "$var wire 1 A hr2_cs0 $end\n"
	 "$var wire 1 B hr2_clk_p $end\n"
	 "$var wire 1 C hr2_reset $end\n"
	 "$var wire 1 D hr2_rwds $end\n"
	 "$var wire 8 E hr2_d $end\n"
	 "$var wire 1 F hr_sample $end\n"

	 "$upscope $end\n"
	 "$enddefinitions $end\n"
	 "$dumpvars\n"
	 "x!\n"
	 "x\"\n"
	 "x&\n"
	 "x%%\n"
	 "bxxxxxxxx ^\n"
	 "xA\n"
	 "xB\n"
	 "xC\n"
	 "xD\n"
	 "bxxxxxxxx E\n"
	 "$end\n"
	 "\n");	
  
  line[0]=0; fgets(line,1024,stdin);
  while (line[0]) {
    if (sscanf(line,"%*[^@]@%dns:(report note): Writing to register $%x",
	       &timepoint,&regnum)==2) {
      active=1000;
    }
    if (sscanf(line,"%*[^@]@%dus:(report note): Writing to register $%x",
	       &timepoint,&regnum)==2) {
      timepoint*=1000; // usec to ns
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
      if (n<13) {
	n=sscanf(line,"%*[^@]@%dus:(report note): hr_cs0 = '%c', hr_clk_p = '%c', hr_reset = '%c', hr_rwds = '%c', hr_d = '%c''%c''%c''%c''%c''%c''%c''%c', ",
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
	timepoint*=1000; // us to ns
      }
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

    if (active) {
      int n=sscanf(line,"%*[^@]@%dns:(report note): hr_sample='%c'",
		   &timepoint,&hr_sample);
      if (n<2) {
	n=sscanf(line,"%*[^@]@%dus:(report note): hr_sample='%c'",
		 &timepoint,&hr_sample);	
	timepoint*=1000; // us to ns
      }
      if (n==2) {
	if (hr_sample=='0') timepoint++;
	printf("#%d\n%cF\n",
	       timepoint,(char)hr_sample);
      }
	
    }      
      
    if (active) {
      int n=sscanf(line,"%*[^@]@%dns:(report note): hr2_cs0 = '%c', hr2_clk_p = '%c', hr2_reset = '%c', hr2_rwds = '%c', hr2_d = '%c''%c''%c''%c''%c''%c''%c''%c', ",
		   &timepoint,&hr2_cs0,&hr2_clk_p,&hr2_reset,&hr2_rwds,
		   &hr2_d[0],
		   &hr2_d[1],
		   &hr2_d[2],
		   &hr2_d[3],
		   &hr2_d[4],
		   &hr2_d[5],
		   &hr2_d[6],
		   &hr2_d[7]
		   );
      if (n<13) {
	n=sscanf(line,"%*[^@]@%dus:(report note): hr2_cs0 = '%c', hr2_clk_p = '%c', hr2_reset = '%c', hr2_rwds = '%c', hr2_d = '%c''%c''%c''%c''%c''%c''%c''%c', ",
		 &timepoint,&hr2_cs0,&hr2_clk_p,&hr2_reset,&hr2_rwds,
		 &hr2_d[0],
		 &hr2_d[1],
		 &hr2_d[2],
		 &hr2_d[3],
		 &hr2_d[4],
		 &hr2_d[5],
		 &hr2_d[6],
		 &hr2_d[7]
		 );
	timepoint*=1000; // us to ns
      }
      if (n==13) {
	printf("%cA\n%cB\n%cC\n%cD\nb%c%c%c%c%c%c%c%c E\n",
	       (char)hr2_cs0,(char)hr2_clk_p,(char)hr2_reset,(char)hr2_rwds,
	       hr2_d[7],hr2_d[6],hr2_d[5],hr2_d[4],hr2_d[3],hr2_d[2],hr2_d[1],hr2_d[0]
	       );
      }

    }      
	if (sscanf(line,"%*[^@]@%dns:(report note): SDA='%c', SCL='%c'",
		 &timepoint,&sda,&scl)==3) {
	printf("#%d\n%c!\n%c\"\n",timepoint,(char)sda,(char)scl);
      }
    }

    if ((time(0)-t)>20) exit(0);
    
    line[0]=0; fgets(line,1024,stdin);
  }
}
