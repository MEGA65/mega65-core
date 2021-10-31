#include <stdio.h>
#include <string.h>

#include <hal.h>
#include <memory.h>
#include <dirent.h>
#include <time.h>

#define HARDWARE_SPI
#define HARDWARE_SPI_WRITE

//#define DEBUG_BITBASH(x) { printf("@%d:%02x",__LINE__,x); }
#define DEBUG_BITBASH(x)

#ifdef A100T
#define SLOT_SIZE (4L*1048576L)
#define SLOT_MB 4
#else
#define SLOT_MB 8
#define SLOT_SIZE (8L*1048576L)
#endif

struct m65_tm tm_start;
struct m65_tm tm_now;

char *select_bitstream_file(void);
void fetch_rdid(void);
void flash_reset(void);
unsigned char check_input(char *m, uint8_t case_sensitive);

unsigned char compare_routine[36]=
  {
   0xa2,0, // LDX #$00
   0xbd,0,0, // loop1: LDA $nnnn,x
   0xdd,0,0, // CMP $nnnn,x
   0xd0,0x14, // BNE fail
   0xe8,      // INX
   0xd0,0xf5, // BNE loop1
   0xbd,0,0, // loop2: LDA $nnnn,x
   0xdd,0,0, // CMP $nnnn,x
   0xd0,0x09, // BNE fail
   0xe8,      // INX
   0xd0,0xf5, // BNE loop2
   0xa9,0x00, // lda #$00
   0x8d,0x7f,0x03, // sta $037f
   0x60,          // rts
   0xa9,0xff, // fail: lda #$ff
   0x8d,0x7f,0x03, // sta $037f
   0x60          // rts
};

unsigned char joy_x=100;
unsigned char joy_y=100;

unsigned int page_size=0;
unsigned char latency_code=0xff;
unsigned char reg_cr1=0x00;
unsigned char reg_sr1=0x00;

unsigned char manufacturer;
unsigned short device_id;
unsigned short cfi_data[512];
unsigned short cfi_length=0;

unsigned char reconfig_disabled=0;

unsigned char data_buffer[512];
// Magic string for identifying properly loaded bitstream
unsigned char bitstream_magic[16]=
  // "MEGA65BITSTREAM0";
  { 0x4d, 0x45, 0x47, 0x41, 0x36, 0x35, 0x42, 0x49, 0x54, 0x53, 0x54, 0x52, 0x45, 0x41, 0x4d, 0x30};

unsigned short mb = 0;

unsigned char buffer[512];

short i,x,y,z;
short a1,a2,a3;
unsigned char n=0;

#define CASE_INSENSITIVE  0
#define CASE_SENSITIVE    1

void progress_bar(unsigned char onesixtieths);
void read_data(unsigned long start_address);
void program_page(unsigned long start_address,unsigned int page_size);
void erase_sector(unsigned long address_in_sector);

