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
  fprintf(stderr,"Read GIF of %d x %d pixels.\n",
	  gif->SWidth,gif->SHeight);

  return 0;
}
