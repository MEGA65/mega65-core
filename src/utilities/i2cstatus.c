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

unsigned char seconds = 0;
unsigned char minutes = 0;
unsigned char hours = 0;
unsigned char date = 0;
unsigned char month = 0;
unsigned char year = 0;

short x,y,z;
short a1,a2,a3;
unsigned char n=0;

void target_megaphone(void)
  {

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

  // Power control IO expander now gets setup by Hypervisor
  
  // Clear screen
  printf("%c",0x93);

  /* For debugging I2C bus glitching:
     It writes the entire screen with the value read from the I2C register.
     This has confirmed that the error persist for hundreds of CPU clock cycles,
     even when the value is being read by DMA repeatedly.  This suggests very
     strongly that the problem is an I2C bus glitch, not a problem with the fastio
     bus. */
  //  while(1) {
  //  lpeek_toscreen(0xffd7001L);
  //  for(n=0;n<50;n++) wait_10ms();    
  //}
  
  //Function to display current time from Real Time Clock
  while(1){
    // 0xffd7026 is the base address for all bytes read from the RTC
    // The I2C Master places them in these memory locations

    // Only update when every second, otherwise wait
    // while(seconds==lpeek(0xffd7026)){};

    // Home cursor
    printf("%c",0x13);


    x=lpeek(0xffd36b9);
    x|=(lpeek(0xffd36bb)&3)<<8;
    y=lpeek(0xffd36ba);
    y|=(lpeek(0xffd36bb)&0x30)<<4;
    printf("touch1: %d,%d\n",x,y);
    
    seconds = lpeek(0xffd701a);
    minutes = lpeek(0xffd701b);
    hours = lpeek(0xffd701c);
    printf("real-time clock: %02x:",hours&0x3f);
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
    printf("    ADCs: 1:%5d 2:%5d 3:%5d      \n",a1,a2,a3);
    // And ADC values of the three volume wheels
    a1=lpeek(0xffd70f0L)+(lpeek(0xffd70f1L)<<8);
    a2=lpeek(0xffd70f2L)+(lpeek(0xffd70f3L)<<8);
    a3=lpeek(0xffd70f4L)+(lpeek(0xffd70f5L)<<8);
    a1=a1>>6; a1+=512;
    a2=a2>>6; a2+=512;
    a3=a3>>6; a3+=512;
    printf("smoothed: 1:%5d 2:%5d 3:%5d      \n",a1,a2,a3);

    // Show joypad and button status

    a1=lpeek(0xffd7000L);
    POKE(0x420,a1);
    POKE(0xD020U,a1&0xf);
    if (a1!=0xff) POKE(0x41F,a1);
	  
    a1=lpeek(0xffd7001L);
    POKE(0x421,a1);
    a1&=0x3f;
    POKE(0x0720U+a1,PEEK(0x0720U+a1)+1);
    
    a1=lpeek(0xffd7000L);
    printf("%02X",a1);

    // Joystick is here
    a1=lpeek(0xffd7001L);
    printf(",%02X",a1);
    POKE(0x0500+n,a1);
    n++;
    if (!(a1&0x20)) joy_x--;
    if (!(a1&0x10)) joy_x++;
    if (!(a1&0x80)) joy_y--;
    if (!(a1&0x40)) joy_y++;
    if (!(a1&0x8)) POKE(0xd027U,(PEEK(0xD027U)+1)&0xf);
    POKE(0xD000U,joy_x);
    POKE(0xD001U,joy_y);
    
    a1=lpeek(0xffd7002L);
    printf(",%02X",a1);
    a1=lpeek(0xffd7003L);
    printf(",%02X",a1);
    a1=lpeek(0xffd7004L);
    printf(",%02X",a1);
    a1=lpeek(0xffd7005L);
    printf(",%02X",a1);
    a1=lpeek(0xffd7006L);
    printf(",%02X",a1);
    a1=lpeek(0xffd7007L);
    printf(",%02X : ",a1);

    
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
    else printf("          ");
    printf("\n");

    // Show black button status
    a1=lpeek(0xffd7000);
    POKE(0x608+a1,PEEK(0x608+a1)+1);
    a1=lpeek(0xffd7001);
    a1=a1^0xff;
    if (a1&1) printf("black3        ");
    else if (a1&2) printf("black4        ");
    else if (a1&4) printf("black2/int        ");
    else printf("               ");
    printf("\n");

    a1=lpeek(0xffd7010L);
    printf("Power status: %02X\n",a1);

    // Set all pins on power control port to output
    lpoke(0xffd7016L,0);
    
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

void target_mega65r2(void)
  {

  while(lpeek(0xffd71ffL)) continue;

  // Clear screen
  printf("%c",0x93);

  //Function to display current time from Real Time Clock
  while(1){
    // 0xffd7110 is the base address for all bytes read from the RTC
    // The I2C Master places them in these memory locations

    // Home cursor
    printf("%c",0x13);

    printf("Unique identifier/MAC seed: ");
    for(n=2;n<8;n++) printf("%02x",lpeek(0xffd7100+n));
    printf("\n");

    printf("NVRAM:\n");
    for(n=0x40;n<0x80;n++) {
      if (!(n&7)) printf("  %02x :",n-0x40);
      printf("%02x",lpeek(0xffd7100+n));
      if ((n&7)==7) printf("\n");
    }
    printf("\n");
    
    seconds = lpeek(0xffd7110);
    minutes = lpeek(0xffd7111);
    hours = lpeek(0xffd7112);
    if (hours&0x80)
      printf("real-time clock: %02x:",hours&0x3f);
    else
      printf("real-time clock: %02x:",hours&0x1f);      
    printf("%02x.",minutes&0x7f);
    printf("%02x",seconds&0x7f); 
    if (hours&0x80) {
      printf(" hours");
    } else {
      if (hours&0x20) printf(" pm"); else printf(" am");
    }

    printf("\n");

    date = lpeek(0xffd7113);
    month = lpeek(0xffd7114);
    year = lpeek(0xffd7115);    
    
    printf("Date: %02x-",date);
    switch(month) {
    case 0x01: printf("jan"); break;
    case 0x02: printf("feb"); break;
    case 0x03: printf("mar"); break;
    case 0x04: printf("apr"); break;
    case 0x05: printf("may"); break;
    case 0x06: printf("jun"); break;
    case 0x07: printf("jul"); break;
    case 0x08: printf("aug"); break;
    case 0x09: printf("sep"); break;
    case 0x10: printf("oct"); break;
    case 0x11: printf("nov"); break;
    case 0x12: printf("dec"); break;
    default: printf("invalid month"); break;
    }
    printf("-20%02x\n",year);
    
  }
}


void main(void)
{
  
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

  if (lpeek(0xffd7100)||lpeek(0xffd71fe))
    target_mega65r2();
  else if (lpeek(0xffd7100)||lpeek(0xffd71fe))
    target_megaphone();
  else
    printf("Unknown hardware revision. No I2C block found.\n");

}
  

