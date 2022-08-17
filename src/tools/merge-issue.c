/*
  Simple little program to allow the merging of all commits
  that are tagged with a particular issue.

*/

#include <stdio.h>
#include <stdlib.h>

#define MAX_COMMITS 65536
char *commits[MAX_COMMITS];
int commit_count = 0;

void usage(void)
{
  fprintf(stderr, "usage: merge-issue <issue number> <source branch>\n");
  exit(-1);
}

int main(int argc, char **argv)
{
  if (argc != 3)
    usage();

  int issue = atoi(argv[1]);
  char *branch = argv[2];

  fprintf(stderr, "Fetching list of commits...\n");
  unlink("merge-issue.log");
  char cmd[8192];
  snprintf(cmd, 8192, "git log %s >merge-issue.log", branch);
  system(cmd);

  char issuetag[1024];
  snprintf(issuetag, 1024, "#%d", issue);

  fprintf(stderr, "Finding relevant commits...\n");
  FILE *f = fopen("merge-issue.log", "r");
  char line[1024];
  char last_commit[1024];
  char commit_msg[1024];
  line[0] = 0;
  fgets(line, 1024, f);
  while (line[0]) {
    sscanf(line, "commit %[^\n\r]", last_commit);
    if (strstr(line, issuetag)) {
      printf("%s : %s", last_commit, line);
      commits[commit_count++] = strdup(last_commit);
    }

    line[0] = 0;
    fgets(line, 1024, f);
  }
  fclose(f);

  fprintf(stderr, "Found %d relevant commits.\n", commit_count);

  for (int i = commit_count - 1; i > -1; i--) {
    snprintf(cmd, 8192, "git cherry-pick %s | tee cherry-pick.log", commits[i]);
    fprintf(stderr, "%s\n", cmd);
    fprintf(stderr, "Press ENTER to apply.\n");
    fgets(line, 1024, stdin);
    system(cmd);
  }
}
