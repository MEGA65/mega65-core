#include <stdio.h>
#define POKE(X,Y) (*(unsigned char*)(X))=Y
#define PEEK(X) (*(unsigned char*)(X))
void m65_io_enable(void);

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

void main(void)
{
  
  unsigned char seconds = 0;
  unsigned char minutes = 0;
  unsigned char hours = 0;

  short x,y,z;
  short a1,a2,a3;

  m65_io_enable();

  
  // Enable acceleromter, 10Hz sampling
  while(lpeek(0xffd70ffL)) continue;
  lpoke(0xFFD7060L,0x27);    
  wait_10ms();
  
  // Enable ADCs
  while(lpeek(0xffd70ffL)) continue;

  lpoke(0xFFD7063L,0x80);
  wait_10ms();

  while(lpeek(0xffd70ffL)) continue;

  lpoke(0xFFD705fL,0x80);

  while(lpeek(0xffd70ffL)) continue;

  // Setup power control IO expander
  
  lpoke(0xFFD7016L,0x00);
  while(lpeek(0xffd70ffL)) continue;
  lpoke(0xFFD7012L,0x00);
  while(lpeek(0xffd70ffL)) continue;
  
  // Clear screen
  printf("%c",0x93);
  
  //Function to display current time from Real Time Clock
  while(1){
    // 0xffd7026 is the base address for all bytes read from the RTC
    // The I2C Master places them in these memory locations

    // Only update when every second, otherwise wait
    // while(seconds==lpeek(0xffd7026)){};

    // Home cursor
    printf("%c",0x13);
    
    seconds = lpeek(0xffd701a);
    minutes = lpeek(0xffd701b);
    hours = lpeek(0xffd701c);
    printf("%02x:",hours&0x3f);
    printf("%02x.",minutes&0x7f);
    printf("%02x",seconds&0x7f); //Prints BCD byte
    //Since bit 7 is always set, mask it off with 0x7f

    printf("\n");


    // Also read Accelerometer status
    x=lpeek(0xffd7068L)+(lpeek(0xffd7069L)<<8L);
    y=lpeek(0xffd706AL)+(lpeek(0xffd706BL)<<8L);
    z=lpeek(0xffd706CL)+(lpeek(0xffd706DL)<<8L);
    printf("Accel: X:%5d Y:%5d Z:%5d      \n",
	   x,y,z);

    // And ADC values of the three volume wheels
    a1=lpeek(0xffd7048L)+(lpeek(0xffd7049L)<<8);
    a2=lpeek(0xffd704AL)+(lpeek(0xffd704BL)<<8);
    a3=lpeek(0xffd704CL)+(lpeek(0xffd704DL)<<8);
    a1=a1>>6; a1+=512;
    a2=a2>>6; a2+=512;
    a3=a3>>6; a3+=512;
    printf("ADCs: 1:%5d 2:%5d 3:%5d      \n",a1,a2,a3);

    // Show joypad and button status
    a1=lpeek(0xffd7000L);
    a1=a1^0xff;
    if (a1&1) printf("up        ");
    else if (a1&2) printf("left        ");
    else if (a1&4) printf("right        ");
    else if (a1&8) printf("down        ");
    else if (a1&0x10) printf("b1        ");
    else if (a1&0x20) printf("b2        ");
    else if (a1&0x40) printf("b3        ");
    else if (a1&0x80) printf("b4        ");
    printf("\n");

    // Show black button status
    a1=lpeek(0xffd7000L);
    POKE(0x608+a1,PEEK(0x608+a1)+1);
    a1=a1^0xff;
    if (a1&1) printf("black3        ");
    else if (a1&2) printf("black4        ");
    else if (a1&4) printf("black2/int        ");
    printf("\n");

    a1=lpeek(0xffd7010L);
    printf("Power status: %02X\n",a1);
    
    __asm__("jsr $ffe4");
    __asm__("sta $0427");
    a1=PEEK(0x427);
    if (a1) {
      POKE(0x426,a1);
      a2=lpeek(0xffd7012L);
      switch(a1) {
      case '1':
	lpoke(0xffd7012L,a2^0x01);
	break;
      case '2':
	lpoke(0xffd7012L,a2^0x02);
	break;
      case '3':
	lpoke(0xffd7012L,a2^0x04);
	break;
      case '4':
	lpoke(0xffd7012L,a2^0x08);
	break;
      case '5':
	lpoke(0xffd7012L,a2^0x10);
	break;
      case '6':
	lpoke(0xffd7012L,a2^0x20);
	break;
      case '7':
	lpoke(0xffd7012L,a2^0x40);
	break;
      case '8':
	lpoke(0xffd7012L,a2^0x80);
	break;
      }
    }
    
  }
}
