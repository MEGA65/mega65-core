/* This was originally based on d6502 v 0.1 from here:

   http://forum.6502.org/viewtopic.php?f=2&t=3644&start=0

   However, it's been reworked so much as to basically be unrecognizable, but I liked the general
   idea of how the table was done.  I've just compressed it significantly so the data size is just
   over 700 bytes or so but still provides enough info for the entire 4510/65CE02 instruction set.

   Now the table just gets used to generate a file that gets included into the monitor disassembler.
   It's much easier to do this with C (and the preprocessor) than it is to maintain it directly in
   Ophis.
 
   -Ken
*/

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GEN_OPCODES(_op_,_opN) \
	_op_(ADC), _op_(AND), _op_(ASL), _op_(ASR), _op_(ASW), _opN(BBR), _opN(BBS), _op_(BCC), \
	_op_(BCS), _op_(BEQ), _op_(BIT), _op_(BMI), _op_(BNE), _op_(BPL), _op_(BRA), _op_(BRK), \
	_op_(BSR), _op_(BVC), _op_(BVS), _op_(CLC), _op_(CLD), _op_(CLE), _op_(CLI), _op_(CLV), \
	_op_(CMP), _op_(CPX), _op_(CPY), _op_(CPZ), _op_(DEC), _op_(DEW), _op_(DEX), _op_(DEY), \
	_op_(DEZ), _op_(EOR), _op_(INC), _op_(INW), _op_(INX), _op_(INY), _op_(INZ), _op_(JMP), \
	_op_(JSR), _op_(LDA), _op_(LDX), _op_(LDY), _op_(LDZ), _op_(LSR), _op_(MAP), _op_(NEG), \
	_op_(NOP), _op_(ORA), _op_(PHA), _op_(PHP), _op_(PHD), _op_(PHX), _op_(PHY), _op_(PHZ), \
	_op_(PLA), _op_(PLP), _op_(PLX), _op_(PLY), _op_(PLZ), _opN(RMB), _op_(ROL), _op_(ROR), \
	_op_(ROW), _op_(RTI), _op_(RTN), _op_(RTS), _op_(SBC), _op_(SEC), _op_(SED), _op_(SEE), \
	_op_(SEI), _opN(SMB), _op_(STA), _op_(STX), _op_(STY), _op_(STZ), _op_(TAB), _op_(TAX), \
	_op_(TAY), _op_(TAZ), _op_(TBA), _op_(TRB), _op_(TSB), _op_(TSX), _op_(TSY), _op_(TXA), \
	_op_(TXS), _op_(TYA), _op_(TYS), _op_(TZA), _op_(KIL)

#define DECLARE_ENUM(opName) opName

#define DEFINE_PACKED_OPCODE_NAME(opName) \
	(((opName[0]-'A') << 0) | ((opName[1]-'A') << 5) | ((opName[2]-'A') << 10))

#define OPCODE_NAME(op) \
		((op >>  0) & 0x1f) + 'A', ((op >>  5) & 0x1f) + 'A',((op >> 10) & 0x1f) + 'A'

enum
{
	GEN_OPCODES(DECLARE_ENUM,DECLARE_ENUM)
};

#define DEFINE_STR(opName) #opName
#define DEFINE_ZERO(opName) 0
#define DEFINE_SPEC(opName) 0x8000

const char *opcodeStrs[] =
{
	GEN_OPCODES(DEFINE_STR,DEFINE_STR)
};

uint16_t opcodeNames[] =
{
	GEN_OPCODES(DEFINE_ZERO,DEFINE_SPEC)
};

// Need 2 bits for this
const char prefixChars[] =
{
	//0,				// 0  (not stored)
	'#',				// 1
	'(',				// 2
	0				// 3 (means relative)
};

const char *prefixStrs[] =
{
	//"",
	"#",
	"(",
	""
};

// Need 3 bits for this
const char *postfixStrs[] =
{
	//"",			// 0		(not stored)
	",X",			// 1
	",Y",			// 2
	")",			// 3
	",X)",			// 4
	"),Y",			// 5
	"),Z",			// 6
	",SP),Y"		// 7
};

#define DEFINE_ADDR_MODES(_op_) \
	_op_(imp, 0, "", 	0, ""),       \
	_op_(imm, 1, "#", 	0, ""),       \
	_op_(idx, 0, "", 	1, ",X"),     \
	_op_(idy, 0, "", 	2, ",Y"),     \
	_op_(ind, 2, "(", 	3, ")"),      \
	_op_(inx, 2, "(",	4, ",X)"),    \
	_op_(iny, 2, "(",	5, "),Y"),    \
	_op_(inz, 2, "(",	6, "),Z"),    \
	_op_(isy, 2, "(",	7, ",SP),Y"), \
	_op_(rel, 3, "", 	0, "")