unsigned long seconds_between(struct m65_tm *a,struct m65_tm *b)
{
  unsigned long d=0;
  if (b->tm_hour>a->tm_hour) d+=3600L*(b->tm_hour-a->tm_hour);
  d+=60L*((signed char)b->tm_min-(signed char)a->tm_min);
  d+=((signed char)b->tm_sec-(signed char)a->tm_sec);
  return d;
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

const unsigned long sd_timeout_value=100000;

unsigned long sdcard_timeout;
unsigned char sdbus=0;

unsigned long fat32_partition_start=0;
unsigned long fat32_partition_end=0;
unsigned char fat32_sectors_per_cluster=0;
unsigned long fat32_reserved_sectors=0;
unsigned long fat32_data_sectors=0;
unsigned long fat32_sectors_per_fat=0;
unsigned long fat32_cluster2_sector=0;

void sdcard_reset(void)
{
  // Reset and release reset

  // Check for external SD card, then internal SD card.

  // Select external SD card slot
  POKE(sd_ctl,0xc1);

  // Clear SDHC flag
  POKE(sd_ctl,0x40);

  POKE(sd_ctl,0);
  POKE(sd_ctl,1);

  sdcard_timeout = sd_timeout_value;

  // Now wait for SD card reset to complete
  while (PEEK(sd_ctl)&3) {
    POKE(0xd020,(PEEK(0xd020)+1)&15);
    sdcard_timeout--;
    if (!sdcard_timeout) {
      if (sdbus==0) {
        POKE(sd_ctl,0xc0);
        POKE(sd_ctl,0);
        POKE(sd_ctl,1);
        sdcard_timeout=sd_timeout_value;
        sdbus=1;
      }
    }
  }

  if (!sdcard_timeout) {
    printf("Could not reset SD card\n");
    while(1) continue;
  }

  // Reassert SDHC flag
  POKE(sd_ctl,0x41);
}

void sdcard_readsector(const uint32_t sector_number)
{
  char tries=0;

  uint32_t sector_address=sector_number*512;
  sector_address=sector_number;


  POKE(sd_addr+0,(sector_address>>0)&0xff);
  POKE(sd_addr+1,(sector_address>>8)&0xff);
  POKE(sd_addr+2,((uint32_t)sector_address>>16)&0xff);
  POKE(sd_addr+3,((uint32_t)sector_address>>24)&0xff);

  //  write_line("Reading sector @ $",0);
  //  screen_hex(screen_line_address-80+18,sector_address);

  while(tries<10) {

    // Wait for SD card to be ready
    sdcard_timeout=50000U;
    while (PEEK(sd_ctl)&0x3)
    {
      sdcard_timeout--; if (!sdcard_timeout) return;
      if (PEEK(sd_ctl)&0x40)
      {
        return;
      }
      // Sometimes we see this result, i.e., sdcard.vhdl thinks it is done,
      // but sdcardio.vhdl thinks not. This means a read error
      if (PEEK(sd_ctl)==0x01) return;
    }

    // Command read
    POKE(sd_ctl,2);

    // Wait for read to complete
    sdcard_timeout=50000U;
    while (PEEK(sd_ctl)&0x3) {
      sdcard_timeout--; if (!sdcard_timeout) return;
      //      write_line("Waiting for read to complete",0);
      if (PEEK(sd_ctl)&0x40)
      {
        return;
      }
      // Sometimes we see this result, i.e., sdcard.vhdl thinks it is done,
      // but sdcardio.vhdl thinks not. This means a read error
      if (PEEK(sd_ctl)==0x01) return;
    }

    // Note result
    // result=PEEK(sd_ctl);

    if (!(PEEK(sd_ctl)&0x67)) {
      // Copy data from hardware sector buffer via DMA
      lcopy(sd_sectorbuffer,(long)buffer,512);

      return;
    }

    POKE(0xd020,(PEEK(0xd020)+1)&0xf);

    // Reset SD card
    sdcard_reset();

    tries++;
  }

}

unsigned char sdcard_setup=0;


void scan_partition_entry(const char i)
{
  char j;

  int offset=0x1be + (i<<4);

  char id=buffer[offset+4];
  uint32_t lba_start,lba_end;

  for(j=0;j<4;j++) ((char *)&lba_start)[j]=buffer[offset+8+j];
  for(j=0;j<4;j++) ((char *)&lba_end)[j]=buffer[offset+12+j];

  if (id==0x0c) {
    // Found FAT partition
    fat32_partition_start=lba_start;
    fat32_partition_end=lba_end;
#if 0
    printf("Partition type $%02x spans sectors $%lx -- $%lx\n",
        id,fat32_partition_start,fat32_partition_end);
#endif
  }

}


void setup_sdcard(void)
{
  unsigned char j;

  sdcard_reset();

  // Get MBR to find FAT32 partition
  sdcard_readsector(0);

  if ((buffer[0x1fe]!=0x55)||(buffer[0x1ff]!=0xAA)) {
    printf("Current partition table is invalid.\n");
    while(1) continue;
  } else {  
    for(i=0;i<4;i++) {
      scan_partition_entry(i);
    }
  }
  if (!fat32_partition_start) {
    printf("Could not find a valid FAT partition\n");
    while(1) continue;
  }

  // Ok, we have the partition, now work out where the FAT is etc
  sdcard_readsector(fat32_partition_start);

#if 0
  for(j=0;j<64;j++) {
    if (!(j&7)) printf("\n %02x :",j);
    printf(" %02x",buffer[j]);
  }
  printf("\n");
#endif

  fat32_sectors_per_cluster=buffer[0x0d];
  for(j=0;j<2;j++) ((char *)&fat32_reserved_sectors)[j]=buffer[0x0e+j];
  for(j=0;j<4;j++) ((char *)&fat32_data_sectors)[j]=buffer[0x20+j];
  for(j=0;j<4;j++) ((char *)&fat32_sectors_per_fat)[j]=buffer[0x24+j];

  fat32_cluster2_sector
    = fat32_partition_start
    + fat32_reserved_sectors
    + fat32_sectors_per_fat
    + fat32_sectors_per_fat;

#if 0
  printf("%ld sectors per fat, %ld reserved sectors, %d sectors per cluster.\n",
      fat32_sectors_per_fat,fat32_reserved_sectors,fat32_sectors_per_cluster);
  printf("Cluster 2 begins at sector $%08lx\n",fat32_cluster2_sector);
#endif  

  sdcard_setup=1;

}

unsigned long fat32_nextclusterinchain(unsigned long cluster)
{
  unsigned short offset_in_sector=(cluster&0x7f)<<2;
  unsigned long fat_sector
    = fat32_partition_start + fat32_reserved_sectors;
  fat_sector+=(cluster>>7);

  sdcard_readsector(fat_sector);
  return *(unsigned long*)(&buffer[offset_in_sector]);

}

void hy_close(void)
{
}

unsigned long hy_opendir_cluster=0;
unsigned long hy_opendir_sector=0;
unsigned char hy_opendir_sector_in_cluster=0;
unsigned int hy_opendir_offset_in_sector=0;

void hy_opendir(void)
{
  if (!sdcard_setup) setup_sdcard();

  hy_opendir_cluster=2;
  hy_opendir_sector=fat32_cluster2_sector;
  hy_opendir_sector_in_cluster=0;
  hy_opendir_offset_in_sector=0;
}

struct m65_dirent hy_dirent;

struct m65_dirent *hy_readdir(void)
{
  unsigned char *dirent;
  unsigned char j;
  unsigned char found=0;

  while(!found) {
    // Chain through directory as required
    if (hy_opendir_offset_in_sector==512) {
      hy_opendir_offset_in_sector=0;
      hy_opendir_sector_in_cluster++;
      hy_opendir_sector++;
    }
    if (hy_opendir_sector_in_cluster>=fat32_sectors_per_cluster) {
      hy_opendir_sector_in_cluster=0;
      hy_opendir_cluster=fat32_nextclusterinchain(hy_opendir_cluster);
      if (hy_opendir_cluster>=0x0ffffff0) return NULL;
      hy_opendir_sector=(hy_opendir_cluster-2)*fat32_sectors_per_cluster+fat32_cluster2_sector;
    }
    if (!hy_opendir_cluster) return NULL;

    sdcard_readsector(hy_opendir_sector);

    // Get DOS directory entry and populate
    dirent = &buffer[hy_opendir_offset_in_sector];
    ((unsigned char *)&hy_dirent.d_ino)[0]=dirent[0x1a];
    ((unsigned char *)&hy_dirent.d_ino)[1]=dirent[0x1b];
    ((unsigned char *)&hy_dirent.d_ino)[2]=dirent[0x14];
    ((unsigned char *)&hy_dirent.d_ino)[3]=dirent[0x15];
    for(j=0;j<8;j++) hy_dirent.d_name[j]=dirent[0+j];
    hy_dirent.d_name[8]='.';
    for(j=0;j<8;j++) hy_dirent.d_name[9+j]=dirent[8+j];
    hy_dirent.d_name[12]=0;

    if (hy_dirent.d_name[0]&&hy_dirent.d_name[0]!=0xe5) found=1;

    hy_opendir_offset_in_sector+=0x20;
  }

  if (found)
    return &hy_dirent;
  else
    return NULL;
}

void hy_closedir(void)
{
}

unsigned long file_cluster=0;
unsigned long file_sector=0;
unsigned char file_sector_in_cluster=0;

unsigned char hy_open(char *filename)
{
  struct m65_dirent *de;
  if (!sdcard_setup) setup_sdcard();
  hy_opendir();
  while(de=hy_readdir()) {
    if (!strcmp(de->d_name,filename)) {
      //      printf("Found file '%s' at cluster $%08lx\n",
      //	     filename,de->d_ino);
      file_cluster=de->d_ino;
      file_sector_in_cluster=0;
      file_sector=(file_cluster-2)*fat32_sectors_per_cluster+fat32_cluster2_sector;
      return 0;
    }
  }
  return 0xff;
}

unsigned short hy_read512(void)
{
  unsigned long the_sector=file_sector;
  if (!sdcard_setup) setup_sdcard();

  if (!file_cluster) return 0;

  file_sector_in_cluster++;
  file_sector++;
  if (file_sector_in_cluster>=fat32_sectors_per_cluster) {
    file_sector_in_cluster=0;
    file_cluster=fat32_nextclusterinchain(file_cluster);
    if (file_cluster>=0x0ffffff0||(!file_cluster)) {
      file_cluster=0; 
    }
    file_sector=(file_cluster-2)*fat32_sectors_per_cluster+fat32_cluster2_sector;    
  }

  sdcard_readsector(the_sector);

  return 512;
}

void hy_closeall(void)
{
}



void reconfig_fpga(unsigned long addr)
{

  if (reconfig_disabled) {
    printf("%cERROR: Remember that warning about\n"
        "having started from JTAG?\n"
        "I really did mean it, when I said that\n"
        "it would stop you being able to launch\n"
        "another core.\n",0x93);
    printf("\nPress any key to return to the menu...\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    while(!PEEK(0xD610)) continue;
    while(PEEK(0xD610)) POKE(0xD610,0);
    printf("%c",0x93);
    return;
  }

  // Black screen when reconfiguring
  POKE(0xd020,0); 
  POKE(0xd011,0);

  mega65_io_enable();

  // Addresses for WBSTAR are shifted by 8 bits
  POKE(0xD6C8U,(addr>>8)&0xff);
  POKE(0xD6C9U,(addr>>16)&0xff);
  POKE(0xD6CAU,(addr>>24)&0xff);
  POKE(0xD6CBU,0x00);

  // Wait a little while, to make sure that the WBSTAR slot in
  // the reconfig sequence gets set before we instruct the FPGA
  // to reconfigure.
  usleep(255);

  // Try to reconfigure
  POKE(0xD6CFU,0x42);
  while(1) {
    POKE(0xD020,PEEK(0xD012));
    POKE(0xD6CFU,0x42);

    // Grey screen if reconfig failing
    POKE(0xd020,0x0d);     
  }
}

unsigned long addr;
unsigned char progress=0;
unsigned long progress_acc=0;
unsigned long offset=0;
unsigned char tries = 0;

void press_any_key(void)
{
  printf("\nPress any key to continue.\n");
  while(PEEK(0xD610)) POKE(0xD610,0);
  while(!PEEK(0xD610)) continue;
  while(PEEK(0xD610)) POKE(0xD610,0);
}

typedef struct
{
  int model_id;
  char* name;
} models_type;

models_type models[] = {
    { 0x01, "MEGA65 R1"},
    { 0x02, "MEGA65 R2"},
    { 0x03, "MEGA65 R3"},
    { 0x21, "MEGAphone R1"},
    { 0x40, "Nexys4 PSRAM"},
    { 0x41, "Nexys4DDR"},
    { 0x42, "Nexys4DDR with widget board"},
    { 0xFD, "QMTECH Wukong A100T board"},
    { 0xFE, "Simulation"}
};

char* get_model_name(uint8_t model_id)
{
  static char* model_unknown = "?unknown?";
  uint8_t k;
  uint8_t l = sizeof(models) / sizeof(models_type);

  for (k = 0; k < l; k++)
  {
    if (model_id == models[k].model_id) {
      return models[k].name;
    }
  }

  return model_unknown;
}

int check_model_id_field(void)
{
  unsigned short bytes_returned;
  uint8_t hardware_model_id = PEEK(0xD629);
  uint8_t core_model_id;

  bytes_returned=hy_read512();

  if (!bytes_returned)
  {
    printf("Failed to read .cor file.\n");
    press_any_key();
    return 0;
  }

  core_model_id = buffer[0x70];

  printf(".COR file model id: $%02X - %s\n", core_model_id, get_model_name(core_model_id));
  printf(" Hardware model id: $%02X - %s\n\n", hardware_model_id, get_model_name(hardware_model_id));

  if (hardware_model_id == core_model_id)
  {
    printf("%cVerified .COR file matches hardware.\n"
           "Safe to flash.%c\n", 0x1e, 0x05);
    press_any_key();
    return 1;
  }

  if (core_model_id == 0x00) {
    printf("\x1c.COR file is missing model-id field.\n"
           "Cannot confirm if .COR matches hardware.\n"
           "%cAre you sure you want to flash? (y/n)\n\n", 0x05);
    if (!check_input("y", CASE_INSENSITIVE)) return 0;

    printf("Ok, will proceed to flash\n");
    press_any_key();
    return 1;
  }

  printf("%cVerification error!\n"
        "This .COR file is not intended for this hardware.%c\n",0x1c, 0x05);
  press_any_key();
  return 0;
}

unsigned char j,k;
unsigned short erase_time=0, flash_time=0,verify_time=0;
void reflash_slot(unsigned char slot)
{
  unsigned long d,d_last;
  unsigned short bytes_returned;
  unsigned char fd;
  unsigned char *file=select_bitstream_file();
  if (!file) return;
  if ((unsigned short)file==0xffff) return;

  printf("%cPreparing to reflash slot %d...\n\n",0x93, slot);

  hy_closeall();

  getrtc(&tm_start);
  
  // magic filename for erasing a slot begins with "-" 
  if (file[0]!='-') {

    fd=hy_open(file);
    if (fd==0xff) {
      // Couldn't open the file.
      printf("ERROR: Could not open flash file '%s'\n",file);

      press_any_key();

      while(1) continue;

      return;
    }

    if (!check_model_id_field())
      return;
  }

  // start reading file from beginning again
  // (as the model_id checking read the first 512 bytes already)
  fd=hy_open(file);

  printf("%cErasing flash slot...\n",0x93);
  lfill((unsigned long)buffer,0,512);

  getrtc(&tm_start);
  
  // Do a smart erase: read blocks, and only erase pages if they are
  // not all $FF.  Later we can make it even smarter, and only clear
  // pages where bits need clearing.
  // Also, we will assume the BIT files contain the 4KB header we want
  // so we will just write upto 4MB of stuff in one go.
  progress=0; progress_acc=0;
  offset=0;
  
  for(addr=(SLOT_SIZE)*slot;addr<(SLOT_SIZE)*(slot+1);addr+=512) {
    progress_acc+=512;
    offset+=512;
#ifdef A100T
    if (progress_acc>26214) {
      progress_acc-=26214;
      progress++;
      progress_bar(progress);
    }
#else
    if (progress_acc>52428UL) {
      progress_acc-=52428UL;
      progress++;
      progress_bar(progress);
    }
#endif     

    // dummy read to flush buffer in flash
    read_data(addr);

    // Show on screen
    lcopy(data_buffer,0x0400+10*40,512);
    
#ifdef HARDWARE_SPI
    // Use hardware accelerated byte comparison when reading QSPI flash
    // to speed up detecting which sectors need erasing
    if (PEEK(0xD689)&0x40) i=0; else i=512;
#else
    i=0;
    for(i=0;i<512;i++) if (data_buffer[i]!=0xff) break;
    tries++;
#endif
    if (!(addr&0xffff)) {
      getrtc(&tm_now);
      d=seconds_between(&tm_start,&tm_now);
      if (d!=d_last) {
	unsigned int speed=(unsigned int)((offset/d)>>10);
	// This division is _really_ slow, which is why we do it only
	// once per second.
        unsigned long eta=((SLOT_SIZE-offset)/speed)>>10;
	d_last=d;
	printf("%c%c%c%c%c%c%c%c%c%cErasing %dKB/sec, done in %ld sec.          \n",
	       0x13,0x11,0x11,0x11,0x11,0x11,0x11,0x11,0x11,0x11,speed,
	       eta
	       );
      }
    }
    
    if (i==512) continue;

    while (i<512) {
      POKE(0xD020,2);
      erase_sector(addr);
      POKE(0xD020,0);
      // Then verify that the sector has been erased
      read_data(addr);
      // XXX Show the read sector on the screen
      lcopy(data_buffer,0x0400+10*40,512);
#ifdef HARDWARE_SPI
      if (PEEK(0xD689)&0x40) i=0; else i=512;
#else
      for(i=0;i<512;i++) if (data_buffer[i]!=0xff) break;
#endif
      if (i<512) {

        tries++;
        if (tries==128) {
          printf("\n! Failed to erase flash page at $%llx\n",addr);
          printf("  byte $%x = $%x instead of $FF\n",i,data_buffer[i]);
          printf("Please reset and try again.\n");
          while(1) continue;
        }
      }
    }

    // Step ahead to the next 4KB boundary, as flash sectors can't be smaller than
    // that.
    //    progress_acc+=0xe00-(addr&0xfff);
    addr+=0x1000; addr&=0xfffff000;
    addr-=512; // since we add this much in the for() loop

  }

  erase_time=seconds_between(&tm_start,&tm_now);

  
  flash_reset();

  // magic filename for erasing a slot begins with "-" 
  if (file[0]!='-') {

    getrtc(&tm_start);
    
    // Read the flash file and write it to the flash
    printf("%cWriting bitstream to flash...\n\n",0x93);
    progress=0; progress_acc=0;
    offset=0;
    for(addr=(SLOT_SIZE)*slot;addr<(SLOT_SIZE)*(slot+1);addr+=512) {
      offset+=512;
      progress_acc+=512;
#ifdef A100T      
      if (progress_acc>26214) {
        progress_acc-=26214;
        progress++;
      }
#else
      if (progress_acc>52428UL) {
        progress_acc-=52428UL;
        progress++;
      }
#endif     
      // Don't do progress bar too often, as it slows things down
      if (!(k&0xf)) progress_bar(progress);
      k++;

      if (!(addr&0xffff)) {
	getrtc(&tm_now);
	d=seconds_between(&tm_start,&tm_now);
	if (d!=d_last) {
	  unsigned int speed=(unsigned int)((offset/d)>>10);
	  // This division is _really_ slow, which is why we do it only
	  // once per second.
	  unsigned long eta=((SLOT_SIZE-offset)/speed)>>10;
	  d_last=d;
	  printf("%c%c%c%c%c%c%c%c%c%cWriting %dKB/sec, done in %ld sec.          \n",
		 0x13,0x11,0x11,0x11,0x11,0x11,0x11,0x11,0x11,0x11,speed,
		 eta
		 );
	}
      }
      
      
      bytes_returned=hy_read512();

      if (!bytes_returned) break;

      // XXX For 64MB flash chips, it is possible to write 512 bytes at once,
      // but 256 at a time will work fine, too.

      lcopy(buffer,0x0400+10*40,512);
      
      if (page_size==256) {
	// Programming works on 256 byte pages, so we have to write two of them.
	lcopy((unsigned long)&buffer[0],(unsigned long)data_buffer,256);
	POKE(0xD020,1);
	program_page(addr,256);
	POKE(0xD020,0);
	
	// Programming works on 256 byte pages, so we have to write two of them.
	lcopy((unsigned long)&buffer[256],(unsigned long)data_buffer,256);
	POKE(0xD020,1);
	program_page(addr+256,256);       
	POKE(0xD020,0);
      } else if (page_size==512) {
	// Programming works on 512 byte pages
	lcopy((unsigned long)&buffer[0],(unsigned long)data_buffer,512);
	POKE(0xD020,1);
	program_page(addr,512);
	POKE(0xD020,0);
      }
    }

    getrtc(&tm_now);
    flash_time=seconds_between(&tm_start,&tm_now);
    getrtc(&tm_start);
    
    /*
      Now read through the file again to verify that we wrote the correct data.
      But before we start, we reset the flash, so that it doesn't read incorrect
      data.
     */

    printf("%cVerifying that bitstream was correctly written to flash...\n",0x93);
    progress=0; progress_acc=0;

    // Setup fast comparison routine
    lcopy(compare_routine,0x380,64);    
    *(unsigned short *)0x383 = data_buffer;
    *(unsigned short *)0x386 = buffer;
    *(unsigned short *)0x38e = data_buffer;
    *(unsigned short *)0x391 = buffer;
    
    flash_reset();

    hy_closeall();
    fd=hy_open(file);
    if (fd==0xff) {
      // Couldn't open the file.
      printf("ERROR: Could not open flash file '%s'\n",file);
      press_any_key();

      while(1) continue;

      return;
    }

    offset=0;
    
    for(addr=(SLOT_SIZE)*slot;addr<(SLOT_SIZE)*(slot+1);addr+=512) {
      progress_acc+=512;
      offset+=512;
#ifdef A100T      
      if (progress_acc>26214) {
        progress_acc-=26214;
        progress++;
      }
#else
      if (progress_acc>52428UL) {
        progress_acc-=52428UL;
        progress++;
      }
#endif

      // Don't do progress bar too often, as it slows things down
      if (!(k&0xff)) progress_bar(progress);
      k++;

      if (!(addr&0xffff)) {
	getrtc(&tm_now);
	d=seconds_between(&tm_start,&tm_now);
	if (d!=d_last) {
	  unsigned int speed=(unsigned int)((offset/d)>>10);
	  // This division is _really_ slow, which is why we do it only
	  // once per second.
	  unsigned long eta=((SLOT_SIZE-offset)/speed)>>10;
	  d_last=d;
	  printf("%c%c%c%c%c%c%c%c%c%cVerifying %dKB/sec, done in %ld sec.          \n",
		 0x13,0x11,0x11,0x11,0x11,0x11,0x11,0x11,0x11,0x11,speed,
		 eta
		 );
	}
      }
      
      // Clear buffers for fast compare
      lfill(data_buffer,0,512);
      lfill(buffer,0,512);
      
      bytes_returned=hy_read512();

      if (!bytes_returned) break;

      read_data(addr);
      lcopy(data_buffer,0x0400+10*40,512);

      // Do fast comparison of data_buffer and buffer
      __asm__ ("jsr $0380");
      if (PEEK(0x037f)) {

        printf("Verification error at address $%llx:\n",
            addr+256+i);
        printf("Read back $%x instead of $%x\n",
            data_buffer[i+256],buffer[i]);
        press_any_key();
        printf("Data read from flash is:\n");
        for(i=0;i<256;i+=64) {
          for(x=0;x<64;x++) {
            if (!(x&7)) printf("%04x : ",i+x);
            printf(" %02x",data_buffer[i+x]);
            if ((x&7)==7) printf("\n");
          }

	  press_any_key();
        }

        printf("(b) Correct data is:\n");

        printf("Correct data is:\n");
        for(i=0;i<256;i+=64) {
          for(x=0;x<64;x++) {
            if (!(x&7)) printf("%04x : ",i+x);
            printf(" %02x",buffer[i+x]);
            if ((x&7)==7) printf("\n");
          }

          press_any_key();
        }
        fetch_rdid();
        i=0;
        break;
      }

      for(i=0;i<256;i++) if (data_buffer[256+i]!=buffer[256+i]) break;
      if (i<256&&(i<(bytes_returned-256))) {
        printf("Verification error at address $%llx:\n",
            addr+256+i);
        printf("Read back $%x instead of $%x\n",
            data_buffer[i+256],buffer[i]+256);
        press_any_key();
        printf("Data read from flash is:\n");
        for(i=0;i<256;i+=64) {
          for(x=0;x<64;x++) {
            if (!(x&7)) printf("%04x : ",i+x);
            printf(" %02x",data_buffer[256+i+x]);
            if ((x&7)==7) printf("\n");
          }

          press_any_key();
        }

        printf("Correct data is:\n");
        for(i=0;i<256;i+=64) {
          for(x=0;x<64;x++) {
            if (!(x&7)) printf("%04x : ",i+x);
            printf(" %02x",buffer[256+i+x]);
            if ((x&7)==7) printf("\n");
          }

          press_any_key();
        }
        fetch_rdid();
        i=0;
      }
    }
  }
  getrtc(&tm_now);
  verify_time=seconds_between(&tm_start,&tm_now);

  // Undraw the sector display before showing results
  lfill(0x0400+10*40,0x20,512);
  
  printf("%c%c%c%c%c"
	 "Flash slot successfully written.\n"
	 "   Erase: %d sec\n"
	 "   Flash: %d sec\n"
	 "  Verify: %d sec\n"
	 "\n"
	 "Press any key to return to menu.\n",
	 0x11,0x11,0x11,0x11,0x11,
	 erase_time,flash_time,verify_time);
  press_any_key();

  hy_close(); // there was once an intent to pass (fd), but it wasn't getting used

  return;
}


int bash_bits=0xFF;

unsigned int di;
void delay(void)
{
  // Slow down signalling when debugging using JTAG monitoring.
  // Not needed for normal operation.

  //   for(di=0;di<1000;di++) continue;
}

void spi_tristate_si(void)
{
  bash_bits|=0x02;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_tristate_si_and_so(void)
{
  bash_bits|=0x03;
  bash_bits&=0x6f;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}

unsigned char spi_sample_si(void)
{
  // Make SI pin input
  bash_bits&=0x7F;
  bash_bits|=0x02;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);

  // Not sure why we need this here, but we do, else it only ever returns 1.
  // (but the delay can be made quite short)
  delay();

  if (PEEK(BITBASH_PORT)&0x02) return 1; else return 0;
}

void spi_so_set(unsigned char b)
{
  // De-tri-state SO data line, and set value
  bash_bits&=(0xff-0x01);
  bash_bits|=(0x1F-0x01);
  if (b) bash_bits|=0x01;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void qspi_nybl_set(unsigned char nybl)
{
  // De-tri-state SO data line, and set value
  bash_bits&=(0xff-0x0f);
  bash_bits&=(0xff-0x10);
  bash_bits|=nybl & 0xf;
  bash_bits|=0x80;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
  printf("$%02x ",bash_bits);
}


void spi_clock_low(void)
{
  bash_bits&=(0xff-0x20);
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_clock_high(void)
{
  bash_bits|=0x20;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_idle_clocks(unsigned int count)
{
  while (count--) {
    spi_clock_low();
    delay();
    spi_clock_high();
    delay();
  }
}

void spi_cs_low(void)
{
  bash_bits&=0xff-0x40;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}

void spi_cs_high(void)
{
  bash_bits|=0x40;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
}


void spi_tx_bit(unsigned char bit)
{
  spi_clock_low();
  spi_so_set(bit);
  delay();
  spi_clock_high();
  delay();
}

void qspi_tx_nybl(unsigned char nybl)
{
  spi_clock_low();
  qspi_nybl_set(nybl);
  delay();
  spi_clock_high();
  delay();
}

void spi_tx_byte(unsigned char b)
{
  unsigned char i;

  bash_bits|=(0x1F-0x01);
  
  for(i=0;i<8;i++) {

    //    spi_tx_bit(b&0x80);
    
    // spi_clock_low();
    bash_bits&=(0xff-0x20);
    POKE(BITBASH_PORT,bash_bits);
    
    // spi_so_set(b&80);
    bash_bits&=(0xff-0x01);
    if (b&0x80) bash_bits|=0x01;
    POKE(BITBASH_PORT,bash_bits);
    
    // spi_clock_high();
    bash_bits|=0x20;
    POKE(BITBASH_PORT,bash_bits);

    b=b<<1;
  }
}

void qspi_tx_byte(unsigned char b)
{
  qspi_tx_nybl((b&0xf0)>>4);
  qspi_tx_nybl(b&0xf);
}

unsigned char qspi_rx_byte()
{
  unsigned char b=0;
  unsigned char i;

  b=0;

  spi_tristate_si_and_so();
  for(i=0;i<2;i++) {
    spi_clock_low();
    b=b<<4;
    delay();
    b|=PEEK(BITBASH_PORT)&0x0f;
    spi_clock_high();
    delay();
  }

  return b;
}

unsigned char spi_rx_byte()
{
  unsigned char b=0;
  unsigned char i;

  b=0;

  spi_tristate_si();
  for(i=0;i<8;i++) {
    spi_clock_low();
    b=b<<1;
    delay();
    if (spi_sample_si()) b|=0x01;
    spi_clock_high();
    delay();
  }

  return b;
}

void flash_reset(void)
{
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x60);
  spi_cs_high();
  usleep(32000);
  usleep(32000);
  usleep(32000);
  usleep(32000);
  usleep(32000);
  usleep(32000);
}

void read_registers(void)
{

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x05);
  reg_sr1=spi_rx_byte();
  spi_cs_high();
  delay();

  // Config Register 1 (CR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x35);
  reg_cr1=spi_rx_byte();
  spi_cs_high();
  delay();  
}

void spi_write_enable(void)
{
  while(!(reg_sr1&0x02)) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x06);
    spi_cs_high();

    read_registers();
  }
}

void erase_sector(unsigned long address_in_sector)
{

  // XXX Send Write Enable command (0x06 ?)
  //  printf("activating write enable...\n");
  spi_write_enable();

  // XXX Clear status register (0x30)
  //  printf("clearing status register...\n");
  while(reg_sr1&0x61) {
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
  //  printf("erasing sector...\n");
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0xdc);
  spi_tx_byte(address_in_sector>>24);
  spi_tx_byte(address_in_sector>>16);
  spi_tx_byte(address_in_sector>>8);
  spi_tx_byte(address_in_sector>>0);
  spi_cs_high();

  while(reg_sr1&0x03) {
    read_registers();
  }

  if (reg_sr1&0x20) printf("error erasing sector @ $%08x\n",address_in_sector);
  else {
    printf("sector at $%08llx erased.\n%c",address_in_sector,0x91);
  }

}

unsigned char first,last;

void program_page(unsigned long start_address,unsigned int page_size)
{
  // XXX Send Write Enable command (0x06 ?)

  first=0;
  last=0xff;

  while(reg_sr1&0x03) {
    //    printf("flash busy. ");
    read_registers();
  }

  // XXX Send Write Enable command (0x06 ?)
  //  printf("activating write enable...\n");
  spi_write_enable();

  // XXX Clear status register (0x30)
  //  printf("clearing status register...\n");
  while(reg_sr1&0x61) {
    spi_cs_high();
    spi_clock_high();
    delay();
    spi_cs_low();
    delay();
    spi_tx_byte(0x30);
    spi_cs_high();

    read_registers();
  }

  if (!reg_sr1&0x02) {
    printf("error: write latch cleared.\n");
  }

  // XXX Send Page Programme (0x12 for 1-bit, or 0x34 for 4-bit QSPI)
  //  printf("writing %d bytes of data...\n",page_size);

  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
#ifdef QPP_WRITE
  spi_tx_byte(0x34);
#else
  spi_tx_byte(0x12);
#endif
  spi_tx_byte(start_address>>24);
  spi_tx_byte(start_address>>16);
  spi_tx_byte(start_address>>8);
  spi_tx_byte(start_address>>0);

#ifdef QPP_WRITE
  for(i=0;i<page_size;i++) qspi_tx_byte(data_buffer[i]);
#else
  
  // XXX For some reason we get stuck bits with QSPI writing, so we aren't going to do it.
  // Flashing actually takes longer normally than the sending of the data, anyway.
  POKE(0xD020,2);
#ifdef HARDWARE_SPI_WRITE
  if (page_size==256) {
    // Write 256 bytes
    // XXX For now we use 512 byte write. According to the
    // erata for the flash that uses 256 byte pages, we can
    // do this, provided the last 256 bytes of data sent is
    // the real data.
    //    printf("256 byte program\n");
    lcopy(data_buffer,0xffd6f00L,256);
    POKE(0xD680,0x50);  
    while(PEEK(0xD680)&3) POKE(0xD020,PEEK(0xD020)+1);    
  } else if (page_size==512) {
    // Write 512 bytes
    lcopy(data_buffer,0xffd6e00L,512);
    POKE(0xD680,0x51);
    while(PEEK(0xD680)&3) POKE(0xD020,PEEK(0xD020)+1);    
  } else 
#else
    for(i=0;i<page_size;i++) spi_tx_byte(data_buffer[i]);
#endif
  POKE(0xD020,1);
#endif
  
  spi_cs_high();

  // Revert lines to input after QSPI operation
  bash_bits|=0x10;
  bash_bits&=0xff-0x80;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);

  while(reg_sr1&0x03) {
    //    printf("flash busy. ");
    read_registers();
  }

  if (reg_sr1&0x60) printf("error writing data @ $%08llx\n",start_address);
  else {
    //    printf("data at $%08llx written.\n",start_address);
  }

}

