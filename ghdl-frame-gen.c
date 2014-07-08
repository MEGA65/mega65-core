/*
  Generate a 32bit BMP image from GHDL output.

*/

#include <stdio.h>

unsigned char bmpHeader[0x36]={
  0x42,0x4d,0x36,0xa0,0x8c,0x00,0x00,0x00,0x00,0x00,0x36,0x00,0x00,0x00,0x28,0x00,
  0x00,0x00,0x80,0x07,0x00,0x00,0xb0,0x04,0x00,0x00,0x01,0x00,0x20,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00,0x00,0x00};

unsigned char palette[17][4]={
  {  0,  0,  0,0xff},
  {255,255,255,0xff},
  {116, 67, 53,0xff},
  {124,172,186,0xff},
  {123, 72,144,0xff},
  {100,151, 79,0xff},
  { 64, 50,133,0xff},
  {191,205,122,0xff},
  {123, 91, 47,0xff},
  { 79, 69,  0,0xff},
  {163,114,101,0xff},
  { 80, 80, 80,0xff},
  {120,120,120,0xff},
  {164,215,142,0xff},
  {120,106,189,0xff},
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
      if (x==4095&&y>=1919) {
	printf("End of frame.\n");
	fclose(out);
	return 0;
      }
    }
  }
}
