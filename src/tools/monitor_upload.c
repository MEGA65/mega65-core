/*

  Upload one or more files to SD card on MEGA65

Copyright (C) 2018 Paul Gardner-Stephen
Portions Copyright (C) 2013 Serval Project Inc.
 
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.
 
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
 
You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/time.h>
#include <time.h>
#include <strings.h>
#include <string.h>
#include <ctype.h>
#include <sys/time.h>
#include <errno.h>
#include <getopt.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>
#include <stdio.h>
#include <readline/readline.h>
#include <readline/history.h>

#ifdef APPLE
static const int B1000000 = 1000000;
static const int B1500000 = 1500000;
static const int B2000000 = 2000000;
static const int B4000000 = 4000000;
#else
#include <sys/ioctl.h>
#include <linux/serial.h>

#endif
time_t start_time=0;
long long start_usec=0;

int upload_file(char *name,char *dest_name);
int sdhc_check(void);
int read_sector(const unsigned int sector_number,unsigned char *buffer, int noCacheP);

int osk_enable=0;

int not_already_loaded=1;

int halt=0;

// 0 = old hard coded monitor, 1= Kenneth's 65C02 based fancy monitor
int new_monitor=0;


int first_load=1;
int first_go64=1;

unsigned char viciv_regs[0x100];
int mode_report=0;

int serial_speed=2000000;
char *serial_port="/dev/ttyUSB1";
char *bitstream=NULL;

unsigned char *sd_read_buffer=NULL;
int sd_read_offset=0;

// From os.c in serval-dna
long long gettime_us()
{
  long long retVal = -1;

  do 
  {
    struct timeval nowtv;

    // If gettimeofday() fails or returns an invalid value, all else is lost!
    if (gettimeofday(&nowtv, NULL) == -1)
    {
      break;
    }

    if (nowtv.tv_sec < 0 || nowtv.tv_usec < 0 || nowtv.tv_usec >= 1000000)
    {
      break;
    }

    retVal = nowtv.tv_sec * 1000000LL + nowtv.tv_usec;
  }
  while (0);

  return retVal;
}

int sd_status_fresh=0;
unsigned char sd_status[16];

int process_char(unsigned char c,int live);


void usage(void)
{
  fprintf(stderr,"MEGA65 cross-development tool for remote access to MEGA65 SD card via serial monitor interface\n");
  fprintf(stderr,"usage: mega65_ftp [-l <serial port>] [-s <230400|2000000|4000000>]  [-b bitstream] [[-c command] ...]\n");
  fprintf(stderr,"  -l - Name of serial port to use, e.g., /dev/ttyUSB1\n");
  fprintf(stderr,"  -s - Speed of serial port in bits per second. This must match what your bitstream uses.\n");
  fprintf(stderr,"       (Older bitstream use 230400, and newer ones 2000000 or 4000000).\n");
  fprintf(stderr,"  -b - Name of bitstream file to load.\n");
  fprintf(stderr,"\n");
  exit(-3);
}

int slow_write(int fd,char *d,int l,int preWait)
{
  // UART is at 2Mbps, but we need to allow enough time for a whole line of
  // writing. 100 chars x 0.5usec = 500usec. So 1ms between chars should be ok.
  //  printf("Writing [%s]\n",d);
  int i;
  usleep(preWait);
  for(i=0;i<l;i++)
    {
      int w=write(fd,&d[i],1);
      while (w<1) {
	usleep(1000);
	w=write(fd,&d[i],1);
      }
      // Only control characters can cause us whole line delays,
      if (d[i]<' ') { usleep(2000); } else usleep(0);
    }
    tcdrain(fd);
  return 0;
}

int fd=-1;

#define READ_SECTOR_BUFFER_ADDRESS 0xFFD6e00
#define WRITE_SECTOR_BUFFER_ADDRESS 0xFFD6e00

unsigned long long gettime_ms()
{
  struct timeval nowtv;
  // If gettimeofday() fails or returns an invalid value, all else is lost!
  if (gettimeofday(&nowtv, NULL) == -1)
    perror("gettimeofday");
  return nowtv.tv_sec * 1000LL + nowtv.tv_usec / 1000;
}

int stop_cpu(void)
{
  // Stop CPU
  usleep(50000);
  slow_write(fd,"t1\r",3,2500);
  return 0;
}

int restart_hyppo(void)
{
  // Start executing in new hyppo
  if (!halt) {
    usleep(50000);
    slow_write(fd,"g8100\r",6,2500);
    usleep(10000);
    slow_write(fd,"t0\r",3,2500);
  }
  return 0;
}

void print_spaces(FILE *f,int col)
{
  for(int i=0;i<col;i++)
    fprintf(f," ");  
}

int dump_bytes(int col, char *msg,unsigned char *bytes,int length)
{
  print_spaces(stderr,col);
  fprintf(stderr,"%s:\n",msg);
  for(int i=0;i<length;i+=16) {
    print_spaces(stderr,col);
    fprintf(stderr,"%04X: ",i);
    for(int j=0;j<16;j++) if (i+j<length) fprintf(stderr," %02X",bytes[i+j]);
    fprintf(stderr,"\n");
  }
  return 0;
}

int process_line(char *line,int live)
{
  //  printf("[%s]\n",line);
  if (!live) return 0;
  if (strstr(line,"ws h RECA8LHC")) {
     if (!new_monitor) printf("Detected new-style UART monitor.\n");
     new_monitor=1;
  }

  {
    int addr;
    int b[16];
    int gotIt=0;
    unsigned int v[4];
    if (line[0]=='?') fprintf(stderr,"%s\n",line);
    if (sscanf(line,":%x:%08x%08x%08x%08x",
	       &addr,&v[0],&v[1],&v[2],&v[3])==5) {
      for(int i=0;i<16;i++) b[i]=(v[i/4]>>( (3-(i&3))*8)) &0xff;
      gotIt=1;
    }
    if (sscanf(line," :%x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
	       &addr,
	       &b[0],&b[1],&b[2],&b[3],
	       &b[4],&b[5],&b[6],&b[7],
	       &b[8],&b[9],&b[10],&b[11],
	       &b[12],&b[13],&b[14],&b[15])==17) gotIt=1;
    if (gotIt) {
      // printf("Read memory @ $%04x\n",addr);

      if (addr==0xffd3680) {
	// SD card status registers
	for(int i=0;i<16;i++) sd_status[i]=b[i];
	// dump_bytes(0,"SDcard status",sd_status,16);
	sd_status_fresh=1;
      }
      else if(addr >= READ_SECTOR_BUFFER_ADDRESS && (addr <= (READ_SECTOR_BUFFER_ADDRESS + 0x200))) {
	// Reading sector card buffer
	int sector_offset=addr-READ_SECTOR_BUFFER_ADDRESS;
	// printf("Read sector buffer 0x%03x - 0x%03x\n",sector_offset,sector_offset+15);
	if (sector_offset<512) {
	  if (sd_read_buffer) {
	    for(int i=0;i<16;i++) sd_read_buffer[sector_offset+i]=b[i];
	  }
	  sd_read_offset=sector_offset+16;
	}
      }
    }
  }

  return 0;
}


char line[1024];
int line_len=0;

int process_char(unsigned char c, int live)
{
  //printf("char $%02x\n",c);
  if (c=='\r'||c=='\n') {
    line[line_len]=0;
    if (line_len>0) process_line(line,live);
    line_len=0;
  } else {
    if (line_len<1023) line[line_len++]=c;
  }
  return 0;
}

int process_waiting(int fd)
{
  unsigned char  read_buff[1024];
  int b=read(fd,read_buff,1024);
  while (b>0) {
    int i;
    for(i=0;i<b;i++) {
      process_char(read_buff[i],1);
    }
    b=read(fd,read_buff,1024);    
  }
  return 0;
}

void set_speed(int fd,int serial_speed)
{
  struct termios t;
  if (serial_speed==230400) {
    if (cfsetospeed(&t, B230400)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B230400)) perror("Failed to set input baud rate");
  } else if (serial_speed==2000000) {
    if (cfsetospeed(&t, B2000000)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B2000000)) perror("Failed to set input baud rate");
  } else if (serial_speed==1000000) {
    if (cfsetospeed(&t, B1000000)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B1000000)) perror("Failed to set input baud rate");
  } else if (serial_speed==1500000) {
    if (cfsetospeed(&t, B1500000)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B1500000)) perror("Failed to set input baud rate");
  } else {
    if (cfsetospeed(&t, B4000000)) perror("Failed to set output baud rate");
    if (cfsetispeed(&t, B4000000)) perror("Failed to set input baud rate");
  }
  t.c_cflag &= ~PARENB;
  t.c_cflag &= ~CSTOPB;
  t.c_cflag &= ~CSIZE;
  t.c_cflag &= ~CRTSCTS;
  t.c_cflag |= CS8 | CLOCAL;
  t.c_lflag &= ~(ICANON | ISIG | IEXTEN | ECHO | ECHOE);
  t.c_iflag &= ~(BRKINT | ICRNL | IGNBRK | IGNCR | INLCR |
                 INPCK | ISTRIP | IXON | IXOFF | IXANY | PARMRK);
  t.c_oflag &= ~OPOST;
  if (tcsetattr(fd, TCSANOW, &t)) perror("Failed to set terminal parameters");

}

int queued_command_count=0;
#define MAX_QUEUED_COMMANDS 64
char *queued_commands[MAX_QUEUED_COMMANDS];

int queue_command(char *c)
{
  if (queued_command_count<MAX_QUEUED_COMMANDS)
    queued_commands[queued_command_count++]=c;
  else {
    fprintf(stderr,"ERROR: Too many commands queued via -c\n");
  }
  return 0;
}

int execute_command(char *cmd)
{
  printf("'%s'\n",cmd);
  return 0;
}

int main(int argc,char **argv)
{
  start_time=time(0);
  start_usec=gettime_us();
  
  int opt;
  while ((opt = getopt(argc, argv, "b:s:l:c:")) != -1) {
    switch (opt) {
    case 'l': strcpy(serial_port,optarg); break;
    case 's':
      serial_speed=atoi(optarg);
      switch(serial_speed) {
      case 1000000:
      case 1500000:
      case 4000000:
      case 230400: case 2000000: break;
      default: usage();
      }
      break;
    case 'b':
      bitstream=strdup(optarg); break;
    case 'c':
      queue_command(optarg); break;
    default: /* '?' */
      usage();
    }
  }  

  if (argc-optind==1) usage();
  
  // Load bitstream if file provided
  if (bitstream) {
    char cmd[1024];
    snprintf(cmd,1024,"fpgajtag -a %s",bitstream);
    fprintf(stderr,"%s\n",cmd);
    system(cmd);
    fprintf(stderr,"[T+%lldsec] Bitstream loaded\n",(long long)time(0)-start_time);
  }

