#include <stdio.h>
#define POKE(X,Y) (*(unsigned char*)(X))=Y
#define PEEK(X) (*(unsigned char*)(X))
void m65_io_enable(void);

unsigned char joy_x=100;
unsigned char joy_y=100;

struct dmagic_dmalist {
  // Enhanced DMA options
  unsigned char option_0b;
  unsigned char option_80;
  unsigned char source_mb;
  unsigned char option_81;
  unsigned char dest_mb;
  unsigned char end_of_options;

  // F018B format DMA request
  unsigned char command;
  unsigned int count;
  unsigned int source_addr;
  unsigned char source_bank;
  unsigned int dest_addr;
  unsigned char dest_bank;
  unsigned char sub_cmd;  // F018B subcmd
  unsigned int modulo;
};

struct dmagic_dmalist dmalist;
unsigned char dma_byte;

void do_dma(void)
{
  m65_io_enable();

  //  for(i=0;i<24;i++)
  // screen_hex_byte(SCREEN_ADDRESS+i*3,PEEK(i+(unsigned int)&dmalist));
  
  // Now run DMA job (to and from anywhere, and list is in low 1MB)
  POKE(0xd702U,0);
  POKE(0xd704U,0x00);  // List is in $00xxxxx
  POKE(0xd701U,((unsigned int)&dmalist)>>8);
  POKE(0xd705U,((unsigned int)&dmalist)&0xff); // triggers enhanced DMA
}

unsigned char lpeek_toscreen(long address)
{
  // Read the byte at <address> in 28-bit address space
  // XXX - Optimise out repeated setup etc
  // (separate DMA lists for peek, poke and copy should
  // save space, since most fields can stay initialised).

  dmalist.option_0b=0x0b;
  dmalist.option_80=0x80;
  dmalist.source_mb=(address>>20);
  dmalist.option_81=0x81;
  dmalist.dest_mb=0x00; // dma_byte lives in 1st MB
  dmalist.end_of_options=0x00;
  dmalist.sub_cmd=0x02; // Hold source address
  
  dmalist.command=0x00; // copy
  dmalist.count=1000;
  dmalist.source_addr=address&0xffff;
  dmalist.source_bank=((address>>16)&0x0f);
  dmalist.dest_addr=0x0400;
  dmalist.dest_bank=0;

  do_dma();
   
  return dma_byte;
}


unsigned char lpeek(long address)
{
  // Read the byte at <address> in 28-bit address space
  // XXX - Optimise out repeated setup etc
  // (separate DMA lists for peek, poke and copy should
  // save space, since most fields can stay initialised).

  dmalist.option_0b=0x0b;
  dmalist.option_80=0x80;
  dmalist.source_mb=(address>>20);
  dmalist.option_81=0x81;
  dmalist.dest_mb=0x00; // dma_byte lives in 1st MB
  dmalist.end_of_options=0x00;
  dmalist.sub_cmd=0x00;
  
  dmalist.command=0x00; // copy
  dmalist.count=1;
  dmalist.source_addr=address&0xffff;
  dmalist.source_bank=(address>>16)&0x0f;
  dmalist.dest_addr=(unsigned int)&dma_byte;
  dmalist.dest_bank=0;

  do_dma();
   
  return dma_byte;
}

void lpoke(long address, unsigned char value)
{  

  dmalist.option_0b=0x0b;
  dmalist.option_80=0x80;
  dmalist.source_mb=0x00; // dma_byte lives in 1st MB
  dmalist.option_81=0x81;
  dmalist.dest_mb=(address>>20);
  dmalist.end_of_options=0x00;
  
  dma_byte=value;
  dmalist.command=0x00; // copy
  dmalist.count=1;
  dmalist.source_addr=(unsigned int)&dma_byte;
  dmalist.source_bank=0;
  dmalist.dest_addr=address&0xffff;
  dmalist.dest_bank=(address>>16)&0x0f;

  do_dma(); 
  return;
}

void lcopy(long source_address, long destination_address,
          unsigned int count)
{
  if (!count) return;
  dmalist.option_0b=0x0b;
  dmalist.option_80=0x80;
  dmalist.source_mb=source_address>>20;
  dmalist.option_81=0x81;
  dmalist.dest_mb=(destination_address>>20);
  dmalist.end_of_options=0x00;

  dmalist.command=0x00; // copy
 dmalist.count=count;
  dmalist.sub_cmd=0;
  dmalist.source_addr=source_address&0xffff;
  dmalist.source_bank=(source_address>>16)&0x0f;
  if (source_address>=0xd000 && source_address<0xe000)
    dmalist.source_bank|=0x80;  
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x0f;
  if (destination_address>=0xd000 && destination_address<0xe000)
    dmalist.dest_bank|=0x80;

  do_dma();
  return;
}

