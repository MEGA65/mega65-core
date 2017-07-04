/*
  Calculate MEGA65 modelines from standard video mode information.

  Takes mode lines in the format of the mythtv database (https://www.mythtv.org/wiki/Modeline_Database), e.g.:
  ModeLine "1920x1080" 148.50 1920 2008 2052 2200 1080 1084 1088 1125 -HSync -VSync
  Modeline "1920x1200" 151.138 1920 1960 1992 2040 1200 1201 1204 1232 -hsync


*/

#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>

void parse_video_mode(int b[16+5])
{
  int hpixels=b[5]+((b[7]&0xf)<<8);
  int hwidth=b[6]+((b[7]&0xf0)<<4);
  int vpixels=b[8]+((b[0xa]&0xf)<<8);
  int vheight=b[9]+((b[0xa]&0xf0)<<4);
  int hsyncadjust=b[0xb]+((b[0xc]&0xf)<<8);
  int hsync_polarity=b[0xc]&0x10;
  int vsync_polarity=b[0xc]&0x20;
  int rasters_per_vicii_raster=((b[0xc]&0xc0)>>6);
  
  float pixelclock=150000000;
  float frame_hertz=pixelclock/(hwidth*vheight);
  float hfreq=pixelclock/hwidth/1000.0;
  
  fprintf(stderr,"Video mode is %dx%d pixels, %dx%d frame, sync=%c/%c, vertical stretch=2+%d, frame rate=%.1fHz, hfreq=%.3fKHz.\n",
	  hpixels,vpixels,hwidth,vheight,
	  hsync_polarity ? '-' : '+',
	  vsync_polarity ? '-' : '+',
	  rasters_per_vicii_raster,
	  frame_hertz,hfreq);  
  return;
}


int main(int argc,char **argv)
{
  if (argc<12) {
    fprintf(stderr,"usage: modeline <modeline information>\n");
    exit(-1);
  }

  if (!strcasecmp(":ffd3075",argv[1]))
    {
      // Decode current mode info
      // e.g. from :FFD3075 80 80 97 20 30 44 02 E7 00 00 00 00 00 01 00 01
      int b[16+5];
      for(int i=0;i<16;i++) b[i+5]=strtoll(argv[i+2],NULL,16);
      parse_video_mode(b);

      return 0;
    }

  
  if (strcasecmp("modeline",argv[1])) { fprintf(stderr,"No modeline keyword.\n"); exit(-1); }
  char *modename=argv[2];
  float pixelclock=atof(argv[3]);
  int hpixels=atoi(argv[4]);
  int hsyncstart=atoi(argv[5]);
  int hsyncend=atoi(argv[6]);
  int hwidth=atoi(argv[7]);
  int vpixels=atoi(argv[8]);
  int vsyncstart=atoi(argv[9]);
  int vstncend=atoi(argv[10]);
  int vheight=atoi(argv[11]);
  int hsync_polarity=0;
  int vsync_polarity=0;
  int rasters_per_vicii_raster=((vpixels-1)/200) -2;

  for(int i=0;i<argc;i++) {
    if (!strcasecmp(argv[i],"-hsync")) hsync_polarity=1;
    if (!strcasecmp(argv[i],"-vsync")) vsync_polarity=1;
  }
  
  fprintf(stderr,"Processing video mode '%s' : %dx%d pixels, %dx%d frame, sync=%c/%c, %.2fMHz nominal pixel clock, vertical stretch=2+%d.\n\n",
	  modename,hpixels,vpixels,hwidth,vheight,
	  hsync_polarity ? '-' : '+',
	  vsync_polarity ? '-' : '+',
	  pixelclock,rasters_per_vicii_raster);  

  // Calculate modeline registers, assuming pixel clock is a match
  int b[16+5];
  b[5]=/* $D075 */	 hpixels&0xff;
  b[6]=/* $D076 */	 hwidth&0xff;
  b[7]=/* $D077 */	 ((hpixels>>8)&0xf) + ((hwidth>>4)&0xf0);
  b[8]=/* $D078 */	 vpixels&0xff;
  b[9]=/* $D079 */	 vheight&0xff;
  b[0xa]=/* $D07A */	 ((vpixels>>8)&0xf) + ((vheight>>4)&0xf0);
  b[0xb]=/* $D07B */	 0x80; // hsync adjust LSB
  b[0xc]=/* $D07C */	 0x0   // hsync adjust MSB
    + (hsync_polarity<<4)
    + (vsync_polarity<<5)
    + (rasters_per_vicii_raster <<6);
  
  printf("sffd3075 %02x %02x %02x %02x %02x %02x %02x %02x\n",
	 b[5],b[6],b[7],b[8],b[9],b[0xa],b[0xb],b[0xc]);
  parse_video_mode(b);
  
  // Then recalculate, assuming we want to match the mode exactly, and either sub- or super-sample pixels horizontally.

  float hscale=150.0 / pixelclock;
  hpixels*=hscale;
  hwidth*=hscale;

  printf("# Scaled by %.3f to match 150MHz pixel clock.\n",hscale);
  b[5]=/* $D075 */	 hpixels&0xff;
  b[6]=/* $D076 */	 hwidth&0xff;
  b[7]=/* $D077 */	 ((hpixels>>8)&0xf) + ((hwidth>>4)&0xf0);
  b[8]=/* $D078 */	 vpixels&0xff;
  b[9]=/* $D079 */	 vheight&0xff;
  b[0xa]=/* $D07A */	 ((vpixels>>8)&0xf) + ((vheight>>4)&0xf0);
  b[0xb]=/* $D07B */	 0x80; // hsync adjust LSB
  b[0xc]=/* $D07C */	 0x0   // hsync adjust MSB
    + (hsync_polarity<<4)
    + (vsync_polarity<<5)
    + (rasters_per_vicii_raster <<6);

  printf("\nsffd3075 %02x %02x %02x %02x %02x %02x %02x %02x\n",
	 b[5],b[6],b[7],b[8],b[9],b[0xa],b[0xb],b[0xc]);
  parse_video_mode(b);
    
  return 0;
}
