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

#ifdef APPLE
static const int B1000000 = 1000000;
static const int B1500000 = 1500000;
static const int B2000000 = 2000000;
static const int B4000000 = 4000000;
#endif
time_t start_time=0;

int upload_file(char *name);
int sdhc_check(void);
int read_sector(const unsigned int sector_number,unsigned char *buffer);

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

int sd_status_fresh=0;
unsigned char sd_status[16];

int process_char(unsigned char c,int live);


void usage(void)
{
  fprintf(stderr,"MEGA65 cross-development tool for uploading files onto the SD card of a MEGA65.\n");
  fprintf(stderr,"usage: monitor_load [-l <serial port>] [-s <230400|2000000|4000000>]  [-b bitstream] <file1 ...>\n");
  fprintf(stderr,"  -l - Name of serial port to use, e.g., /dev/ttyUSB1\n");
  fprintf(stderr,"  -s - Speed of serial port in bits per second. This must match what your bitstream uses.\n");
  fprintf(stderr,"       (Older bitstream use 230400, and newer ones 2000000 or 4000000).\n");
  fprintf(stderr,"  -b - Name of bitstream file to load.\n");
  fprintf(stderr,"  filename - Upload this file onto the SD card of a MEGA65.\n");
  fprintf(stderr,"\n");
  exit(-3);
}

int slow_write(int fd,char *d,int l)
{
  // UART is at 2Mbps, but we need to allow enough time for a whole line of
  // writing. 100 chars x 0.5usec = 500usec. So 1ms between chars should be ok.
  // printf("Writing [%s]\n",d);
  int i;
  for(i=0;i<l;i++)
    {
      usleep(2000);
      int w=write(fd,&d[i],1);
      while (w<1) {
	usleep(1000);
	w=write(fd,&d[i],1);
      }
    }
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
  slow_write(fd,"t1\r",3);
  return 0;
}

