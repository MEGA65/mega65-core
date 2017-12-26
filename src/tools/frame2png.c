#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define PNG_DEBUG 3
#include <png.h>

#define MAXX 800
#define MAXY 600
unsigned char frame[MAXY][MAXX*4];

int maxx=0;
int maxy=0;

int image_number=0;

void write_image(int image_number);

int main(int argc,char **argv)
{
  int x,y,r,g,b;

  char line[1024];

  printf("Clear frame...\n");
  
  for(y=0;y<MAXY;y++)
    for(x=0;x<MAXX*4;x++)
      frame[y][x]=0;

  printf("Read pixels...\n");

  line [0]=0; fgets(line,1024,stdin);
  unsigned int rgba,p;
  while(line[0]) {
    if (sscanf(line,"%*[^\\.].vhdl:%*[^:]:%*d:%*[^:]:(report note): PIXEL (%d,%d) = $%x, RGBA = $%x",
	       &x,&y,&p,&rgba)==4) {
      r=(rgba>>24)&0xff;
      g=(rgba>>16)&0xff;
      b=(rgba>>8)&0xff;
      //      printf("x=%d,y=%d, max=%d,%d\n",x,y,maxx,maxy);
      if (y<maxy) {
	printf("Writing image %d\n",++image_number);
	write_image(image_number);
	// Clear frame for next one
	maxx=0; maxy=0;
	for(y=0;y<MAXY;y++)
	  for(x=0;x<MAXX*4;x++)
	    frame[y][x]=0;	
      }
      if (x>=0&&x<MAXX&&y>=0&&y<MAXY) {
	frame[y][x*4+0]=r;
	frame[y][x*4+1]=g;
	frame[y][x*4+2]=b;
	frame[y][x*4+3]=0xff;
	if (x>maxx) maxx=x;
	if (y>maxy) maxy=y;
      }
      if (x==20&&(maxy>1)) {
	// Save image progressively as each line written
	printf("  Writing raster %d\n",y-1);
	write_image(image_number);
      }
    } // else printf("%s",line);      

    line [0]=0; fgets(line,1024,stdin);
  }
  return 0;
}
  
void write_image(int image_number)
{
  int y;
  png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING,NULL,NULL,NULL);
  if (!png) abort();

  png_infop info = png_create_info_struct(png);
  if (!info) abort();

  if (setjmp(png_jmpbuf(png))) abort();

  char filename[1024];
  snprintf(filename,1024,"frame-%d.png",image_number);
  FILE *f=fopen(filename,"wb");
  if (!f) abort();

  png_init_io(png,f);

  png_set_IHDR(
	       png,
	       info,
	       MAXX,MAXY,
	       8,
	       PNG_COLOR_TYPE_RGBA,
	       PNG_INTERLACE_NONE,
	       PNG_COMPRESSION_TYPE_BASE,
	       PNG_FILTER_TYPE_DEFAULT
	       );

  png_write_info(png,info);

  for(y=0;y<maxy;y++) {
    //    printf("  writing y=%d\n",y);
    fflush(stdout);
    png_write_row(png,frame[y]);
  }
  unsigned char empty_row[MAXX*4];
  bzero(empty_row,sizeof(empty_row));
  for(;y<1024;y++) {
    png_write_row(png,empty_row);
  }

  png_write_end(png,info);
  fclose(f);
  
  return;
}