#ifndef APPLE
  // Try to set USB serial port to low latency
  {
    char latency_timer[1024];
    int offset=strlen(serial_port);
    while(offset&&serial_port[offset-1]!='/') offset--;
    snprintf(latency_timer,1024,"/sys/bus/usb-serial/devices/%s/latency_timer",
	     &serial_port[offset]);
    int old_latency=999;
    FILE *f=fopen(latency_timer,"r");
    if (f) { fscanf(f,"%d",&old_latency); fclose(f); }
    if (old_latency!=1) {
      snprintf(latency_timer,1024,"echo 1 | sudo tee /sys/bus/usb-serial/devices/%s/latency_timer",
	       &serial_port[offset]);
      printf("Attempting to reduce USB latency via '%s'\n",latency_timer);
      system(latency_timer);
    }
  }

  // And also another way
  struct serial_struct serial;
  ioctl(fd, TIOCGSERIAL, &serial); 
  serial.flags |= ASYNC_LOW_LATENCY;
  ioctl(fd, TIOCSSERIAL, &serial);
#endif
  
  errno=0;
  fd=open(serial_port,O_RDWR);
  if (fd==-1) {
    fprintf(stderr,"Could not open serial port '%s'\n",serial_port);
    perror("open");
    exit(-1);
  }
  fcntl(fd,F_SETFL,fcntl(fd, F_GETFL, NULL)|O_NONBLOCK);

  // Set higher speed on serial interface to improve throughput
  set_speed(fd,2000000);
  slow_write(fd,"\r+9\r",4,5000);
  set_speed(fd,4000000);
  
  stop_cpu();

  sdhc_check();
  
  if (queued_command_count) {
    for(int i=0;i<queued_command_count;i++) execute_command(queued_commands[i]);
    return 0;
  } else {
    char *cmd=NULL;
    while((cmd=readline("MEGA65 SD-card> "))!=NULL) {
      execute_command(cmd);
    }
  }
  
  return 0;
}

