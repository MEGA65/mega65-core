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

unsigned char v,i,j,write_latency;
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

  for(write_latency=0x00;write_latency<0x20;write_latency++) {
    printf("Write latency = $%02x:\n",write_latency);
    
    for(i=0;i<16;i++) lpoke(0x8000000+i,0xbd);    
    for(i=0;i<16;i++) lpoke(0x8000000+i,0x40+i);    
    for(i=0;i<16;i++) after[i]=lpeek(0x8000000+i);

    for(j=0;j<16;j++) {
      test_num++;

      for(i=0;i<16;i++) before[i]=lpeek(0x8000000+(test_num<<4)+i);
      
      // Find byte value that is not present in any of the bytes of the row
      v=0x40;
      i=0;
      while(i<16) {
	for(i=0;i<16;i++) if (before[i]==v) break;
	if (i<16) v++;
      }
      printf("Writing unique value $%0x to $%08lx\n",v,
	     0x8000000+(test_num<<4)+j);
      
      lpoke(0x8000000+(test_num<<4)+j,v);

      for(i=0;i<16;i++) after[i]=lpeek(0x8000000+(test_num<<4)+i);

      for(i=0;i<16;i++) {
	if (after[i]==v) {
	  if (i==j) printf("Value was correctly written.\n");
	  else printf("  Value ended up in $%08lx\n",0x8000000+(test_num<<4)+i);
	}
	else if (after[i]!=before[i]) printf("  $xxxxxx%x corrupted: $%02x -> $%02x\n",
					     i,before[i],after[i]);
      }

#if 0
      printf("Before:\n");
      for(i=0;i<16;i++) {
	if (!(i&1)) printf(" ");
	printf("%02x",before[i]);
      }
    //    printf("\n");
      printf("After:\n");
      for(i=0;i<16;i++) {
	if (!(i&1)) printf(" ");
	printf("%02x",after[i]);
      }
      printf("\n");
#endif
      
      while(PEEK(0xD610)) POKE(0xD610,0);
      printf("Press any key...\n");
      while(!PEEK(0xD610)) continue;
      while(PEEK(0xD610)) POKE(0xD610,0);
    }
    
  }
  
  
}
