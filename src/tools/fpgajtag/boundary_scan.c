/*
  JTAG boundary scan helper functions.
  see also fpgajtag.c for the xilinx_boundaryscan() function.

  (C) Paul Gardner-Stephen, 2020. GPLv3.

  These routines are designed to read in BSDL files and XDC files for Vivado
  projects, so that the boundary scan can show the state of the various pins.


*/
#include <stdio.h>
#define _GNU_SOURCE 1
#include <string.h>
#include <strings.h>
#include <time.h>

char *strcasestr(const char *haystack, const char *needle);

unsigned long long gettime_ms(void);
unsigned long long gettime_us(void);
int dump_bytes(int col,char *msg,unsigned char *b,int count);

#define MAX_PINS 4096
char *pin_names[MAX_PINS];
char *signal_names[MAX_PINS];
int pin_count=0;

#define MAX_BOUNDARY_BITS 8192
char *boundary_bit_type[MAX_BOUNDARY_BITS];
char *boundary_bit_fullname[MAX_BOUNDARY_BITS];
char *boundary_bit_pin[MAX_BOUNDARY_BITS];
int boundary_bit_count=0;
char part_name[1024];

FILE *vcd=NULL;

void set_vcd_file(char *name)
{
  vcd=fopen(name,"w");
  if (!vcd) perror("Failed to open VCD file for writing");
}

int parse_xdc(char *xdc)
{
  FILE *f=fopen(xdc,"r");
  if (!f) {
    perror("Could not open XDC file for reading");
    exit(-1);
  }

  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    if (line[0]!='#') {
      char *package_pin=strstr(line,"PACKAGE_PIN");
      char *get_ports=strstr(line,"get_ports");
      char *pin_name=NULL;
      char *signal_name=NULL;
      
      if (package_pin) {
	pin_name=&package_pin[strlen("PACKAGE_PIN ")];
	for(int i=0;pin_name[i];i++) if (pin_name[i]==' ') { pin_name[i]=0; break; }      
      }
      
      if (get_ports) {
	int opening_square_brackets=0;
	signal_name=&get_ports[strlen("get_ports ")];      
	for(int i=0;signal_name[i];i++) {
	  if (signal_name[i]=='[') opening_square_brackets++;
	  if (signal_name[i]==']') {
	    if (opening_square_brackets) opening_square_brackets--;
	    else { signal_name[i]=0; break; }
	  }
	}
      }

      // Trim { and } from names where required
      while (signal_name&&signal_name[0]=='{') signal_name++;
      while (signal_name&&signal_name[0]&&signal_name[strlen(signal_name)-1]=='}')
	     signal_name[strlen(signal_name)-1]=0;
      
      if (pin_name&&signal_name) {
	//      printf("Found pin '%s' for signal '%s'\n",pin_name,signal_name);
	pin_names[pin_count]=strdup(pin_name);
	signal_names[pin_count]=strdup(signal_name);
	pin_count++;
      }
    }
    
    line[0]=0; fgets(line,1024,f);
  }

  fclose(f);
  return 0;
}

int parse_bsdl(char *bsdl)
{
  FILE *f=fopen(bsdl,"r");
  if (!f) {
    perror("Could not open BSDL file for reading");
    exit(-1);
  }

  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    if (sscanf(line,"attribute BOUNDARY_LENGTH of %s : entity is %d;",
	       part_name,&boundary_bit_count)==2) {
      fprintf(stderr,"FPGA is assumed to be a %s, with %d bits of boundary scan data.\n",
	      part_name,boundary_bit_count);
    }
    int bit_number;
    char bit_name[1024];
    char bit_type[1024];
    char bit_default[1024];
    int n=sscanf(line,"%*[ \t]\"%*[ \t]%d (BC_%*d, %[^,], %[^,], %[^,)]",
		 &bit_number,bit_name,bit_type,bit_default);
    if (n==4) {
      if (bit_number>=0&&bit_number<MAX_BOUNDARY_BITS) {
	boundary_bit_type[bit_number]=strdup(bit_type);
	boundary_bit_fullname[bit_number]=strdup(bit_name);
        char *bit_pin=bit_name;
	for(int i=0;bit_name[i];i++) if (bit_name[i]=='_') bit_pin=&bit_name[i+1];
	boundary_bit_pin[bit_number]=strdup(bit_pin);
	if (0) fprintf(stderr,"Found boundary scan bit #%d : %s %s %s (pin %s)\n",
		       bit_number,bit_name,bit_type,bit_default,bit_pin);
      }
    } 
	       
    
    line[0]=0; fgets(line,1024,f);
  }

  fclose(f);
  return 0;
}

