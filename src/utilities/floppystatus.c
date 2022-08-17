#include <stdio.h>
#define POKE(X, Y) (*(unsigned char *)(X)) = Y
#define PEEK(X) (*(unsigned char *)(X))
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
  unsigned char sub_cmd; // F018B subcmd
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
  POKE(0xd702U, 0);
  POKE(0xd704U, 0x00); // List is in $00xxxxx
  POKE(0xd701U, ((unsigned int)&dmalist) >> 8);
  POKE(0xd705U, ((unsigned int)&dmalist) & 0xff); // triggers enhanced DMA
}

unsigned char lpeek_toscreen(long address)
{
  // Read the byte at <address> in 28-bit address space
  // XXX - Optimise out repeated setup etc
  // (separate DMA lists for peek, poke and copy should
  // save space, since most fields can stay initialised).

  dmalist.option_0b = 0x0b;
  dmalist.option_80 = 0x80;
  dmalist.source_mb = (address >> 20);
  dmalist.option_81 = 0x81;
  dmalist.dest_mb = 0x00; // dma_byte lives in 1st MB
  dmalist.end_of_options = 0x00;
  dmalist.sub_cmd = 0x02; // Hold source address

  dmalist.command = 0x00; // copy
  dmalist.count = 1000;
  dmalist.source_addr = address & 0xffff;
  dmalist.source_bank = ((address >> 16) & 0x0f);
  dmalist.dest_addr = 0x0400;
  dmalist.dest_bank = 0;

  do_dma();

  return dma_byte;
}

unsigned char lpeek(long address)
{
  // Read the byte at <address> in 28-bit address space
  // XXX - Optimise out repeated setup etc
  // (separate DMA lists for peek, poke and copy should
  // save space, since most fields can stay initialised).

  dmalist.option_0b = 0x0b;
  dmalist.option_80 = 0x80;
  dmalist.source_mb = (address >> 20);
  dmalist.option_81 = 0x81;
  dmalist.dest_mb = 0x00; // dma_byte lives in 1st MB
  dmalist.end_of_options = 0x00;
  dmalist.sub_cmd = 0x00;

  dmalist.command = 0x00; // copy
  dmalist.count = 1;
  dmalist.source_addr = address & 0xffff;
  dmalist.source_bank = (address >> 16) & 0x0f;
  dmalist.dest_addr = (unsigned int)&dma_byte;
  dmalist.dest_bank = 0;

  do_dma();

  return dma_byte;
}

void lpoke(long address, unsigned char value)
{

  dmalist.option_0b = 0x0b;
  dmalist.option_80 = 0x80;
  dmalist.source_mb = 0x00; // dma_byte lives in 1st MB
  dmalist.option_81 = 0x81;
  dmalist.dest_mb = (address >> 20);
  dmalist.end_of_options = 0x00;

  dma_byte = value;
  dmalist.command = 0x00; // copy
  dmalist.count = 1;
  dmalist.source_addr = (unsigned int)&dma_byte;
  dmalist.source_bank = 0;
  dmalist.dest_addr = address & 0xffff;
  dmalist.dest_bank = (address >> 16) & 0x0f;

  do_dma();
  return;
}

void lcopy(long source_address, long destination_address, unsigned int count)
{
  if (!count)
    return;
  dmalist.option_0b = 0x0b;
  dmalist.option_80 = 0x80;
  dmalist.source_mb = source_address >> 20;
  dmalist.option_81 = 0x81;
  dmalist.dest_mb = (destination_address >> 20);
  dmalist.end_of_options = 0x00;

  dmalist.command = 0x00; // copy
  dmalist.count = count;
  dmalist.sub_cmd = 0;
  dmalist.source_addr = source_address & 0xffff;
  dmalist.source_bank = (source_address >> 16) & 0x0f;
  if (source_address >= 0xd000 && source_address < 0xe000)
    dmalist.source_bank |= 0x80;
  dmalist.dest_addr = destination_address & 0xffff;
  dmalist.dest_bank = (destination_address >> 16) & 0x0f;
  if (destination_address >= 0xd000 && destination_address < 0xe000)
    dmalist.dest_bank |= 0x80;

  do_dma();
  return;
}

void lfill(long destination_address, unsigned char value, unsigned int count)
{
  if (!count)
    return;
  dmalist.option_0b = 0x0b;
  dmalist.option_80 = 0x80;
  dmalist.source_mb = 0x00;
  dmalist.option_81 = 0x81;
  dmalist.dest_mb = destination_address >> 20;
  dmalist.end_of_options = 0x00;

  dmalist.command = 0x03; // fill
  dmalist.sub_cmd = 0;
  dmalist.count = count;
  dmalist.source_addr = value;
  dmalist.dest_addr = destination_address & 0xffff;
  dmalist.dest_bank = (destination_address >> 16) & 0x0f;
  if (destination_address >= 0xd000 && destination_address < 0xe000)
    dmalist.dest_bank |= 0x80;
  do_dma();
  return;
}

void m65_io_enable(void)
{
  // Gate C65 IO enable
  POKE(0xd02fU, 0x47);
  POKE(0xd02fU, 0x53);
  // Force to full speed
  POKE(0, 65);
}

void wait_10ms(void)
{
  // 16 x ~64usec raster lines = ~1ms
  int c = 160;
  unsigned char b;
  while (c--) {
    b = PEEK(0xD012U);
    while (b == PEEK(0xD012U))
      continue;
  }
}

void main(void)
{

  unsigned char seconds = 0;
  unsigned char minutes = 0;
  unsigned char hours = 0;

  unsigned char t, s, h, b1, b2, b3, b4, b5, b6, b7;
  short a1;
  unsigned char n = 0;

  m65_io_enable();

  // Disable OSK
  lpoke(0xFFD3615L, 0x7F);

  // FDC motor on
  lpoke(0xFFD3080L, 0x30);

  // Clear screen
  printf("%c", 0x93);

  for (t = 0; t < 40; t++)
    ((unsigned char *)0x658)[t] = '-';

  while (1) {
    // 0xffd7026 is the base address for all bytes read from the RTC
    // The I2C Master places them in these memory locations

    // Only update when every second, otherwise wait
    // while(seconds==lpeek(0xffd7026)){};

    // Home cursor
    printf("%c", 0x13);

    t = lpeek(0xffd36a3L);
    s = lpeek(0xffd36a4L);
    h = lpeek(0xffd36a5L);
    printf("last seen sector: T:%d, S:%d, Side:%d     \n", t, s, h);

    b1 = lpeek(0xffd36a6L);
    b2 = lpeek(0xffd36a7L);
    b3 = lpeek(0xffd36a8L);
    b4 = lpeek(0xffd36a9L);
    b5 = lpeek(0xffd36aaL);
    b6 = lpeek(0xffd36abL);
    b7 = lpeek(0xffd36acL);

    printf("Decoded MFM byte: $%x (last = $%x)  \n", b1, b3);
    printf("MFM FSM state: %d  \n", b2);
    printf("Last MFM gap interval: %x   \n", b4 + (b5 << 8));
    printf("Last 7 MFM rdata bits: %x   \n", b6);
    printf("MFM last quantised gap: %x   \n", b7);

    // Show last decoded MFM byte
    a1 = lpeek(0xffd368L);
    POKE(0x0680U + a1, PEEK(0x0680U + a1) + 1);

    a1 = lpeek(0xffd7000L);
  }
}