void lfill(long destination_address, unsigned char value,
          unsigned int count)
{
  if (!count) return;
  dmalist.option_0b=0x0b;
  dmalist.option_80=0x80;
  dmalist.source_mb=0x00;
  dmalist.option_81=0x81;
  dmalist.dest_mb=destination_address>>20;
  dmalist.end_of_options=0x00;

  dmalist.command=0x03; // fill
  dmalist.sub_cmd=0;
  dmalist.count=count;
  dmalist.source_addr=value;
  dmalist.dest_addr=destination_address&0xffff;
  dmalist.dest_bank=(destination_address>>16)&0x0f;
  if (destination_address>=0xd000 && destination_address<0xe000)
    dmalist.dest_bank|=0x80;
  do_dma();
  return;
}

void m65_io_enable(void)
{
  // Gate C65 IO enable
  POKE(0xd02fU,0x47);
  POKE(0xd02fU,0x53);
  // Force to full speed
  POKE(0,65);
}

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
  $D6CC.0 = data bit 0 / SI (serial input)
  $D6CC.1 = data bit 1 / SO (serial output)
  $D6CC.2 = data bit 2 / WP# (write protect)
  $D6CC.3 = data bit 3 / HOLD#
  $D6CC.4 = tri-state SI only (to enable single bit SPI communications)
  $D6CC.5 = clock
  $D6CC.6 = CS#
  $D6CC.7 = data bits DDR (all 4 bits at once)
*/

/*
  $D6CD.0 = clock free run if set, or under bitbash control when 0
  $D6CD.1 = alternate control of clock pin
*/
#define CLOCKCTL_PORT 0xD6CDU

unsigned int di;
void delay(void)
{
   for(di=0;di<1000;di++) continue;
}

void spi_tristate_si(void)
{
  POKE(0xD6CCU,PEEK(0xD6CCU)|0x10);
}

unsigned char spi_sample_si(void)
{
  return (PEEK(BITBASH_PORT)&0x02);
}

void spi_so_set(unsigned char b)
{
  // De-tri-state SO data line, and set value
  POKE(BITBASH_PORT,
       (PEEK(BITBASH_PORT)&(0xFF-(0x01)))
       |0x80
       |(b?1:0));
}


void spi_clock_low(void)
{
  POKE(0xD6CCU,PEEK(0xD6CCU)&(0xFF-0x20));
}

void spi_clock_high(void)
{
  POKE(0xD6CCU,PEEK(0xD6CCU)|0x20);
}

void spi_cs_low(void)
{
  POKE(0xD6CCU,PEEK(0xD6CCU)&(0xFF-0x40));
}

void spi_cs_high(void)
{
  POKE(0xD6CCU,PEEK(0xD6CCU)|0x40);
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
    spi_tx_bit(b&1);
    b=b>>1;
  }
}

unsigned char spi_rx_byte()
{
  unsigned char b=0;
  unsigned char i;

  spi_tristate_si();
  for(i=0;i<8;i++) {
    spi_clock_low();
    b=b>>1;
    delay();
    if (spi_sample_si()) b|=0x80;
    spi_clock_high();
    delay();
  }
}

unsigned char manufacturer;
unsigned short device_id;
unsigned short cfi_data[512];
unsigned short cfi_length=0;

void fetch_rdid(void)
{
  /* Run command 0x9F and fetch CFI etc data.
     (Section 9.2.2)
   */

  unsigned short i;

  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT,0x00);
  
  spi_cs_high();
  spi_cs_low();
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
  
}


void main(void)
{
  
  unsigned char seconds = 0;
  unsigned char minutes = 0;
  unsigned char hours = 0;

  short x,y,z;
  short a1,a2,a3;
  unsigned char n=0;

  m65_io_enable();

  // Sprite 0 on
  lpoke(0xFFD3015L,0x01);
  // Sprite data at $03c0
  *(unsigned char *)2040 = 0x3c0/0x40;

  for(n=0;n<64;n++) 
    *(unsigned char*)(0x3c0+n)=
      sprite_data[n];
  
  // Disable OSK
  lpoke(0xFFD3615L,0x7F);  
  
  // Clear screen
  printf("%c",0x93);    
  
  fetch_rdid();
  printf("QSPI flash manufacturer = $%02x\n",manufacturer);
  printf("QSPI device ID = $%04x\n",device_id);

#if 0
  n=0;
  do {
    delay();
    POKE(0xD6CCU,n);
    n++;
  }  while (n);
#endif
  
    delay();
  spi_so_set(0);
    delay();
  spi_so_set(1);
    delay();
  spi_so_set(0);
  
}


