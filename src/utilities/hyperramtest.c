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
  $BFFFFF2.2 = hr_clk_n_int
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
  
  if (v)
    hr_flags|=1;
  lpoke(0xbfffff2,hr_flags);  
}


void set_clock(unsigned char v)
{
  hr_flags&=(0xff-0x0c);
  
  if (v)
    hr_flags|=8;
  else
    hr_flags|=4;
  lpoke(0xbfffff2,hr_flags);  
}

void set_cs(unsigned char v)
{
  hr_flags&=(0xff-0x30);
  hr_flags|=(v<<4);
  lpoke(0xbfffff2,hr_flags);
}

unsigned char i;

void main(void)
{
  hr_debug_enable();
  set_clock(0);
  set_reset(1);
  set_cs(1);
  set_cs(2);
  set_cs(1);
  set_rwds(1);
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
  
  
}