void wait_for_sdready(void)
{
  do {  
  //    long long start=gettime_us();

    // Ask for SD card status
    sd_status[0]=0xff;
    while(sd_status[0]&3) {
      sd_status_fresh=0;
      slow_write(fd,"mffd3680\r",strlen("mffd3680\r"),0);
      while(!sd_status_fresh) process_waiting(fd);
      if (sd_status[0]&3) {
	// Send reset sequence
	printf("SD card not yet ready, so reset it.\n");
	slow_write(fd,"sffd3680 0\rsffd3680 1\r",strlen("sffd3680 0\rsffd3680 1\r"),2500);
	sleep(1);
      }
    }
    //     printf("SD Card looks ready.\n");
    //    printf("wait_for_sdready() took %lld usec\n",gettime_us()-start);
  } while(0);
  return;
}

int wait_for_sdready_passive(void)
{
  int retVal=0;
  do {
  //    long long start=gettime_us();
    
    // Ask for SD card status
    sd_status[0]=0xff;
    process_waiting(fd);
    while(sd_status[0]&3) {
      sd_status_fresh=0;
      slow_write(fd,"mffd3680\r",strlen("mffd3680\r"),0);
      while(!sd_status_fresh) process_waiting(fd);
      if ((sd_status[0]&3)==0x03)
	{ // printf("SD card error 0x3 - failing\n");
	  retVal=-1; break; }
    }
    // printf("SD Card looks ready.\n");
    //    printf("wait_for_sdready_passive() took %lld usec\n",gettime_us()-start);
  } while(0);
  return retVal;
}

int sdhc=-1;
int onceOnly=1;

int sdhc_check(void)
{
  unsigned char buffer[512];

  sdhc=0;

  // Force early detection of old vs new uart monitor
  if (onceOnly) slow_write(fd,"r\r",2,2500);
  onceOnly=0;
  
  int r0=read_sector(0,buffer,1);
  int r1=read_sector(1,buffer,1);
  int r200=read_sector(0x200,buffer,1);
  // printf("%d %d %d\n",r0,r1,r200);
  if (r0||r200) {
    fprintf(stderr,"Could not detect SD/SDHC card\n");
    exit(-3);
  }
  sdhc=r1;
  return sdhc;
}

#define SECTOR_CACHE_SIZE 4096
int sector_cache_count=0;
unsigned char sector_cache[SECTOR_CACHE_SIZE][512];
unsigned int sector_cache_sectors[SECTOR_CACHE_SIZE];

