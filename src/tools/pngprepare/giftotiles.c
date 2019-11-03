#include <stdio.h>
#include <stdlib.h>
#include <gif_lib.h>

int main(int argc,char **argv)
{
  int gif_error=0;
  GifFileType* gif = NULL;

  gif = DGifOpenFileName(argv[1], &gif_error);
  if (!gif) {
    fprintf(stderr,"Could not read GIF file '%s'\n",argv[1]);
    exit(-1);
  }
  fprintf(stderr,"Read GIF of %d x %d pixels, %d frames\n",
	  gif->SWidth,gif->SHeight,gif->ImageCount);
  if (DGifSlurp(gif)!=GIF_OK) {
    fprintf(stderr,"DGifSlurp() failed.\n");
    exit(-1);
  }
  
  
  return 0;
}
