/*
 * Copyright 2002-2010 Guillaume Cottenceau.
 * Copyright 2015 Paul Gardner-Stephen.
 *
 * This software may be freely redistributed under the terms
 * of the X11 license.
 *
 */

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#define PNG_DEBUG 3
#include <png.h>

char *vhdl_prefix="library IEEE;\n"
  "use IEEE.STD_LOGIC_1164.ALL;\n"
  "use ieee.numeric_std.all;\n"
  "use work.debugtools.all;\n"
  "\n"
  "--\n"
  "entity charrom is\n"
  "port (Clk : in std_logic;\n"
  "        address : in integer range 0 to 4095;\n"
  "        -- chip select, active low       \n"
  "        cs : in std_logic;\n"
  "        data_o : out std_logic_vector(7 downto 0);\n"
  "\n"
  "        writeclk : in std_logic;\n"
  "        -- Yes, we do have a write enable, because we allow modification of ROMs\n"
  "        -- in the running machine, unless purposely disabled.  This gives us\n"
  "        -- something like the WOM that the Amiga had.\n"
  "        writecs : in std_logic;\n"
  "        we : in std_logic;\n"
  "        writeaddress : in unsigned(11 downto 0);\n"
  "        data_i : in std_logic_vector(7 downto 0)\n"
  "      );\n"
  "end charrom;\n"
  "\n"
  "architecture Behavioral of charrom is\n"
  "\n"
  "-- 4K x 8bit pre-initialised RAM for character ROM\n"
  "\n"
  "type ram_t is array (0 to 4095) of std_logic_vector(7 downto 0);\n"
  "signal ram : ram_t := (\n"
  "\n";
char *vhdl_suffix=
  ");\n"
  "\n"
  "begin\n"
  "\n"
  "--process for read and write operation.\n"
  "PROCESS(Clk)\n"
  "BEGIN\n"
  "  data_o <= ram(address);          \n"
  "\n"
  "  if(rising_edge(writeClk)) then \n"
  "    if writecs='1' then\n"
  "      if(we='1') then\n"
  "        ram(to_integer(writeaddress)) <= data_i;\n"
  "      end if;\n"
  "    end if;\n"
  "  end if;\n"
  "END PROCESS;\n"
  "\n"
  "end Behavioral;\n";


void abort_(const char * s, ...)
{
  va_list args;
  va_start(args, s);
  vfprintf(stderr, s, args);
  fprintf(stderr, "\n");
  va_end(args);
  abort();
}

int x, y;

int width, height;
png_byte color_type;
png_byte bit_depth;

png_structp png_ptr;
png_infop info_ptr;
int number_of_passes;
png_bytep * row_pointers;

void read_png_file(char* file_name)
{
  unsigned char header[8];    // 8 is the maximum size that can be checked

  /* open file and test for it being a png */
  FILE *fp = fopen(file_name, "rb");
  if (!fp)
    abort_("[read_png_file] File %s could not be opened for reading", file_name);
  fread(header, 1, 8, fp);
  if (png_sig_cmp(header, 0, 8))
    abort_("[read_png_file] File %s is not recognized as a PNG file", file_name);


  /* initialize stuff */
  png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);

  if (!png_ptr)
    abort_("[read_png_file] png_create_read_struct failed");

  info_ptr = png_create_info_struct(png_ptr);
  if (!info_ptr)
    abort_("[read_png_file] png_create_info_struct failed");

  if (setjmp(png_jmpbuf(png_ptr)))
    abort_("[read_png_file] Error during init_io");

  png_init_io(png_ptr, fp);
  png_set_sig_bytes(png_ptr, 8);

  // Convert palette to RGB values
  png_set_expand(png_ptr);

  png_read_info(png_ptr, info_ptr);

  width = png_get_image_width(png_ptr, info_ptr);
  height = png_get_image_height(png_ptr, info_ptr);
  color_type = png_get_color_type(png_ptr, info_ptr);
  bit_depth = png_get_bit_depth(png_ptr, info_ptr);

  number_of_passes = png_set_interlace_handling(png_ptr);
  png_read_update_info(png_ptr, info_ptr);

  /* read file */
  if (setjmp(png_jmpbuf(png_ptr)))
    abort_("[read_png_file] Error during read_image");

  row_pointers = (png_bytep*) malloc(sizeof(png_bytep) * height);
  for (y=0; y<height; y++)
    row_pointers[y] = (png_byte*) malloc(png_get_rowbytes(png_ptr,info_ptr));

  png_read_image(png_ptr, row_pointers);

  fclose(fp);
}