// XXX - DO NOT USE A BUFFER THAT IS ON THE STACK OR BAD BAD THINGS WILL HAPPEN
int read_sector(const unsigned int sector_number,unsigned char *buffer,int noCacheP)
{
  int retVal=0;
  do {

    int cachedRead=0;

    if (!noCacheP) {
      for(int i=0;i<sector_cache_count;i++) {
	if (sector_cache_sectors[i]==sector_number) {
	  bcopy(sector_cache[i],buffer,512);
	  retVal=0; cachedRead=1; break;
	}
      }
    }

    if (cachedRead) break;
    
    // Clear backlog
    // printf("Clearing serial backlog in preparation for reading sector 0x%x\n",sector_number);
    process_waiting(fd);

    // printf("Getting SD card ready\n");
    wait_for_sdready();

    // printf("Commanding SD read\n");
    char cmd[1024];
    unsigned int sector_address;
    if (!sdhc) sector_address=sector_number*0x0200; else sector_address=sector_number;
    snprintf(cmd,1024,"sffd3681 %02x %02x %02x %02x\rsffd3680 2\r",
	     (sector_address>>0)&0xff,
	     (sector_address>>8)&0xff,
	     (sector_address>>16)&0xff,
	     (sector_address>>24)&0xff);
    slow_write(fd,cmd,strlen(cmd),0);
    if (wait_for_sdready_passive()) {
      printf("wait_for_sdready_passive() failed\n");
      retVal=-1; break;
    }

    // Read succeeded, so fetch sector contents
    // printf("Reading back sector contents\n");
    sd_read_buffer=buffer;
    sd_read_offset=0;
    snprintf(cmd,1024,"M%x\r",READ_SECTOR_BUFFER_ADDRESS);
    slow_write(fd,cmd,strlen(cmd),0);
    while(sd_read_offset!=256) process_waiting(fd);

    snprintf(cmd,1024,"M%x\r",READ_SECTOR_BUFFER_ADDRESS+0x100);
    slow_write(fd,cmd,strlen(cmd),0);
    while(sd_read_offset!=512) process_waiting(fd);
    sd_read_buffer=NULL;
        // printf("Read sector %d (0x%x)\n",sector_number,sector_number);

    // Store in cache / update cache
    int i;
    for(i=0;i<sector_cache_count;i++) 
      if (sector_cache_sectors[i]==sector_number) break;
    if (i<SECTOR_CACHE_SIZE) {
      bcopy(buffer,sector_cache[i],512);
      sector_cache_sectors[i]=sector_number;
    }
    if (sector_cache_count<(i+1)) sector_cache_count=i+1;

  } while(0);
  if (retVal) printf("FAIL reading sector %d\n",sector_number);
  return retVal;
     
}

unsigned char verify[512];

int write_sector(const unsigned int sector_number,unsigned char *buffer)
{
  int retVal=0;
  do {
    int sectorUnchanged=0;
    // Force sector into read buffer
    read_sector(sector_number,verify,0);
    // See if it matches what we are writing, if so, don't write it!
    for(int i=0;i<sector_cache_count;i++) {
      if (sector_number==sector_cache_sectors[i]) {
	if (!bcmp(sector_cache[i],buffer,512)) {
	  //	  printf("Writing unchanged sector -- skipping physical write\n");
	  sectorUnchanged=1; break;
	}
      }
    }
    if (sectorUnchanged) {
      //      printf("Skipping physical write\n");
      break;
    }
    else printf("Proceeding with physical write\n");
    
    // Clear backlog
    // printf("Clearing serial backlog in preparation for reading sector 0x%x\n",sector_number);
    process_waiting(fd);

    // printf("Getting SD card ready\n");
    wait_for_sdready();

    printf("Writing sector data\n");
    char cmd[1024];
    snprintf(cmd,1024,"l%x %x\r",
	     WRITE_SECTOR_BUFFER_ADDRESS,(WRITE_SECTOR_BUFFER_ADDRESS+512)&0xffff);
    slow_write(fd,cmd,strlen(cmd),500);
    usleep(10000); // give uart monitor time to get ready for the data
    process_waiting(fd);
    int written=write(fd,buffer,512);
    if (written!=512) {
      printf("ERROR: Failed to write 512 bytes of sector data to serial port\n");
      retVal=-1;
      break;
    }
    process_waiting(fd);
    
    printf("Commanding SD write to sector %d\n",sector_number);
    unsigned int sector_address;
    if (!sdhc) sector_address=sector_number*0x0200; else sector_address=sector_number;
    snprintf(cmd,1024,"sffd3681 %02x %02x %02x %02x\rsffd3680 3\r",
	     (sector_address>>0)&0xff,
	     (sector_address>>8)&0xff,
	     (sector_address>>16)&0xff,
	     (sector_address>>24)&0xff);
    slow_write(fd,cmd,strlen(cmd),2500);
    if (wait_for_sdready_passive()) {
      printf("wait_for_sdready_passive() failed\n");
      retVal=-1; break;
    }

    if (read_sector(sector_number,verify,1)) {
      printf("ERROR: Failed to read sector to verify after writing to sector %d\n",sector_number);
      retVal=-1;
      break;
    }
    if (bcmp(verify,buffer,512)) {
      printf("ERROR: Verification error: Read back different data than we wrote to sector %d\n",sector_number);
      retVal=-1;
      break;
    }

    // Store in cache / update cache
    int i;
    for(i=0;i<sector_cache_count;i++) 
      if (sector_cache_sectors[i]==sector_number) break;
    if (i<SECTOR_CACHE_SIZE) {
      bcopy(buffer,sector_cache[i],512);
      sector_cache_sectors[i]=sector_number;
    }
    if (sector_cache_count<(i+1)) sector_cache_count=i+1;
    
  } while(0);
  if (retVal) printf("FAIL reading sector %d\n",sector_number);
  return retVal;
     
}


int file_system_found=0;
unsigned int partition_start=0;
unsigned int partition_size=0;
unsigned char sectors_per_cluster=0;
unsigned int sectors_per_fat=0;
unsigned int data_sectors=0;
unsigned int first_cluster=0;
unsigned int fsinfo_sector=0;
unsigned int reserved_sectors=0;
unsigned int fat1_sector=0,fat2_sector=0,first_cluster_sector;

unsigned char mbr[512];
unsigned char fat_mbr[512];