void read_data(unsigned long start_address)
{

  // Status Register 1 (SR1)
  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();
  spi_tx_byte(0x6c);
  spi_tx_byte(start_address>>24);
  spi_tx_byte(start_address>>16);
  spi_tx_byte(start_address>>8);
  spi_tx_byte(start_address>>0);

  // Table 25 latency codes
  switch(latency_code) {
  case 3:
    break;
  default:
    // 8 cycles = equivalent of 4 bytes
    for (z=0;z<4;z++) qspi_rx_byte();
    break;
  }

  // Actually read the data.
#ifdef HARDWARE_SPI
  // Use hardware-accelerated QSPI RX
  POKE(0xD020,1);
  POKE(0xD680,0x52); // Read 512 bytes from QSPI flash
  while(PEEK(0xD680)&3) POKE(0xD020,PEEK(0xD020)+1);
  lcopy(0xFFD6E00L,data_buffer,512);

  POKE(0xD020,0);
#else
  for(z=0;z<512;z++) {
    POKE(0xD020,1);
#if 1
    // Inlined RX for a bit extra speed
    spi_tristate_si_and_so();

    spi_clock_low();
    b=(PEEK(BITBASH_PORT)&0x0f)<<4;
    spi_clock_high();
    
    spi_clock_low();
    data_buffer[z]=(PEEK(BITBASH_PORT)&0x0f)|b;
    spi_clock_high();
#else 
    data_buffer[z]=qspi_rx_byte();
#endif
    POKE(0xD020,0);
  }
#endif

  spi_cs_high();
  delay();

}

