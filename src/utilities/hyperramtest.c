#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <fileio.h>

unsigned long addr,upper_addr,time,speed;
unsigned char r2;
unsigned char cr0hi;
unsigned char cr0lo;
unsigned char id0hi;
unsigned char id0lo;
unsigned int mbs;
unsigned int temp_addr;
unsigned int i,j,k;

/*
  0x01 = Send command fast  (not currently working)
  0x02 = Read bytes fast
  0x04 = Write data fast (not currently working)
*/
unsigned char fast_flags=0x0a; 
unsigned char slow_flags=0x0a; 

void bust_cache(void) {
  lpeek(0x8000100);
  lpeek(0x8000110);
  lpeek(0x8000120);
  lpeek(0x8000130);
  lpeek(0x8000140);
  lpeek(0x8000150);
  lpeek(0x8000160);
  lpeek(0x8000170);
  lpoke(0x8000100,0x99);
  lpoke(0x8000110,0x99);
  lpoke(0x8000120,0x99);
  lpoke(0x8000130,0x99);
  lpoke(0x8000140,0x99);
  lpoke(0x8000150,0x99);
  lpoke(0x8000160,0x99);
  lpoke(0x8000170,0x99);

  lpoke(0xbfffff2,0x00);
  lpoke(0xbfffff2,0x80+fast_flags);
}


