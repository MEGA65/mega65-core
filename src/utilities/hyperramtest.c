#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <fileio.h>

unsigned long addr,time,speed;
unsigned char r2;

void main(void)
{
  POKE(0,65);
  
  // Cache off
  lpoke(0xbfffff2,0x00);
  
  /*
    Test complete HyperRAM, including working out the size.
  */
  printf("Determining size of Extra RAM");
  
  lpoke(0x8000000,0xbd);
  for(addr=0x8000100;(lpeek(0x8000000)==0xbd)&&(addr<0xbff0000);addr+=0x100)
    {
      if (!(addr&0xfffff)) printf(".");
      lpoke(addr,0x55);
      if (lpeek(addr)!=0x55) break;
      lpoke(addr,0xAA);
      if (lpeek(addr)!=0xAA) break;
      if (lpeek(0x8000000)!=0xbd) break;
    } 

  printf("%c",0x93);
  
  while(1) {
    printf("%cUpper limit of Extra RAM is $%08lx\n",0x13,addr);  
    printf("%cExtra RAM is %ld MB\n",(addr-0x8000000L)>>20L);
    
    // Test read speed of normal and extra ram  
    while(PEEK(0xD012)!=0x10)
      while(PEEK(0xD011)&0x80) continue;
    lcopy(0x20000,0x40000,32768);
    r2=PEEK(0xD012);
    printf("Copy Fast RAM to Fast RAM: ");
    // 63usec / raster
    time=(r2-0x10)*63;
    speed=32768000L/time;
    printf("%ld KB/sec\n",speed);
    
    // Hyperram Cache on
    lpoke(0xbfffff2,0x80);
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
    lfill(0x8000000,0,4096);
    r2=PEEK(0xD012);
    printf("Fill Extra RAM: ");
    time=(r2-0x10)*63;
    speed=4096000L/time;
    printf("%ld KB/sec\n",speed);
    
    // Hyperram Cache off
    lpoke(0xbfffff2,0x00);
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
    POKE(0xD020,1);
    lcopy(0x40000,0x8000000,4096);
    POKE(0xD020,0);
    r2=PEEK(0xD012);
    printf("Copy Fast RAM to Extra RAM: ");
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
