#include <stdio.h>

volatile unsigned char *i2c_master=(unsigned char *)0xd6d0L;

unsigned char bus,addr,i;

void write_register(const unsigned char bus,const unsigned char addr, const unsigned char regnum, const unsigned char value)
{
#pragma optimize(push, off)
  
  // Set up bus and address
  i2c_master[0]=bus;
  i2c_master[2]=addr;

  // Reset I2C bus
  i2c_master[1]=0x00;
  i2c_master[1]=0x01;

  // Wait for bus to go ready?
  do {
    if ((i2c_master[1]&0xc7)==0x01) break;
  } while(1);

  /*
    When writing to $D6D1:
    Bit 0 = _RESET
    Bit 1 = Command Enable
    Bit 2 = READ/_WRITE

    When reading:
    Bit 7 = ERROR
    Bit 6 = BUSY
  */

  // Issue WRITE command to set the register to read from
  i2c_master[3]=regnum;
  i2c_master[1]
    =0x01   // Release from reset
    |0x02   // Issue a command
    |0x00;  // WRITE

  // At 1MHz the I2C transaction happens so fast, that
  // we just wait for BUSY to clear.

  // Wait for busy to assert
  while(!(i2c_master[1]&0x40)) continue;

  // Wait for busy to clear
  while((i2c_master[1]&0x40)) continue;
  
  i2c_master[3]=value;
  i2c_master[1]=0x01 // Release from resets
    | 0x02 // do command
    | 0x00; // Write
  
  // Wait for busy to assert
  while(!(i2c_master[1]&0x40)) continue;

  // Wait for busy to clear
  while((i2c_master[1]&0x40)) continue;

  // Check success by checking error bit
  if (i2c_master[1]&0x80) {
    // Error -- so do no more on this address;
    return;
  }
#pragma optimize(pop)
}

unsigned char read_register(const unsigned char bus,const unsigned char addr, const unsigned char regnum)
{
#pragma optimize(push, off)
  
  // Set up bus and address
  i2c_master[0]=bus;
  i2c_master[2]=addr;

  // Reset I2C bus
  i2c_master[1]=0x00;
  i2c_master[1]=0x01;

  // Wait for bus to go ready?
  do {
    if ((i2c_master[1]&0xc7)==0x01) break;
  } while(1);

  /*
    When writing to $D6D1:
    Bit 0 = _RESET
    Bit 1 = Command Enable
    Bit 2 = READ/_WRITE

    When reading:
    Bit 7 = ERROR
    Bit 6 = BUSY
  */

  // Issue WRITE command to set the register to read from
  i2c_master[3]=regnum;
  i2c_master[1]
    =0x01   // Release from reset
    |0x02   // Issue a command
    |0x00;  // WRITE

  // At 1MHz the I2C transaction happens so fast, that
  // we just wait for BUSY to clear.

  // Wait for busy to assert
  while(!(i2c_master[1]&0x40)) continue;
  
  // Check success by checking error bit
  //  if (i2c_master[1]&0x80) {
    // Error -- so do no more on this address;
  //   return 0xFF;
  // }
  
  // Issue READ command 
  i2c_master[3]=regnum;

  // Wait for busy to clear before issuing read
  // (This is required to correctly read from the IO expanders,
  // since they actually don't change address on request unless there
  // is a STOP between the set address and the actual read.
  while((i2c_master[1]&0x40)) continue;

  i2c_master[1]
    =0x01   // Release from reset
    |0x02   // Issue a command
    |0x04;  // READ not write

  // At 1MHz the I2C transaction happens so fast, that
  // we just wait for BUSY to clear.

  // Wait for busy to assert
  while(!(i2c_master[1]&0x40)) continue;
  
  // Wait for busy to clear
  while((i2c_master[1]&0x40)) continue;

  // Check success by checking error bit
  if (i2c_master[1]&0x80) {
    // Error -- so do no more on this address;
    return 0xFF;
  }

  // Return value read
  return i2c_master[4];
#pragma optimize(pop)
  
}

void probe_address(const unsigned char bus,const unsigned char addr)
{

#pragma optimize(push, off)
  
  // Set up bus and address
  i2c_master[0]=bus;
  i2c_master[2]=addr;

  // Reset I2C bus
  i2c_master[1]=0x00;
  i2c_master[1]=0x01;

  // Wait for bus to go ready?
  do {
    if ((i2c_master[1]&0xc7)==0x01) break;
  } while(1);

  /*
    When writing to $D6D1:
    Bit 0 = _RESET
    Bit 1 = Command Enable
    Bit 2 = READ/_WRITE

    When reading:
    Bit 7 = ERROR
    Bit 6 = BUSY
  */

  // Issue READ command 

  // Begin reading from register $00
  i2c_master[3]=0x00;

  i2c_master[1]
    =0x01   // Release from reset
    |0x02   // Issue a command
    |0x04;  // READ not write

  // At 1MHz the I2C transaction happens so fast, that
  // we just wait for BUSY to clear.

  // Wait for busy to assert
  while(!(i2c_master[1]&0x40)) continue;
  
  // Wait for busy to clear
  while((i2c_master[1]&0x40)) continue;

  // Check success by checking error bit
  if (i2c_master[1]&0x80) {
    // Error -- so do no more on this address;
    return;
  }
#pragma optimize(pop)

  printf("Found dev $%02x (%d)\n  ",
	 addr,addr);

  // Get back to start of 16 byte slab of registers
  // (since detection reads once)
  for(i=0;i<15;i++)
    read_register(bus,addr,i);

  for(i=0;i<12;i++)
    printf("%02X ",read_register(bus,addr,i));
  printf("\n  ");
  for(i=12;i<24;i++)
    printf("%02X ",read_register(bus,addr,i));
  printf("\n");
  if (addr==0x32) {
    printf("  ");
    for(i=24;i<36;i++)
      printf("%02X ",read_register(bus,addr,i));
    printf("\n  ");
    for(i=36;i<48;i++)
      printf("%02X ",read_register(bus,addr,i));
    printf("\n  ");
    for(i=48;i<60;i++)
      printf("%02X ",read_register(bus,addr,i));
    printf("\n  ");
    for(i=60;i<72;i++)
      printf("%02X ",read_register(bus,addr,i));
    printf("\n");

    // Enable X,Y,Z axes and 10Hz data collection
    write_register(bus,addr,0x20,0x27);
  }

  
}


void main(void)
{
#pragma optimize(push,off)
  // Enable MEGA65 IO
  *(unsigned char *)0xD02fL=0x47;
  *(unsigned char *)0xD02fL=0x53;

  // Fast CPU
  *(unsigned char *)0=0x41;
#pragma optimize(pop)

  
  printf("%c",0x93);

  while(1) 
    for(bus=1;bus<2;bus++)
      {
	printf("%c",0x13);
	// printf("%cScanning bus %d\n",0x13,bus);
	addr=0;
	do {
	  probe_address(bus,addr);
	  addr+=2;
	} while(addr);
      }
}
