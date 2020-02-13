#include <stdio.h>
#include <string.h>

#include "mega65_hal.h"
#include "mega65_memory.h"
#include "dirent.h"
#include "fileio.h"

char *select_bitstream_file(void);
void fetch_rdid(void);

unsigned char joy_x=100;
unsigned char joy_y=100;

unsigned char latency_code=0xff;
unsigned char reg_cr1=0x00;
unsigned char reg_sr1=0x00;

unsigned char manufacturer;
unsigned short device_id;
unsigned short cfi_data[512];
unsigned short cfi_length=0;

unsigned char data_buffer[512];
// Magic string for identifying properly loaded bitstream
unsigned char bitstream_magic[16]="MEGA65BITSTREAM0";

unsigned short mb = 0;

short i,x,y,z;
short a1,a2,a3;
unsigned char n=0;

void progress_bar(unsigned char onesixtieths);
void read_data(unsigned long start_address);
void program_page(unsigned long start_address);
void erase_sector(unsigned long address_in_sector);

void wait_10ms(void)
{
  // 16 x ~64usec raster lines = ~1ms
  int c=160;
  unsigned char b;
  while(c--) {
    b=PEEK(0xD012U);    
    while (b==PEEK(0xD012U))
      continue;
  }
}

unsigned char sprite_data[63]={
  0xff,0,0,
  0xe0,0,0,
  0xb0,0,0,
  0x98,0,0,
  0x8c,0,0,
  0x86,0,0,
  0x83,0,0,
  0x81,0x80,0,

  0,0xc0,0,
  0,0x60,0,
  0,0x30,0,
  0,0x18,0,
  0,0,0,
  0,0,0,
  0,0,0,
  0,0,0,

  0,0,0,
  0,0,0,
  0,0,0,
  0,0,0,
  0,0,0
};

/*
  $D6C8-B = address for FPGA to boot from in flash
  $D6CF = trigger address for FPGA reconfiguration: Write $42 to trigger

  $D6CC.0 = data bit 0 / SI (serial input)
  $D6CC.1 = data bit 1 / SO (serial output)
  $D6CC.2 = data bit 2 / WP# (write protect)
  $D6CC.3 = data bit 3 / HOLD#
  $D6CC.4 = tri-state SI only (to enable single bit SPI communications)
  $D6CC.5 = clock
  $D6CC.6 = CS#
  $D6CC.7 = data bits DDR (all 4 bits at once)
*/
#define BITBASH_PORT 0xD6CCU

/*
  $D6CD.0 = clock free run if set, or under bitbash control when 0
  $D6CD.1 = alternate control of clock pin
*/
#define CLOCKCTL_PORT 0xD6CDU

void reconfig_fpga(unsigned long addr)
{
  // Black screen when reconfiguring
  POKE(0xd020,0); 
  POKE(0xd011,0);
 
  mega65_io_enable();
  POKE(0xD6C8U,(addr>>0)&0xff);
  POKE(0xD6C9U,(addr>>8)&0xff);
  POKE(0xD6CAU,(addr>>16)&0xff);
  POKE(0xD6CBU,(addr>>24)&0xff);

  // Try to reconfigure
  POKE(0xD6CFU,0x42);
  while(1) {
    POKE(0xD020,PEEK(0xD012));
    POKE(0xD6CFU,0x42);

    // Grey screen if reconfig failing
    POKE(0xd020,0x0d);     
  }
}

unsigned char buffer[512];
unsigned long addr;
unsigned char progress=0;
unsigned long progress_acc=0;

unsigned char verify_enable=0;
unsigned char tries;

