#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define MAX_LINES 32
char line_history[MAX_LINES][1024];
int line_numbers[MAX_LINES];

int main(int argc, char **argv)
{
  if (argc < 3) {
    fprintf(stderr, "usage: vhdl-path-finder <signal> <vhdl file(s) ...>\n");
    exit(-1);
  }

  char *target = argv[1];

  for (int i = 2; i < argc; i++) {
    int line_count = 0;
    int n = 0;
    FILE *f = fopen(argv[i], "rb");
    if (!f)
      continue;
    char line[1024];
    line[0] = 0;
    fgets(line, 1024, f);
    while (line[0]) {
      n++;
      if (strstr(line, "end if;")) {
        if (line_count > 0) {
          // Get rid of any elsif statements first
          while (line_count && strstr(line_history[line_count - 1], "elsif "))
            line_count--;
          // Remove the last statement.
          line_count--;
        }
        else {
          fprintf(stderr, "ERROR: 'end if;' without 'if' statement.\n");
          exit(-1);
        }
      }
      else if (strstr(line, "if ")) {
        char *s = strstr(line, "if ");
        char *comment = strstr(line, "--");
        if ((!comment) || (comment > s)) {
          if (line_count < MAX_LINES) {
            line_numbers[line_count] = n;
            strcpy(line_history[line_count++], line);
          }
          else {
            fprintf(stderr, "ERROR: Too deeply nested if statements.\n");
            exit(-1);
          }
        }
      }
      else if (strstr(line, target)) {
        printf("---------------------------------------\n");
        for (int j = 0; j < line_count; j++) {
          printf("%4d    %s", line_numbers[j], line_history[j]);
        }
        printf("%4d >>> %s", n, line);
      }

      line[0] = 0;
      fgets(line, 1024, f);
    }
  }
}
