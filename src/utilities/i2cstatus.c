#include <stdio.h>
#include <memory.h>
#include <targets.h>
#include <time.h>

struct m65_tm tm;

unsigned char joy_x=100;
unsigned char joy_y=100;

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


  short x,y,z;
  short a1,a2,a3;
  unsigned char n=0;

void show_rtc(void)
{
    getrtc(&tm);
    
    //    seconds = lpeek_debounced(0xffd7110);
    //    minutes = lpeek_debounced(0xffd7111);

    printf("Real-time clock: %02d:%02d.%02d",tm.tm_hour,tm.tm_min,tm.tm_sec);
    printf("\n");

    printf("Date:            %02d-",tm.tm_mday+1);
    switch(tm.tm_mon) {
    case 1: printf("jan"); break;
    case 2: printf("feb"); break;
    case 3: printf("mar"); break;
    case 4: printf("apr"); break;
    case 5: printf("may"); break;
    case 6: printf("jun"); break;
    case 7: printf("jul"); break;
    case 8: printf("aug"); break;
    case 9: printf("sep"); break;
    case 10: printf("oct"); break;
    case 11: printf("nov"); break;
    case 12: printf("dec"); break;
    default: printf("invalid month"); break;
    }
    printf("-%04d\n",tm.tm_year+1900);

}

void target_megaphone(void)
  {

  // Sprite 0 on
  lpoke(0xFFD3015L,0x01);
  // Sprite data at $03c0
  *(unsigned char *)2040 = 0x3c0/0x40;

  for(n=0;n<64;n++) 
    *(unsigned char*)(0x3c0+n)=
      sprite_data[n];
  
  // Disable OSK
  lpoke(0xFFD3615L,0x7F);  
  
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

    show_rtc();
    
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

unsigned char bcd_add(unsigned char in, unsigned char delta)
{
  unsigned char v=in+delta;
  if ((v&0xf)>0x09) v+=0x06;
  return v;
}

void clip_date(void) {
  if (tm.tm_mday>=30) tm.tm_mday=0;
  if ((tm.tm_mon==2)&&(tm.tm_mday>28)) tm.tm_mday=0;
  if (((tm.tm_mon==4)
       ||(tm.tm_mon==6)
       ||(tm.tm_mon==6)
       ||(tm.tm_mon==9)
       ||(tm.tm_mon==11)
       )
      &&(tm.tm_mday>29)) tm.tm_mday=0;
}

unsigned char hours;

void target_mega65r2(void)
  {

    //  while(lpeek(0xffd71ffL)) continue;

  // Clear screen
  printf("%c",0x93);

  //Function to display current time from Real Time Clock
  while(1){
    // 0xffd7110 is the base address for all bytes read from the RTC
    // The I2C Master places them in these memory locations

    // Home cursor
    printf("%c",0x13);

    printf("Unique identifier/MAC seed: ");
    for(n=2;n<8;n++) printf("%02x",lpeek_debounced(0xffd7100+n));
    printf("\n");

    printf("NVRAM:\n");
    for(n=0x40;n<0x80;n++) {
      if (!(n&7)) printf(" $%02x :",n-0x40);
      printf(" %02x",lpeek_debounced(0xffd7100+n));
      if ((n&7)==7) printf("\n");
    }
    printf("\n");

    show_rtc();
    
    printf("\nPress 1-6 to adjust time/date.\n      7 toggles 12/24 hour time.\n");

    if (lpeek(0xffd3610)) {
      // Wait for any previous write to complete
      while(lpeek(0xffd71ff)) continue;

      switch(lpeek(0xffd3610)) {
      case '0':
	setrtc(&tm);
	break;
      case '1':
	tm.tm_hour++;
	if (tm.tm_hour>23) tm.tm_hour=0;
	setrtc(&tm);
	break;
      case '2':
	tm.tm_min++;
	if (tm.tm_min>59) tm.tm_min=0;
	setrtc(&tm);
	break;
      case '3':
	tm.tm_sec++;
	if (tm.tm_sec>59) tm.tm_sec=0;
	setrtc(&tm);
	break;
      case '4':
	tm.tm_mday++;
	clip_date();
	setrtc(&tm);
	break;
      case '5':
	tm.tm_mon++;
	if (tm.tm_mon>12) tm.tm_mon=1;
	clip_date();
	setrtc(&tm);
	break;
      case '6':
	tm.tm_year++;
	if (tm.tm_year>199) tm.tm_year=0;
	setrtc(&tm);
	break;
      case '7':
	// 12/24 toggle is not supported by the libc, so do it manually
	hours=lpeek_debounced(0xffd7112);
	if (hours&0x80) {
	  // Switch to 12 hour time.
	  hours&=0x7f;
	  if ((hours&0x7f)>0x12) {
	    hours=bcd_add(hours,-0x12);
	    hours|=0x20;
	  }	  
	} else {
	  if (hours&0x20) {
	    hours=bcd_add(hours&0x1f,0x12);
	  }
	  hours|=0x80;
	}
	while(lpeek(0xffd71ff)) continue;
	lpoke(0xffd7112,hours);
	break;
      default:
	break;
      }
      
      lpoke(0xffd3610,0);
    }
    
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

  switch (detect_target()) {
  case TARGET_MEGA65R2:
    target_mega65r2();
    break;
  case TARGET_MEGAPHONER1:
    target_megaphone();
    break;
  default:
    printf("Unknown hardware revision. No I2C block found.\n");
  }

}
  