void reflash_slot(unsigned char slot)
{
  unsigned short bytes_returned;
  unsigned char fd;
  unsigned char *file=select_bitstream_file();
  if (!file) return;
  if ((unsigned short)file==0xffff) return;

  
  printf("%c",0x93);

  closeall();
  fd=open(file);
  if (fd==0xff) {
    // Couldn't open the file.
    printf("ERROR: Could not open flash file '%s'\n",file);
    printf("\nPress any key to continue.\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    while (!PEEK(0xD610)) continue;

    while(1) continue;
    
    return;
  }

  printf("Erasing flash slot...%c%c%c%c%c%c\n",17,17,17,17,17,17);
  lfill((unsigned long)buffer,0,512);

  // Do a smart erase: read blocks, and only erase pages if they are
  // not all $FF.  Later we can make it even smarter, and only clear
  // pages where bits need clearing.
  // Also, we will assume the BIT files contain the 4KB header we want
  // so we will just write upto 4MB of stuff in one go.
  progress=0; progress_acc=0;

  for(addr=(4L*1024L*1024L)*slot;addr<(4L*1024L*1024L)*(slot+1);addr+=512) {
    progress_acc+=512;
    if (progress_acc>26214) {
      progress_acc-=26214;
      progress++;
      progress_bar(progress);
    }
    read_data(addr);
    for(i=0;i<512;i++) if (data_buffer[i]!=0xff) break;
    i=0; tries=0;

    if (i==512) continue;
    
    while (i<512) {
      erase_sector(addr);
      // Then verify that the sector has been erased
      read_data(addr);
      for(i=0;i<512;i++) if (data_buffer[i]!=0xff) break;
      if (i<512) {
	tries++;
	if (tries==16) {
	  printf("\n! Failed to erase flash page at $%llx\n",addr);
	  printf("  byte %d = $%x instead of $FF\n",i,data_buffer[i]);
	  printf("Please reset and try again.\n");
	  while(1) continue;
	}
      }
    }

    // Step ahead to the next 4KB boundary, as flash sectors can't be smaller than
    // that.
    progress_acc+=0xe00-(addr&0xfff);
    addr+=0x1000; addr&=0xfffff000;
    addr-=512; // since we add this much in the for() loop
    
  }
  
  // Read the flash file and write it to the flash
  printf("Writing bitstream to flash...\n\n",0x93);
  progress=0; progress_acc=0;
  for(addr=(4L*1024L*1024L)*slot;addr<(4L*1024L*1024L)*(slot+1);addr+=512) {
    progress_acc+=512;
    if (progress_acc>26214) {
      progress_acc-=26214;
      progress++;
    }
    progress_bar(progress);

    bytes_returned=read512(buffer);
    
    if (!bytes_returned) break;

    // Verify
    i=0;
    while(i<256) {
      read_data(addr);
      for(i=0;i<256;i++) if (data_buffer[i]!=buffer[i]) break;
      if (i==256) {
	printf("%cPage $%08llx is already programmed.\n",0x91,addr);
	break;
      }

      // Programming works on 256 byte pages, so we have to write two of them.
      lcopy((unsigned long)&buffer[0],(unsigned long)data_buffer,256);
      program_page(addr);

      read_data(addr);
      for(i=0;i<256;i++) if (data_buffer[i]!=buffer[i]) break;
      if (i==256) {
	break;
      }
      printf("%cPage $%08llx written.\n",0x91,addr);

      if (!verify_enable) break;
      
      printf("Verification error at address $%llx:\n",
	     addr+i);
      printf("Read back $%x instead of $%x\n",
	     data_buffer[i],buffer[i]);
      printf("Press any key to continue...\n");
      while(PEEK(0xD610)) POKE(0xD610,0);
      while(!PEEK(0xD610)) continue;
      while(PEEK(0xD610)) POKE(0xD610,0);
      printf("Data read from flash is:\n");
      for(i=0;i<256;i+=64) {
	for(x=0;x<64;x++) {
	  if (!(x&7)) printf("%04x : ",i+x);
	  printf(" %02x",data_buffer[i+x]);
	  if ((x&7)==7) printf("\n");
	}
      
	printf("Press any key to continue...\n");
	while(PEEK(0xD610)) POKE(0xD610,0);
	while(!PEEK(0xD610)) continue;
	while(PEEK(0xD610)) POKE(0xD610,0);
      }

      printf("Correct data is:\n");
      for(i=0;i<256;i+=64) {
	for(x=0;x<64;x++) {
	  if (!(x&7)) printf("%04x : ",i+x);
	  printf(" %02x",buffer[i+x]);
	  if ((x&7)==7) printf("\n");
	}
      
	printf("Press any key to continue...\n");
	while(PEEK(0xD610)) POKE(0xD610,0);
	while(!PEEK(0xD610)) continue;
	while(PEEK(0xD610)) POKE(0xD610,0);
      }
      fetch_rdid();
      i=0; 
    }

    i=0;
    while(i<256) {
      read_data(addr);
      for(i=0;i<256;i++) if (data_buffer[256+i]!=buffer[256+i]) break;
      if (i==256) {
	printf("%cPage $%08llx is already programmed.\n",0x91,addr+256);
	break;
      }

      // Programming works on 256 byte pages, so we have to write two of them.
      lcopy((unsigned long)&buffer[256],(unsigned long)data_buffer,256);
      program_page(addr+256);

      read_data(addr);
      for(i=0;i<256;i++) if (data_buffer[256+i]!=buffer[256+i]) break;
      if (i==256) {
	break;
      }
      printf("%cPage $%08llx written.\n",0x91,addr+256);

      if (!verify_enable) break;

      printf("Verification error at address $%llx:\n",
	     addr+256+i);
      printf("Read back $%x instead of $%x\n",
	     data_buffer[i],buffer[i]);
      printf("Press any key to continue...\n");
      while(PEEK(0xD610)) POKE(0xD610,0);
      while(!PEEK(0xD610)) continue;
      while(PEEK(0xD610)) POKE(0xD610,0);
      printf("Data read from flash is:\n");
      for(i=0;i<256;i+=64) {
	for(x=0;x<64;x++) {
	  if (!(x&7)) printf("%04x : ",i+x);
	  printf(" %02x",data_buffer[256+i+x]);
	  if ((x&7)==7) printf("\n");
	}
      
	printf("Press any key to continue...\n");
	while(PEEK(0xD610)) POKE(0xD610,0);
	while(!PEEK(0xD610)) continue;
	while(PEEK(0xD610)) POKE(0xD610,0);
      }

      printf("Correct data is:\n");
      for(i=0;i<256;i+=64) {
	for(x=0;x<64;x++) {
	  if (!(x&7)) printf("%04x : ",i+x);
	  printf(" %02x",buffer[256+i+x]);
	  if ((x&7)==7) printf("\n");
	}
      
	printf("Press any key to continue...\n");
	while(PEEK(0xD610)) POKE(0xD610,0);
	while(!PEEK(0xD610)) continue;
	while(PEEK(0xD610)) POKE(0xD610,0);
      }
      fetch_rdid();
      i=0; 
    }
    
    
  }

  printf("%cFlash slot successfully written.\nPress any key to return to menu.\n");
  while(PEEK(0xD610)) POKE(0xD610,0);
  while(!PEEK(0xD610)) continue;
  POKE(0xD610,0);
  
  close(fd);

  return;
}

int bash_bits=0xFF;

unsigned int di;
void delay(void)
{
  // Slow down signalling when debugging using JTAG monitoring.
  // Not needed for normal operation.
  
  //   for(di=0;di<1000;di++) continue;
}

void spi_tristate_si(void)
{
  bash_bits|=0x02;
  POKE(BITBASH_PORT,bash_bits);
}

void spi_tristate_si_and_so(void)
{
  bash_bits|=0x03;
  bash_bits&=0x6f;
  POKE(BITBASH_PORT,bash_bits);
}

unsigned char spi_sample_si(void)
{
  // Make SI pin input
  bash_bits&=0x7F;
  bash_bits|=0x02;
  POKE(BITBASH_PORT,bash_bits);

  // Not sure why we need this here, but we do, else it only ever returns 1.
  // (but the delay can be made quite short)
  delay();
  
  if (PEEK(BITBASH_PORT)&0x02) return 1; else return 0;
}

void spi_so_set(unsigned char b)
{
  // De-tri-state SO data line, and set value
  bash_bits&=(0xff-0x01);
  bash_bits|=(0x1F-0x01);
  if (b) bash_bits|=0x01;
  POKE(BITBASH_PORT,bash_bits);
}


void spi_clock_low(void)
{
  bash_bits&=0xff-0x20;
  POKE(BITBASH_PORT,bash_bits);
}

void spi_clock_high(void)
{
  bash_bits|=0x20;
  POKE(BITBASH_PORT,bash_bits);
}

void spi_cs_low(void)
{
    bash_bits&=0xff-0x40;
    POKE(BITBASH_PORT,bash_bits);
}

void spi_cs_high(void)
{
  bash_bits|=0x40;
  POKE(BITBASH_PORT,bash_bits);
}


void spi_tx_bit(unsigned char bit)
{
  spi_clock_low();
  spi_so_set(bit);
  delay();
  spi_clock_high();
  delay();
}

void spi_tx_byte(unsigned char b)
{
  unsigned char i;
  
  for(i=0;i<8;i++) {
    spi_tx_bit(b&0x80);
    b=b<<1;
  }
}

unsigned char qspi_rx_byte()
{
  unsigned char b=0;
  unsigned char i;

  b=0;

  spi_tristate_si_and_so();
  for(i=0;i<2;i++) {
    spi_clock_low();
    b=b<<4;
    delay();
    b|=PEEK(BITBASH_PORT)&0x0f;
    spi_clock_high();
    delay();
  }

  return b;
}

unsigned char spi_rx_byte()
{
  unsigned char b=0;
  unsigned char i;

  b=0;

  spi_tristate_si();
  for(i=0;i<8;i++) {
    spi_clock_low();
    b=b<<1;
    delay();
    if (spi_sample_si()) b|=0x01;
    spi_clock_high();
    delay();
  }

  return b;
}

void read_registers(void)
{
  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT,0x00);

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x05);
  reg_sr1=spi_rx_byte();
  spi_cs_high();
  delay();

  // Config Register 1 (CR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x35);
  reg_cr1=spi_rx_byte();
  spi_cs_high();
  delay();  
}

