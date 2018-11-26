/*
  Capture real-time instruction stream from MEGA65 via ethernet.

  (C) Paul Gardner-Stephen 2014, 2018.

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

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
// #include <sys/filio.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <linux/types.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/if_ether.h>
#include <netinet/tcp.h>
#include <netinet/ip.h>
#include <string.h>
#include <strings.h>
#include <signal.h>
#include <netdb.h>
#include <time.h>
#include <pcap.h>

char *oplist[]={
  "00   BRK\n",
  "01   ORA ($nn,X)\n",
  "02   CLE\n",
  "03   SEE\n",
  "04   TSB $nn\n",
  "05   ORA $nn\n",
  "06   ASL $nn\n",
  "07   RMB0 $nn\n",
  "08   PHP\n",
  "09   ORA #$nn\n",
  "0A   ASL A\n",
  "0B   TSY\n",
  "0C   TSB $nnnn\n",
  "0D   ORA $nnnn\n",
  "0E   ASL $nnnn\n",
  "0F   BBR0 $nn,$rr\n",
  "10   BPL $rr\n",
  "11   ORA ($nn),Y\n",
  "12   ORA ($nn),Z\n",
  "13   BPL $rrrr\n",
  "14   TRB $nn\n",
  "15   ORA $nn,X\n",
  "16   ASL $nn,X\n",
  "17   RMB1 $nn\n",
  "18   CLC\n",
  "19   ORA $nnnn,Y\n",
  "1A   INC\n",
  "1B   INZ\n",
  "1C   TRB $nnnn\n",
  "1D   ORA $nnnn,X\n",
  "1E   ASL $nnnn,X\n",
  "1F   BBR1 $nn,$rr\n",
  "20   JSR $nnnn\n",
  "21   AND ($nn,X)\n",
  "22   JSR ($nnnn)\n",
  "23   JSR ($nnnn,X)\n",
  "24   BIT $nn\n",
  "25   AND $nn\n",
  "26   ROL $nn\n",
  "27   RMB2 $nn\n",
  "28   PLP\n",
  "29   AND #$nn\n",
  "2A   ROL A\n",
  "2B   TYS\n",
  "2C   BIT $nnnn\n",
  "2D   AND $nnnn\n",
  "2E   ROL $nnnn\n",
  "2F   BBR2 $nn,$rr\n",
  "30   BMI $rr\n",
  "31   AND ($nn),Y\n",
  "32   AND ($nn),Z\n",
  "33   BMI $rrrr\n",
  "34   BIT $nn,X\n",
  "35   AND $nn,X\n",
  "36   ROL $nn,X\n",
  "37   RMB3 $nn\n",
  "38   SEC\n",
  "39   AND $nnnn,Y\n",
  "3A   DEC\n",
  "3b   DEZ\n",
  "3C   BIT $nnnn,X\n",
  "3D   AND $nnnn,X\n",
  "3E   ROL $nnnn,X\n",
  "3F   BBR3 $nn,$rr\n",
  "40   RTI\n",
  "41   EOR ($nn,X)\n",
  "42   NEG\n",
  "43   ASR\n",
  "44   ASR $nn\n",
  "45   EOR $nn\n",
  "46   LSR $nn\n",
  "47   RMB4 $nn\n",
  "48   PHA\n",
  "49   EOR #$nn\n",
  "4A   LSR A\n",
  "4B   TAZ\n",
  "4C   JMP $nnnn\n",
  "4D   EOR $nnnn\n",
  "4E   LSR $nnnn\n",
  "4F   BBR4 $nn,$rr\n",
  "50   BVC $rr\n",
  "51   EOR ($nn),Y\n",
  "52   EOR ($nn),Z\n",
  "53   BVC $rrrr\n",
  "54   ASR $nn,X\n",
  "55   EOR $nn,X\n",
  "56   LSR $nn,X\n",
  "57   RMB5 $nn\n",
  "58   CLI\n",
  "59   EOR $nnnn,Y\n",
  "5A   PHY\n",
  "5B   TAB\n",
  "5C   MAP\n",
  "5D   EOR $nnnn,X\n",
  "5E   LSR $nnnn,X\n",
  "5F   BBR5 $nn,$rr\n",
  "60   RTS\n",
  "61   ADC ($nn,X)\n",
  "62   RTS #$nn\n",
  "63   BSR $rrrr\n",
  "64   STZ $nn\n",
  "65   ADC $nn\n",
  "66   ROR $nn\n",
  "67   RMB6 $nn\n",
  "68   PLA\n",
  "69   ADC #$nn\n",
  "6A   ROR A\n",
  "6B   TZA\n",
  "6C   JMP ($nnnn)\n",
  "6D   ADC $nnnn\n",
  "6E   ROR $nnnn\n",
  "6F   BBR6 $nn,$rr\n",
  "70   BVS $rr\n",
  "71   ADC ($nn),Y\n",
  "72   ADC ($nn),Z\n",
  "73   BVS $rrrr\n",
  "74   STZ $nn,X\n",
  "75   ADC $nn,X\n",
  "76   ROR $nn,X\n",
  "77   RMB7 $nn\n",
  "78   SEI\n",
  "79   ADC $nnnn,Y\n",
  "7A   PLY\n",
  "7B   TBA\n",
  "7C   JMP ($nnnn,X)\n",
  "7D   ADC $nnnn,X\n",
  "7E   ROR $nnnn,X\n",
  "7F   BBR7 $nn,$rr\n",
  "80   BRA $rr\n",
  "81   STA ($nn,X)\n",
  "82   STA ($nn,SP),Y\n",
  "83   BRA $rrrr\n",
  "84   STY $nn\n",
  "85   STA $nn\n",
  "86   STX $nn\n",
  "87   SMB0 $nn\n",
  "88   DEY\n",
  "89   BIT #$nn\n",
  "8A   TXA\n",
  "8B   STY $nnnn,X\n",
  "8C   STY $nnnn\n",
  "8D   STA $nnnn\n",
  "8E   STX $nnnn\n",
  "8F   BBS0 $nn,$rr\n",
  "90   BCC $rr\n",
  "91   STA ($nn),Y\n",
  "92   STA ($nn),Z\n",
  "93   BCC $rrrr\n",
  "94   STY $nn,X\n",
  "95   STA $nn,X\n",
  "96   STX $nn,Y\n",
  "97   SMB1 $nn\n",
  "98   TYA\n",
  "99   STA $nnnn,Y\n",
  "9A   TXS\n",
  "9B   STX $nnnn,Y\n",
  "9C   STZ $nnnn\n",
  "9D   STA $nnnn,X\n",
  "9E   STZ $nnnn,X\n",
  "9F   BBS1 $nn,$rr\n",
  "A0   LDY #$nn\n",
  "A1   LDA ($nn,X)\n",
  "A2   LDX #$nn\n",
  "A3   LDZ #$nn\n",
  "A4   LDY $nn\n",
  "A5   LDA $nn\n",
  "A6   LDX $nn\n",
  "A7   SMB2 $nn\n",
  "A8   TAY\n",
  "A9   LDA #$nn\n",
  "AA   TAX\n",
  "AB   LDZ $nnnn\n",
  "AC   LDY $nnnn\n",
  "AD   LDA $nnnn\n",
  "AE   LDX $nnnn\n",
  "AF   BBS2 $nn,$rr\n",
  "B0   BCS $rr\n",
  "B1   LDA ($nn),Y\n",
  "B2   LDA ($nn),Z\n",
  "B3   BCS $rrrr\n",
  "B4   LDY $nn,X\n",
  "B5   LDA $nn,X\n",
  "B6   LDX $nn,Y\n",
  "B7   SMB3 $nn\n",
  "B8   CLV\n",
  "B9   LDA $nnnn,Y\n",
  "BA   TSX\n",
  "BB   LDZ $nnnn,X\n",
  "BC   LDY $nnnn,X\n",
  "BD   LDA $nnnn,X\n",
  "BE   LDX $nnnn,Y\n",
  "BF   BBS3 $nn,$rr\n",
  "C0   CPY #$nn\n",
  "C1   CMP ($nn,X)\n",
  "C2   CPZ #$nn\n",
  "C3   DEW $nn\n",
  "C4   CPY $nn\n",
  "C5   CMP $nn\n",
  "C6   DEC $nn\n",
  "C7   SMB4 $nn\n",
  "C8   INY\n",
  "C9   CMP #$nn\n",
  "CA   DEX\n",
  "CB   ASW $nnnn\n",
  "CC   CPY $nnnn\n",
  "CD   CMP $nnnn\n",
  "CE   DEC $nnnn\n",
  "CF   BBS4 $nn,$rr\n",
  "D0   BNE $rr\n",
  "D1   CMP ($nn),Y\n",
  "D2   CMP ($nn),Z\n",
  "D3   BNE $rrrr\n",
  "D4   CPZ $nn\n",
  "D5   CMP $nn,X\n",
  "D6   DEC $nn,X\n",
  "D7   SMB5 $nn\n",
  "D8   CLD\n",
  "D9   CMP $nnnn,Y\n",
  "DA   PHX\n",
  "DB   PHZ\n",
  "DC   CPZ $nnnn\n",
  "DD   CMP $nnnn,X\n",
  "DE   DEC $nnnn,X\n",
  "DF   BBS5 $nn,$rr\n",
  "E0   CPX #$nn\n",
  "E1   SBC ($nn,X)\n",
  "E2   LDA ($nn,SP),Y\n",
  "E3   INW $nn\n",
  "E4   CPX $nn\n",
  "E5   SBC $nn\n",
  "E6   INC $nn\n",
  "E7   SMB6 $nn\n",
  "E8   INX\n",
  "E9   SBC #$nn\n",
  "EA   EOM\n",
  "EB   ROW $nnnn\n",
  "EC   CPX $nnnn\n",
  "ED   SBC $nnnn\n",
  "EE   INC $nnnn\n",
  "EF   BBS6 $nn,$rr\n",
  "F0   BEQ $rr\n",
  "F1   SBC ($nn),Y\n",
  "F2   SBC ($nn),Z\n",
  "F3   BEQ $rrrr\n",
  "F4   PHW #$nnnn\n",
  "F5   SBC $nn,X\n",
  "F6   INC $nn,X\n",
  "F7   SMB7 $nn\n",
  "F8   SED\n",
  "F9   SBC $nnnn,Y\n",
  "FA   PLX\n",
  "FB   PLZ\n",
  "FC   PHW $nnnn\n",
  "FD   SBC $nnnn,X\n",
  "FE   INC $nnnn,X\n",
  "FF   BBS7 $nn,$rr\n",
  NULL
};


char *opnames[256]={NULL};
char *modes[256]={NULL};

int instruction_address=0xFFFF;

int decode_instruction(const unsigned char *b)
{
  printf("%c%c%c%c%c%c%c%c($%02X), SP=$xx%02X, A=$%02X : $%04X : %02X",
	 b[5]&0x80?'N':'-',
	 b[5]&0x40?'V':'-',
	 b[5]&0x20?'E':'-',
	 b[5]&0x10?'B':'-',
	 b[5]&0x08?'D':'-',
	 b[5]&0x04?'I':'-',
	 b[5]&0x02?'Z':'-',
	 b[5]&0x01?'C':'-',
	 b[5],b[6],b[7],instruction_address,b[2]);

  int opcode=b[2];
  int mem[3]={b[2],b[3],b[4]};
  char args[1024];
  int o=0;
  int i=1;
  int c=0;
  int value;
  int digits;
  
  int load_address=instruction_address;
  
  for(int j=0;modes[opcode][j];) {
    args[o]=0;
    // printf("j=%d, args=[%s], template=[%s]\n",j,args,modes[opcode]);
    switch(modes[opcode][j]) {
    case 'n': // normal argument
      digits=0;
      while (modes[opcode][j++]=='n') { digits++; } j--;
      if (digits==2) {
	value=mem[i];
	printf(" %02X",mem[i++]);
	sprintf(&args[o],"%02X",value); o+=2;
	c+=3;
      }
      if (digits==4) {
	value=mem[i]+(mem[i+1]<<8);
	printf(" %02X",mem[i++]);
	printf(" %02X",mem[i++]);
	sprintf(&args[o],"%04X",value); o+=4;
	c+=6;
      }
      break;
    case 'r': // relative argument
      digits=0;
      while (modes[opcode][j++]=='r') { digits++; } j--;
      if (digits==2) {
	value=mem[i];
	if (value&0x80) value-=0x100;
	printf(" %02X",mem[i++]);
	value+=load_address+i;
	sprintf(&args[o],"%04X",value); o+=4;
	c+=3;
      }
      if (digits==4) {
	value=mem[i]+(mem[i+1]<<8);
	if (value&0x8000) value-=0x10000;
	printf(" %02X",mem[i++]);
	// 16 bit branches are still relative to the same point as 8-bit ones,
	// i.e., after the 2nd of the 3 bytes
	value+=load_address+i;        
	printf(" %02X",mem[i++]);
	sprintf(&args[o],"%04X",value); o+=4;
	c+=6;
      }
      break;
    default: 
      args[o++]=modes[opcode][j++];
      break;
    }
    args[o]=0;
    // printf("[%s]\n",args);
  }
  args[o]=0;
  while(c<9) { printf(" "); c++; }
  printf("%s %s\n",opnames[opcode],args);      
  c+=strlen(opnames[opcode])+1+strlen(args); 

  // Remember instruction address for next display
  instruction_address = (b[1]<<8)+b[0];
  // JSR passes PC+1 instead of PC of next instruction, so adjust
  switch (opcode) {
  case 0x6c:
    // indirect jump leaves correct address
    break;
  case 0xf0:
    // Branches taken leave correct address, but
    // untaken branches do not.
    if (instruction_address!=(load_address+2))
      break;
    /* fall through */
  default:
    instruction_address--;
  }
  
  return 0;
}

