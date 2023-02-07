#include <stdio.h>
#define POKE(X, Y) (*(volatile unsigned char *)(X)) = Y
#define PEEK(X) (*(volatile unsigned char *)(X))
void m65_io_enable(void);

unsigned char joy_x = 100;
unsigned char joy_y = 100;

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

unsigned char latency_code = 0xff;
unsigned char reg_cr1 = 0x00;
unsigned char reg_sr1 = 0x00;

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

unsigned char sprite_data[63] = { 0xff, 0, 0, 0xe0, 0, 0, 0xb0, 0, 0, 0x98, 0, 0, 0x8c, 0, 0, 0x86, 0, 0, 0x83, 0, 0, 0x81,
  0x80, 0,

  0, 0xc0, 0, 0, 0x60, 0, 0, 0x30, 0, 0, 0x18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

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

int bash_bits = 0xFF;

unsigned int di;
void delay(void)
{
  // Slow down signalling when debugging using JTAG monitoring.
  // Not needed for normal operation.

  //   for(di=0;di<1000;di++) continue;
}

void spi_tristate_si(void)
{
  bash_bits |= 0x02;
  POKE(BITBASH_PORT, bash_bits);
}

void spi_tristate_si_and_so(void)
{
  bash_bits |= 0x03;
  bash_bits &= 0x6f;
  POKE(BITBASH_PORT, bash_bits);
}

unsigned char spi_sample_si(void)
{
  // Make SI pin input
  bash_bits &= 0x7F;
  bash_bits |= 0x02;
  POKE(BITBASH_PORT, bash_bits);

  // Not sure why we need this here, but we do, else it only ever returns 1.
  // (but the delay can be made quite short)
  delay();

  if (PEEK(BITBASH_PORT) & 0x02)
    return 1;
  else
    return 0;
}

void spi_so_set(unsigned char b)
{
  // De-tri-state SO data line, and set value
  bash_bits &= (0xff - 0x01);
  bash_bits |= (0x1F - 0x01);
  if (b)
    bash_bits |= 0x01;
  POKE(BITBASH_PORT, bash_bits);
}

void spi_clock_low(void)
{
  bash_bits &= 0xff - 0x20;
  POKE(BITBASH_PORT, bash_bits);
}

void spi_clock_high(void)
{
  bash_bits |= 0x20;
  POKE(BITBASH_PORT, bash_bits);
}

void spi_cs_low(void)
{
  bash_bits &= 0xff - 0x40;
  POKE(BITBASH_PORT, bash_bits);
}

void spi_cs_high(void)
{
  bash_bits |= 0x40;
  POKE(BITBASH_PORT, bash_bits);
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

  for (i = 0; i < 8; i++) {
    spi_tx_bit(b & 0x80);
    b = b << 1;
  }
}

unsigned char qspi_rx_byte()
{
  unsigned char b = 0;
  unsigned char i;

  b = 0;

  spi_tristate_si_and_so();
  for (i = 0; i < 2; i++) {
    spi_clock_low();
    b = b << 4;
    delay();
    b |= PEEK(BITBASH_PORT) & 0x0f;
    spi_clock_high();
    delay();
  }

  return b;
}

unsigned char spi_rx_byte()
{
  unsigned char b = 0;
  unsigned char i;

  b = 0;

  spi_tristate_si();
  for (i = 0; i < 8; i++) {
    spi_clock_low();
    b = b << 1;
    delay();
    if (spi_sample_si())
      b |= 0x01;
    spi_clock_high();
    delay();
  }
}

unsigned char manufacturer;
unsigned short device_id;
unsigned short cfi_data[512];
unsigned short cfi_length = 0;

unsigned char data_buffer[512];
// Magic string for identifying properly loaded bitstream
unsigned char bitstream_magic[16] = "MEGA65BITSTREAM0";

unsigned short mb = 0;

short i, x, y, z;
short a1, a2, a3;
unsigned char n = 0;

void read_registers(void)
{
  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT, 0x00);

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x05);
  reg_sr1 = spi_rx_byte();
  spi_cs_high();
  delay();

  // Config Register 1 (CR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x35);
  reg_cr1 = spi_rx_byte();
  spi_cs_high();
  delay();
}