void erase_sector(unsigned long address_in_sector)
{

  // XXX Send Write Enable command (0x06 ?)
  //  printf("activating write enable...\n");
  while(!(reg_sr1&0x02)) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x06);
    spi_cs_high();
    
    read_registers();
  }  
  
  // XXX Clear status register (0x30)
  //  printf("clearing status register...\n");
  while(reg_sr1&0x61) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x30);
    spi_cs_high();

    read_registers();
  }
    
  // XXX Erase 64/256kb (0xdc ?)
  // XXX Erase 4kb sector (0x21 ?)
  //  printf("erasing sector...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xdc);
  spi_tx_byte(address_in_sector>>24);
  spi_tx_byte(address_in_sector>>16);
  spi_tx_byte(address_in_sector>>8);
  spi_tx_byte(address_in_sector>>0);
  spi_cs_high();

  while(reg_sr1&0x01) {
    read_registers();
  }

  if (reg_sr1&0x20) printf("error erasing sector @ $%08x\n",address_in_sector);
  else {
    printf("sector at $%08llx erased.\n%c",address_in_sector,0x91);
  }
  
}

void program_page(unsigned long start_address)
{
  // XXX Send Write Enable command (0x06 ?)

  while(reg_sr1&0x01) {
    printf("flash busy. ");
    read_registers();
  }

  // XXX Send Write Enable command (0x06 ?)
  //  printf("activating write enable...\n");
  while(!(reg_sr1&0x02)) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x06);
    spi_cs_high();
    
    read_registers();
  }  
  
  // XXX Clear status register (0x30)
  //  printf("clearing status register...\n");
  while(reg_sr1&0x61) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x30);
    spi_cs_high();

    read_registers();
  }

  if (!reg_sr1&0x02) {
    printf("error: write latch cleared.\n");
  }
  
  // XXX Send Page Programme (0x12 for 1-bit, or 0x34 for 4-bit QSPI)
  //  printf("writing 256 bytes of data...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x12);
  spi_tx_byte(start_address>>24);
  spi_tx_byte(start_address>>16);
  spi_tx_byte(start_address>>8);
  spi_tx_byte(start_address>>0);
  for(x=0;x<256;x++) spi_tx_byte(data_buffer[x]);
  
  spi_cs_high();

  while(reg_sr1&0x01) {
    //    printf("flash busy. ");
    read_registers();
  }

  if (reg_sr1&0x60) printf("error writing data @ $%08llx\n",start_address);
  else {
    //    printf("data at $%08llx written.\n",start_address);
  }
  
}

