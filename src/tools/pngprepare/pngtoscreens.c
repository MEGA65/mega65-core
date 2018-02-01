/*
 * Copyright 2002-2010 Guillaume Cottenceau.
 * Copyright 2015-2018 Paul Gardner-Stephen.
 *
 * This software may be freely redistributed under the terms
 * of the X11 license.
 *
 */

/* ============================================================= */

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <stdarg.h>

#define PNG_DEBUG 3
#include <png.h>

/* ============================================================= */

char *vhdl_prefix=
  "library IEEE;\n"
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
  "PROCESS(Clk,ram,writeclk)\n"
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

/* ============================================================= */

int x, y;

int width, height;
png_byte color_type;
png_byte bit_depth;

png_structp png_ptr;
png_infop info_ptr;
int number_of_passes;
png_bytep * row_pointers;
int multiplier;

/* ============================================================= */

void abort_(const char * s, ...)
{
  va_list args;
  va_start(args, s);
  vfprintf(stderr, s, args);
  fprintf(stderr, "\n");
  va_end(args);
  abort();
}

/* ============================================================= */

struct tile {
  unsigned char bytes[8][8];
};

struct rgb {
  int r;
  int g;
  int b;
};

struct tile_set {
  struct tile *tiles;
  int tile_count;
  int max_tiles;

  // Palette
  struct rgb colours[256];
  int colour_count;
  
  struct tile_set *next;
};

int palette_lookup(struct tile_set *ts,int r,int g, int b)
{
  int i;

  // Do we know this colour already?
  for(i=0;i<ts->colour_count;i++) {
    if (r==ts->colours[i].r
	&&g==ts->colours[i].g
	&&b==ts->colours[i].b) {
      // It's a colour we have seen before, so return the index
      return i;
    }
  }
  
  // new colour, check if palette has space
  if (ts->colour_count>255) {
    fprintf(stderr,"Too many colours in image: Must be <= %d\n",
	    256);
    exit(-1);
  }

  // allocate the new colour
  ts->colours[ts->colour_count].r=r;
  ts->colours[ts->colour_count].g=g;
  ts->colours[ts->colour_count].b=b;
  return ts->colour_count++;  
}

unsigned char nyblswap(unsigned char in)
{
  return ((in&0xf)<<4)+((in&0xf0)>>4);
}

struct tile_set *new_tileset(int max_tiles)
{
  struct tile_set *ts=calloc(sizeof(struct tile_set),1);
  if (!ts) { perror("calloc() failed"); exit(-3); }
  ts->tiles=calloc(sizeof(struct tile),max_tiles);
  if (!ts->tiles) { perror("calloc() failed"); exit(-3); }
  ts->max_tiles=max_tiles;
  return ts;  
}

struct screen {
  // Unique identifier
  unsigned char screen_id;
  // Which tile set the screen uses
  struct tile_set *tiles;
  unsigned char width,height;
  unsigned char **screen_rows;
  unsigned char **colourram_rows;

  struct screen *next;
};

struct screen *new_screen(int id,struct tile_set *tiles,int width,int height)
{
  struct screen *s=calloc(sizeof(struct screen),1);
  if (!s) {
    perror("calloc() failed");
    exit(-3);
  }

  if ((width<1)||(width>255)||(height<1)|(height>255)) {
    fprintf(stderr,"Illegal screen dimensions, must be 1-255 x 1-255 characters.\n");
    exit(-3);
  }
  
  s->screen_id=id;
  s->tiles=tiles;
  s->width=width;
  s->height=height;
  s->screen_rows=calloc(sizeof(unsigned char *),height);
  s->colourram_rows=calloc(sizeof(unsigned char *),height);
  if ((!s->screen_rows)||(!s->colourram_rows)) {
    perror("calloc() failed");
    exit(-3);
  }
  for(int i=0;i<height;i++) {
    s->screen_rows[i]=calloc(sizeof(unsigned char)*2,width);
    s->colourram_rows[i]=calloc(sizeof(unsigned char)*2,width);
    if ((!s->screen_rows[i])||(!s->colourram_rows[i])) {
      perror("calloc() failed");
      exit(-3);
    }
  }
  
  return s;
}

int tile_lookup(struct tile_set *ts,struct tile *t)
{
  // See if tile matches any that we have already stored.
  // (Also check if it matches flipped in either or both X,Y
  // axes.
  for(int i=0;i<ts->tile_count;i++)
    {
      int matches=1;
      // Compare unflipped
      for(int y=0;y<8;y++)
	for(int x=0;x<8;x++)
	  if (ts->tiles[i].bytes[x][y]!=t->bytes[x][y]) {
	    matches=0; break;
	  }
      if (matches) return i;
      // Compare with flipped X
      for(int y=0;y<8;y++)
	for(int x=0;x<8;x++)
	  if (ts->tiles[i].bytes[x][y]!=t->bytes[7-x][y]) {
	    matches=0; break;
	  }
      if (matches) return i|0x4000;
      // Compare with flipped Y
      for(int y=0;y<8;y++)
	for(int x=0;x<8;x++)
	  if (ts->tiles[i].bytes[x][y]!=t->bytes[x][7-y]) {
	    matches=0; break;
	  }
      if (matches) return i|0x8000;
      // Compare with flipped X and Y
      for(int y=0;y<8;y++)
	for(int x=0;x<8;x++)
	  if (ts->tiles[i].bytes[x][y]!=t->bytes[7-x][7-y]) {
	    matches=0; break;
	  }
      if (matches) return i|0xC000;           
    }

  // The tile is new.
  if (ts->tile_count>=ts->max_tiles) {
    fprintf(stderr,"ERROR: Used up all %d tiles.\n",
	    ts->max_tiles);
    exit(-3);
  }

  // Allocate new tile and return
  for(int y=0;y<8;y++)
    for(int x=0;x<8;x++)
      ts->tiles[ts->tile_count].bytes[x][y]=t->bytes[x][y];
  return ts->tile_count++;
}

