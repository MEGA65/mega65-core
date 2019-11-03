#include <stdio.h>

// #define MEGAPHONER1
#define MEGA65R2

struct entry {
  int addr;
  int reg_low;
  int reg_high;

  int reg_offset;

  char *desc;
};

struct entry e[]={

  // The IO expanders can only be read one register pair at a time,
  // so we have to schedule multiple jobs.

#ifdef MEGAPHONER1
  // First IO expander
  {0x72,0x00,0x01,0x00,"IO Expander #0 regs 0-1"},
  {0x72,0x02,0x03,0x02,"IO Expander #0 regs 2-3"},
  {0x72,0x04,0x05,0x04,"IO Expander #0 regs 4-5"},
  {0x72,0x06,0x07,0x06,"IO Expander #0 regs 6-7"},

  // Second IO expander
  {0x74,0x00,0x01,0x08,"IO Expander #1 regs 0-1"},
  {0x74,0x02,0x03,0x0a,"IO Expander #1 regs 2-3"},
  {0x74,0x04,0x05,0x0c,"IO Expander #1 regs 4-5"},
  {0x74,0x06,0x07,0x0e,"IO Expander #1 regs 6-7"},

  // Third IO expander
  {0x76,0x00,0x01,0x10,"IO Expander #2 regs 0-1"},
  {0x76,0x02,0x03,0x12,"IO Expander #2 regs 2-3"},
  {0x76,0x04,0x05,0x14,"IO Expander #2 regs 4-5"},
  {0x76,0x06,0x07,0x16,"IO Expander #2 regs 6-7"},

  // Real Time Clock
  {0xA2,0x00,0x12,0x18,"Real Time clock regs 0 -- 18"},

  // Audio amplifier
  {0x68,0x00,0x0F,0x30,"Audio amplifier regs 0 - 15"},

  // Accelerometer
  // (Reg nums here are the lower 7 bits, the upper bit indicating auto-increment of
  // register address, which we set, so that we can read all the regs in one go.)
  {0x32,0x80,0xBF,0x40,"Acclerometer regs 0 - 63"},
#endif

#ifdef MEGA65R2
  // UUID
  // XXX - We could also map some EEPROM space
  {0xA1,0xF8,0xFF,0x00,"Serial EEPROM UUID"},
  
  // Real Time Clock
  {0xDF,0x00,0x2F,0x10,"Real Time clock regs 0 -- 2F"},

  // RTC SRAM
  {0xAF,0x00,0x3F,0x40,"RTC SRAM (64 of 128 bytes)"},
#endif

  
  {-1,-1,-1,-1}
};
  
int main(int argc,char **argv)
{
  int busy_count=0;


  for(int i=0;e[i].addr>-1;i++) {
    printf("when %d =>\n"
	   "report \"%s\";\n"	   
	   "  i2c1_command_en <= '1';\n"
	   "  i2c1_address <= \"%c%c%c%c%c%c%c\"; -- 0x%02X/2 = I2C address of device;\n"
	   "  i2c1_wdata <= x\"%02X\";\n"
	   "  i2c1_rw <= '0';\n",
	   busy_count,
	   e[i].desc,
	   (e[i].addr&0x80)?'1':'0',
	   (e[i].addr&0x40)?'1':'0',
	   (e[i].addr&0x20)?'1':'0',
	   (e[i].addr&0x10)?'1':'0',
	   (e[i].addr&0x8)?'1':'0',
	   (e[i].addr&0x4)?'1':'0',
	   (e[i].addr&0x2)?'1':'0',
	   e[i].addr,
	   e[i].reg_low);
    busy_count++;
    int first=busy_count;
    printf(" when");
    for(int j=e[i].reg_low;j<=e[i].reg_high+1;j++)
      printf(" %d %s",busy_count++,
	     (j<=e[i].reg_high)?"|":"");
    printf("=>\n"
	   "  -- Read the %d bytes from the device\n"
	   "  i2c1_rw <= '1';\n"
	   "  i2c1_command_en <= '1';\n"
	   "  if busy_count > %d then\n"
	   "    bytes(busy_count - 1 - %d + %d) <= i2c1_rdata;\n"
	   "  end if;\n",
	   e[i].reg_high-e[i].reg_low+1,
	   first,
	   first,e[i].reg_offset);
  }
  
  
}
