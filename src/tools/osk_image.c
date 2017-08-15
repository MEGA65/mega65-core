#include <stdio.h>
#include <stdlib.h>

#define PNG_DEBUG 3
#include <png.h>

unsigned char frame[480][640*4];

int main(int argc,char **argv)
{
  int x,y,r,g,b;

  char line[1024];

  printf("Clear frame...\n");
  
  for(y=0;y<480;y++)
    for(x=0;x<640*4;x++)
      frame[y][x]=0;

  printf("Read pixels...\n");

  line [0]=0; fgets(line,1024,stdin);
  while(line[0]) {
    if (sscanf(line,"%*[^\\.].vhdl:%*[^:]:%*d:%*[^:]:(report note): PIXEL:%d:%d:%x:%x:%x",
	       &x,&y,&r,&g,&b)==5) {
      if (x>=0&&x<640&&y>=0&&y<480) {
	frame[y][x*4+0]=r;
	frame[y][x*4+1]=g;
	frame[y][x*4+2]=b;
	frame[y][x*4+3]=0xff;
      }
      if (x==640&&y==480) {
	printf("Stopping on %s",line);
	break;
      }
    } else printf("%s",line);      

    line [0]=0; fgets(line,1024,stdin);
  }
  
  png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING,NULL,NULL,NULL);
  if (!png) abort();

  png_infop info = png_create_info_struct(png);
  if (!info) abort();

  if (setjmp(png_jmpbuf(png))) abort();

  FILE *f=fopen("oskimage.png","wb");
  if (!f) abort();

  png_init_io(png,f);

  png_set_IHDR(
	       png,
	       info,
	       640,480,
	       8,
	       PNG_COLOR_TYPE_RGBA,
	       PNG_INTERLACE_NONE,
	       PNG_COMPRESSION_TYPE_BASE,
	       PNG_FILTER_TYPE_DEFAULT
	       );

  png_write_info(png,info);

  for(y=0;y<480;y++) {
    png_write_row(png,frame[y]);
  }

  png_write_end(png,info);
  
  return 0;
}
