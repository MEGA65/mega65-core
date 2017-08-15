#include <stdio.h>
#include <stdlib.h>

#define PNG_DEBUG 3
#include <png.h>

unsigned char frame[640][480];

int main(int argc,char **argv)
{
  int x,y,p;

  char line[1024];
  
  for(x=0;x<640;x++)
    for(y=0;y<480;y++)
      frame[x][y]=0;

  line [0]=0; fgets(line,1024,stdin);
  while(line[0]) {
    if (sscanf(line,"vhdl/visual_keyboard.vhdl:%*[^:]:%*d:%*[^:]:(report note): PIXEL:%d:%d:'%d'",
	       &x,&y,&p)==3)
      if (x>=0&&x<640&&y>=0&&y<480) {
	frame[x][y]=p;
      }

    if (x==640&&y==480) break;
    
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
    unsigned char buffer[640*4];
    for(x=0;x<640;x++) {
      if (frame[x][y]) printf("x=%d,y=%d\n",x,y);
      buffer[4*x+0]=frame[x][y]?0xff:0; // red
      buffer[4*x+1]=frame[x][y]?0xff:0; // green
      buffer[4*x+2]=frame[x][y]?0xff:0; // blue
      buffer[4*x+3]=0xff; // alpha
    }
    png_write_row(png,buffer);
  }

  png_write_end(png,info);
  
  return 0;
}
