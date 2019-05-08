#include <stdio.h>

volatile unsigned char *i2c_master=(unsigned char *)0xd6d0L;

unsigned char bus,addr;

void probe_address(const unsigned char bus,const unsigned char addr)
{

  // Set up bus and address
  i2c_master[0]=bus;
  i2c_master[2]=addr;

  // Reset I2C bus
  i2c_master[1]=0x08;
  i2c_master[1]=0x09;

#pragma optimize(push, off)
  // Wait for bus to go ready?
  do {
    if ((i2c_master[1]&0xc7)==0x01) break;
    *(unsigned char *)0x0400 = i2c_master[1];
  } while(1);

  // Ask bus to do something?
  i2c_master[1]=0x0f;

  // At 1MHz the I2C transaction happens so fast, that
  // we just wait for BUSY to clear.
  
  // Wait for busy to assert
  //  while(!(i2c_master[1]&0x40)) continue;

  // Wait for error flag to clear
  //  while((i2c_master[1]&0x80)) continue;

  // Wait for busy to clear
  while((i2c_master[1]&0x40)) continue;

  // Check success by checking error bit
  if (i2c_master[1]&0x80) {
    // Error -- so do no more on this address;
    return;
  }
#pragma optimize(pop)

  printf("  found device $%02x (%d)\n",addr,addr);
}


void main(void)
{
#pragma optimize(push,off)
  *(unsigned char *)0xD02fL=0x47;
  *(unsigned char *)0xD02fL=0x53;
#pragma optimize(pop)
  
  for(bus=1;bus<2;bus++)
    {
      printf("Scanning bus %d\n",bus);
      addr=0;
      do {
	probe_address(bus,addr);
	addr+=2;
      } while(addr);
    }
}
