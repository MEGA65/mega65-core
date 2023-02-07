/*
  Simple program to take multiple lines of input on stdin,
  and output them as constant width lines without CR or LF
  between them.  This is used to make the default banner
  message in the matrix mode overlay display.

*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
  if (argc != 3) {
    fprintf(stderr, "usage: format_banner <outfile> <columns per line>\n");
    if (argc > 1)
      unlink(argv[1]);
    exit(-1);
  }

  int cols = atoi(argv[2]);
  if (cols < 1 || cols > 999) {
    fprintf(stderr, "Columns per line should be between 1 and 999.\n");
    unlink(argv[1]);
    exit(-2);
  }

  FILE *f = fopen(argv[1], "w");
  if (!f) {
    perror("fopen");
    fprintf(stderr, "Failed to open output file '%s' for writing.\n", argv[1]);
    unlink(argv[1]);
    exit(-3);
  }

  char line[1024];
  line[0] = 0;
  fgets(line, 1024, stdin);
  while (line[0]) {
    // Trim CR/LF from end of line
    for (int i = 0; i < 1024; i++)
      if (line[i] == '\r' || line[i] == '\n')
        line[i] = 0;

    if (strlen(line) > cols) {
      fprintf(stderr, "Line too long (must be <= %d characters, but saw %d characters)\n", cols, (int)strlen(line));
      fprintf(stderr, "The line in question was '%s'\n", line);
      unlink(argv[1]);
      exit(-4);
    }

    // Pad line to correct width
    int padding = 0;
    for (int i = 0; i < cols; i++) {
      if (!line[i])
        padding = 1;
      if (padding)
        line[i] = ' ';
    }
    line[cols] = 0;

    // Write to output file
    fprintf(f, "%s", line);

    line[0] = 0;
    fgets(line, 1024, stdin);
  }

  fclose(f);
  return 0;
}