void erase_sector(unsigned long address_in_sector)
{

  // XXX Send Write Enable command (0x06 ?)
  printf("activating write enable...\n");
  while (!(reg_sr1 & 0x02)) {
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
  printf("clearing status register...\n");
  while (reg_sr1 & 0x61) {
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
  printf("erasing sector...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xdc);
  spi_tx_byte(address_in_sector >> 24);
  spi_tx_byte(address_in_sector >> 16);
  spi_tx_byte(address_in_sector >> 8);
  spi_tx_byte(address_in_sector >> 0);
  spi_cs_high();

  while (reg_sr1 & 0x01) {
    read_registers();
  }

  if (reg_sr1 & 0x20)
    printf("error erasing sector @ $%08x\n", address_in_sector);
  else {
    printf("sector at $%08llx erased.\n", address_in_sector);
  }
}

void program_page(unsigned long start_address)
{
  // XXX Send Write Enable command (0x06 ?)

  // XXX Send Write Enable command (0x06 ?)
  printf("activating write enable...\n");
  while (!(reg_sr1 & 0x02)) {
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
  printf("clearing status register...\n");
  while (reg_sr1 & 0x61) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x30);
    spi_cs_high();

    read_registers();
  }

  // XXX Send Page Programme (0x12 for 1-bit, or 0x34 for 4-bit QSPI)
  printf("writing 256 bytes of data...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x12);
  spi_tx_byte(start_address >> 24);
  spi_tx_byte(start_address >> 16);
  spi_tx_byte(start_address >> 8);
  spi_tx_byte(start_address >> 0);
  for (x = 0; x < 256; x++)
    spi_tx_byte(data_buffer[x]);

  spi_cs_high();

  while (reg_sr1 & 0x01) {
    printf("flash busy. ");
    read_registers();
  }

  if (reg_sr1 & 0x60)
    printf("error writing data @ $%08x\n", start_address);
  else {
    printf("data at $%08llx written.\n", start_address);
  }
}

void read_data(unsigned long start_address)
{

  // XXX Send read command (0x13 for 1-bit, 0x6c for QSPI)
  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT, 0x00);

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x6c);
  spi_tx_byte(start_address >> 24);
  spi_tx_byte(start_address >> 16);
  spi_tx_byte(start_address >> 8);
  spi_tx_byte(start_address >> 0);

  // Table 25 latency codes
  switch (latency_code) {
  case 3:
    break;
  default:
    // 8 cycles = equivalent of 4 bytes
    for (z = 0; z < 4; z++)
      qspi_rx_byte();
    break;
  }

  // Actually read the data.
  for (z = 0; z < 512; z++)
    data_buffer[z] = qspi_rx_byte();

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
  POKE(CLOCKCTL_PORT, 0x00);

  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();

  spi_tx_byte(0x9f);

  // Data format according to section 11.2

  // Start with 3 byte manufacturer + device ID
  manufacturer = spi_rx_byte();
  device_id = spi_rx_byte() << 8;
  device_id |= spi_rx_byte();

  // Now get the CFI data block
  for (i = 0; i < 512; i++)
    cfi_data[i] = 0x00;
  cfi_length = spi_rx_byte();
  if (cfi_length == 0)
    cfi_length = 512;
  for (i = 0; i < cfi_length; i++)
    cfi_data[i] = spi_rx_byte();

  spi_cs_high();
  delay();
  spi_clock_high();
  delay();
}

struct erase_region {
  unsigned short sectors;
  unsigned int sector_size;
};

int erase_region_count = 0;
#define MAX_ERASE_REGIONS 4
struct erase_region erase_regions[MAX_ERASE_REGIONS];

unsigned char slot_empty_check(unsigned short mb_num)
{
  unsigned long addr;
  for (addr = (mb_num * 1048576L); addr < ((mb_num + 4) * 1048576L); addr += 512) {
    read_data(addr);
    y = 0xff;
    for (x = 0; x < 512; x++)
      y &= data_buffer[x];
    if (y != 0xff)
      return -1;

    *(unsigned long *)(0x0400) = addr;
  }
  return 0;
}

void main(void)
{

  m65_io_enable();

  // Sprite 0 on
  lpoke(0xFFD3015L, 0x01);
  // Sprite data at $03c0
  *(unsigned char *)2040 = 0x3c0 / 0x40;

  for (n = 0; n < 64; n++)
    *(unsigned char *)(0x3c0 + n) = sprite_data[n];

  // Disable OSK
  lpoke(0xFFD3615L, 0x7F);

  // Clear screen
  printf("%c", 0x93);

  // Start by resetting to CS high etc
  bash_bits = 0xff;
  POKE(BITBASH_PORT, bash_bits);
  delay();
  delay();
  delay();
  delay();
  delay();

  fetch_rdid();
  read_registers();
  printf("qspi flash manufacturer = $%02x\n", manufacturer);
  printf("qspi device id = $%04x\n", device_id);
  printf("rdid byte count = %d\n", cfi_length);
  printf("sector architecture is ");
  if (cfi_data[4 - 4] == 0x00)
    printf("uniform 256kb sectors.\n");
  else if (cfi_data[4 - 4] == 0x01)
    printf("4kb parameter sectors with 64kb sectors.\n");
  else
    printf("unknown ($%02x).\n", cfi_data[4 - 4]);
  printf("part family is %02x-%c%c\n", cfi_data[5 - 4], cfi_data[6 - 4], cfi_data[7 - 4]);
  printf("2^%d byte page, program typical time is 2^%d microseconds.\n", cfi_data[0x2a - 4], cfi_data[0x20 - 4]);
  printf("erase typical time is 2^%d milliseconds.\n", cfi_data[0x21 - 4]);

  // Work out size of flash in MB
  {
    unsigned char n = cfi_data[0x27 - 4];
    mb = 1;
    n -= 20;
    while (n) {
      mb = mb << 1;
      n--;
    }
  }
  printf("flash size is %dmb.\n", mb);

  // What erase regions do we have?
  erase_region_count = cfi_data[0x2c - 4];
  if (erase_region_count > MAX_ERASE_REGIONS) {
    printf("error: device has too many erase regions. increase max_erase_regions?\n");
    return;
  }
  for (i = 0; i < erase_region_count; i++) {
    erase_regions[i].sectors = cfi_data[0x2d - 4 + (i * 4)];
    erase_regions[i].sectors |= (cfi_data[0x2e - 4 + (i * 4)]) << 8;
    erase_regions[i].sectors++;
    erase_regions[i].sector_size = cfi_data[0x2f - 4 + (i * 4)];
    erase_regions[i].sector_size |= (cfi_data[0x30 - 4 + (i * 4)]) << 8;
    printf("erase region #%d : %d sectors x %dkb\n", i + 1, erase_regions[i].sectors, erase_regions[i].sector_size >> 2);
  }
  if (reg_cr1 & 4)
    printf("warning: small sectors are at top, not bottom.\n");
  latency_code = reg_cr1 >> 6;
  printf("latency code = %d\n", latency_code);
  if (reg_sr1 & 0x80)
    printf("flash is write protected.\n");
  if (reg_sr1 & 0x40)
    printf("programming error occurred.\n");
  if (reg_sr1 & 0x20)
    printf("erase error occurred.\n");
  if (reg_sr1 & 0x02)
    printf("write latch enabled.\n");
  else
    printf("write latch not (yet) enabled.\n");
  if (reg_sr1 & 0x01)
    printf("device busy.\n");

  // Scan for existing bitstreams
  // (ignore golden bitstream at offset #0)
  if (1)
    for (i = 0; i < mb; i += 4) {
      read_data(i * 1048576);
      //    for(x=0;x<256;x++) printf("%02x ",data_buffer[x]); printf("\n");
      y = 0xff;
      z = 1;
      for (x = 0; x < 256; x++)
        y &= data_buffer[x];
      for (x = 0; x < 16; x++)
        if (data_buffer[x] != bitstream_magic[x])
          z = 0;
      if (y == 0xff)
        printf("bitstream slot #%d header is empty.\n", i);
      else if (z == 0) {
        printf("bitstream slot #%d is invalid.\n", i);
        for (x = 0; x < 64; x++) {
          printf("%02x ", data_buffer[x]);
          if ((x & 7) == 7)
            printf("\n");
        }
      }
      else {
        // Something valid in the slot
        printf("bitstream slot #%d valid.\n", i >> 2);
        // Display info about it
      }
      // Check if entire slot is empty
      //    if (slot_empty_check(i)) printf("  slot is not completely empty.\n");
    }

#if 1
  erase_sector(4 * 1048576L);
#endif
#if 0
  data_buffer[0]=0x12;
  data_buffer[1]=0x34;
  data_buffer[2]=0x56;
  data_buffer[3]=0x78;
  program_page(4*1048576L);
#endif

#if 1
  n = 0;
  do {
    delay();
    delay();
    delay();
    delay();
    delay();
    delay();
    delay();
    delay();
    POKE(0xD6CCU, n);
    POKE(0xD6CCU, n);
    n++;
  } while (n);
#endif

  delay();
  spi_so_set(0);
  delay();
  spi_so_set(1);
  delay();
  spi_so_set(0);
}