int open_file_system(void)
{
  int retVal=0;
  do {
    if (read_sector(0,mbr,0)) {
      fprintf(stderr,"ERROR: Could not read MBR\n");
      retVal=-1;
      break;
    }

    for(int i=0;i<4;i++) {
      unsigned char *part_ent = &mbr[0x1be + (i*0x10)];
      //      dump_bytes(0,"partent",part_ent,16);
      if (part_ent[4]==0x0c||part_ent[4]==0x0b) {
	partition_start=part_ent[8]+(part_ent[9]<<8)+(part_ent[10]<<16)+(part_ent[11]<<24);
	partition_size=part_ent[12]+(part_ent[13]<<8)+(part_ent[14]<<16)+(part_ent[15]<<24);
	printf("Found FAT32 partition in partition slot %d : start=0x%x, size=%d MB\n",
	       i,partition_start,partition_size/2048);
	break;
      }
    }

    if (!partition_start) { retVal=-1; break; }
    if (!partition_size) { retVal=-1; break; }

    // Ok, so we know where the partition starts, so now find the FATs
    if (read_sector(partition_start,fat_mbr,0)) {
      printf("ERROR: Could not read FAT MBR\n");
      retVal=-1; break; }

    if (fat_mbr[510]!=0x55) {
      printf("ERROR: Invalid FAT MBR signature\n");
      retVal=-1; break;
    }
    if (fat_mbr[511]!=0xAA) {
      printf("ERROR: Invalid FAT MBR signature\n");
      retVal=-1; break;
    }
    if (fat_mbr[12]!=2) {
      printf("ERROR: FAT32 file system uses a sector size other than 512 bytes\n");
      retVal=-1; break;
    }
    if (fat_mbr[16]!=2) {
      printf("ERROR: FAT32 file system has more or less than 2 FATs\n");
      retVal=-1; break;
    }    
    sectors_per_cluster=fat_mbr[13];
    reserved_sectors=fat_mbr[14]+(fat_mbr[15]<<8);
    data_sectors=(fat_mbr[0x20]<<0)|(fat_mbr[0x21]<<8)|(fat_mbr[0x22]<<16)|(fat_mbr[0x23]<<24);
    sectors_per_fat=(fat_mbr[0x24]<<0)|(fat_mbr[0x25]<<8)|(fat_mbr[0x26]<<16)|(fat_mbr[0x27]<<24);
    first_cluster=(fat_mbr[0x2c]<<0)|(fat_mbr[0x2d]<<8)|(fat_mbr[0x2e]<<16)|(fat_mbr[0x2f]<<24);
    fsinfo_sector=fat_mbr[0x30]+(fat_mbr[0x31]<<8);
    fat1_sector=reserved_sectors;
    fat2_sector=fat1_sector+sectors_per_fat;
    first_cluster_sector=fat2_sector+sectors_per_fat;
    
    printf("FAT32 file system has %dMB formatted capacity, first cluster = %d, %d sectors per FAT\n",
	   data_sectors/2048,first_cluster,sectors_per_fat);
    printf("FATs begin at sector 0x%x and 0x%x\n",fat1_sector,fat2_sector);

    file_system_found=1;
    
  } while (0);
  return retVal;
}

unsigned char buf[512];

unsigned int get_next_cluster(int cluster)
{
  unsigned int retVal=0xFFFFFFFF;
  
  do {
    // Read chain entry for this cluster
    int cluster_sector_number=cluster/(512/4);
    int cluster_sector_offset=(cluster*4)&511;

    // Read sector of cluster
    if (read_sector(partition_start+fat1_sector+cluster_sector_number,buf,0)) break;

    // Get value out
    retVal=
      (buf[cluster_sector_offset+0]<<0)|
      (buf[cluster_sector_offset+1]<<8)|
      (buf[cluster_sector_offset+2]<<16)|
      (buf[cluster_sector_offset+3]<<24);
    
  } while(0);
  return retVal;
  
}

unsigned char dir_sector_buffer[512];
unsigned int dir_sector=-1; // no dir
int dir_cluster=0;
int dir_sector_in_cluster=0;
int dir_sector_offset=0;

int fat_opendir(char *path)
{
  int retVal=0;
  do {
    if (strcmp(path,"/")) {
      printf("XXX Sub-directories not implemented\n");
    }

    dir_cluster=first_cluster;
    dir_sector=first_cluster_sector;
    dir_sector_offset=-32;
    dir_sector_in_cluster=0;
    retVal=read_sector(partition_start+dir_sector,dir_sector_buffer,0);
    if (retVal) dir_sector=-1;
    
  } while(0);
  return retVal;
}