int restart_kickstart(void)
{
  // Start executing in new kickstart
  if (!halt) {
    usleep(50000);
    slow_write(fd,"g8100\r",6);
    usleep(10000);
    slow_write(fd,"t0\r",3);
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
  // printf("[%s]\n",line);
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
	  for(int i=0;i<16;i++) sd_read_buffer[sector_offset+i]=b[i];
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

int main(int argc,char **argv)
{
  start_time=time(0);
  
  int opt;
  while ((opt = getopt(argc, argv, "b:s:l:")) != -1) {
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
    default: /* '?' */
      usage();
    }
  }  

  if (argc-optind<1) usage();
  
  // Load bitstream if file provided
  if (bitstream) {
    char cmd[1024];
    snprintf(cmd,1024,"fpgajtag -a %s",bitstream);
    fprintf(stderr,"%s\n",cmd);
    system(cmd);
    fprintf(stderr,"[T+%lldsec] Bitstream loaded\n",(long long)time(0)-start_time);
  }
  
  errno=0;
  fd=open(serial_port,O_RDWR);
  if (fd==-1) {
    fprintf(stderr,"Could not open serial port '%s'\n",serial_port);
    perror("open");
    exit(-1);
  }
  fcntl(fd,F_SETFL,fcntl(fd, F_GETFL, NULL)|O_NONBLOCK);
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

  stop_cpu();

  sdhc_check();
  
  for(int i=optind;i<argc;i++)
    upload_file(argv[i]);

  return 0;
}

void wait_for_sdready(void)
{
  do {  
    // Ask for SD card status
    sd_status[0]=0xff;
    while(sd_status[0]&3) {
      sd_status_fresh=0;
      slow_write(fd,"mffd3680\r",strlen("mffd3680\r"));
      while(!sd_status_fresh) process_waiting(fd);
      if (sd_status[0]&3) {
	// Send reset sequence
	printf("SD card not yet ready, so reset it.\n");
	slow_write(fd,"sffd3680 0\rsffd3680 1\r",strlen("sffd3680 0\rsffd3680 1\r"));
	sleep(1);
      }
    }
    //     printf("SD Card looks ready.\n");
  } while(0);
  return;
}

int wait_for_sdready_passive(void)
{
  int retVal=0;
  do {  
    // Ask for SD card status
    sd_status[0]=0xff;
    while(sd_status[0]&3) {
      sd_status_fresh=0;
      slow_write(fd,"mffd3680\r",strlen("mffd3680\r"));
      while(!sd_status_fresh) process_waiting(fd);
      if ((sd_status[0]&3)==0x03)
	{ // printf("SD card error 0x3 - failing\n");
	  retVal=-1; break; }
    }
    // printf("SD Card looks ready.\n");
  } while(0);
  return retVal;
}

int sdhc=-1;

int sdhc_check(void)
{
  unsigned char buffer[512];

  sdhc=0;
  int r0=read_sector(0,buffer);
  int r1=read_sector(1,buffer);
  int r200=read_sector(0x200,buffer);
  // printf("%d %d %d\n",r0,r1,r200);
  if (r0||r200) {
    fprintf(stderr,"Could not detect SD/SDHC card\n");
    exit(-3);
  }
  sdhc=r1;
  return sdhc;
}

int read_sector(const unsigned int sector_number,unsigned char *buffer)
{
  int retVal=0;
  do {
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
    slow_write(fd,cmd,strlen(cmd));
    if (wait_for_sdready_passive()) {
      printf("wait_for_sdready_passive() failed\n");
      retVal=-1; break;
    }

    // Read succeeded, so fetch sector contents
    // printf("Reading back sector contents\n");
    snprintf(cmd,1024,"M%x\rM%x\rM%x\rM%x\r",
	     READ_SECTOR_BUFFER_ADDRESS,
	     READ_SECTOR_BUFFER_ADDRESS+0x80,
	     READ_SECTOR_BUFFER_ADDRESS+0x100,
	     READ_SECTOR_BUFFER_ADDRESS+0x180);
    slow_write(fd,cmd,strlen(cmd));
	     
    sd_read_buffer=buffer;
    sd_read_offset=0;
    while(sd_read_offset!=512) process_waiting(fd);

    // printf("Read sector %d (0x%x)\n",sector_number,sector_number);
    
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
    if (read_sector(0,mbr)) {
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
    if (read_sector(partition_start,fat_mbr)) {
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

unsigned int get_next_cluster(int cluster)
{
  unsigned int retVal=0xFFFFFFFF;

  unsigned char buf[512];
  
  do {
    // Read chain entry for this cluster
    int cluster_sector_number=cluster/(512/4);
    int cluster_sector_offset=(cluster*4)&511;

    // Read sector of cluster
    if (read_sector(partition_start+fat1_sector+cluster_sector_number,buf)) break;

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
    retVal=read_sector(partition_start+dir_sector,dir_sector_buffer);
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
      if (dir_sector!=-1) retVal=read_sector(partition_start+dir_sector,dir_sector_buffer);
      if (retVal) dir_sector=-1;      
    }    

    if (dir_sector==-1) { retVal=-1; break; }
    if (!d) { retVal=-1; break; }

    // printf("Found dirent %d %d %d\n",dir_sector,dir_sector_offset,dir_sector_in_cluster);

    // XXX - Support FAT32 long names!
    d->d_ino=
      (dir_sector_buffer[dir_sector_offset+0x1A]<<0)|
      (dir_sector_buffer[dir_sector_offset+0x1B]<<8)|
      (dir_sector_buffer[dir_sector_offset+0x14]<<16)|
      (dir_sector_buffer[dir_sector_offset+0x15]<<24);
    for(int i=0;i<11;i++) d->d_name[i]=dir_sector_buffer[dir_sector_offset+i];
    d->d_name[11]=0;

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

int upload_file(char *name)
{
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
    printf("Opened directory\n");
    struct dirent de;
    while(!fat_readdir(&de)) {
      if (de.d_name[0])
	printf("  '%s' %-10d\n",de.d_name,(int)de.d_off);
    }
    // printf("End of directory\n");
    
  } while(0);

  return retVal;
}
