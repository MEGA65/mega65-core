/*
  Generate a 32bit BMP image from GHDL output.

*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <strings.h>
#include <string.h>

unsigned char bmpHeader[0x36]={
  0x42,0x4d,0x36,0xa0,0x8c,0x00,0x00,0x00,0x00,0x00,0x36,0x00,0x00,0x00,0x28,0x00,
  0x00,0x00,0x80,0x07,0x00,0x00,0xb0,0x04,0x00,0x00,0x01,0x00,0x20,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x00};

unsigned char palette[17][4]={
  {  0,  0,  0,0xff},
  {255,255,255,0xff},
  { 53, 67,116,0xff},
  {186,172,124,0xff},
  {144, 72,123,0xff},
  { 79,151,100,0xff},
  {133, 50, 64,0xff},
  {122,205,191,0xff},
  { 47, 91,123,0xff},
  {  0, 69, 79,0xff},
  {101,114,163,0xff},
  { 80, 80, 80,0xff},
  {120,120,120,0xff},
  {142,215,164,0xff},
  {189,106,120,0xff},
  {159,159,159,0xff},
  {  0,  255,  0,0xff}
};

int main(int argc,char **argv)
{
  FILE *out=fopen("frame.bmp","w");

  if (!out) {
    fprintf(stderr,"could not create frame.bmp\n");
    exit(-1);
  }

  fseek(out,0,SEEK_SET);
  fwrite(bmpHeader,0x36,1,out);
  fflush(out);

  // Write pixel at end of file so that even partially drawn frames should open
  fseek(out,0x36 + (1919 + 1199*1920) * 4,SEEK_SET);
  fwrite(palette[0],4,1,out);

  while(1) {
    unsigned int x,y,colour,rgba;
    char line[1024]; line[0]=0; fgets(line,1024,stdin); 
    unsigned int char_pix,sprite_pix;

    // if (strstr(line,"right edge")) printf("%s",line);
    //    if (strstr(line,"SPRITE: Painting pixel using bits")) printf("%s",line);
    // if (strstr(line,"SPRITE: drawing row")) printf("%s",line);
    // if (strstr(line,"SPRITE: sprite #0 accepting data byte")) printf("%s",line);
    // if (strstr(line,"SPRITE: fetching sprite #0")) printf("%s",line);
    // if (strstr(line,"will fetch pointer value from")) printf("%s",line);

    if (sscanf(line,"viciv.vhdl:%*d:%*d:@%*[^:]:(report note): SPRITE: pre_pixel_colour = $%x, postsprite_pixel_colour = $%x",&char_pix,&sprite_pix)==2)
      {
	if (sprite_pix!=char_pix) {
	  printf("Sprite pixel colour = $%02x at (%d,%d)\n",
		 sprite_pix,x,y);
	}
      }
    if (sscanf(line,"viciv.vhdl:%*d:%*d:@%*[^:]:(report note): PIXEL (%d,%d) = $%x, RGBA = $%x",
	       &x,&y,&colour,&rgba)==4) {
      if (x<1920&&y<1200) {
	int address = 0x36 + (x + (1199-y) * 1920) *4;
	fseek(out,address,SEEK_SET);
	//	printf("%02x",colour); fflush(stdout);
	if (colour>15) colour=16;
	fwrite(palette[colour],4,1,out);
	fflush(out);
      }
      if (x==1) printf("Raster %d\n",y);
      if (feof(stdin)||line[0]==0||(x==4095&&y>=1919)) {
	printf("End of frame or simulation terminated.\n");
	fclose(out);
	return 0;
      }
    }
  }
}