void read_data(unsigned long start_address)
{
  
  // XXX Send read command (0x13 for 1-bit, 0x6c for QSPI)
  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT,0x00);

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x6c);
  spi_tx_byte(start_address>>24);
  spi_tx_byte(start_address>>16);
  spi_tx_byte(start_address>>8);
  spi_tx_byte(start_address>>0);

  // Table 25 latency codes
  switch(latency_code) {
  case 3:
    break;
  default:
    // 8 cycles = equivalent of 4 bytes
    for (z=0;z<4;z++) qspi_rx_byte();
    break;
  }

  // Actually read the data.
  for(z=0;z<512;z++)
    data_buffer[z]=qspi_rx_byte();
  
  spi_cs_high();
  delay();
  
}

void fetch_rdid(void)
{
  /* Run command 0x9F and fetch CFI etc data.
     (Section 9.2.2)
   */

  unsigned short i;

  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT,0x00);
  
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();

  spi_tx_byte(0x9f);

  // Data format according to section 11.2

  // Start with 3 byte manufacturer + device ID
  manufacturer=spi_rx_byte();
  device_id=spi_rx_byte()<<8;
  device_id|=spi_rx_byte();

  // Now get the CFI data block
  for(i=0;i<512;i++) cfi_data[i]=0x00;  
  cfi_length=spi_rx_byte();
  if (cfi_length==0) cfi_length = 512;
  for(i=0;i<cfi_length;i++)
    cfi_data[i]=spi_rx_byte();

  spi_cs_high();
  delay();
  spi_clock_high();
  delay();
  
}