void fetch_rdid(void)
{
  /* Run command 0x9F and fetch CFI etc data.
     (Section 9.2.2)
   */

  unsigned short i;

  spi_cs_high();
  spi_clock_high();
  delay();
  spi_cs_low();
  delay();

  spi_tx_byte(0x9f);

  // Data format according to section 11.2

  // Start with 3 byte manufacturer + device ID
  manufacturer=spi_rx_byte();
  device_id=spi_rx_byte()<<8;
  device_id|=spi_rx_byte();

  // Now get the CFI data block
  for(i=0;i<512;i++) cfi_data[i]=0x00;  
  cfi_length=spi_rx_byte();
  if (cfi_length==0) cfi_length = 512;
  for(i=0;i<cfi_length;i++)
    cfi_data[i]=spi_rx_byte();

  spi_cs_high();
  delay();
  spi_clock_high();
  delay();

}

unsigned char slot_empty_check(unsigned short mb_num)
{
  unsigned long addr;
  for(addr=(mb_num*1048576L);addr<((mb_num*1048576L)+SLOT_SIZE);addr+=512)
  {
    read_data(addr);
    y=0xff;
    for(x=0;x<512;x++) y&=data_buffer[x];
    if (y!=0xff) return -1;

    *(unsigned long *)(0x0400)=addr;
  }
  return 0;
}

