/*
  Generate a 32bit BMP image from GHDL output.

*/

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <strings.h>
#include <string.h>

#define BMP_WIDTH 860
#define BMP_HEIGHT 700

unsigned char bmpHeader[0x36] = { 0x42, 0x4d, 0x36, 0xa0, 0x8c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x36, 0x00, 0x00, 0x00, 0x28,
  0x00, 0x00, 0x00, BMP_WIDTH % 256, BMP_WIDTH / 256, 0x00, 0x00, BMP_HEIGHT % 256, BMP_HEIGHT / 256, 0x00, 0x00, 0x01, 0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

unsigned char palette[17][4] = {
	// in (B,G,R,A) format
	{ 0x00, 0x00, 0x00, 0xff },	// black
	{ 0xf0, 0xf0, 0xf0, 0xff },	// white
	{ 0x00, 0x00, 0xf0, 0xff },	// red
	{ 0xf0, 0xf0, 0x00, 0xff },	// cyan

  	{ 0xf0, 0x00, 0xf0, 0xff },	// purple
	{ 0x00, 0xf0, 0x00, 0xff },	// green
	{ 0xf0, 0x00, 0x00, 0xff },	// blue
	{ 0x00, 0xf0, 0xf0, 0xff },	// yellow

	{ 0x00, 0x60, 0xf0, 0xff },	// orange
	{ 0x00, 0x40, 0xa0, 0xff },	// brown
	{ 0x70, 0x70, 0xf0, 0xff },	// lt red (pink)
	{ 0x50, 0x50, 0x50, 0xff },	// dk grey

	{ 0x80, 0x80, 0x80, 0xff },	// grey
	{ 0x90, 0xf0, 0x90, 0xff },	// lt green
  	{ 0xf0, 0x90, 0x90, 0xff },	// lt blue
	{ 0xb0, 0xb0, 0xb0, 0xff },	// lt grey

	{ 0, 255, 0, 0xff } };

int main(int argc, char **argv)
{
  FILE *out = fopen("frame.bmp", "w");

  if (!out) {
    fprintf(stderr, "could not create frame.bmp\n");
    exit(-1);
  }

  fseek(out, 0, SEEK_SET);
  fwrite(bmpHeader, 0x36, 1, out);
  fflush(out);

  // Write pixel at end of file so that even partially drawn frames should open
  fseek(out, 0x36 + (BMP_WIDTH-1 + (BMP_HEIGHT-1) * BMP_WIDTH) * 4, SEEK_SET);
  fwrite(palette[0], 4, 1, out);

  while (1) {
    unsigned int x, y, colour, rgba;
    char line[1024];
    line[0] = 0;
    fgets(line, 1024, stdin);
    unsigned int char_pix, sprite_pix;

    // if (strstr(line,"right edge")) printf("%s",line);
    //    if (strstr(line,"SPRITE: Painting pixel using bits")) printf("%s",line);
    // if (strstr(line,"SPRITE: drawing row")) printf("%s",line);
    // if (strstr(line,"SPRITE: sprite #0 accepting data byte")) printf("%s",line);
    // if (strstr(line,"SPRITE: fetching sprite #0")) printf("%s",line);
    // if (strstr(line,"will fetch pointer value from")) printf("%s",line);
    if (strstr(line, "error:") > 0) {
      printf("%s\n", line);
    }

    if (sscanf(line,
            "src/vhdl/viciv.vhdl:%*d:%*d:@%*[^:]:(report note): SPRITE: pre_pixel_colour = $%x, postsprite_pixel_colour = $%x",
            &char_pix, &sprite_pix)
        == 2) {
      if (sprite_pix != char_pix) {
        printf("Sprite pixel colour = $%02x at (%d,%d)\n", sprite_pix, x, y);
      }
    }
    if (sscanf(line, "src/vhdl/viciv.vhdl:%*d:%*d:@%*[^:]:(report note): PIXEL (%d,%d) : colour =\\ $%x, RGBA = $%x, alpha = $%*x,", &x, &y, &colour, &rgba)
        == 4) {
      if (x < BMP_WIDTH && y < BMP_HEIGHT) {
        int address = 0x36 + (x + (BMP_HEIGHT-1 - y) * BMP_WIDTH) * 4;
        fseek(out, address, SEEK_SET);
        	printf("colour = %02x, x=%d, y=%d\n",colour, x, y); fflush(stdout);
        if (colour > 15)
          colour = 16;
        fwrite(palette[colour], 4, 1, out);
        fflush(out);
      }
      if (x == 1)
        printf("Raster %d\n", y);
      if (feof(stdin) || line[0] == 0 || (x == 4095 && y >= 1919)) {
        printf("End of frame or simulation terminated.\n");
        fclose(out);
        return 0;
      }
    }
  }
}