struct erase_region {
  unsigned short sectors;
  unsigned int sector_size;
};

int erase_region_count=0;
#define MAX_ERASE_REGIONS 4
struct erase_region erase_regions[MAX_ERASE_REGIONS];

unsigned char slot_empty_check(unsigned short mb_num)
{
  unsigned long addr;
  for(addr=(mb_num*1048576L);addr<((mb_num+4)*1048576L);addr+=512)
    {
      read_data(addr);
      y=0xff;
      for(x=0;x<512;x++) y&=data_buffer[x];
      if (y!=0xff) return -1;

      *(unsigned long *)(0x0400)=addr;
    }
  return 0;
}

void main(void)
{
  unsigned char valid;
  
  mega65_io_enable();

  // Sprite 0 on
  lpoke(0xFFD3015L,0x01);
  // Sprite data at $03c0
  *(unsigned char *)2040 = 0x3c0/0x40;

  for(n=0;n<64;n++) 
    *(unsigned char*)(0x3c0+n)=
      sprite_data[n];
  
  // Disable OSK
  lpoke(0xFFD3615L,0x7F);  

  // Enable VIC-III attributes
  POKE(0xD031,0x20);
  
  // Clear screen
  printf("%c",0x93);    

  // Start by resetting to CS high etc
  bash_bits=0xff;
  POKE(BITBASH_PORT,bash_bits);
  delay();
  delay();
  delay();
  delay();
  delay();
  
  fetch_rdid();
  read_registers();
  if ((manufacturer==0xff) && (device_id==0xffff)) {
    printf("ERROR: Cannot communicate with QSPI            flash device.\n");
    return;
  }
  printf("qspi flash manufacturer = $%02x\n",manufacturer);
  printf("qspi device id = $%04x\n",device_id);
  printf("rdid byte count = %d\n",cfi_length);
  printf("sector architecture is ");
  if (cfi_data[4-4]==0x00) printf("uniform 256kb sectors.\n");
  else if (cfi_data[4-4]==0x01) printf("4kb parameter sectors with 64kb sectors.\n");
  else printf("unknown ($%02x).\n",cfi_data[4-4]);
  printf("part family is %02x-%c%c\n",
	 cfi_data[5-4],cfi_data[6-4],cfi_data[7-4]);
  printf("2^%d byte page, program typical time is 2^%d microseconds.\n",
	 cfi_data[0x2a-4],
	 cfi_data[0x20-4]);
  printf("erase typical time is 2^%d milliseconds.\n",
	 cfi_data[0x21-4]);

  // Work out size of flash in MB
  {
    unsigned char n=cfi_data[0x27-4];
    mb=1;
    n-=20;
    while(n) { mb=mb<<1; n--; }
  }
  printf("flash size is %dmb.\n",mb);

  // What erase regions do we have?
  erase_region_count=cfi_data[0x2c-4];
  if (erase_region_count>MAX_ERASE_REGIONS) {
    printf("error: device has too many erase regions. increase max_erase_regions?\n");
    return;
  }
  for(i=0;i<erase_region_count;i++) {
    erase_regions[i].sectors=cfi_data[0x2d-4+(i*4)];
    erase_regions[i].sectors|=(cfi_data[0x2e-4+(i*4)])<<8;
    erase_regions[i].sectors++;
    erase_regions[i].sector_size=cfi_data[0x2f-4+(i*4)];
    erase_regions[i].sector_size|=(cfi_data[0x30-4+(i*4)])<<8;
    printf("erase region #%d : %d sectors x %dkb\n",
	   i+1,erase_regions[i].sectors,erase_regions[i].sector_size>>2);
  }
  if (reg_cr1&4) printf("warning: small sectors are at top, not bottom.\n");
  latency_code=reg_cr1>>6;
  printf("latency code = %d\n",latency_code);
  if (reg_sr1&0x80) printf("flash is write protected.\n");
  if (reg_sr1&0x40) printf("programming error occurred.\n");
  if (reg_sr1&0x20) printf("erase error occurred.\n");
  if (reg_sr1&0x02) printf("write latch enabled.\n"); else printf("write latch not (yet) enabled.\n");
  if (reg_sr1&0x01) printf("device busy.\n");

#if 0
  read_data(0x400100L);
  printf("00: ");
  for(x=128;x<256;x++) {
    printf("%02x ",data_buffer[x]);
    if ((x&7)==7) {
      printf("\n");
      if (x!=0xff) printf("%02x: ",x+1);
    }
  }
  while(1) continue;
#endif
  
  while(1)
    {  

      // Clear screen
      printf("%c",0x93);

      // Draw footer line with instructions
      for(y=0;y<24;y++) printf("%c",0x11);
      printf("%c0-7 = Launch Core.  CTRL 0-7 = Edit Slo%c",0x12,0x92);
      POKE(1024+999,0x14+0x80);

      // Scan for existing bitstreams
      // (ignore golden bitstream at offset #0)
      for(i=0;i<mb;i+=4) {
	
	// Position cursor for slot
	z=i>>2;
	printf("%c%c%c%c%c",0x13,0x11,0x11,0x11,0x11);
	for(y=0;y<z;y++) printf("%c%c",0x11,0x11);
	
	read_data(i*1048576+0*256);
	//       for(x=0;x<256;x++) printf("%02x ",data_buffer[x]); printf("\n");
	y=0xff;
	valid=1;
	for(x=0;x<256;x++) y&=data_buffer[x];
	for(x=0;x<16;x++) if (data_buffer[x]!=bitstream_magic[x]) { valid=0; break; }
	
	// Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
	read_data(i*1048576+1*256);
	for(x=0;x<256;x++) y&=data_buffer[x];
	
	if (y==0xff) printf("(%d) EMPTY SLOT\n",i>>2);
	else {
	  if (!valid) {
	    if (!i) {
	      // Assume contains golden bitstream
	      printf("(%d) MEGA65 FACTORY CORE",i>>2);
	    } else {
	      printf("(%d) UNKNOWN CONTENT\n",i>>2);
	    }
#if 0
	    for(x=0;x<64;x++) {
	      printf("%02x ",data_buffer[x]);
	      if ((x&7)==7) printf("\n");
	    }
#endif
	  }
	  else {
	    // Something valid in the slot
	    printf("%c(%d) VALID\n",0x05,i>>2);
	    // Display info about it
	  }
	}
	// Check if entire slot is empty
	//    if (slot_empty_check(i)) printf("  slot is not completely empty.\n");
      }

      x=0;
      while(!x) {
	x=PEEK(0xd610);
      }

      if (x) {
	POKE(0xd610,0);
	if (x>='0'&&x<'8') {
	  if (x=='0') {
	    reconfig_fpga(0);
	  }
	  else reconfig_fpga((x-'0')*(4*1048576)+0); // +4096);
	}
	switch(x) {
	case 146: case 0x41: case 0x61:  // CTRL-0
	  reflash_slot(0);
	  break;
	case 144: case 0x42: case 0x62: // CTRL-1
	  reflash_slot(1);
	  break;
	case 5: case 0x43: case 0x63: // CTRL-2
	  reflash_slot(2);
	  break;
	case 28: case 0x44: case 0x64: // CTRL-3
	  reflash_slot(3);
	  break;
	case 159: // CTRL-4
	  reflash_slot(4);
	  break;
	case 156: // CTRL-5
	  reflash_slot(5);
	  break;
	case 30:  // CTRL-6
	  reflash_slot(6);
	  break;
	case 31:  // CTRL-7
	  reflash_slot(7);
	  break;
	}
      }
    }
  
#if 0
  erase_sector(4*1048576L);
#endif
#if 0
  data_buffer[0]=0x12;
  data_buffer[1]=0x34;
  data_buffer[2]=0x56;
  data_buffer[3]=0x78;
  program_page(4*1048576L);  
#endif

}