#define _X(x) x
#define DECLARE_ADDR_ENUM(mode, preIdx, pre, postIdx, post) mode
#define DECLARE_ADDR_PRE(mode, preIdx, pre, postIdx, post) pre
#define DECLARE_ADDR_POST(mode, preIdx, pre, postIdx, post) post
#define DECLARE_ADDR_DATA_ENUM(mode, preIdx, pre, postIdx, post) \
	_X(k_ ## mode ## _data) = (preIdx << 5) | (postIdx << 2)
enum
{
	DEFINE_ADDR_MODES(DECLARE_ADDR_ENUM)
};

enum
{
	DEFINE_ADDR_MODES(DECLARE_ADDR_DATA_ENUM)
};

const char *prefix[] =
{
	DEFINE_ADDR_MODES(DECLARE_ADDR_PRE)
};

const char *postfix[] =
{
	DEFINE_ADDR_MODES(DECLARE_ADDR_POST)
};

#define GEN_OPCODE_PROPERTIES(_op_) \
            _op_(BRK,2,imp),_op_(ORA,2,inx),_op_(CLE,1,imp),_op_(SEE,1,imp),_op_(TSB,2,imp),_op_(ORA,2,imp),_op_(ASL,2,imp),_op_(RMB,2,imp),_op_(PHP,1,imp),_op_(ORA,2,imm),_op_(ASL,1,imp),_op_(TSY,1,imp),_op_(TSB,3,imp),_op_(ORA,3,imp),_op_(ASL,3,imp),_op_(BBR,3,imp), \
            _op_(BPL,2,rel),_op_(ORA,2,iny),_op_(ORA,2,idy),_op_(BPL,3,rel),_op_(TRB,2,imp),_op_(ORA,2,idx),_op_(ASL,2,idx),_op_(RMB,2,imp),_op_(CLC,1,imp),_op_(ORA,3,idy),_op_(INC,1,imp),_op_(INZ,1,imp),_op_(TRB,3,imp),_op_(ORA,3,idx),_op_(ASL,3,idx),_op_(BBR,3,imp), \
            _op_(JSR,3,imp),_op_(AND,2,inx),_op_(JSR,3,ind),_op_(JSR,3,inx),_op_(BIT,2,imp),_op_(AND,2,imp),_op_(ROL,2,imp),_op_(RMB,2,imp),_op_(PLP,1,imp),_op_(AND,2,imm),_op_(ROL,1,imp),_op_(TYS,1,imp),_op_(BIT,3,imp),_op_(AND,3,imp),_op_(ROL,3,imp),_op_(BBR,3,imp), \
            _op_(BMI,2,rel),_op_(AND,2,iny),_op_(AND,2,iny),_op_(BMI,3,rel),_op_(BIT,2,idx),_op_(AND,2,idx),_op_(ROL,2,idx),_op_(RMB,2,imp),_op_(SEC,1,imp),_op_(AND,3,idy),_op_(DEC,1,imp),_op_(DEZ,1,imp),_op_(BIT,3,idx),_op_(AND,3,idx),_op_(ROL,3,idx),_op_(BBR,3,imp), \
            _op_(RTI,1,imp),_op_(EOR,2,inx),_op_(NEG,1,imp),_op_(ASR,1,imp),_op_(ASR,2,imp),_op_(EOR,2,imp),_op_(LSR,2,imp),_op_(RMB,2,imp),_op_(PHA,1,imp),_op_(EOR,2,imm),_op_(LSR,1,imp),_op_(TAZ,1,imp),_op_(JMP,3,imp),_op_(EOR,3,imp),_op_(LSR,3,imp),_op_(BBR,3,imp), \
            _op_(BVC,2,rel),_op_(EOR,2,iny),_op_(EOR,2,inz),_op_(BVC,3,rel),_op_(ASR,2,idx),_op_(EOR,2,idx),_op_(LSR,2,idx),_op_(RMB,2,imp),_op_(CLI,1,imp),_op_(EOR,3,idy),_op_(PHY,1,imp),_op_(TAB,1,imp),_op_(MAP,1,imp),_op_(EOR,3,idx),_op_(LSR,3,idx),_op_(BBR,3,imp), \
            _op_(RTS,1,imp),_op_(ADC,2,inx),_op_(RTN,2,imm),_op_(BSR,3,rel),_op_(STZ,2,imp),_op_(ADC,2,imp),_op_(ROR,2,imp),_op_(RMB,2,imp),_op_(PLA,1,imp),_op_(ADC,2,imm),_op_(ROR,1,imp),_op_(TZA,1,imp),_op_(JMP,3,ind),_op_(ADC,3,imp),_op_(ROR,3,imp),_op_(BBR,3,imp), \
            _op_(BVS,2,rel),_op_(ADC,2,iny),_op_(ADC,2,inz),_op_(BVS,3,rel),_op_(STZ,2,idx),_op_(ADC,2,idx),_op_(ROR,2,idx),_op_(RMB,2,imp),_op_(SEI,1,imp),_op_(ADC,3,idy),_op_(PLY,1,imp),_op_(TBA,1,imp),_op_(JMP,3,inx),_op_(ADC,3,idx),_op_(ROR,3,idx),_op_(BBR,3,imp), \
            _op_(BRA,2,rel),_op_(STA,2,inx),_op_(STA,2,isy),_op_(BRA,3,rel),_op_(STY,2,imp),_op_(STA,2,imp),_op_(STX,2,imp),_op_(SMB,2,imp),_op_(DEY,1,imp),_op_(BIT,1,imp),_op_(TXA,1,imp),_op_(STY,3,idx),_op_(STY,3,imp),_op_(STA,3,imp),_op_(STX,3,imp),_op_(BBS,3,imp), \
            _op_(BCC,2,rel),_op_(STA,2,iny),_op_(STA,2,inz),_op_(BCC,3,rel),_op_(STY,2,idx),_op_(STA,2,idx),_op_(STX,2,idy),_op_(SMB,2,imp),_op_(TYA,1,imp),_op_(STA,3,idy),_op_(TXS,1,imp),_op_(STX,3,idy),_op_(STZ,3,imp),_op_(STA,3,idx),_op_(STZ,3,idx),_op_(BBS,3,imp), \
            _op_(LDY,2,imm),_op_(LDA,2,inx),_op_(LDX,2,imm),_op_(LDZ,2,imm),_op_(LDY,2,imp),_op_(LDA,2,imp),_op_(LDX,2,imp),_op_(SMB,2,imp),_op_(TAY,1,imp),_op_(LDA,2,imm),_op_(TAX,1,imp),_op_(LDZ,3,imp),_op_(LDY,3,imp),_op_(LDA,3,imp),_op_(LDX,3,imp),_op_(BBS,3,imp), \
            _op_(BCS,2,rel),_op_(LDA,2,iny),_op_(LDA,2,inz),_op_(BCS,3,rel),_op_(LDY,2,idx),_op_(LDA,2,idx),_op_(LDX,2,idy),_op_(SMB,2,imp),_op_(CLV,1,imp),_op_(LDA,3,idy),_op_(TSX,1,imp),_op_(LDZ,3,idx),_op_(LDY,3,idx),_op_(LDA,3,idx),_op_(LDX,3,idy),_op_(BBS,3,imp), \
            _op_(CPY,2,imm),_op_(CMP,2,inx),_op_(CPZ,2,imm),_op_(DEW,2,imp),_op_(CPY,2,imp),_op_(CMP,2,imp),_op_(DEC,2,imp),_op_(SMB,2,imp),_op_(INY,1,imp),_op_(CMP,2,imm),_op_(DEX,1,imp),_op_(ASW,3,imp),_op_(CPY,3,imp),_op_(CMP,3,imp),_op_(DEC,3,imp),_op_(BBS,3,imp), \
            _op_(BNE,2,rel),_op_(CMP,2,iny),_op_(CMP,2,inz),_op_(BNE,3,rel),_op_(CPZ,2,imp),_op_(CMP,2,idx),_op_(DEC,2,idx),_op_(SMB,2,imp),_op_(CLD,1,imp),_op_(CMP,3,idy),_op_(PHX,1,imp),_op_(PHZ,1,imp),_op_(CPZ,3,imp),_op_(CMP,3,idx),_op_(DEC,3,idx),_op_(BBS,3,imp), \
            _op_(CPX,2,imm),_op_(SBC,2,inx),_op_(LDA,2,isy),_op_(INW,2,imp),_op_(CPX,2,imp),_op_(SBC,2,imp),_op_(INC,2,imp),_op_(SMB,2,imp),_op_(INX,1,imp),_op_(SBC,2,imm),_op_(NOP,1,imp),_op_(ROW,3,imp),_op_(CPX,3,imp),_op_(SBC,3,imp),_op_(INC,3,imp),_op_(BBS,3,imp), \
            _op_(BEQ,2,rel),_op_(SBC,2,iny),_op_(SBC,2,inz),_op_(BEQ,3,rel),_op_(PHD,3,imm),_op_(SBC,2,idx),_op_(INC,2,idx),_op_(SMB,2,imp),_op_(SED,1,imp),_op_(SBC,3,idy),_op_(PLX,1,imp),_op_(PLZ,1,imp),_op_(PHD,3,imp),_op_(SBC,3,idx),_op_(INC,3,idx),_op_(BBS,3,imp)

     // Opcode Properties for 256 opcodes {mnemonic_lookup, length_in_bytes, mode_chars_lookup}
     	uint8_t opcode_name_idx[256] = {
#define NAME(a,b,c) a
		GEN_OPCODE_PROPERTIES(NAME)
     	};

	uint8_t opcode_data[256] = {
#define DATA(name,cnt,mode)	(uint8_t)(_X(k_ ## mode ## _data) | (cnt))
		GEN_OPCODE_PROPERTIES(DATA)
	};

#define GENERATE_ASM_TABLES 1
#if GENERATE_ASM_TABLES
int main(int argc, char **argv) {
	int i;

	// Init packed name table
	for(i = 0; i < sizeof(opcodeStrs)/sizeof(char *); i++)
	{
		opcodeNames[i] |= DEFINE_PACKED_OPCODE_NAME(opcodeStrs[i]);
	}

	// prefix character table
	printf("prefix_chars:\n");
	printf("        .byte ");
	for(i = 0; i < sizeof(prefixChars)/sizeof(char); i++)
	{
		if(i > 0)
			printf(",");
		printf("$%02x",prefixChars[i]);
	}
	printf("\n");

	// postfix string table
	for(i = 0; i < sizeof(postfixStrs)/sizeof(char *); i++)
	{
		printf("post_str%d:\n",i);
		printf("        .byte \"%s\",0\n",postfixStrs[i]);
	}
	// postfix string pointer table
	printf("post_str_ptrs:\n        .word ");
	for(i = 0; i < sizeof(postfixStrs)/sizeof(char *); i++)
	{
		if(i > 0)
			printf(",");
		printf("post_str%d",i);
	}
	printf("\n");
	// packed opcode names
	printf("opnames_lo:\n");
	for(i = 0; i < sizeof(opcodeNames)/ sizeof(opcodeNames[0]); i++)
	{
		if(i % 16 == 0)
			printf("        .byte ");
		else
			printf(",");
		printf("$%02X",opcodeNames[i] & 0xff);
		if(i % 16 == 15)
			printf("\n");
	}
	printf("\n");
	printf("opnames_hi:\n");
	for(i = 0; i < sizeof(opcodeNames)/ sizeof(opcodeNames[0]); i++)
	{
		if(i % 16 == 0)
			printf("        .byte ");
		else
			printf(",");
		printf("$%02X",opcodeNames[i] >> 8);
		if(i % 16 == 15)
			printf("\n");
	}
	printf("\n");
	printf("opnameidx:\n");
	for(i = 0; i < 256; i++)
	{
		if(i % 16 == 0)
			printf("        .byte ");
		else
			printf(",");
		printf("$%02X",opcode_name_idx[i]);
		if(i % 16 == 15)
			printf("\n");
	}
	printf("\n");
	printf("opdata:\n");
	for(i = 0; i < 256; i++)
	{
		if(i % 16 == 0)
			printf("        .byte ");
		else
			printf(",");
		printf("$%02X",opcode_data[i]);
		if(i % 16 == 15)
			printf("\n");
	}
	exit(0);
}
#else
// "Simple" disassembler to validate data tables for how I expect the 6502 monitor code to work (more or less).
int main(int argc, char **argv) {

        FILE *file;
        uint8_t *buffer;
        unsigned long fileLen;
        int address;
        int i;
        int currentbyte;
        int previousbyte;
        int paramcount;
	int premode, postmode;
	uint8_t opdata, opcode;
	uint16_t opcodeName;
	int16_t reloffset;
	uint16_t relbase;
        const char *pad;
	const char *pre;
	const char *post;

        if (argc < 2) {                                                //If no parameters given, display usage instructions and exit.
            fprintf(stderr, "Usage: %s filename address\n\n", argv[0]);
            fprintf(stderr, "Example: %s dump.rom E000\n", argv[0]);
            exit(1);
        }

        if (argc == 3) {
            address = strtol(argv[2], NULL, 16);			//If second parameter, accept it as HEX address for start of dissasembly. 
        }

        file = fopen(argv[1], "rb");                                    //Open file
        if (!file) {
            fprintf(stderr, "Can't open file %s", argv[1]);             //Error if file not found
            exit(1);
        }

        fseek(file, 0, SEEK_END);                                       //Seek to end of file to find length
        fileLen = ftell(file);
        fseek(file, 0, SEEK_SET);                                       //And back to the start

        buffer = (uint8_t * ) malloc(fileLen + 1);				//Set up file buffer

        if (!buffer) {                                                  //If memory allocation error...
            fprintf(stderr, "Memory allocation error!");                           //...display message...
            fclose(file);                                               //...and close file
            exit(1);
        }

        fread(buffer, fileLen, 1, file);                                //Read entire file into buffer and...
        fclose(file);                                                   //...close file

        paramcount = 0;
        printf("                  * = $%04X \n", address);               //Display org address

	// Init packed name table
	for(i = 0; i < sizeof(opcodeStrs)/sizeof(char *); i++)
	{
		opcodeNames[i] |= DEFINE_PACKED_OPCODE_NAME(opcodeStrs[i]);
	}

	for(i = 0; i < fileLen; )
	{
		uint8_t paramlo, paramhi;
		uint8_t bytecount;
		uint8_t j;
		uint8_t ibytes[3];
		uint16_t ea;
		
		// print address
                printf("%04X   ", address);                             //Display current address at beginning of line

		// "fetch" opcode", increment address by 1 (so relative branch calculations are what we want
		uint8_t opcode = buffer[i];
		address++;
		i++;
		
		// get opcode metadata
		opdata = opcode_data[opcode];
		opcodeName = opcodeNames[opcode_name_idx[opcode]];
		
		bytecount = opdata & 0x3; // get instruction length
		ibytes[0] = opcode;
		
		if(bytecount > 1)
		{
			// get low byte of parameter
			paramlo = buffer[i];
			ibytes[1] = paramlo;
			i++;
			address++;
			relbase = (int16_t)address;  // remember this for later

			if(bytecount > 2)
			{
				paramhi = buffer[i];
				ibytes[2] = paramhi;
				i++;
				address++;
			}
		}
		
		// Display opcode bytes
		for(j = 0; j < bytecount; j++)
			printf("%02X ",ibytes[j]);
		for(; j < 3; j++)
			printf("   ");
		
		// print opcode name, deal with 65C02 special cases
		printf(" %c%c%c",OPCODE_NAME(opcodeName));
		if(opcodeName & 0x8000)
		{
			uint8_t bit = (opcode >> 4) & 7;
			printf("%c  ",bit+'0');
		}
		else
		{
			printf("   ");
		}
		
		// If any parameters, deal with that now.
		if(bytecount > 1)
		{
			// BBR/BBS require special handling
			if((opcode & 0xf) == 0xf)
			{
				printf("$%02X,",paramlo);
				reloffset = ((paramhi << 8) >> 8);	// Sign extend offset to 16 bits
				ea = address+reloffset;
				goto print_ea;
			}
			else
			{
				// print addressing mode prefix
				premode = (opdata >> 5) & 0x7; 		               //Get info required to display addressing mode
				if(premode)
				{
					uint8_t prechar = prefixChars[premode-1];                               //Look up pre-operand formatting text
					if(prechar)
						printf("%c",prechar);
				}
				
				// Is this a relative argument?
				if(premode == 3)
				{
					reloffset = ((paramlo << 8) >> 8);	// Sign extend offset to 16 bits
					if(bytecount == 3)
					{
						reloffset &= 0xff;
						reloffset |= paramhi << 8;	// replace upper 8 bits of relative offset
					}
					ea = relbase + reloffset;
					goto print_ea;
				}
				else
				{
					if(bytecount < 3)
					{
						printf("$%02X",paramlo);
					}
					else
					{
						ea = paramlo | (paramhi << 8);
print_ea:
						printf("$%04X",ea);
					}
				}

				postmode = (opdata >> 2) & 0x7; 		       //Get info required to display addressing mode
				if(postmode)
				{
					post = postfixStrs[postmode-1];                              //Look up post-operand formatting text
					printf("%s",post);
				}
			}
		}
		if(premode == 3)
			printf("\t; relbase = %04x, reloffset = %04x",relbase,reloffset);
		printf("\n");
	}
        printf("%04X                .END\n", address);                    //Add .END directive to end of output
        free(buffer);                                                   //Return buffer memory to the system
        return 0;                                                       //All done, exit to the OS
    }

#endif