#define BOUNDARY_PPAT INT32(0xff), REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff), REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff), REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff),  REPEAT10(0xff)

static uint8_t boundary_ppattern[] = DITEM(BOUNDARY_PPAT);


int xilinx_boundaryscan(char *xdc,char *bsdl,char *sensitivity)
{
  ENTER();

  char last_rdata[1024];
  int loop=1;
  int first_time=1;
  
  if (xdc) parse_xdc(xdc);
  else {
    fprintf(stderr,"WARNING: No XDC file, so cannot associate pins to project top-level port signals.\n");
  }
  for(int i=0;i<MAX_BOUNDARY_BITS;i++) {
    boundary_bit_type[i]=NULL;
    boundary_bit_fullname[i]=NULL;
    boundary_bit_pin[i]=NULL;
  }
  if (bsdl) parse_bsdl(bsdl);
  else {
    fprintf(stderr,"WARNING: No BSDL file, so cannot decode boundary scan information.\n");
  }

  char *bbit_names[MAX_BOUNDARY_BITS];
  int bbit_ignore[MAX_BOUNDARY_BITS];
  int bbit_show[MAX_BOUNDARY_BITS];
  char bbit_vcdchar[MAX_BOUNDARY_BITS];

  int next_vcdchar=33;
  
  // Map JTAG bits to pins
  for(int i=0;i<boundary_bit_count;i++) {
    char *s="<unknown>";
    if (boundary_bit_pin[i]) {
      for(int j=0;j<pin_count;j++)
	if (!strcmp(pin_names[j],boundary_bit_pin[i])) s=signal_names[j];
      if (!strcmp(boundary_bit_type[i],"input"))
	bbit_names[i]=strdup(s);
      else {
	// Not an input bit, so assume its a control bit.
	char t[1024];
	snprintf(t,1024,"%s.ctl",s);
	bbit_names[i]=strdup(t);
      }
      if (!strcmp(s,"<unknown>")) {
	//	printf("Unknown signal '%s'\n",boundary_bit_pin[i]);
	s=boundary_bit_pin[i];
      }
    } else bbit_names[i]="<unknown>";
    bbit_vcdchar[i]=0;
    if (!strcmp("CLK_IN",s)) bbit_ignore[i]=1; else bbit_ignore[i]=0;
    if (sensitivity) {
      if (!i) printf("Applying sensitivity list '%s'\n",sensitivity);
      if (strcasestr(sensitivity,s)) {
	bbit_ignore[i]=0;
	if (next_vcdchar<=126) {
	  bbit_vcdchar[i]=next_vcdchar++;
	} else {
	  if (vcd)
	    fprintf(stderr,"WARNING: Too many signals on sensitivity list for VCD output.\n");
	}
	printf("Adding '%s' to sensitivity list.\n",s);
      } else bbit_ignore[i]=1;
    }
    if (boundary_bit_type[i]&&(!strcmp(boundary_bit_type[i],"input")))
      bbit_show[i]=1; else {
      bbit_show[i]=0;
    }
  }

  // Write out VCD file header.
  if (vcd) {
    time_t the_time=time(0);
    fprintf(vcd,"$date\n"
	    "   %s\n"
	    "$end\n"
	    "$version\n"
	    "   MEGA65 monitor_load JTAG scan tool.\n"
	    "$end\n"
	    "$comment\n"
	    "   No comment.\n"
	    "$end\n"
	    "$timescale 1us $end\n"
	    "$scope module logic $end\n"
	    ,
	    ctime(&the_time));
    for(int i=0;i<MAX_BOUNDARY_BITS;i++) {
      if (bbit_vcdchar[i]) {
	fprintf(vcd,"$var wire 1 %c %s $end\n",
		bbit_vcdchar[i],bbit_names[i]);
	
      }
    }
    fprintf(vcd,"$upscope $end\n"
	    "$enddefinitions $end\n"
	    "$dumpvars\n");
    for(int i=0;i<MAX_BOUNDARY_BITS;i++) {
      if (bbit_vcdchar[i]) {
	fprintf(vcd,"x%c\n",
		bbit_vcdchar[i]);
	
      }
    }
    fprintf(vcd,"$end\n");
  }
  
  unsigned long long start_time = gettime_us();
  
  do {
  
    write_tms_transition("IR1");

    LOGNOTE("Checkpoint pre marker_for_reset()");

    // Send 1 + 4 TMS reset bits?
    marker_for_reset(4);

    // PGS: Try to explicitly send the IDCODE command.
    // Once we get this working, we know we can then adapt for BOUNDARY command.
    // The following seems to work:
    // 1. Switch to idle.
    // 2. Switch to Select IR scan
    // 3. Clock a null bit (maybe to switch to capture IR ?)
    // 4. Send IDCODE command. Not sure why we need 5 instead of 6 for length/
    // 5. Switch to IDLE after done
    ENTER_TMS_STATE('I');
    ENTER_TMS_STATE('S');
    write_bit(0, 0, 0xff, 0);     // Select first device on bus
    write_bit(0, 5, IRREG_SAMPLE, 0);     // Send IDCODE command
    ENTER_TMS_STATE('I');
    
    LOGNOTE("Checkpoint pre write-pattern");

    // This sends the transition to Shift-DR, but doesn't seem to actually send
    // the IDCODE command.  Does the FPGA default to IDCODE?
    // Yes: This seems to be the case, according to here:
    // https://forums.xilinx.com/t5/Spartan-Family-FPGAs-Archived/Spartan-3AN-200-JTAG-Idcode-debugging-on-a-new-board/td-p/131792
    uint8_t *rdata = write_pattern(0, boundary_ppattern, 'I');

    unsigned long long now = gettime_us();
    unsigned long long time_delta = now - start_time;

    
    if (!bsdl) {
      dump_bytes(0,"boundary data",rdata,256);
    } else {
      int count_shown=0;
      for(int i=0;i<boundary_bit_count;i++) {
	int value=(rdata[(i)>>3]>>((i)&7))&1;
	int last_value=(last_rdata[(i)>>3]>>((i)&7))&1;
	
	if (bbit_show[i]|bbit_vcdchar[i])
	  {
	    if (first_time||last_value!=value) {
	      
	      if ((first_time&&((!sensitivity)||vcd))
		   ||(!bbit_ignore[i]))
		{

		  if(!count_shown) {
		    if (vcd) fprintf(vcd,"#%lld\n",time_delta);
		    else
		      printf("T+%lldusec >>> Signal(s) changed.\n",
			     time_delta);

		  }
		  count_shown++;

		  if (vcd) {
		    if (bbit_vcdchar[i])
		      fprintf(vcd,"%d%c\n",value,bbit_vcdchar[i]);
		  }
		  else
		    printf("bit#%d : %s (pin %s, signal %s) = %x\n",
			   i,
			   boundary_bit_fullname[i],
			   boundary_bit_pin[i],
			   bbit_names[i],value);
	      }
	    }
	  }
      }
      if (vcd) fflush(vcd);
    }

    LOGNOTE("Checkpoint post write-pattern");

    ENTER_TMS_STATE('I');

    // Copy this data to old
    bcopy(rdata,last_rdata,1024);
    first_time=0;
    
  } while(loop);
    
    EXIT();
    return 0;
}