unsigned char progress_chars[4]={32,101,97,231};

void progress_bar(unsigned char onesixtieths)
{
  /* Draw a progress bar several chars high */

  if (onesixtieths>3) {
    for(i=1;i<=(onesixtieths/4);i++) {
      POKE(0x0400+(4*40)-1+i,160);
      POKE(0x0400+(5*40)-1+i,160);
      POKE(0x0400+(6*40)-1+i,160);
    }    
  }
  for(;i<=39;i++) {
    POKE(0x400+(4*40)+i,0x20);
    POKE(0x400+(5*40)+i,0x20);
    POKE(0x400+(6*40)+i,0x20);
  }
  POKE(0x0400+(4*40)+(onesixtieths/4),progress_chars[onesixtieths & 3]);
  POKE(0x0400+(5*40)+(onesixtieths/4),progress_chars[onesixtieths & 3]);
  POKE(0x0400+(6*40)+(onesixtieths/4),progress_chars[onesixtieths & 3]);
  return;
}


/*
  Bitstream file chooser. Adapted from Freeze Menu disk
  image chooser.

  Disk chooser for freeze menu.

  It is displayed over the top of the normal freeze menu,
  and so we use that screen mode.

  We get our list of disknames and put them at $40000.
  As we only care about their names, and file names are
  limited to 64 characters, we can fit ~1000.
  In fact, we can only safely mount images with names <32
  characters.

  We return the disk image name or a NULL pointer if the
  selection has failed and $FFFF if the user cancels selection
  of a disk.
*/