int fat_readdir(struct dirent *d)
{
  int retVal=0;
  do {

    // Advance to next entry
    dir_sector_offset+=32;
    if (dir_sector_offset==512) {
      dir_sector_offset=0;
      dir_sector++;
      dir_sector_in_cluster++;
      if (dir_sector_in_cluster==sectors_per_cluster) {
	// Follow to next cluster
	int next_cluster=get_next_cluster(dir_cluster);
	if (next_cluster<0xFFFFFF0) {
	  dir_cluster=next_cluster;
	  dir_sector_in_cluster=0;
	  dir_sector=first_cluster_sector+(next_cluster-first_cluster)*sectors_per_cluster;
	} else {
	  // End of directory reached
	  dir_sector=-1;
	  retVal=-1;
	  break;
	}
      }
      if (dir_sector!=-1) retVal=read_sector(partition_start+dir_sector,dir_sector_buffer,0);
      if (retVal) dir_sector=-1;      
    }    

    if (dir_sector==-1) { retVal=-1; break; }
    if (!d) { retVal=-1; break; }

    // printf("Found dirent %d %d %d\n",dir_sector,dir_sector_offset,dir_sector_in_cluster);

    // XXX - Support FAT32 long names!

    // Put cluster number in d_ino
    d->d_ino=
      (dir_sector_buffer[dir_sector_offset+0x1A]<<0)|
      (dir_sector_buffer[dir_sector_offset+0x1B]<<8)|
      (dir_sector_buffer[dir_sector_offset+0x14]<<16)|
      (dir_sector_buffer[dir_sector_offset+0x15]<<24);

    int namelen=0;
    if (dir_sector_buffer[dir_sector_offset]) {
      for(int i=0;i<8;i++)
	if (dir_sector_buffer[dir_sector_offset+i])
	  d->d_name[namelen++]=dir_sector_buffer[dir_sector_offset+i];
      while(namelen&&d->d_name[namelen-1]==' ') namelen--;
    }
    if (dir_sector_buffer[dir_sector_offset+8]&&dir_sector_buffer[dir_sector_offset+8]!=' ') {
      d->d_name[namelen++]='.';
      for(int i=0;i<3;i++)
	if (dir_sector_buffer[dir_sector_offset+8+i])
	  d->d_name[namelen++]=dir_sector_buffer[dir_sector_offset+8+i];
      while(namelen&&d->d_name[namelen-1]==' ') namelen--;
    }
    d->d_name[namelen]=0;

    //    if (d->d_name[0]) dump_bytes(0,"dirent raw",&dir_sector_buffer[dir_sector_offset],32);
    
    d->d_off= //  XXX As a hack we put the size here
      (dir_sector_buffer[dir_sector_offset+0x1C]<<0)|
      (dir_sector_buffer[dir_sector_offset+0x1D]<<8)|
      (dir_sector_buffer[dir_sector_offset+0x1E]<<16)|
      (dir_sector_buffer[dir_sector_offset+0x1F]<<24);
    d->d_reclen=dir_sector_buffer[dir_sector_offset+0xb]; // XXX as a hack, we put DOS file attributes here
    if (d->d_off&0xC8) d->d_type=DT_UNKNOWN;
    else if (d->d_off&0x10) d->d_type=DT_DIR;
    else d->d_type=DT_REG;

  } while(0);
  return retVal;
}

int chain_cluster(unsigned int cluster,unsigned int next_cluster)
{
  int retVal=0;

  do {
    int fat_sector_num=cluster/(512/4);
    int fat_sector_offset=(cluster*4)&0x1FF;
    if (fat_sector_num>=sectors_per_fat) {
      printf("ERROR: cluster number too large.\n");
      retVal=-1; break;
    }

    // Read in the sector of FAT1
    unsigned char fat_sector[512];
    if (read_sector(partition_start+fat1_sector+fat_sector_num,fat_sector,0)) {
      printf("ERROR: Failed to read sector $%x of first FAT\n",fat_sector_num);
      retVal=-1; break;
    }

    dump_bytes(0,"FAT sector",fat_sector,512);
    
    printf("Marking cluster $%x in use by writing to offset $%x of FAT sector $%x\n",
	   cluster,fat_sector_offset,fat_sector_num);
    
    // Set the bytes for this cluster to $0FFFFF8 to mark end of chain and in use
    fat_sector[fat_sector_offset+0]=(next_cluster>>0)&0xff;
    fat_sector[fat_sector_offset+1]=(next_cluster>>8)&0xff;
    fat_sector[fat_sector_offset+2]=(next_cluster>>16)&0xff;
    fat_sector[fat_sector_offset+3]=(next_cluster>>24)&0x0f;

    printf("Marking cluster in use in FAT1\n");

    // Write sector back to FAT1
    if (write_sector(partition_start+fat1_sector+fat_sector_num,fat_sector)) {
      printf("ERROR: Failed to write updated FAT sector $%x to FAT1\n",fat_sector_num);
      retVal=-1; break; }

    printf("Marking cluster in use in FAT2\n");

    // Write sector back to FAT2
    if (write_sector(partition_start+fat2_sector+fat_sector_num,fat_sector)) {
      printf("ERROR: Failed to write updated FAT sector $%x to FAT1\n",fat_sector_num);
      retVal=-1; break; }

    printf("Done allocating cluster\n");
    
  } while(0);
  
  return retVal;
}

int allocate_cluster(unsigned int cluster)
{
  int retVal=0;

  do {
    int fat_sector_num=cluster/(512/4);
    int fat_sector_offset=(cluster*4)&0x1FF;
    if (fat_sector_num>=sectors_per_fat) {
      printf("ERROR: cluster number too large.\n");
      retVal=-1; break;
    }

    // Read in the sector of FAT1
    unsigned char fat_sector[512];
    if (read_sector(partition_start+fat1_sector+fat_sector_num,fat_sector,0)) {
      printf("ERROR: Failed to read sector $%x of first FAT\n",fat_sector_num);
      retVal=-1; break;
    }

    dump_bytes(0,"FAT sector",fat_sector,512);
    
    printf("Marking cluster $%x in use by writing to offset $%x of FAT sector $%x\n",
	   cluster,fat_sector_offset,fat_sector_num);
    
    // Set the bytes for this cluster to $0FFFFF8 to mark end of chain and in use
    fat_sector[fat_sector_offset+0]=0xf8;
    fat_sector[fat_sector_offset+1]=0xff;
    fat_sector[fat_sector_offset+2]=0xff;
    fat_sector[fat_sector_offset+3]=0x0f;

    printf("Marking cluster in use in FAT1\n");

    // Write sector back to FAT1
    if (write_sector(partition_start+fat1_sector+fat_sector_num,fat_sector)) {
      printf("ERROR: Failed to write updated FAT sector $%x to FAT1\n",fat_sector_num);
      retVal=-1; break; }

    printf("Marking cluster in use in FAT2\n");

    // Write sector back to FAT2
    if (write_sector(partition_start+fat2_sector+fat_sector_num,fat_sector)) {
      printf("ERROR: Failed to write updated FAT sector $%x to FAT1\n",fat_sector_num);
      retVal=-1; break; }

    printf("Done allocating cluster\n");
    
  } while(0);
  
  return retVal;
}