void process_file(int mode,char *outputfilename)
{
  int multiplier=-1;
  if (png_get_color_type(png_ptr, info_ptr) == PNG_COLOR_TYPE_RGB)
    multiplier=3;
    
  if (png_get_color_type(png_ptr, info_ptr) == PNG_COLOR_TYPE_RGBA)
    multiplier=4;

  if (multiplier==-1) {
    fprintf(stderr,"Could not convert file to RGB or RGBA\n");
  }

  if (mode==0) {
    // Logo mode
    FILE *outfile=fopen(outputfilename,"w");
    if (height!=64||width!=64) {
      fprintf(stderr,"Logo images must be 64x64\n");
    }
    for (y=0; y<height; y++) {
      png_byte* row = row_pointers[y];
      for (x=0; x<width; x++) {
	png_byte* ptr = &(row[x*multiplier]);
	int r=ptr[0],g=ptr[1],b=ptr[2]; // a=ptr[3];

	// Compute colour cube colour
	unsigned char c=(r&0xe0)|((g>>5)<<2)|(b>>6);

	/* work out where in logo file it must be written.
	   image is made of 8x8 blocks.  So every 8 pixels across increases address
	   by 64, and every 8 pixels down increases pixel count by (64*8), and every
	   single pixel down increases address by 8.
	*/
	int address=(x&7)+(y&7)*8;
	address+=(x>>3)*64;
	address+=(y>>3)*64*8;
	fseek(outfile,address,SEEK_SET);
	int n=fwrite(&c,1,1,outfile);
	if (n!=1) {
	  fprintf(stderr,"Could not write pixel (%d,%d) @ $%x\n",x,y,address);
	  exit(-1);
	}
      }
    }
    fclose(outfile);
  }

  if (mode==1) {
    // charrom mode
    int bytes=0;
    FILE *outfile=fopen(outputfilename,"w");
    fprintf(outfile,"%s",vhdl_prefix);
    if (width!=8) {
      fprintf(stderr,"Fonts must be 8 pixels wide\n");
    }

    int spots[8][8];

    for (y=0; y<height; y++) {
      png_byte* row = row_pointers[y];
      int byte=0;
      
      int yy=y&7;
      for (x=0; x<width; x++) {
	png_byte* ptr = &(row[x*multiplier]);
	int r=ptr[0]; // g=ptr[1],b=ptr[2], a=ptr[3];

	if (x<8) {
	  if (r>0x7f) {
	    byte|=(1<<(7-x));
	    spots[yy][x]=1;
	  } else spots[yy][x]=0;
	}
	
      }
      fflush(stdout);
      char comma = ',';
      if (y==height-1) comma=' ';
      fprintf(outfile,"x\"%02x\"%c",byte,comma);
      bytes++;
      if ((y&7)==7) {
	fprintf(outfile,"\n");
	int yy;
	for(yy=0;yy<8;yy++) {
	  fprintf(outfile,"-- [");
	  for(x=0;x<8;x++) {
	    if (spots[yy][x]) fprintf(outfile,"*"); else fprintf(outfile," ");	    
	  }
	  fprintf(outfile,"]\n");
	}
      }
    }
    // Fill in any missing bytes
    if (bytes<4096) {
      fprintf(outfile,",\n");
      for(;bytes<4096;bytes+=8) {
	fprintf(outfile,"x\"00\",x\"00\",x\"00\",x\"00\",x\"00\",x\"00\",x\"00\",x\"00\"%c\n",
		bytes<(4096-8)?',':' ');
      }
    }
    fprintf(outfile,"%s",vhdl_suffix);
    fclose(outfile);
  }

  if (mode==2) {
    // hi-res image preparation mode
    // int bytes=0;
    if (width%8||height%8) {
      fprintf(stderr,"Image must be multiple of 8 pixels wide and high\n");
    }
    int problems=0;
    int total=0;
    int threes=0;
    int fours=0;
    int ones=0;

    int tiles[8000][8][8];
    int tile_count=0;

    int this_tile[8][8];
    
    for (y=0; y<height; y+=8) {
      for (x=0; x<width; x+=8) {
	int yy,xx;
	int i;
	int colour_count=0;
	int colours[64];

	printf("[%d,%d]\n",x,y);
	
	total++;
	
	for(yy=y;yy<y+8;yy++) {
	  png_byte* row = row_pointers[yy];
	  for(xx=x;xx<x+8;xx++) {
	    png_byte* ptr = &(row[xx*multiplier]);
	    int r=ptr[0], g=ptr[1],b=ptr[2]; // , a=ptr[3];
	    int c=r+256*g+65536*b;
	    this_tile[yy-y][xx-x]=c;
	    for(i=0;i<colour_count;i++) if (c==colours[i]) break;
	    if (i==colour_count) {
	      colours[colour_count++]=c;
	    }
	  }
	}

	for(i=0;i<tile_count;i++) {
	  int dud=0;
	  int xx,yy;
	  for(xx=0;xx<8;xx++)
	    for(yy=0;yy<8;yy++) {
	      if (this_tile[yy][xx]!=tiles[i][yy][xx]) dud=1;
	    }
	  if (!dud) break;
	}
	if (i==tile_count) {
	  int xx,yy;
	  for(xx=0;xx<8;xx++)
	    for(yy=0;yy<8;yy++) {
	      tiles[tile_count][yy][xx]=this_tile[yy][xx];
	    }
	  printf(".[%d]",tile_count); fflush(stdout);
	  tile_count++;
	  if (tile_count>=8000) {
	    fprintf(stderr,"Too many tiles\n");
	    exit(-1);
	  }
	}
	
	if (colour_count==1) ones++;
	if (colour_count==3) threes++;
	if (colour_count==4) fours++;
	if (colour_count>2) {
	  printf("%d colours in card\n",colour_count);
	  problems++;
	}
      }
    }
    printf("%d problem tiles out of %d total tiles\n",problems,total);
    printf("%d with 3, %d with 4, %d with only one colour\n",threes,fours,ones);
    printf("%d unique tiles\n",tile_count);
  }
      
}


int main(int argc, char **argv)
{
  if (argc != 4) {
    fprintf(stderr,"Usage: program_name <logo|charrom> <file_in> <file_out>\n");
    exit(-1);
  }

  int mode=-1;

  if (!strcasecmp("logo",argv[1])) mode=0;
  if (!strcasecmp("charrom",argv[1])) mode=1;
  if (!strcasecmp("hires",argv[1])) mode=2;
  if (mode==-1) {
    fprintf(stderr,"Usage: program_name <logo|charrom> <file_in> <file_out>\n");
    exit(-1);
  }
  read_png_file(argv[2]);
  process_file(mode,argv[3]);

  return 0;
}