void flash_inspector(void)
{
#if 1
  addr=0;
  read_data(addr);
  printf("Flash @ $%08x:\n",addr);
  for(i=0;i<256;i++)
  {
    if (!(i&15)) printf("+%03x : ",i);
    printf("%02x",data_buffer[i]);
    if ((i&15)==15) printf("\n");
  }
  while(1)
  {
    x=0;
    while(!x) {
      x=PEEK(0xd610);
    }

    if (x) {
      POKE(0xd610,0);
      switch(x) {
      case 0x11: addr+=256; break;
      case 0x91: addr-=256; break;
      case 0x1d: addr+=0x400000; break;
      case 0x9d: addr-=0x400000; break;
      case 0x03: return;
      }

      read_data(addr);
      printf("%cFlash @ $%08lx:\n",0x93,addr);
      for(i=0;i<256;i++)
      {
        if (!(i&15)) printf("+%03x : ",i);
        printf("%02x",data_buffer[i]);
        if ((i&15)==15) printf("\n");
      }

    }
  }
#endif
}

unsigned char check_input(char *m, uint8_t case_sensitive)
{
  while(PEEK(0xD610)) POKE(0xD610,0);

  while(*m) {
    // Weird CC65 PETSCII/ASCII fix ups
    if (*m==0x0a) *m=0x0d;

    if (!PEEK(0xD610)) continue;
    if (PEEK(0xD610)!=((*m)&0x7f)) {
      if (case_sensitive)
        return 0;
      if (PEEK(0xD610) != ((*m ^ 0x20)&0x7f))
        return 0;
    }
    POKE(0xD610,0);
    m++;
  }
  return 1;
}