struct screen *png_to_screen(int id,struct tile_set *ts)
{
  int x,y;

  if (height%8||width%8) {
    fprintf(stderr,"ERROR: PNG image dimensions must be a multiple of 8.\n");
    exit(-3);
  }

  struct screen *s=new_screen(id,ts,width/8,height/8);
  
  for(y=0;y<height;y+=8)
    for(x=0;x<width;x+=8)
      {
	int transparent_tile=1;
	struct tile t;
	for(int yy=0;yy<8;yy++) {
	  png_byte* row = row_pointers[yy+y];
	  for(int xx=0;xx<8;xx++)
	    {
	      png_byte* ptr = &(row[x*multiplier]);	      
	      int r,g,b,a,c;
	      r=ptr[0];
	      g=ptr[1];
	      b=ptr[2];
	      if (multiplier==4) a=ptr[3]; else a=0xff;
	      if (a) {
		transparent_tile=0;
		c=palette_lookup(ts,r,g,b);
	      } else c=0;
	      t.bytes[xx][yy]=c;
	    }
	}
	if (transparent_tile) {
	  // Set screen and colour bytes to all $00 to indicate
	  // non-set block.
	  s->screen_rows[y/8][x*2+0]=0x00;
	  s->screen_rows[y/8][x*2+1]=0x00;
	  s->colourram_rows[y/8][x*2+0]=0x00;
	  s->colourram_rows[y/8][x*2+1]=0x00;
	} else {
	  // Block has non-transparent pixels, so add to tileset,
	  // or lookup to see if it is already there.
	  int tile_number=tile_lookup(ts,&t);
	  s->screen_rows[y/8][x/8*2+0]=tile_number&0xff;
	  s->screen_rows[y/8][x/8*2+1]=(tile_number>>8)&0xff;
	  s->colourram_rows[y/8][x/8*2+0]=0x00;
	  s->colourram_rows[y/8][x/8*2+1]=0xff; // FG colour
	}
      }
  return s;
}


void read_png_file(char* file_name)
{
  unsigned char header[8];    // 8 is the maximum size that can be checked

  /* open file and test for it being a png */
  FILE *infile = fopen(file_name, "rb");
  if (infile == NULL)
    abort_("[read_png_file] File %s could not be opened for reading", file_name);

  fread(header, 1, 8, infile);
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

  png_init_io(png_ptr, infile);
  png_set_sig_bytes(png_ptr, 8);

  // Convert palette to RGB values
  png_set_expand(png_ptr);

  png_read_info(png_ptr, info_ptr);

  width = png_get_image_width(png_ptr, info_ptr);
  height = png_get_image_height(png_ptr, info_ptr);
  color_type = png_get_color_type(png_ptr, info_ptr);
  bit_depth = png_get_bit_depth(png_ptr, info_ptr);

  printf("Input-file is: width=%d, height=%d.\n", width, height);

  number_of_passes = png_set_interlace_handling(png_ptr);
  png_read_update_info(png_ptr, info_ptr);

  /* read file */
  if (setjmp(png_jmpbuf(png_ptr)))
    abort_("[read_png_file] Error during read_image");

  row_pointers = (png_bytep*) malloc(sizeof(png_bytep) * height);
  for (y=0; y<height; y++)
    row_pointers[y] = (png_byte*) malloc(png_get_rowbytes(png_ptr,info_ptr));

  png_read_image(png_ptr, row_pointers);

  if (infile != NULL) {
    fclose(infile);
    infile = NULL;
  }

  if (png_get_color_type(png_ptr, info_ptr) == PNG_COLOR_TYPE_RGB)
    multiplier=3;
  else if (png_get_color_type(png_ptr, info_ptr) == PNG_COLOR_TYPE_RGBA)
    multiplier=4;
  else {
    fprintf(stderr,"Could not convert file to RGB or RGBA\n");
    exit(-3);
  }

  return;
}

/* ============================================================= */