unsigned int chained_cluster(unsigned int cluster)
{
  unsigned int retVal=0;

  do {
    int fat_sector_num=cluster/(512/4);
    int fat_sector_offset=(cluster*4)&0x1FF;
    if (fat_sector_num>=sectors_per_fat) {
      printf("ERROR: cluster number too large.\n");
      retVal=-1; break;
    }

    // Read in the sector of FAT1
    unsigned char fat_sector[512];
    if (read_sector(partition_start+fat1_sector+fat_sector_num,fat_sector,0)) {
      printf("ERROR: Failed to read sector $%x of first FAT\n",fat_sector_num);
      retVal=-1; break;
    }

    // Set the bytes for this cluster to $0FFFFF8 to mark end of chain and in use
    retVal=fat_sector[fat_sector_offset+0];
    retVal|=fat_sector[fat_sector_offset+1]<<8;
    retVal|=fat_sector[fat_sector_offset+2]<<16;
    retVal|=fat_sector[fat_sector_offset+3]<<24;

    printf("Cluster %d chains to cluster %d ($%x)\n",cluster,retVal,retVal);
    
  } while(0);
  
  return retVal;
}


unsigned char fat_sector[512];

unsigned int find_free_cluster(unsigned int first_cluster)
{
  unsigned int cluster=0;

  int retVal=0;

  do {
    int i,o;

    i = first_cluster / (512/4);
    o = (first_cluster % (512/4)) * 4;
    
    for(;i<sectors_per_fat;i++) {
      // Read FAT sector
      printf("Checking FAT sector $%x for free clusters.\n",i);
      if (read_sector(partition_start+fat1_sector+i,fat_sector,0)) {
	printf("ERROR: Failed to read sector $%x of first FAT\n",i);
	retVal=-1; break;
      }

      if (retVal) break;
      
      // Search for free sectors
      for(;o<512;o+=4) {
	if (!(fat_sector[o]|fat_sector[o+1]|fat_sector[o+2]|fat_sector[o+3]))
	  {
	    // Found a free cluster.
	    cluster = i*(512/4)+(o/4);
	    printf("cluster sector %d, offset %d yields cluster %d\n",i,o,cluster);
	    break;
	  }
      }
      o=0;
    
      if (cluster||retVal) break;
    }

    printf("I believe cluster $%x is free.\n",cluster);
    
    retVal=cluster;
  } while(0);
  
  return retVal;
}