unsigned char user_has_been_warned(void)
{
  printf("%c"
      "Replacing the bitstream in slot 0 can\n"
      "brick your MEGA65. If you are REALLY\n"
      "SURE that you want to do this, type:\n"
      "I ACCEPT THIS VOIDS MY WARRANTY\n",
      0x93);
  if (!check_input("I ACCEPT THIS VOIDS MY WARRANTY\r", CASE_SENSITIVE)) return 0;
  printf("\nAnd now:\n"
      "ITS MY FAULT ALONE WHEN IT GOES WRONG\n");
  if (!check_input("ITS MY FAULT ALONE WHEN IT GOES WRONG\r", CASE_SENSITIVE)) return 0;
  printf("\nAlso, type in the 32768th prime:\n");
  if (!check_input("386093\r", CASE_SENSITIVE)) return 0;
  printf("\nFinally, what is the average airspeed of"
      " a laden (european) swallow?\n");
  if (!check_input("11 METRES PER SECOND\r", CASE_SENSITIVE)) return 0;
  return 1;
}

unsigned int base_addr;

unsigned long autoboot_address=0;

void main(void)
{
  unsigned char valid;
  unsigned char selected=0;
  unsigned char selected_reflash_slot;
  unsigned char slot_count=0;

  mega65_io_enable();

  // Disable OSK
  lpoke(0xFFD3615L,0x7F);  

  // Enable VIC-III attributes
  POKE(0xD031,0x20);

  // Start by resetting to CS high etc
  bash_bits=0xff;
  POKE(BITBASH_PORT,bash_bits);
  DEBUG_BITBASH(bash_bits);
  delay();
  delay();
  delay();
  delay();
  delay();

  // Put QSPI clock under bitbash control
  POKE(CLOCKCTL_PORT,0x00);  

  fetch_rdid();
  read_registers();
  if ((manufacturer==0xff) && (device_id==0xffff)) {
    printf("ERROR: Cannot communicate with QSPI            flash device.\n");
    return;
  }
#if 0
  printf("qspi flash manufacturer = $%02x\n",manufacturer);
  printf("qspi device id = $%04x\n",device_id);
  printf("rdid byte count = %d\n",cfi_length);
  printf("sector architecture is ");
  if (cfi_data[4-4]==0x00) printf("uniform 256kb sectors.\n");
  else if (cfi_data[4-4]==0x01) printf("4kb parameter sectors with 64kb sectors.\n");
  else printf("unknown ($%02x).\n",cfi_data[4-4]);
  printf("part family is %02x-%c%c\n",
      cfi_data[5-4],cfi_data[6-4],cfi_data[7-4]);
  printf("2^%d byte page, program typical time is 2^%d microseconds.\n",
      cfi_data[0x2a-4],
      cfi_data[0x20-4]);
  printf("erase typical time is 2^%d milliseconds.\n",
      cfi_data[0x21-4]);
#endif

  // Work out size of flash in MB
  {
    unsigned char n=cfi_data[0x27-4];
    mb=1;
    n-=20;
    while(n) { mb=mb<<1; n--; }
  }
  slot_count = mb/SLOT_MB;
#if 0
  printf("flash size is %dmb.\n",mb);
#endif

  latency_code=reg_cr1>>6;


  printf("%c",0x93);


  // We care about whether the IPROG bit is set.
  // If the IPROG bit is set, then we are post-config, and we
  // don't want to automatically change config. Rather, we just
  // exit to allow the Hypervisor to boot normally.  The exception
  // is if the fire button on either joystick is held, or the TAB
  // key is being pressed.  In that case, we show the menu of
  // flash slots, and allow the user to select which core to load.

  // Holding ESC on boot will prevent flash menu starting
  if (PEEK(0xD610)==0x1b) {
    // Switch back to normal speed control before exiting
    POKE(0,64);
    POKE(0xCF7f,0x4C);
    asm (" jmp $cf7f ");
  }


  //  while(PEEK(0xD610)) POKE(0xD610,0);

  //  POKE(0x0400,PEEK(0xD610));
  //  while(1) POKE(0xD020,PEEK(0xD020));

  // TAB key or NO SCROLL bucky held forces menu to appear
  if ((PEEK(0xD610)!=0x09)&&(!(PEEK(0xD611)&0x20))) {

    // Select BOOTSTS register
    POKE(0xD6C4,0x16);
    usleep(10);
    // Allow a little while for it to be fetched.
    // (about 40 cycles should be long enough)
    if (PEEK(0xD6C5)&0x01) {
      // FPGA has been reconfigured, so assume that we should boot
      // normally, unless magic keys are being pressed.
      if ((PEEK(0xD610)==0x09)||(!(PEEK(0xDC00)&0x10))||(!(PEEK(0xDC01)&0x10)))
      {
        // Magic key pressed, so proceed to flash menu after flushing keyboard input buffer
        while(PEEK(0xD610)) POKE(0xD610,0);
      }
      else {      
        // We should actually jump ($CF80) to resume hypervisor booting
        // (see src/hyppo/main.asm launch_flash_menu routine for more info)

#if 0
        printf("Continuing booting with this bitstream...\n");
        printf("Trying to return control to hypervisor...\n");

        press_any_key();
#endif

        // Switch back to normal speed control before exiting
        POKE(0,64);
        POKE(0xCF7f,0x4C);
        asm (" jmp $cf7f ");
      }
    } else {
      // FPGA has NOT been reconfigured
      // So if we have a valid upgrade bitstream in slot 1, then run it.
      // Else, just show the menu.
      // XXX - For now, we just always show the menu

      // Check valid flag and empty state of the slot before launching it.


      // Allow booting from slot 1 if dipsw4=off, or slot 2 if dipsw4=on (issue #443)
      autoboot_address=SLOT_SIZE*(1+((PEEK(0xD69D)>>3)^1));
      
      read_data(autoboot_address+0*256);
      y=0xff;
      valid=1;
      for(x=0;x<256;x++) y&=data_buffer[x];
      for(x=0;x<16;x++) if (data_buffer[x]!=bitstream_magic[x]) { valid=0; break; }
      // Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
      if (y==0xff) {
        read_data(autoboot_address+1*256);
        for(x=0;x<256;x++) y&=data_buffer[x];
      } else {
        //      for(i=0;i<255;i++) printf("%02x",data_buffer[i]);
        //      printf("\n");
        printf("(First sector not empty. Code $%02x)\n",y);
      }

      if (valid) {
        // Valid bitstream -- so start it
        reconfig_fpga(autoboot_address+4096);
      } else if (y==0xff) {
        // Empty slot -- ignore and resume
        // Switch back to normal speed control before exiting
        POKE(0,64);
        POKE(0xCF7f,0x4C);
        asm (" jmp $cf7f ");
      } else {
        printf("WARNING: Flash slot %d seems to be\n"
            "messed up (code $%02X).\n",
	       1+((PEEK(0xD69D)>>3)&1),
	       y);
        printf("To avoid seeing this message every time,either "
            "erase or re-flash the slot.\n");
        printf("\nPress almost any key to continue...\n");
        while(PEEK(0xD610)) POKE(0xD610,0);
        // Ignore TAB, since they might still be holding it
        while((!PEEK(0xD610))||(PEEK(0xD610)==0x09)) {
          if (PEEK(0xD610)==0x09) POKE(0xD610,0);
          continue;
        }
        while(PEEK(0xD610)) POKE(0xD610,0);

        printf("%c",0x93);

      }
    }
  } else {
    // We have started by holding TAB down
    // So just proceed with showing the menu
  }

  //  printf("BOOTSTS = $%02x%02x%02x%02x\n",
  //	 PEEK(0xD6C7),PEEK(0xD6C6),PEEK(0xD6C5),PEEK(0xD6C4));

  if (PEEK(0xD6C7)==0xFF) {
    // BOOTSTS not reading properly.  This usually means we have
    // started from a bitstream via JTAG, and the ECAPE2 thingy
    // isn't working. This means we can't successfully reconfigure
    // so we should probably display a warning.
    printf("WARNING: You appear to have started this"
        "bitstream via JTAG.  This means that you"
        "can't use this menu to launch other\n"
        "cores.  You will still be able to flash "
        " new bitstreams, though.\n");
    reconfig_disabled=1;
    printf("\nPress almost any key to continue...\n");
    while(PEEK(0xD610)) POKE(0xD610,0);
    // Ignore TAB, since they might still be holding it
    while((!PEEK(0xD610))||(PEEK(0xD610)==0x09)) {
      if (PEEK(0xD610)==0x09) POKE(0xD610,0);
      continue;
    }
    while(PEEK(0xD610)) POKE(0xD610,0);

    printf("%c",0x93);
  }

#if 0
  POKE(0xD6C4,0x10);  
  printf("WBSTAR = $%02x%02x%02x%02x\n",
      PEEK(0xD6C7),PEEK(0xD6C6),PEEK(0xD6C5),PEEK(0xD6C4));
#endif  

  while(1)
  {
    // home cursor
    printf("%c",0x13);

    // Draw footer line with instructions
    for(y=0;y<24;y++) printf("%c",0x11);
    printf("%c0-%u = Launch Core.  CTRL 1-%u = Edit Slo%c", 0x12, slot_count-1, slot_count-1, 0x92);
    POKE(1024+999,0x14+0x80);

    // Scan for existing bitstreams
    // (ignore golden bitstream at offset #0)
    for(i=0;i<mb;i+=SLOT_MB) {
      // Position cursor for slot
      z=i/SLOT_MB;
      printf("%c%c",0x13,0x11);
      for(y=0;y<z;y++) printf("%c%c%c",0x11,0x11,0x11);

      read_data(i*1048576+0*256);
      //       for(x=0;x<256;x++) printf("%02x ",data_buffer[x]); printf("\n");
      y=0xff;
      valid=1;
      for(x=0;x<256;x++) y&=data_buffer[x];
      for(x=0;x<16;x++) if (data_buffer[x]!=bitstream_magic[x]) { valid=0; break; }

      // Always treat golden bitstream slot as valid
      if (!i) valid=1;

      // Check 512 bytes in total, because sometimes >256 bytes of FF are at the start of a bitstream.
      read_data(i*1048576+1*256);
      for(x=0;x<256;x++) y&=data_buffer[x];

      if (!i) {
        // Assume contains golden bitstream
        printf("    (%c) MEGA65 FACTORY CORE",'0'+(i/SLOT_MB));
      }
      else if (y==0xff) printf("    (%c) EMPTY SLOT\n",'0'+(i/SLOT_MB));
      else if (!valid) {
        printf("    (%c) UNKNOWN CONTENT\n",'0'+(i/SLOT_MB));
      } else {
        // Something valid in the slot
        char core_name[32];
        char core_version[32];
        unsigned char j;
        read_data(i*1048576+0*256);
        for(j=0;j<32;j++) {
          core_name[j]=data_buffer[16+j];
          core_version[j]=data_buffer[48+j];
          // ASCII to PETSCII conversion
          if ((core_name[j]>=0x41&&core_name[j]<=0x57)
              ||(core_name[j]>=0x61&&core_name[j]<=0x77)) core_name[j]^=0x20;
        }
        core_name[31]=0;
        core_version[31]=0;

        // Display info about it
        printf("    %c(%c) %s\n",0x05,'0'+(i/SLOT_MB),core_name);
        printf("        %s\n",core_version);
      }

      // Check if entire slot is empty
      //    if (slot_empty_check(i)) printf("  slot is not completely empty.\n");

      base_addr = 0x0400 + (i/SLOT_MB)*(3*40);
      if ((i/SLOT_MB)==selected) {
        // Highlight selected item
        for(x=0;x<(3*40);x++) {
          POKE(base_addr+x,PEEK(base_addr+x)|0x80);
          POKE(base_addr+0xd400+x,valid?1:((y==0xff)?2:7));
        }
      } else {
        // Don't highlight non-selected items
        for(x=0;x<(3*40);x++) {
          POKE(base_addr+x,PEEK(base_addr+x)&0x7F);
        }
      }
    }


    x=0;
    while(!x) {
      x=PEEK(0xd610);
    }

    if (x) {
      POKE(0xd610,0);
      if (x>='0'&&x<slot_count+'0') {
        if (x=='0') {
          reconfig_fpga(0);
        }
        else reconfig_fpga((x-'0')*(SLOT_SIZE)+4096);
      }

      selected_reflash_slot=0;

      switch(x) {
      case 0x03: case 0x1b:
        // Simply exit flash menu without doing anything.

        // Switch back to normal speed control before exiting
        POKE(0,64);
        POKE(0xCF7f,0x4C);
        asm (" jmp $cf7f ");

      case 0x1d: case 0x11:
        selected++;
        if (selected>=(mb/SLOT_MB)) selected=0;
        break;
      case 0x9d: case 0x91:
        if (selected==0) selected=(mb/SLOT_MB)-1; else selected--;
        break;
      case 0x0d:
        // Launch selected bitstream
        if (!selected) {
          reconfig_fpga(0);
          printf("%c",0x93);
        }
        else reconfig_fpga(selected*(SLOT_SIZE)+4096);
        break;
#if 1
      case 0x4d: case 0x6d: // M / m
        // Flash memory monitor
        flash_inspector();
        printf("%c",0x93);
        break;
#endif
      case 0x7e: // TILDE
        if (user_has_been_warned())
          reflash_slot(0);
        printf("%c",0x93);
        break;
      case 144: case 0x42: case 0x62: // CTRL-1
        selected_reflash_slot = 1;
        break;
      case 5: case 0x43: case 0x63: // CTRL-2
        selected_reflash_slot = 2;
        break;
      case 28: case 0x44: case 0x64: // CTRL-3
        selected_reflash_slot = 3;
        break;
      case 159: // CTRL-4
        selected_reflash_slot = 4;
        break;
      case 156: // CTRL-5
        selected_reflash_slot = 5;
        break;
      case 30:  // CTRL-6
        selected_reflash_slot = 6;
        break;
      case 31:  // CTRL-7
        selected_reflash_slot = 7;
        break;
      }

      if (selected_reflash_slot>0 && selected_reflash_slot<slot_count) {
        reflash_slot(selected_reflash_slot);
        printf("%c",0x93);
      }
    }
  }

}