int main(int argc,char **argv)
{
    char *dev;
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t* descr;
    //    struct bpf_program fp;        /* to hold compiled program */
    bpf_u_int32 pMask;            /* subnet mask */
    bpf_u_int32 pNet;             /* ip address*/
    pcap_if_t *alldevs;

    int i;
    for(i=0;oplist[i];i++) {
      int n;
      char opcode[1024];
      char mode[1024];
      
      int r=sscanf(oplist[i],"%02x   %s %s",&n,opcode,mode);
      if (n==i) {
	if (r==3) {
	  opnames[i] = strdup(opcode);
	  modes[i]=strdup(mode);
	} else if (r==2) {
	  opnames[i] = strdup(opcode);
	  modes[i]="";
	}
      }
    }

    
    // Prepare a list of all the devices
    if (pcap_findalldevs(&alldevs, errbuf) == -1)
    {
        fprintf(stderr,"Error in pcap_findalldevs: %s\n", errbuf);
        exit(1);
    }

    if (argv[1]) dev=argv[1]; else {
      fprintf(stderr,"You must specify the interface to listen on.\n");
      exit(-1);
    }

    // If something was not provided
    // return error.
    if(dev == NULL)
    {
        printf("\n[%s]\n", errbuf);
        return -1;
    }

    // fetch the network address and network mask
    pcap_lookupnet(dev, &pNet, &pMask, errbuf);

    // Now, open device for sniffing with big snaplen and 
    // promiscuous mode enabled.
    descr = pcap_open_live(dev, 8192, 1, 10, errbuf);
    if(descr == NULL)
    {
        printf("pcap_open_live() failed due to [%s]\n", errbuf);
        return -1;
    }

    printf("Started.\n"); fflush(stdout);

    while(1) {

      struct pcap_pkthdr hdr;
      hdr.caplen=0;
      const unsigned char *packet = pcap_next(descr,&hdr);
      if (packet) {
	if (hdr.caplen == 2132) {
	  for(int offset=0x48+14;offset<hdr.caplen;offset+=8) {
	    decode_instruction(&packet[offset]);
	  }
	}
      }
    }
    printf("Exiting.\n");

    return 0;
}

