#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <fileio.h>

unsigned long addr,time,speed;
unsigned char r2;
unsigned char cr0hi;
unsigned char cr0lo;
unsigned char id0hi;
unsigned char id0lo;
unsigned int mbs;

void bust_cache(void) {
  lpeek(0x8000000);
  lpeek(0x8000010);
  lpeek(0x8000020);
  lpeek(0x8000030);
  lpeek(0x8000040);
  lpeek(0x8000050);
  lpeek(0x8000060);
  lpeek(0x8000070);
}


void main(void)
{
  POKE(0,65);
  POKE(0xD02F,0x47);
  POKE(0xD02F,0x53);
  
  // Cache off
  lpoke(0xbfffff2,0x02);

  /*
    Test complete HyperRAM, including working out the size.
  */
  printf("Determining size of Extra RAM");
  
  lpoke(0x8000000,0xbd);
  for(addr=0x8001000;(lpeek(0x8000000)==0xbd)&&(addr<0xbff0000);addr+=0x1000)
    {
      if (!(addr&0xfffff)) printf(".");
      lpoke(addr,0x55);
      if (lpeek(addr)!=0x55) break;
      lpoke(addr,0xAA);
      if (lpeek(addr)!=0xAA) break;
      if (lpeek(0x8000000)!=0xbd) break;
    } 

  printf("%c",0x93);

  bust_cache();
  cr0hi=lpeek(0x9001000);
  bust_cache();
  cr0lo=lpeek(0x9001001);

  bust_cache();
  id0hi=lpeek(0x9000000);
  bust_cache();
  id0lo=lpeek(0x9000001);

  while(1) {
    printf("%cUpper limit of Extra RAM is $%08lx\n",0x13,addr);
    mbs=(unsigned int)((addr-0x8000000L)>>20L);
    printf("Extra RAM is %d MB\n",mbs);
    printf("Chip ID: %d rows, %d columns\n",
	   (id0hi&0x1f)+1,(id0lo>>4)+1);
    printf("Expected capacity: %d MB\n",
	   1<<((id0hi&0x1f)+1+(id0lo>>4)+1+1-20));
    printf("Vendor: ");
    switch(id0lo&0xf) {
    case 1: printf("Cypress"); break;
    case 3: printf("ISSI"); break;
    default: printf("<unknown>");
    }
    printf("\n");

    printf("Config: Powered up=%c,\n drive strength=$%x,\n",(cr0hi&0x80)?'Y':'N',(cr0hi>>4)&7);
    switch((cr0lo&0xf0)>>4) {
    case 0: printf(" 5 clock latency,\n"); break;
    case 1: printf(" 6 clock latency,\n"); break;
    case 14: printf(" 3 clock latency,\n"); break;
    case 15: printf(" 4 clock latency,\n"); break;
    default:
      printf("unknown latency clocks ($%x),\n",(cr0lo&0xf0)>>4);      
    }
    if (cr0lo&8) printf(" fixed latency,"); else printf(" variable latency,");
    printf("\n");
    if (cr0lo&28) printf(" legacy burst,"); else printf(" hybrid burst,");
    printf("\n");
    switch(cr0lo&3) {
    case 0: printf(" 128 byte burst length.\n"); break;
    case 1: printf(" 64 byte burst length.\n"); break;
    case 2: printf(" 16 byte burst length.\n"); break;
    case 3: printf(" 32 byte burst length.\n"); break;
    }

    // Test read speed of normal and extra ram  
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x20000L,0x40000L,32768);
    r2=PEEK(0xD012);
    printf("Copy Fast RAM to Fast RAM: ");
    // 63usec / raster
    time=(r2-0x10)*63;
    speed=32768000L/time;
    printf("%ld KB/sec\n",speed);
    
    // Hyperram Cache on
    lpoke(0xbfffff2,0x82);
    printf("With Cache enabled:\n");
    
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x8000000,0x40000,4096);
    r2=PEEK(0xD012);
    printf("Copy Extra RAM to Fast RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
    
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x40000,0x8000000,4096);
    r2=PEEK(0xD012);
    printf("Copy Fast RAM to Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
    
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x8000000,0x8010000,4096);
    r2=PEEK(0xD012);
    printf("Copy Extra RAM to Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);

    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lfill(0x8000000,0,4096);
    r2=PEEK(0xD012);
    printf("Fill Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
    
    // Hyperram Cache off
    lpoke(0xbfffff2,0x02);
    printf("With Cache disabled:\n");
    
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x8000000,0x40000,4096);
    r2=PEEK(0xD012);
    printf("Copy Extra RAM to Fast RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
    
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x40000,0x8000000,4096);
    r2=PEEK(0xD012);
    printf("Copy Fast RAM to Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
    
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x8000000,0x8010000,4096);
    r2=PEEK(0xD012);
    printf("Copy Extra RAM to Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);

    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lfill(0x8000000,0,4096);
    r2=PEEK(0xD012);
    printf("Fill Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
  }
  
  
}