unsigned char progress_chars[4]={32,101,97,231};

void progress_bar(unsigned char onesixtieths)
{
#if 1
  /* Draw a progress bar several chars high */

  if (onesixtieths>3) {
    for(i=1;i<=(onesixtieths/4);i++) {
      POKE(0x0400+(4*40)-1+i,160);
      POKE(0x0400+(5*40)-1+i,160);
      POKE(0x0400+(6*40)-1+i,160);
    }    
  }
  for(;i<=39;i++) {
    POKE(0x400+(4*40)+i,0x20);
    POKE(0x400+(5*40)+i,0x20);
    POKE(0x400+(6*40)+i,0x20);
  }
  POKE(0x0400+(4*40)+(onesixtieths/4),progress_chars[onesixtieths & 3]);
  POKE(0x0400+(5*40)+(onesixtieths/4),progress_chars[onesixtieths & 3]);
  POKE(0x0400+(6*40)+(onesixtieths/4),progress_chars[onesixtieths & 3]);
#endif
  return;
}


/*
  Bitstream file chooser. Adapted from Freeze Menu disk
  image chooser.

  Disk chooser for freeze menu.

  It is displayed over the top of the normal freeze menu,
  and so we use that screen mode.

  We get our list of disknames and put them at $40000.
  As we only care about their names, and file names are
  limited to 64 characters, we can fit ~1000.
  In fact, we can only safely mount images with names <32
  characters.

  We return the disk image name or a NULL pointer if the
  selection has failed and $FFFF if the user cancels selection
  of a disk.
 */


