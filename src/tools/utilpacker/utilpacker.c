/*
  Utility packer:  Takes one or more program files and attaches them with a header
  block in the format that Kickstart expects them to be found in the 32KB colour RAM.
  These are the utilities that the hypervisor can launch, without needing to load
  anything from SD card or other storage.

*/

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>

int util_len=0;
unsigned char header_magic[4]={'M','6','5','U'};
unsigned char util_body[32*1024];

// XXX - We really should have a checksum or other integrity check
#define HEADER_LEN 40
struct util_header {
  unsigned char magic[4];
  char name[32];
  unsigned char length_lo,length_hi;
  unsigned char entry_lo,entry_hi;
};

struct util_header header;

int load_util(char *filename)
{
  bzero(&header,sizeof(header));
  FILE *f=fopen(filename,"r");
  if (!f) {
    fprintf(stderr,"Could not read utility '%s'\n",filename);
    exit(-1);
  }
  int len=0;
  int bytes;
  while((bytes=fread(&util_body[len],1,32*1024-len,f))>0) {
    len+=bytes;
  }
  if (len==32*1024) {
    fprintf(stderr,"ERROR: Utility '%s' is >=32KB.\n",filename);
    exit(-1);
  }

  
  // Search utility for name string
  header.name[0]=0;
  for(int i=0;i<len;i++)
    if (!strncmp("PROP.M65U.NAME=",(const char *)&util_body[i],15)) {
      // Found utility name
      header.name[0]=0;
      for(int j=0;j<31;j++) {
	if (util_body[i+15+j]) {
	  header.name[j]=util_body[i+15+j];
	  header.name[j+1]=0;
	}
      }
    }
  for(int i=0;i<4;i++) header.magic[i]=header_magic[i];
  header.length_lo=len&0xff;
  header.length_hi=(len>>8)&0xff;

  if (!header.name[0]) {
    fprintf(stderr,"ERROR: Utility does not contain PROP.M65U.NAME= string.\n");
    exit(-1);
  }
  
  // Find entry point low by looking for SYS token
  for(int i=0;i<256;i++)
    if ((util_body[i]==0x9e)
	&&(util_body[i+1]>='0')
	&&(util_body[i+1]<='9'))
      {
	char entry[6];
	for(int j=0;j<6;j++) entry[j]=util_body[i+1+j];
	entry[5]=0;
	int entry_addr=atoi(entry);
	header.entry_lo=entry_addr&0xff;
	header.entry_hi=(entry_addr>>8)&0xff;
	break;
      }
  if (!header.entry_hi) {
    // No SYS nnnn found
    // Look for PROP.M65U.ADDR= string instead
    for(int i=0;i<len;i++)
      if (!strncmp("PROP.M65U.ADDR=",(const char *)&util_body[i],15)) {
	int entry;
	char addr[7];
	addr[0]=0;
	for(int j=0;j<7;j++) {
	  if (util_body[i+15+j]) {
	    addr[j]=util_body[i+15+j];
	    addr[j+1]=0;
	  }
	}
	if (addr[0]=='$') {
	  // Hex
	  entry=strtol(&addr[1],NULL,16);
	} else entry=atoi(addr);
	header.entry_lo=entry&0xff;
	header.entry_hi=(entry>>8)&0xff;
	break;
      }
  }
  if (!header.entry_hi) {
    fprintf(stderr,"ERROR: Utility contains no entry point.  Add PROP.M65U.ADDR= or BASIC SYS nnnn header.\n");
    exit(-1);
  }
  
  fclose(f);
  return 0;
}

int util_describe(struct util_header *h)
{
  fprintf(stderr,"Preparing to pack utility '%s'\n",
	  h->name);
  return 0;
}

int main(int argc,char **argv)
{
  if (argc<3) {
    fprintf(stderr,"usage: utilpacker <output.bin> <file.prg [...]>\n");
    exit(-1);
  }
  
  FILE *o=fopen(argv[1],"w");
  if (!o) {
    fprintf(stderr,"Could not open '%s' to write utility archive.\n",argv[1]);
    exit(-1);
  }

  int ar_size=32*1024;
  unsigned char archive[ar_size];
  bzero(archive,ar_size);

  // Skip the first 2KB of colour RAM, as it is used by C65 system.  This leaves
  // us 30KB of available space.
  int ar_offset=2048;
  
  for(int i=2;i<argc;i++)
    {
      load_util(argv[i]);
      if (util_len>(HEADER_LEN+ar_size-ar_offset)) {
	fprintf(stderr,"Insufficient space to fit utility '%s' (%d bytes required, %d available)\n",
		header.name,HEADER_LEN+util_len,
		ar_size-ar_offset);
	exit(-1);
      }
      
    }
  
}