short file_count=0;
short selection_number=0;
short display_offset=0;

char *reading_disk_list_message="sCANNING dIRECTORY ...";
char *no_disk_list_message="nO mega65 cORE fILES fOUND";

char *diskchooser_instructions=
  "  SELECT FLASH FILE, THEN PRESS RETURN  "
  "       OR PRESS RUN/STOP TO ABORT       ";

unsigned char normal_row[20]={
  1,1,1,1,
  1,1,1,1,
  1,1,1,1,
  1,1,1,1,
  1,1,1,1
};

unsigned char highlight_row[20]={
  0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x21,
  0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x21,
  0x21,0x21,0x21,0x21
};

char disk_name_return[32];

unsigned char joy_to_key_disk[32]={
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x0d, // With fire pressed
  0,0,0,0,0,0,0,0x9d,0,0,0,0x1d,0,0x11,0x91,0     // without fire
};

#define SCREEN_ADDRESS 0x0400
#define COLOUR_RAM_ADDRESS 0x1f800

void draw_file_list(void)
{
  unsigned addr=SCREEN_ADDRESS;
  unsigned char i,x;
  unsigned char name[64];
  // First, clear the screen
  POKE(SCREEN_ADDRESS+0,' ');
  POKE(SCREEN_ADDRESS+1,' ');
  lcopy(SCREEN_ADDRESS,SCREEN_ADDRESS+2,40*23-2);
  lpoke(COLOUR_RAM_ADDRESS+0,1);
  lpoke(COLOUR_RAM_ADDRESS+1,1);
  lcopy(COLOUR_RAM_ADDRESS,COLOUR_RAM_ADDRESS+2,40*23-2);

  // Draw instructions
  for(i=0;i<80;i++) {
    if (diskchooser_instructions[i]>='A'&&diskchooser_instructions[i]<='Z') 
      POKE(SCREEN_ADDRESS+23*40+i+0,diskchooser_instructions[i]&0x1f);
    else
      POKE(SCREEN_ADDRESS+23*40+i+0,diskchooser_instructions[i]);
  }
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(23*40)+0,20);
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(23*40)+20,20);
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(24*40)+0,20);
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(24*40)+20,20);

  
  for(i=0;i<23;i++) {
    if ((display_offset+i)<file_count) {
      // Real line
      lcopy(0x40000U+((display_offset+i)<<6),(unsigned long)name,64);

      for(x=0;x<20;x++) {
	if ((name[x]>='A'&&name[x]<='Z') ||(name[x]>='a'&&name[x]<='z'))
	  POKE(addr+x,name[x]&0x1f);
	else
	  POKE(addr+x,name[x]);
      }
    } else {
      // Blank dummy entry
      for(x=0;x<20;x++) POKE(addr+x,' ');
    }
    if ((display_offset+i)==selection_number) {
      // Highlight the row
      lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(i*40),20);
    } else {
      // Normal row
      lcopy((long)normal_row,COLOUR_RAM_ADDRESS+(i*40),20);
    }
    addr+=(40*1);  
  }

  
}