int upload_file(char *name,char *dest_name)
{
  struct dirent de;
  int retVal=0;
  do {
    struct stat st;
    if (stat(name,&st)) {
      fprintf(stderr,"ERROR: Could not stat file '%s'\n",name);
      perror("stat() failed");
    }
    printf("File '%s' is %ld bytes long.\n",name,(long)st.st_size);

    if (!file_system_found) open_file_system();
    if (!file_system_found) {
      fprintf(stderr,"ERROR: Could not open file system.\n");
      retVal=-1;
      break;
    }

    if (fat_opendir("/")) { retVal=-1; break; }
    printf("Opened directory, dir_sector=%d (absolute sector = %d)\n",dir_sector,partition_start+dir_sector);
    while(!fat_readdir(&de)) {
      if (de.d_name[0]) printf("%13s   %d\n",de.d_name,(int)de.d_off);
      //      else dump_bytes(0,"empty dirent",&dir_sector_buffer[dir_sector_offset],32);
      if (!strcasecmp(de.d_name,dest_name)) {
	// Found file, so will replace it
	printf("%s already exists on the file system, beginning at cluster %d\n",name,(int)de.d_ino);
	break;
      }
    }
    if (dir_sector==-1) {
      // File does not (yet) exist, get ready to create it
      printf("%s does not yet exist on the file system -- searching for empty directory slot to create it in.\n",name);

      if (fat_opendir("/")) { retVal=-1; break; }
      struct dirent de;
      while(!fat_readdir(&de)) {
	if (!de.d_name[0]) {
	  printf("Found empty slot at dir_sector=%d, dir_sector_offset=%d\n",
		 dir_sector,dir_sector_offset);

	  // Create directory entry, and write sector back to SD card
	  unsigned char dir[32];
	  bzero(dir,32);

	  // Write name
	  for(int i=0;i<11;i++) dir[i]=0x20;
	  for(int i=0;i<8;i++)
	    if (dest_name[i]=='.') {
	      // Write out extension
	      for(int j=0;j<3;j++)
		if (dest_name[i+1+j]) dir[8+j]=dest_name[i+1+j];
	      break;
	    } else if (!dest_name[i]) break;
	    else dir[i]=dest_name[i];

	  // Set file attributes (only archive bit)
	  dir[0xb]=0x20;

	  // Store create time and date
	  time_t t=time(0);
	  struct tm *tm=localtime(&t);
	  dir[0xe]=(tm->tm_sec>>1)&0x1F;  // 2 second resolution
	  dir[0xe]|=(tm->tm_min&0x7)<<5;
	  dir[0xf]=(tm->tm_min&0x3)>>3;
	  dir[0xf]|=(tm->tm_hour)<<2;
	  dir[0x10]=tm->tm_mday&0x1f;
	  dir[0x10]|=((tm->tm_mon+1)&0x7)<<5;
	  dir[0x11]=((tm->tm_mon+1)&0x1)>>3;
	  dir[0x11]|=(tm->tm_year-80)<<1;

	  dump_bytes(0,"New directory entry",dir,32);
	  
	  // (Cluster and size we set after writing to the file)

	  // Copy back into directory sector, and write it
	  bcopy(dir,&dir_sector_buffer[dir_sector_offset],32);
	  if (write_sector(partition_start+dir_sector,dir_sector_buffer)) {
	    printf("Failed to write updated directory sector.\n");
	    retVal=-1; break; }
	  
	  break;
	}
      }
    }
    if (dir_sector==-1) {
      printf("ERROR: Directory is full.  Request support for extending directory into multiple clusters.\n");
      retVal=-1;
      break;
    } else {
      printf("Directory entry is at offset $%03x of sector $%x\n",dir_sector_offset,dir_sector);
    }

    // Read out the first cluster. If zero, then we need to allocate a first cluster.
    // After that, we can allocate and chain clusters in a constant manner
    unsigned int first_cluster_of_file=
      (dir_sector_buffer[dir_sector_offset+0x1A]<<0)
      |(dir_sector_buffer[dir_sector_offset+0x1B]<<8)
      |(dir_sector_buffer[dir_sector_offset+0x14]<<16)
      |(dir_sector_buffer[dir_sector_offset+0x15]<<24);
    if (!first_cluster_of_file) {
      printf("File currently has no first cluster allocated.\n");

      int a_cluster=find_free_cluster(0);
      if (!a_cluster) {
	printf("ERROR: Failed to find a free cluster.\n");
	retVal=-1; break;
      }
      if (allocate_cluster(a_cluster)) {
	printf("ERROR: Could not allocate cluster $%x\n",a_cluster);
	retVal=-1; break;	
      }

      // Write cluster number into directory entry
      dir_sector_buffer[dir_sector_offset+0x1A]=(a_cluster>>0)&0xff;
      dir_sector_buffer[dir_sector_offset+0x1B]=(a_cluster>>8)&0xff;
      dir_sector_buffer[dir_sector_offset+0x14]=(a_cluster>>16)&0xff;
      dir_sector_buffer[dir_sector_offset+0x15]=(a_cluster>>24)&0xff;
      
      if (write_sector(partition_start+dir_sector,dir_sector_buffer)) {
	printf("ERROR: Failed to write updated directory sector after allocating first cluster.\n");
	retVal=-1; break; }
      
      first_cluster_of_file=a_cluster;
    } else printf("First cluster of file is $%x\n",first_cluster_of_file);

    // Now write the file out sector by sector, and allocate new clusters as required
    int remaining_length=st.st_size;
    int sector_in_cluster=0;
    int file_cluster=first_cluster_of_file;
    unsigned int sector_number;
    FILE *f=fopen(name,"r");

    if (!f) {
      printf("ERROR: Could not open file '%s' for reading.\n",name);
      retVal=-1; break;
    }

    while(remaining_length) {
      if (sector_in_cluster>=sectors_per_cluster) {
	// Advance to next cluster
	// If we are currently the last cluster, then allocate a new one, and chain it in

	int next_cluster=chained_cluster(file_cluster);
	if (next_cluster==0||next_cluster>=0xffffff8) {
	  next_cluster=find_free_cluster(file_cluster);
	  if (allocate_cluster(next_cluster)) {
	    printf("ERROR: Could not allocate cluster $%x\n",next_cluster);
	    retVal=-1; break;
	  }
	  if (chain_cluster(file_cluster,next_cluster)) {
	    printf("ERROR: Could not chain cluster $%x to $%x\n",file_cluster,next_cluster);
	    retVal=-1; break;
	  }
	}
	if (!next_cluster) {
	  printf("ERROR: Could not find a free cluster\n");
	  retVal=-1; break;
	}
	
	
	file_cluster=next_cluster;
	sector_in_cluster=0;
      }

      // Write sector
      unsigned char buffer[512];
      bzero(buffer,512);
      int bytes=fread(buffer,1,512,f);
      sector_number=partition_start+first_cluster_sector+(sectors_per_cluster*(file_cluster-first_cluster))+sector_in_cluster;
      printf("T+%lld : Read %d bytes from file, writing to sector $%x (%d) for cluster %d\n",
	     gettime_us()-start_usec,bytes,sector_number,sector_number,file_cluster);

      if (write_sector(sector_number,buffer)) {
	printf("ERROR: Failed to write to sector %d\n",sector_number);
	retVal=-1;
	break;
      }
      //      printf("T+%lld : after write.\n",gettime_us()-start_usec);

      sector_in_cluster++;
      remaining_length-=512;
    }

    // XXX check for orphan clusters at the end, and if present, free them.

    // Write file size into directory entry
    dir_sector_buffer[dir_sector_offset+0x1C]=(st.st_size>>0)&0xff;
    dir_sector_buffer[dir_sector_offset+0x1D]=(st.st_size>>8)&0xff;
    dir_sector_buffer[dir_sector_offset+0x1E]=(st.st_size>>16)&0xff;
    dir_sector_buffer[dir_sector_offset+0x1F]=(st.st_size>>24)&0xff;

    if (write_sector(partition_start+dir_sector,dir_sector_buffer)) {
      printf("ERROR: Failed to write updated directory sector after updating file length.\n");
      retVal=-1; break; }

    
  } while(0);

  return retVal;
}
