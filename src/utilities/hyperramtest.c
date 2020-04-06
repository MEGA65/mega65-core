#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <fileio.h>

/*
  Bit bash interface for Hyperram:

  $BFFFFF0 = read debug mode ($FF = debug mode, $00 = normal mode)  (write $DE to enable, or $1d to disable)
  $BFFFFF1 = Read hr_d, and if hr_ddr bit set, write it
  $BFFFFF2.0 = hr_rwds
  $BFFFFF2.1 = hr_reset_int
  $BFFFFF2.2 = hr_rwds_ddr
  $BFFFFF2.3 = hr_clk_p_int
  $BFFFFF2.4 = hr_cs0_int
  $BFFFFF2.5 = hr_cs1_int
  $BFFFFF2.6 = hr_ddr (data direction for hr_d)
  $BFFFFF2.7 = cache_enable
  $BFFFFF3 = write_latency
  $BFFFFF4 = read hyperram state machine value
*/

unsigned char hr_flags=0;

void hr_debug_enable(void)
{
  lpoke(0xbfffff0,0xDE);
}

void hr_debug_disable(void)
{
  lpoke(0xbfffff0,0x1D);
}

unsigned char read_hr_d(void)
{
  hr_flags&=(0xff-0x40);
  lpoke(0xbfffff2,hr_flags);
  return lpeek(0xBFFFFF0);
}

void write_hr_d(unsigned char v)
{
  hr_flags|=0x40;
  lpoke(0xbfffff1,v);
}

void set_reset(unsigned char v)
{
  hr_flags&=(0xff-0x02);
  
  if (v)
    hr_flags|=2;
  lpoke(0xbfffff2,hr_flags);  
}

void set_rwds(unsigned char v)
{
  hr_flags&=(0xff-0x01);
  hr_flags|=0x04; // set ddr
  
  if (v)
    hr_flags|=1;
  lpoke(0xbfffff2,hr_flags);  
}

unsigned char read_rwds(void)
{
  hr_flags&=(0xff-0x04);
  lpoke(0xbfffff2,hr_flags);
  return lpeek(0xbfffff2)&0x01;
}


void set_clock(unsigned char v)
{
  hr_flags&=(0xff-0x0c);
  
  if (v) hr_flags|=8;
  lpoke(0xbfffff2,hr_flags);  
}

void set_cs(unsigned char v)
{
  hr_flags&=(0xff-0x30);
  hr_flags|=(v<<4);
  lpoke(0xbfffff2,hr_flags);
}

unsigned char v,i,j,write_latency,correct,incorrect,actual,corrupt;
unsigned char before[16];
unsigned char after[16];

unsigned long test_num=0;

void main(void)
{
#if 0
  hr_debug_enable();
  set_clock(0);
  set_reset(1);
  set_cs(1);
  set_cs(2);
  set_cs(1);
  read_rwds(); // cause RWDS to tri-state
  // Command is read (bit 47 high), normal address space (bit 46=0), linear burst (bit 45 set)
  set_rwds(0xa0);  
  set_clock(1);
  // Address = 0 (all other bytes zero)
  set_rwds(0x0);  
  set_clock(0);
  set_rwds(0x0);  
  set_clock(1);
  set_rwds(0x0);  
  set_clock(0);
  set_rwds(0x0);  
  set_clock(1);
  set_rwds(0x0);  
  set_clock(0);
  for(i=0;i<32;i++)
    {
      printf("%2d : $%02x, ",i,read_hr_d());
      set_clock((i&1)^1);
    }
#endif

  /*
    Test HyperRAM reading and writing.
  */

  // Cache off
  lpoke(0xbfffff2,0x00);
  
  // Work out which write latency works for which offset
  for(i=0;i<16;i++) {
    printf("Analysing for addresses $xxxxxxx%x:\n",i);

    for(write_latency=0x0e;write_latency<0x0f;write_latency++)
      for(j=0;j<16;j++) {
	for(actual=0;actual<4;actual++) {
	  lpoke(0xbfffff3,0x0f); for(v=0;v<48;v++) lpoke(0x8000000+v,0xbd);
	  lpoke(0xbfffff3,0x0e); for(v=0;v<48;v++) lpoke(0x8000000+v,0xbd);
	  lpoke(0xbfffff3,0x0d); for(v=0;v<48;v++) lpoke(0x8000000+v,0xbd);
	  lpoke(0xbfffff3,0x0c); for(v=0;v<48;v++) lpoke(0x8000000+v,0xbd);
	  lpoke(0xbfffff3,0x0b); for(v=0;v<48;v++) lpoke(0x8000000+v,0xbd);
	}
	for(v=0;v<48;v++)
	  if (lpeek(0x8000000+v)!=0xbd) {
	    printf("ERROR: Could not erase 48 byte block.\n");
	    return;
	  }
	
	lpoke(0xbfffff3,write_latency);
	lpoke(0x8000010+j,0x55);
	incorrect=0; correct=0; corrupt=0;
	actual=0xff;
	for(v=0;v<48;v++) {
	  if (lpeek(0x8000000+v)==0x55) {
	    if (v==(0x10+i)) correct=1;
	    else { incorrect++; actual=v; }
	  } else if (lpeek(0x8000000+v)!=0xbd) {
	    corrupt++;
	  }
	}

	if (correct&&(!incorrect)&&(!corrupt))
	  printf("write latency $%02x works perfectly.\n",write_latency);
        else if ((!corrupt)&&(!correct)&&(incorrect==1)) {
	  printf("write latency $%02x writes to memory location delta %d\n",
		 write_latency,actual-0x10-i);
	}
	else
	  printf("wl$%02x, j$%02x: %d, %d, %d\n",write_latency,j,
		 correct,incorrect,corrupt);

	for(v=0;v<48;v++) {
	  if (!(v&0x3)) printf(" ");
	  if (!(v&0xf)) printf("\n");
	  printf("%02x",lpeek(0x8000000+v));
	}
	printf("\n");
		 
#if 1
      while(PEEK(0xD610)) POKE(0xD610,0);
      //      printf("Press any key...\n");
      while(!PEEK(0xD610)) continue;
      while(PEEK(0xD610)) POKE(0xD610,0);
#endif  

	
      }
  }

  
}
