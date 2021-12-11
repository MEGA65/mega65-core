extern struct m65_tm tm_start;
extern struct m65_tm tm_now;

#ifdef A100T
#define SLOT_SIZE (4L*1048576L)
#define SLOT_MB 4
#else
#define SLOT_MB 8
#define SLOT_SIZE (8L*1048576L)
#endif

extern unsigned char slot_count;
extern unsigned char bash_bits;
extern unsigned int page_size;
extern unsigned char latency_code;
extern unsigned char reg_cr1;
extern unsigned char reg_sr1;

extern unsigned char manufacturer;
extern unsigned short device_id;
extern unsigned char cfi_data[512];
extern unsigned short cfi_length;
extern unsigned char flash_sector_bits;
extern unsigned char last_sector_num;
extern unsigned char sector_num;

extern unsigned char reconfig_disabled;

extern unsigned char data_buffer[512];
extern unsigned char bitstream_magic[16];

extern unsigned short mb;

extern unsigned char buffer[512];

extern short i,x,y,z;

void probe_qpsi_flash(unsigned char verboseP);
void reflash_slot(unsigned char slot);
void reconfig_fpga(unsigned long addr);
void flash_inspector(void);


void read_registers(void);
void query_flash_protection(unsigned long addr_in_sector);
char *select_bitstream_file(void);
void fetch_rdid(void);
void flash_reset(void);
unsigned char check_input(char *m, uint8_t case_sensitive);
void unprotect_flash(unsigned long addr_in_sector);
unsigned char verify_data_in_place(unsigned long start_address);
void progress_bar(unsigned char onesixtieths);
void read_data(unsigned long start_address);
void program_page(unsigned long start_address,unsigned int page_size);
void erase_sector(unsigned long address_in_sector);
void enable_quad_mode(void);

void spi_clock_low(void);
void spi_clock_high(void);
void spi_cs_low(void);
void spi_cs_high(void);
void press_any_key(void);
void delay(void);
void spi_tx_byte(unsigned char b);
unsigned char qspi_rx_byte(void);
unsigned char spi_rx_byte(void);
void read_sr1(void);
void spi_write_enable(void);
void spi_clear_sr1(void);
void spi_write_disable(void);



//#define DEBUG_BITBASH(x) { printf("@%d:%02x",__LINE__,x); }
#define DEBUG_BITBASH(x)

#define CASE_INSENSITIVE  0
#define CASE_SENSITIVE    1

/*
  $D6C8-B = address for FPGA to boot from in flash
  $D6CF = trigger address for FPGA reconfiguration: Write $42 to trigger

  $D6CC.0 = data bit 0 / SI (serial input)
  $D6CC.1 = data bit 1 / SO (serial output)
  $D6CC.2 = data bit 2 / WP# (write protect)
  $D6CC.3 = data bit 3 / HOLD#
  $D6CC.4 = tri-state SI only (to enable single bit SPI communications)
  $D6CC.5 = clock
  $D6CC.6 = CS#
  $D6CC.7 = data bits DDR (all 4 bits at once)
*/
#define BITBASH_PORT 0xD6CCU

/*
  $D6CD.0 = clock free run if set, or under bitbash control when 0
  $D6CD.1 = alternate control of clock pin
*/
#define CLOCKCTL_PORT 0xD6CDU

/*
  Here are our routines for accessing the SD card without relying on the
  hypervisor.  Note that we can't even assume that the hypervisor has 
  found and reset the SD card, because of the very early point at which
  the flash menu gets called.  "Alles muss man selber machen" ;)
  Oh, yes, and we have only about 5KB space left in this utility, before
  we start having memory overrun problems. So we have to keep this
  absolutely minimalistic.
 */

#define sd_sectorbuffer 0xffd6e00L
#define sd_ctl 0xd680L
#define sd_addr 0xd681L

extern const unsigned long sd_timeout_value;