void setup_hyperram(void)
{
  /*
    Test complete HyperRAM, including working out the size.
  */
  printf("Determining size of Slow RAM");
  
  lpoke(0xbfffff2,0x80+fast_flags);
  lpoke(0x8000000,0xbd);
  //  if (lpeek(0x8000000)!=0xbd) {
  //    printf("ERROR: $8000000 didn't hold its value.\n"
  //	   "Should be $BD, but saw $%02x\n",lpeek(0x8000000));
  //  }
  for(addr=0x8001000;(lpeek(0x8000000)==0xbd)&&(addr!=0x9000000);addr+=0x1000)
    {
      if (!(addr&0xfffff)) printf(".");

      lpoke(addr,0x55);

      bust_cache();
      
      i=lpeek(addr);
      if (i!=0x55) {
	printf("\n$%08lx corrupted != $55\n (saw $%02x, re-read yields $%02x)",addr,i,lpeek(addr));
	break;
      }

      lpoke(addr,0xAA);

      bust_cache();

      i=lpeek(addr);
      if (i!=0xaa) {
	printf("\n$%08lx corrupted != $AA\n  (saw $%02x, re-read yields $%02x)",addr,i,lpeek(addr));
	break;
      }

      bust_cache();

      i=lpeek(0x8000000);
      if (i!=0xbd) {
	printf("\n$8000000 corrupted != $BD\n  (saw $%02x, re-read yields $%02x)",i,lpeek(0x8000000));
	break;
      }
    }


  upper_addr=addr;

  if (addr!=0x8800000) {
    printf("\nError(s) while testing Slow RAM\n");
    printf("\nPress any key to continue...\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    while(!PEEK(0xD610)) continue;
    if (PEEK(0xd610)==0x03) return;
    while(PEEK(0xD610)) POKE(0xD610,0);
  }

  // Pre-fill all hyperram for convenience
  printf("\nErasing hyperram");
  lpoke(0xbfffff2,0x80+fast_flags);  // cache on for much faster linear writes

  // Allow for upto 16MB of HyperRAM
  for(addr=0x8000000;(addr<upper_addr);addr+=0x8000)
    { lfill(addr,0x00,0x8000);
      if (!(addr&0xfffff)) printf(".");
    }
  printf("\n");
 
  
}

void test_continuousread(void)
{
  i=0;
  for(addr=0x8000000;addr<0x8800000;addr+=0x8000)
    lfill(addr,i++,0x8000);
  

  addr=0x8000000;
  lfill(addr,0xbd,0x800);

  // Write test pattern somewhere
  for(j=0;j<16;j++) lpoke(addr+120+j,0x10+j);
  
  // Copy slow RAM back and check
  while(!PEEK(0xD610)) {
    lcopy(addr,0xc000,0x800);
    lcopy(0xc000,0x0400,0x3c0);
  }
  
}

void test_cacheerror(void)
{
  printf("Performing cache error test.\n");

  //  for(addr=0x8000000;addr<0x8800000;addr+=0x8000)
  //    lfill(addr,0x00,0x8000);

  addr=0x8000000;
  lfill(addr,0x00,0x800);
  for(j=0;j<16;j++) lpoke(addr+j,0x10+j);
  lcopy(addr,0xc000,0x800);

  addr=0x8000800;
  lfill(addr,0x00,0x800);
  for(j=0;j<16;j++) lpoke(addr+j,0x10+j);
  lcopy(addr,0xc000,0x800);

  for(j=0;j<16;j++) {
    i=0;
    if (PEEK(0xc000+j)!=(0x10+(j-i*4))) {
      printf("ERROR: Read $%02x from $%08lx, expected $%02x (i=%d)\n",
	     PEEK(0xc000+j),addr+j,
	     0x10+j-i*4,i);
      
      while(PEEK(0xD610)) POKE(0xD610,0);
      while(!PEEK(0xD610)) continue;
      if (PEEK(0xD610)==0x03) return;
      while(PEEK(0xD610)) POKE(0xD610,0);
      
    }
    printf("$%02x ",PEEK(0xc000+j));
  }

}



void test_miswrite(void)
{
  printf("Performing mis-write test.\n");

  printf("Erasing HyperRAM\n");
  for(addr=0x8000000;addr<upper_addr;addr+=0x8000)
    {
      if (!(addr&0xfffff)) printf(".");
      lfill(addr,0,0x8000);
    }
  printf("\n");

  for(addr=0x8000000;addr<upper_addr;addr+=0x800)
    {
      printf("\nTesting @ $%08lx",addr);
      for(i=0;i<256;i++) {
	if (!(i&0xf)) printf(".");
	lfill(addr,0x00,0x800);
	// Write test pattern somewhere
	for(j=0;j<16;j++) lpoke(addr+(i*4)+j,0x10+j);

	// Copy slow RAM back and check
	//while(1) {
	lcopy(addr,0xc000,0x800);
	//	  lcopy(0xc000,0x0400,0x3c0);
	//	}
	  
	{
	for(j=0x000;j<0x800;j+=0x800) {
	  if (PEEK(0xD610)==0x03) return;
	  while(PEEK(0xD610)) POKE(0xD610,0);
	  if (j<(i*4)||j>=((i*4+16))) {
	    if (PEEK(0xc000+j)) {
	      printf("ERROR: Read $%02x from $%08lx, expected $00 (i=%d)\n",
		     PEEK(0xc000+j),addr+j,i);
	      /*
	    while(PEEK(0xD610)) POKE(0xD610,0);
	    while(!PEEK(0xD610)) continue;
	    while(PEEK(0xD610)) POKE(0xD610,0);
	      */
	    }	    
	  }
	  else
	    {
	      if (PEEK(0xc000+j)!=(0x10+(j-i*4))) {
	      printf("ERROR: Read $%02x from $%08lx, expected $%02x (i=%d)\n",
		     PEEK(0xc000+j),addr+j,
		     0x10+j-i*4,i);
	      
	      while(PEEK(0xD610)) POKE(0xD610,0);
	      while(!PEEK(0xD610)) continue;
	      if (PEEK(0xD610)==0x03) return;
	      while(PEEK(0xD610)) POKE(0xD610,0);
	    
	      }
	    }
	}
	}
	
      }
    }
  

}

void test_checkerboard(void)
{
  printf("Performing checkerboard test.\n");

  // Make 2KB checkerboard block, and then copy it into all RAM
  // (last 16 bytes of $CXXX is used by libc for dma lists, so can't be used).
  for(addr=0xc000;addr<0xc800;addr++)
    if (addr&1) POKE(addr,0x55); else POKE(addr,0xaa);

  printf("Filling HyperRAM with checkerboard pattern");
  for(addr=0x8000000;addr<upper_addr;addr+=0x800)
    {
      if (!(addr&0xfffff)) printf(".");
      lcopy(0xc000,addr,0x800);
    }
  printf("\n");

  // Now copy out blocks of HypeRAM and verify that the checkerboard pattern is still there.
  printf("Verifying");
  for(addr=0x8000000;addr<upper_addr;addr+=0x800)
    {
      if (PEEK(0xD610)==0x03) return;
      while(PEEK(0xD610)) POKE(0xD610,0);
      if (!(addr&0xffff)) printf(".");
      lcopy(addr,0xc000,0x800);
      for(temp_addr=0xc000;temp_addr<0xc800;temp_addr++)
	if (
	    ((temp_addr&1)&(PEEK(temp_addr)!=0x55))
	    ||
	    ((!(temp_addr&1))&(PEEK(temp_addr)!=0xAA))
	    )
	  {
	    printf("\nVerify error: $%08lx contained $%02x instead of $%02x\n",
		   addr+temp_addr-0xc000,PEEK(temp_addr),
		   (addr&1)?0x55:0xaa);
	    while(PEEK(0xD610)) POKE(0xD610,0);
	    while(!PEEK(0xD610)) continue;
	    if (PEEK(0xd610)==0x03) return;
	    while(PEEK(0xD610)) POKE(0xD610,0);
	  }      		 
    }
  printf("\n");
  

  // Make 2KB inverse checkerboard block, and then copy it into all RAM
  // (last 16 bytes of $CXXX is used by libc for dma lists, so can't be used).
  for(addr=0xc000;addr<0xc800;addr++)
    if (addr&1) POKE(addr,0xaa); else POKE(addr,0x55);

  printf("Filling HyperRAM with inverse checkerboard pattern");
  for(addr=0x8000000;addr<upper_addr;addr+=0x800)
    {
      if (!(addr&0xfffff)) printf(".");
      lcopy(0xc000,addr,0x800);
    }
  printf("\n");

  // Now copy out blocks of HypeRAM and verify that the checkerboard pattern is still there.
  printf("Verifying");
  for(addr=0x8000000;addr<upper_addr;addr+=0x800)
    {
      if (PEEK(0xD610)==0x03) return;
    while(PEEK(0xD610)) POKE(0xD610,0);
      if (!(addr&0xffff)) printf(".");
      lcopy(addr,0xc000,0x800);
      for(temp_addr=0xc000;temp_addr<0xc800;temp_addr++)
	if (
	    ((temp_addr&1)&(PEEK(temp_addr)!=0xAA))
	    ||
	    ((!(temp_addr&1))&(PEEK(temp_addr)!=0x55))
	    )
	  {
	    printf("\nVerify error: $%08lx contained $%02x instead of $%02x\n",
		   addr+temp_addr-0xc000,PEEK(temp_addr),
		   (addr&1)?0x55:0xaa);
	    while(PEEK(0xD610)) POKE(0xD610,0);
	    while(!PEEK(0xD610)) continue;
	    if (PEEK(0xd610)==0x03) return;
	    while(PEEK(0xD610)) POKE(0xD610,0);
	  }      		 
    }
  printf("\n");
  

  
}

void show_info(void)
{
  printf("%cUpper limit of Slow RAM is $%08lx\n",0x13,upper_addr);
  mbs=(unsigned int)((addr-0x8000000L)>>20L);
  printf("Slow RAM is %d MB\n",mbs);
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
  
  printf("Config: Powered up=%c, drive strength=$%x\n",(cr0hi&0x80)?'Y':'N',(cr0hi>>4)&7);
  switch((cr0lo&0xf0)>>4) {
  case 0: printf(" 5 clock latency,"); break;
  case 1: printf(" 6 clock latency,"); break;
  case 14: printf(" 3 clock latency,"); break;
  case 15: printf(" 4 clock latency,"); break;
  default:
    printf("unknown latency clocks ($%x),",(cr0lo&0xf0)>>4);      
  }
  if (cr0lo&8) printf(" fixed latency,"); else printf(" variable latency,");
  printf("\n");
  if (cr0lo&28) printf(" legacy burst,"); else printf(" hybrid burst,");
  switch(cr0lo&3) {
  case 0: printf(" 128 byte burst length.\n"); break;
  case 1: printf(" 64 byte burst length.\n"); break;
  case 2: printf(" 16 byte burst length.\n"); break;
  case 3: printf(" 32 byte burst length.\n"); break;
  }
  
}

void test_speed(void)
{
  printf("%c",0x93);
  while(!PEEK(0xD610))
    {
      printf("%c",0x13);
      show_info();
      printf("\n");

      // Test read speed of normal and extra ram  
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x20000L,0x40000L,32768);
      r2=PEEK(0xD012);
      printf("Copy Chip RAM to Chip RAM: ");
      // 63usec / raster
      time=(r2-0x10)*63;
      speed=32768000L/time;
      printf("%ld KB/s \n",speed);

      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lfill(0x40000L,0,32768);
      r2=PEEK(0xD012);
      printf("            Fill Chip RAM: ");
      // 63usec / raster
      time=(r2-0x10)*63;
      speed=32768000L/time;
      printf("%ld KB/s \n\n",speed);

      // Hyperram fast transactions
      lpoke(0xbfffff2,0x80+fast_flags);
      printf("%cWith fast access enabled:%c\n",0x92,0x12);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x8000000,0x40000,4096);
      r2=PEEK(0xD012);
      printf("Copy Slow RAM to Chip RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x40000,0x8000000,4096);
      r2=PEEK(0xD012);
      printf("Copy Chip RAM to Slow RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x8000000,0x8010000,4096);
      r2=PEEK(0xD012);
      printf("Copy Slow RAM to Slow RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lfill(0x8000000,0,4096);
      r2=PEEK(0xD012);
      printf("            Fill Slow RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      // Hyperram slow transactions
      lpoke(0xbfffff2,0x80+slow_flags);
      printf("\n%cWith fast access disabled:%c\n",0x92,0x12);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x8000000,0x40000,4096);
      r2=PEEK(0xD012);
      printf("Copy Slow RAM to Chip RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x40000,0x8000000,4096);
      r2=PEEK(0xD012);
      printf("Copy Chip RAM to Slow RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x8000000,0x8010000,4096);
      r2=PEEK(0xD012);
      printf("Copy Slow RAM to Slow RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x10)
	while(PEEK(0xD011)&0x80) continue;
      lfill(0x8000000,0,4096);
      r2=PEEK(0xD012);
      printf("            Fill Slow RAM: ");
      time=(r2-0x10)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      // cache back on after no-cache test
      lpoke(0xbfffff2,0x80+fast_flags);
      
    }
}

void main(void)
{
  POKE(0,65);
  POKE(0xD02F,0x47);
  POKE(0xD02F,0x53);

  printf("%c",0x93);

  setup_hyperram();

  // Turn cache back on before reading config registers etc
  lpoke(0xbfffff2,0x80+fast_flags);
  
  cr0hi=lpeek(0xA001000);
  cr0lo=lpeek(0xA001001);
  id0hi=lpeek(0xA000000);
  id0lo=lpeek(0xA000001);

  while (PEEK(0xd610)) POKE(0xd610,0);
  
  while(1) {

    printf("%c",0x93);
    show_info();

    while (PEEK(0xd610)) POKE(0xd610,0);

    printf("\nSelect test:\n"
	   "0 - Reprobe RAM size\n"
	   "1 - Speed test\n"
	   "2 - Read stability\n"
	   "3 - Mis-write test\n"
	   "4 - Checkerboard test\n"
	   "\n"
	   "Press RUN/STOP to return to menu from\nany test.\n"
	   );

    while(!PEEK(0xD610)) continue;

    i=PEEK(0xD610); POKE(0xD610,0);
    
    printf("%c",0x93);
    show_info();

    switch(i) {
    case '0': setup_hyperram(); break;
    case '1': test_speed(); break;
    case '2': test_continuousread(); break;
    case '3': test_miswrite(); break;
    case '4': test_checkerboard(); break;
    case '5': test_cacheerror(); break;
    }

    while(PEEK(0xD610)) POKE(0xD610,0);
  }
}