char *select_bitstream_file(void)
{
  unsigned char x,dir;
  signed char j;
  struct m65_dirent *dirent;
  int idle_time=0;
  
  file_count=0;
  selection_number=0;
  display_offset=0;
  
  // First, clear the screen
  POKE(SCREEN_ADDRESS+0,' ');
  POKE(SCREEN_ADDRESS+1,' ');
  lcopy(SCREEN_ADDRESS,SCREEN_ADDRESS+2,40*25-2);

  for(x=0;reading_disk_list_message[x];x++)
    POKE(SCREEN_ADDRESS+12*40+(9)+(x*1),reading_disk_list_message[x]&0x3f);

  dir=opendir();
  dirent=readdir(dir);
  while(dirent&&((unsigned short)dirent!=0xffffU)) {
    j=strlen(dirent->d_name)-4;
    if (j>=0) {
      if ((!strncmp(&dirent->d_name[j],".BIT",4))||(!strncmp(&dirent->d_name[j],".bit",4))) {
	// File is a disk image
	lfill(0x40000L+(file_count*64),' ',64);
	lcopy((long)&dirent->d_name[0],0x40000L+(file_count*64),j+4);
	file_count++;
      }
    }
    
    dirent=readdir(dir);
  }

  closedir(dir);

  // If we didn't find any disk images, then just return
  if (!file_count) {
    printf("%c",0x93);
    for(x=0;no_disk_list_message[x];x++)
      POKE(SCREEN_ADDRESS+12*40+(7)+(x*1),no_disk_list_message[x]&0x3f);
    for(x=0;x<32;x++) usleep(65000);
    return NULL;
  }

  // Okay, we have some disk images, now get the user to pick one!
  draw_file_list();
  while(1) {
    x=PEEK(0xD610U);

    if(!x) {
      // We use a simple lookup table to do this
      x=joy_to_key_disk[PEEK(0xDC00)&PEEK(0xDC01)&0x1f];
      // Then wait for joystick to release
      while((PEEK(0xDC00)&PEEK(0xDC01)&0x1f)!=0x1f) continue;
    }
    
    if (!x) {
      idle_time++;

      usleep(10000);
      continue;
    } else idle_time=0;

    // Clear read key
    POKE(0xD610U,0);

    switch(x) {
    case 0x03:             // RUN-STOP = make no change
      return NULL;
    case 0x0d:             // Return = select this disk.
      // Copy name out
      lcopy(0x40000L+(selection_number*64),(unsigned long)disk_name_return,32);
      // Then null terminate it
      for(x=31;x;x--)
	if (disk_name_return[x]==' ') { disk_name_return[x]=0; } else { break; }
      
      return disk_name_return;
      break;
    case 0x11: case 0x9d:  // Cursor down or left
      selection_number++;
      if (selection_number>=file_count) selection_number=0;
      break;
    case 0x91: case 0x1d:  // Cursor up or right
      selection_number--;
      if (selection_number<0) selection_number=file_count-1;
      break;
    }

    // Adjust display position
    if (selection_number<display_offset) display_offset=selection_number;
    if (selection_number>(display_offset+23)) display_offset=selection_number-22;
    if (display_offset>(file_count-22)) display_offset=file_count-22;
    if (display_offset<0) display_offset=0;

    draw_file_list();
    
  }
  
  return NULL;
}