short file_count=0;
short selection_number=0;
short display_offset=0;

char *diskchooser_instructions=
    "  SELECT FLASH FILE, THEN PRESS RETURN  "
    "       OR PRESS RUN/STOP TO ABORT       ";

unsigned char normal_row[20]={
    1,1,1,1,
    1,1,1,1,
    1,1,1,1,
    1,1,1,1,
    1,1,1,1
};

unsigned char highlight_row[20]={
    0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x21,
    0x21,0x21,0x21,0x21,0x21,0x21,0x21,0x21,
    0x21,0x21,0x21,0x21
};

char disk_name_return[32];

unsigned char joy_to_key_disk[32]={
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x0d, // With fire pressed
    0,0,0,0,0,0,0,0x9d,0,0,0,0x1d,0,0x11,0x91,0     // without fire
};

#define SCREEN_ADDRESS 0x0400
#define COLOUR_RAM_ADDRESS 0x1f800

void draw_file_list(void)
{
  unsigned addr=SCREEN_ADDRESS;
  unsigned char i,x;
  unsigned char name[64];
  // First, clear the screen
  POKE(SCREEN_ADDRESS+0,' ');
  POKE(SCREEN_ADDRESS+1,' ');
  lcopy(SCREEN_ADDRESS,SCREEN_ADDRESS+2,40*23-2);
  lpoke(COLOUR_RAM_ADDRESS+0,1);
  lpoke(COLOUR_RAM_ADDRESS+1,1);
  lcopy(COLOUR_RAM_ADDRESS,COLOUR_RAM_ADDRESS+2,40*23-2);

  // Draw instructions
  for(i=0;i<80;i++) {
    if (diskchooser_instructions[i]>='A'&&diskchooser_instructions[i]<='Z') 
      POKE(SCREEN_ADDRESS+23*40+i+0,diskchooser_instructions[i]&0x1f);
    else
      POKE(SCREEN_ADDRESS+23*40+i+0,diskchooser_instructions[i]);
  }
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(23*40)+0,20);
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(23*40)+20,20);
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(24*40)+0,20);
  lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(24*40)+20,20);


  for(i=0;i<23;i++) {
    if ((display_offset+i)<file_count) {
      // Real line
      lcopy(0x40000U+((display_offset+i)<<6),(unsigned long)name,64);

      for(x=0;x<20;x++) {
        if ((name[x]>='A'&&name[x]<='Z') ||(name[x]>='a'&&name[x]<='z'))
          POKE(addr+x,name[x]&0x1f);
        else
          POKE(addr+x,name[x]);
      }
    } else {
      // Blank dummy entry
      for(x=0;x<20;x++) POKE(addr+x,' ');
    }
    if ((display_offset+i)==selection_number) {
      // Highlight the row
      lcopy((long)highlight_row,COLOUR_RAM_ADDRESS+(i*40),20);
    } else {
      // Normal row
      lcopy((long)normal_row,COLOUR_RAM_ADDRESS+(i*40),20);
    }
    addr+=(40*1);  
  }


}

char *select_bitstream_file(void)
{
  unsigned char x;
  signed char j;
  struct m65_dirent *dirent;
  int idle_time=0;

  file_count=0;
  selection_number=0;
  display_offset=0;

  // First, clear the screen
  POKE(SCREEN_ADDRESS+0,' ');
  POKE(SCREEN_ADDRESS+1,' ');
  lcopy(SCREEN_ADDRESS,SCREEN_ADDRESS+2,40*25-2);

  // Add dummy entry for erasing the slot
  lfill(0x40000L+(file_count*64),' ',64);
  lcopy((long)"-erase slot-",0x40000L+(file_count*64),12);
  file_count++;

  // ARGH!!! We are running from in hypervisor mode, so we can't use hypervisor
  // traps to get the directory listing!
  hy_closeall();
  hy_opendir();
  printf("%cScanning directory...\n",0x93);
  dirent=hy_readdir();
  while(dirent&&((unsigned short)dirent!=0xffffU)) {
    j=strlen(dirent->d_name)-4;
    if (j>=0) {
      if ((!strncmp(&dirent->d_name[j],".COR",4))||(!strncmp(&dirent->d_name[j],".cor",4)))
      {
        // File is a core
        lfill(0x40000L+(file_count*64),' ',64);
        lcopy((long)&dirent->d_name[0],0x40000L+(file_count*64),j+4);
        file_count++;
      }
    }

    dirent=hy_readdir();
  }

  hy_closedir();

  // Okay, we have some disk images, now get the user to pick one!
  draw_file_list();
  while(1) {
    x=PEEK(0xD610U);

    if(!x) {
      // We use a simple lookup table to do this
      x=joy_to_key_disk[PEEK(0xDC00)&PEEK(0xDC01)&0x1f];
      // Then wait for joystick to release
      while((PEEK(0xDC00)&PEEK(0xDC01)&0x1f)!=0x1f) continue;
    }

    if (!x) {
      idle_time++;

      usleep(10000);
      continue;
    } else idle_time=0;

    // Clear read key
    POKE(0xD610U,0);

    switch(x) {
    case 0x03:             // RUN-STOP = make no change
      return NULL;
    case 0x0d:             // Return = select this disk.
      // Copy name out
      lcopy(0x40000L+(selection_number*64),(unsigned long)disk_name_return,32);
      // Then null terminate it
      for(x=31;x;x--)
        if (disk_name_return[x]==' ') { disk_name_return[x]=0; } else { break; }

      return disk_name_return;
      break;
    case 0x11: case 0x9d:  // Cursor down or left
      selection_number++;
      if (selection_number>=file_count) selection_number=0;
      break;
    case 0x91: case 0x1d:  // Cursor up or right
      selection_number--;
      if (selection_number<0) selection_number=file_count-1;
      break;
    }

    // Adjust display position
    if (selection_number<display_offset) display_offset=selection_number;
    if (selection_number>(display_offset+23)) display_offset=selection_number-22;
    if (display_offset>(file_count-22)) display_offset=file_count-22;
    if (display_offset<0) display_offset=0;

    draw_file_list();

  }

  return NULL;
}
