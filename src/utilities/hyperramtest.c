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
  0x08 = Read phase offset

  XXX Weirdly, the external hyperram only works stably with the cache enabled
  ($80 set), or else it gets lots of transient single byte errors.


*/
unsigned char fast_flags=0x70; // 0xb0; 
unsigned char slow_flags=0x00;
unsigned char cache_bit=0x80; // =0x80;

void bust_cache(void) {
  lpoke(0xbfffff2,fast_flags&(0xff-cache_bit));
  lpoke(0xbfffff2,fast_flags|cache_bit);
}


void setup_hyperram(void)
{
  /*
    Test complete HyperRAM, including working out the size.
  */
  printf("Determining size of Slow RAM");

  // Set default timing for 2nd hyperram
  //  lpoke(0xbfffffd,0x03);
  //  lpoke(0xbfffffe,0x01);

  lpoke(0x8000000,0xbd);
  while(lpeek(0x8000000)!=0xBD) {
    printf("Rewriting $8000000 = $BD.\n");
    lpoke(0x8000000,0xbd);    
  }
  for(addr=0x8001000;(addr!=0x9000000);addr+=0x1000)
    {

      // XXX There is still some cache consistency bugs,
      // so we bust the cache before checking various things
      bust_cache();
      
      if (lpeek(0x8000000)!=0xbd) {
	printf("\nERROR: $8000000 didn't hold its value.\n"
	       "Should be $BD, but saw $%02x\n",lpeek(0x8000000));
	printf("(occurred while probing $%08lx)\n",addr);
	break;
      }
      
      if (!(addr&0xfffff)) printf(".");

      bust_cache();
      
      lpoke(addr,0x55);

      bust_cache();
      
      i=lpeek(addr);
      if (i!=0x55) {
	if ((addr!=0x8800000)&&(addr!=0x9000000))
	  printf("\n$%08lx corrupted != $55\n (saw $%02x, re-read yields $%02x)",addr,i,lpeek(addr));
	break;
      }

      bust_cache();

      lpoke(addr,0xAA);

      bust_cache();

      i=lpeek(addr);
      if (i!=0xaa) {
	if ((addr!=0x8800000)&&(addr!=0x9000000))
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

  if ((addr!=0x8800000)&&(addr!=0x9000000)) {
    printf("\nError(s) while testing Slow RAM\n");
    printf("\nPress any key to continue...\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    while(!PEEK(0xD610)) continue;
    if (PEEK(0xd610)==0x03) return;
    while(PEEK(0xD610)) POKE(0xD610,0);
  }

  // Pre-fill all hyperram for convenience
  printf("\nErasing hyperram");
  // Cache helps with linear write speed
  lpoke(0xbfffff2,fast_flags|cache_bit);

  // Allow for upto 16MB of HyperRAM
  for(addr=0x8000000;(addr<upper_addr);addr+=0x8000)
    { lfill(addr,0x00,0x8000);
      if (!(addr&0xfffff)) printf(".");
    }
  printf("\n");
 

  lpoke(0xbfffff2,fast_flags|cache_bit);
  
}

void test_continuousread(void)
{
  i=0;
  for(addr=0x8000000;addr<0x8800000;addr+=0x8000)
    lfill(addr,i++,0x8000);

  printf("Initialising hyperram contents...\n");

  addr=0x8000000;
  lfill(addr,0xbd,0x800);

  addr=0x8800000;
  lfill(addr,0xbd,0x800);

  // Write test pattern to both ATTIC and CELLAR hyperram areas
  j=0;
  addr=0x8000000;
  do { lpoke(addr+j,+j); j++; } while(j);
  addr=0x8800000;
  do { lpoke(addr+j,+j); j++; } while(j);
  
  // Copy slow RAM back and check
  while(!PEEK(0xD610)) {
    lcopy(0x8000000,0x0400,40*12);
    lcopy(0x8800000,0x0400+40*13,40*12);

    // Mark mismatches red
    // Internal hyperram:
    i=0;
    for(j=0;j<255;j++)
      { if (PEEK(0x0400+j)!=j) { i++; POKE(0xD800+j,2); } else POKE(0xD800+j,0xe); }
    for(j=0;j<(40*12-256);j++)
      { if (PEEK(0x0500+j)!=j) { i++; POKE(0xD900+j,2); } else POKE(0xD900+j,0xe); }
    if (i>0) {
      // Wait for user press while debugging external hyperram read problems.
      while(!PEEK(0xD610)) { POKE(0xD020,PEEK(0xD020)+1); }
      if (PEEK(0xD610)==3) return;
      POKE(0xD610,0);
    }

    // External hyperram:
    i=0;
    for(j=0;j<255;j++)
      { if (PEEK(0x0400+40*13+j)!=j) { POKE(0xD800+40*13+j,2); i++; } else POKE(0xD800+40*13+j,0xe); }
    for(j=0;j<(40*12-256);j++)
      { if (PEEK(0x0500+40*13+j)!=j) { POKE(0xD900+40*13+j,2); i++; }  else POKE(0xD900+40*13+j,0xe); }
  }
  
}

void test_ramtiming(void)
{
  printf("%c%cThis message should appear without\n"
	 "error, and beginning at the start of the"
	 "second line of the screen.  Otherwise,\n"
	 "the RAM timings are still incorrect.\n",0x93,0x11);
  printf("Press RUN/STOP when correct.\n");
  lcopy(0x0428,0xc000,0x200);
  
  // Test for both hyperram chips
  for(i=1;i<16;i++)
    for(j=1;j<16;j++) {
      lpoke(0xbfffff3,i);
      lpoke(0xbfffff4,j);

      lfill(0x8000000,0x00,0x800);
      lcopy(0xc000,0x8000000,0x200);

      printf("%cwrite_latency=%d, extra_latency=%d:\n",0x93,i,j);
      
      lcopy(0x8000000,0x428,0x200);

      for(k=0;k<0x200;k++) if (PEEK(0xC000+k)!=PEEK(0x428+k)) break;

      if (k!=0x200) continue;

#if 1
      printf("Correct timing for HyperRAM @ $8000000-$87FFFFF\n");
      while(!PEEK(0xD610)) continue;
#endif
      i=17; j=17; // exit both loops immediately
      POKE(0xD610,0);
      
    }


  for(i=1;i<8;i++)
    for(j=1;j<8;j++) {
      lpoke(0xbfffffd,i);
      lpoke(0xbfffffe,j);

      lfill(0x8800000,0x00,0x800);
      lcopy(0xc000,0x8800000,0x200);

      printf("%cwrite_latency=%d, extra_latency=%d:\n",0x93,i,j);

      bust_cache();
      
      lcopy(0x8800000,0x428,0x200);

      for(k=0;k<0x200;k++) if (PEEK(0xC000+k)!=PEEK(0x428+k)) break;

      //      if (k!=0x200) continue;

#if 1
      //      printf("Correct timing for HyperRAM @ $8800000-$8FFFFFF\n");
      while(!PEEK(0xD610)) continue;
      if (PEEK(0xD610)==3) return;
      POKE(0xD610,0);
#endif
      
    }
}

long cache_row_addr;

void show_cache_line(unsigned long addr,int row)
{
  printf("Row%d: ",row);
  if (lpeek(addr+3)==0xAA) {
    // Old style
    cache_row_addr=lpeek(addr+2);
    cache_row_addr|=(((long)lpeek(addr+1))<<8);
    cache_row_addr|=(((long)lpeek(addr+0))<<16);
    cache_row_addr=cache_row_addr<<3;
    cache_row_addr|=0x8000000;
  } else {
    cache_row_addr=lpeek(addr+3);
    cache_row_addr|=(((long)lpeek(addr+2))<<8);
    cache_row_addr|=(((long)lpeek(addr+1))<<16);
    cache_row_addr|=(((long)lpeek(addr+0))<<24);
  }
  printf("$%07lx:",cache_row_addr);
  for(k=0;k<8;k++) {
    if (lpeek(addr+4)&(1<<k)) {
      printf(" %02x",lpeek(addr+8+k));
    } else printf(" xx");
  }
  printf("\n");
}

void show_cache_contents(void)
{
  show_cache_line(0xb000000L,0);
  show_cache_line(0xb000010L,1);
}

void test_cacheerror(void)
{
  printf("\nPerforming cache error test.\n\n");

  printf("Testing read-after-write:\n");
  printf("Writing $99\n");
  lpoke(0x8000800L,0x99);
  bust_cache();
  
  printf("  read $%02x\n",lpeek(0x8000800L));
  printf("Writing $10, ");
  lpoke(0x8000800L,0x10);
  // ... and so, we will read $99 here instead of $10
  printf("  read $%02x\n",lpeek(0x8000800L));

  printf("Flushing cache.\n");
  bust_cache();
  printf("  read $%02x\n",lpeek(0x8000800L));

  printf("\nTesting more complex read-after-write:\n");
  lfill(0x8000800,0x00,0x800);
  printf("Cache contents before writing:\n");
  show_cache_contents();
  for(j=0;j<16;j++) lpoke(0x8000800+j,0x10+j);
  printf("Cache contents before reading:\n");
  show_cache_contents();
  //  lcopy(0x8000000,0xc000,0x800);
  for(j=0;j<16;j++) {
    k=lpeek(0x8000800+j);
    if (k!=(j+0x10)) {
      printf("Read $%02x from $%08lx instead of $%02x\n",
	     k,0x8000800L+j,j+0x10);
      show_cache_contents();
    }
  }
  
  
  printf("\nPress any key to return.\n");
  while(PEEK(0xD610)) POKE(0xD610,0);
  while(!PEEK(0xD610)) continue;
  if (PEEK(0xD610)==0x03) return;
  while(PEEK(0xD610)) POKE(0xD610,0);


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

	//	show_cache_contents();
	
	// Write test pattern somewhere
	for(j=0;j<16;j++) lpoke(addr+(i*4)+j,0x10+j);

	//	show_cache_contents();
	
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

  printf("Internal Slow RAM:\n");
  cr0hi=lpeek(0xA001000);
  cr0lo=lpeek(0xA001001);
  id0hi=lpeek(0xA000000);
  id0lo=lpeek(0xA000001);

  //  printf("Chip ID: %d rows, %d columns\n",
  //	 (id0hi&0x1f)+1,(id0lo>>4)+1);
  printf("  Expected capacity: %d MB\n",
	 1<<((id0hi&0x1f)+1+(id0lo>>4)+1+1-20));
  printf("  Vendor: ");
  switch(id0lo&0xf) {
  case 1: printf("Cypress"); break;
  case 3: printf("ISSI"); break;
  default: printf("<unknown>");
  }
  printf("\n");
  
  //  printf("Config: Powered up=%c, drive strength=$%x\n",(cr0hi&0x80)?'Y':'N',(cr0hi>>4)&7);
  switch((cr0lo&0xf0)>>4) {
  case 0: printf("  5 clock latency,"); break;
  case 1: printf("  6 clock latency,"); break;
  case 14: printf("  3 clock latency,"); break;
  case 15: printf("  4 clock latency,"); break;
  default:
    printf("  unknown latency clocks ($%x),",(cr0lo&0xf0)>>4);      
  }
  if (cr0lo&8) printf(" fixed latency,"); else printf(" variable latency,");
  printf("\n");
  /*  if (cr0lo&28) printf(" legacy burst,"); else printf(" hybrid burst,");
  switch(cr0lo&3) {
  case 0: printf(" 128 byte burst length.\n"); break;
  case 1: printf(" 64 byte burst length.\n"); break;
  case 2: printf(" 16 byte burst length.\n"); break;
  case 3: printf(" 32 byte burst length.\n"); break;
  }
  */

  printf("Trapdoor Slow RAM:\n");
  cr0hi=lpeek(0xA801000);
  cr0lo=lpeek(0xA801001);
  id0hi=lpeek(0xA800000);
  id0lo=lpeek(0xA800001);
  if ((1<<((id0hi&0x1f)+1+(id0lo>>4)+1+1-20))>0
      &&
      ((1<<((id0hi&0x1f)+1+(id0lo>>4)+1+1-20))<=32)) {
    printf("  Expected capacity: %d MB\n",
	   1<<((id0hi&0x1f)+1+(id0lo>>4)+1+1-20));
    printf("  Vendor: ");
    switch(id0lo&0xf) {
    case 1: printf("Cypress"); break;
    case 3: printf("ISSI"); break;
    default: printf("<unknown>");
    }
    printf("\n");
    
    switch((cr0lo&0xf0)>>4) {
    case 0: printf("  5 clock latency,"); break;
    case 1: printf("  6 clock latency,"); break;
    case 14: printf("  3 clock latency,"); break;
    case 15: printf("  4 clock latency,"); break;
    default:
      printf("  unknown latency clocks ($%x),",(cr0lo&0xf0)>>4);      
    }
    if (cr0lo&8) printf(" fixed latency,"); else printf(" variable latency,");
  } else
    printf("  Not detected.\n");
  printf("\n");
  
}

void test_chipsetdma(void)
{
  // Get some data to show
  // (Should show a single repeating 8x8 block with many colours)

  // Clear screen and RAM used to show the blocks
  lfill(0x0400,0x00,0x400);
  lfill(0x777d800,0x00,0x400);
  lfill(0x8000000,0x00,0xffff);

  // Make some coloured blocks
  for(i=0;i<16;i++) lfill(0x8000000+(i<<6),i,0x40);
  for(i=0;i<16;i++) POKE(0x0400+40*1+i,i);
  
  // Make a mult-colour block
  for(i=0;i<64;i++) lpoke(0x8000000+i,i&0xf);
  
  // VIC-IV 256-colour text mode, fetch data from hyperram
  POKE(0xD054,0x06);
  POKE(0xD063,0x80);
  // Disable debug feeding of lots of data to VIC-IV
  lpoke(0xbfffff2L,0);
  
  i=PEEK(0xD07D);
  while(!PEEK(0xD610)) {
    j=PEEK(0xD07D);
    if (i!=j) POKE(0xD020,(PEEK(0xD020)+1)&0xf);
    i=j;
    // For some reason accessing the HyperRAM allows the next chipset DMA request to occur.
    // But without, they occur only very, very slowly, or something like that.
    //    lpeek(0x8000000);
  }
  POKE(0xD610,0);
  POKE(0xD054,0);
}

void test_speed(void)
{
  POKE(0xD06F,0x80); // PAL, so that we have 63usec per raster for calculations below
  POKE(0xD011,0x1b);
  
  printf("%c",0x93);
  while(!PEEK(0xD610))
    {
      printf("%c",0x13);
      show_info();
      printf("\n%cFast Chip RAM:%c\n",0x12,0x92);

      // Test read speed of normal and extra ram  
      while(PEEK(0xD012)!=0x20)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x20000L,0x40000L,32768);
      r2=PEEK(0xD012);
      printf("Copy Chip RAM to Chip RAM: ");
      // 63usec / raster
      time=(r2-0x20)*63;
      speed=32768000L/time;
      printf("%ld KB/s \n",speed);

      while(PEEK(0xD012)!=0x20)
	while(PEEK(0xD011)&0x80) continue;
      lfill(0x40000L,0,32768);
      r2=PEEK(0xD012);
      printf("            Fill Chip RAM: ");
      // 63usec / raster
      time=(r2-0x20)*63;
      speed=32768000L/time;
      printf("%ld KB/s \n",speed);

      // Hyperram fast transactions
      lpoke(0xbfffff2,fast_flags|cache_bit);

      printf("%cInternal Slow RAM:%c\n",0x12,0x92);
      
      while(PEEK(0xD012)!=0x20)
	while(PEEK(0xD011)&0x80) continue;
      //      POKE(0xD020,1);
      lcopy(0x8000000,0x40000,4096);
      POKE(0xD020,14);
      r2=PEEK(0xD012);
      printf("Copy Slow RAM to Chip RAM: ");
      time=(r2-0x20)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x20)
	while(PEEK(0xD011)&0x80) continue;
      lcopy(0x40000,0x8000000,4096);
      r2=PEEK(0xD012);
      printf("Copy Chip RAM to Slow RAM: ");
      time=(r2-0x20)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x20)
	while(PEEK(0xD011)&0x80) continue;
      //      POKE(0xD020,2);
      lcopy(0x8000000,0x8010000,4096);
      POKE(0xD020,14);
      r2=PEEK(0xD012);
      printf("Copy Slow RAM to Slow RAM: ");
      time=(r2-0x20)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      while(PEEK(0xD012)!=0x20)
	while(PEEK(0xD011)&0x80) continue;
      lfill(0x8000000,0,4096);
      r2=PEEK(0xD012);
      printf("            Fill Slow RAM: ");
      time=(r2-0x20)*63;
      speed=4096000L/time;
      printf("%ld KB/s \n",speed);
      
      // Hyperram slow transactions
      lpoke(0xbfffff2,slow_flags|cache_bit);

      printf("%cTrapdoor Slow RAM:%c\n",0x12,0x92);

      if (upper_addr<=0x8800000)
	printf("  Not detected.\n");
      else {
	
	while(PEEK(0xD012)!=0x20)
	  while(PEEK(0xD011)&0x80) continue;
	//      POKE(0xD020,1);
	lcopy(0x8800000,0x40000,4096);
	POKE(0xD020,14);
	r2=PEEK(0xD012);
	printf("Copy Slow RAM to Chip RAM: ");
	time=(r2-0x20)*63;
	speed=4096000L/time;
	printf("%ld KB/s \n",speed);
	
	while(PEEK(0xD012)!=0x20)
	  while(PEEK(0xD011)&0x80) continue;
	lcopy(0x40000,0x8800000,4096);
	r2=PEEK(0xD012);
	printf("Copy Chip RAM to Slow RAM: ");
	time=(r2-0x20)*63;
	speed=4096000L/time;
	printf("%ld KB/s \n",speed);
	
	while(PEEK(0xD012)!=0x20)
	  while(PEEK(0xD011)&0x80) continue;
	//      POKE(0xD020,2);
	lcopy(0x8800000,0x8810000,4096);
	POKE(0xD020,14);
	r2=PEEK(0xD012);
	printf("Copy Slow RAM to Slow RAM: ");
	time=(r2-0x20)*63;
	speed=4096000L/time;
	printf("%ld KB/s \n",speed);
	
	while(PEEK(0xD012)!=0x20)
	  while(PEEK(0xD011)&0x80) continue;
	lfill(0x8800000,0,4096);
	r2=PEEK(0xD012);
	printf("            Fill Slow RAM: ");
	time=(r2-0x20)*63;
	speed=4096000L/time;
	printf("%ld KB/s \n",speed);
	
	// Hyperram slow transactions
	lpoke(0xbfffff2,slow_flags|cache_bit);
      }
      
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
  lpoke(0xbfffff2,fast_flags|cache_bit);
  
  while (PEEK(0xd610)) POKE(0xd610,0);
  
  while(1) {

    printf("%c",0x93);
    show_info();

    while (PEEK(0xd610)) { POKE(0xD020,PEEK(0xD020)+1); POKE(0x0427,PEEK(0xD610)); POKE(0xd610,0); }

    printf("\nSelect test:\n"
	   "0 - Reprobe RAM size\n"
	   "1 - Speed test\n"
	   "2 - Read stability\n"
	   "3 - Mis-write test\n"
	   "4 - Checkerboard test\n"
	   "5 - Test cache consistency cases\n"
	   "6 - Probe RAM timings\n"
	   "7 - Test chipset DMA\n"
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
    case '6': test_ramtiming(); break;
    case '7': test_chipsetdma(); break;
    }

    while(PEEK(0xD610)) POKE(0xD610,0);
  }
}