int main(int argc, char **argv)
{
  int i,x,y;
  
  if (argc <3) {
    fprintf(stderr,"Usage: pngtoscreens <output file> <png file ...>\n");
    exit(-1);
  }

  FILE *outfile=fopen(argv[1],"w");
  if (!outfile) {
    perror("Could not open output file");
    exit(-3);
  }

  // Allow upto 128KB of tiles (we will complain later when
  // saving out, if the whole thing is too big).
  struct tile_set *ts=new_tileset(2048);

  struct screen *screen_list[256];
  int screen_count=0;

  if (argc>255) {
    fprintf(stderr,"ERROR: Too many input files. Maximum of 250 PNG files.\n");
    exit(-3);
  }

  int image_tiles=0;
  
  for(int i=2;i<argc;i++) {
    printf("Reading %s\n",argv[i]);
    read_png_file(argv[i]);
    image_tiles+=width*height/64;
    struct screen *s = png_to_screen(i-1,ts);
    screen_list[screen_count++]=s;
  }

  printf("Images consists of %d tiles (%d unique) and %d unique colours found.\n",
	 image_tiles,ts->tile_count,ts->colour_count);

  // Write out tile set structure
  /*
    Tile set consists of:
    64 byte header
    header + 0-15 = magic string "MEGA65 TILESET00" [becomes tokenised ID after loading]
    header + 16,17 = tile count
    header + 18 = number of palette slots used
    [ header + 19,20 = first tile number (set only when loaded) ]
    
    header + 61-63 = size of section in bytes [becomes pointer to next section after loading]
    3x256 bytes palette values
    Tiles, 64 bytes each.
  */
  printf("Writing headers...\n");
  unsigned char header[64];
  bzero(header,sizeof(header));
  snprintf((char *)header,64,"MEGA65 TILESET00");
  header[16]=ts->tile_count&0xff;
  header[17]=(ts->tile_count>>8)&0xff;
  header[18]=ts->colour_count;
  unsigned size = 64 + 256 + 256 + 256 + (ts->tile_count * 64);
  header[61]=(size>>00)&0xff;
  header[62]=(size>>8)&0xff;
  header[63]=(size>>16)&0xff;
  fwrite(header,64,1,outfile);
  unsigned char paletteblock[256];
  for(i=0;i<256;i++) paletteblock[i]=nyblswap(ts->colours[i].r);
  fwrite(paletteblock,256,1,outfile);
  for(i=0;i<256;i++) paletteblock[i]=nyblswap(ts->colours[i].g);
  fwrite(paletteblock,256,1,outfile);
  for(i=0;i<256;i++) paletteblock[i]=nyblswap(ts->colours[i].b);
  fwrite(paletteblock,256,1,outfile);

  printf("Writing tiles"); fflush(stdout);
  for(i=0;i<ts->tile_count;i++) {
    unsigned char tile[64];
    for(y=0;y<8;y++)
      for(x=0;x<8;x++)
	tile[y*8+x]=ts->tiles[i].bytes[x][y];
    fwrite(tile,64,1,outfile);
    printf("."); fflush(stdout);
  }
  printf("\n");

  // Write out screen structures
  /* 
    Screen consists of
    64 byte header
    header + 0-14 = magic string "MEGA65 SCREEN00" [becomes tokenised ID after loading]
    header + 15 = screen ID number
    header + 16 = width
    header + 17 = height
    
    header + 18-20 = offset of screenram rows [becomes absolute pointer after loading]
    header + 21-24 = offset of colourram rows [becomes absolute pointer after loading]

    header + 61-63 = size of section in bytes [becomes pointer to next section after loading]

    screenram bytes (2 bytes x width) x height [get resolved to absolute tile numbers after loading]
    colourram bytes (2 bytes x width) x height     
  */
  printf("Writing screens"); fflush(stdout);
  for(i=0;i<screen_count;i++)
    {
      unsigned char header[64];
      bzero(header,sizeof(header));
      snprintf((char *)header,64,"MEGA65 SCREEN00");
      header[15]=screen_list[i]->screen_id;
      header[16]=screen_list[i]->width;
      header[17]=screen_list[i]->height;
      unsigned int screenram_rows_offset
	= 64;
      unsigned int colourram_rows_offset
	= screenram_rows_offset + (2*screen_list[i]->width)*screen_list[i]->height;
      unsigned int size = colourram_rows_offset + (2*screen_list[i]->width)*screen_list[i]->height;
      header[61]=(size>>0)&0xff;
      header[62]=(size>>8)&0xff;
      header[63]=(size>>16)&0xff;
      fwrite(header,64,1,outfile);
      for(y=0;y<screen_list[i]->height;y++)
	fwrite(screen_list[i]->screen_rows[y],2*screen_list[i]->width,1,outfile);
      for(y=0;y<screen_list[i]->height;y++)
	fwrite(screen_list[i]->colourram_rows[y],2*screen_list[i]->width,1,outfile);
      printf("."); fflush(stdout);
    }
  printf("\n");

  /* Finish off with a null header */
  printf("Adding end of file marker.\n");
  bzero(header,sizeof(header));
  fwrite(header,64,1,outfile);
  
  long length = ftell(outfile);
  printf("Wrote %d bytes\n",(int)length);
  
  if (outfile != NULL) {
    fclose(outfile);
    outfile = NULL;
  }

  return 0;
}

/* ============================================================= */
