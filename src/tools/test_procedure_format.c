#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>

int max_issue=0;

int main(int argc,char **argv)
{

  // Parse list of issues
  // This actually only returns the 30 most recent issues.  But the first one will always
  // be the newest, so it at least delimits what we need to search.
  // We will heavily cache, since the ##BREAKS tags are not expected to change often.
  // system("curl -i https://api.github.com/repos/mega65/mega65-core/issues > issues.txt");
  FILE *f=fopen("issues.txt","r");
  if (!f) {
    fprintf(stderr,"ERROR: Could not read issues.txt.\n");
    exit(-3);
  }
  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    while(line[0]&&(line[0]<=' '))
      bcopy(&line[1],&line[0],strlen(line));
    while(line[0]&&(line[strlen(line)-1]<' '))
      line[strlen(line)-1]=0;
    //    printf("> '%s'\n",line);
    if (!max_issue) {
      sscanf(line,"\"number\": %d",&max_issue);
    }

    
    line[0]=0; fgets(line,1024,f);
  }

  fprintf(stderr,"Maximum issue number is %d\n",max_issue);

  for(int issue=1;issue<=max_issue;issue++) {
    char issue_file[1024];
    snprintf(issue_file,1024,"issues/issue%d.txt",issue);
    FILE *isf=fopen(issue_file,"r");
    if (isf) {
      char line[1024]; line[0]=0;
      fgets(line,1024,isf);
      while(line[0]&&(line[strlen(line)-1]<' '))
	line[strlen(line)-1]=0;
      if (strcmp(line,"HTTP/1.1 200 OK")) {
	// Ignore files that didn't fetch correctly.
	fclose(isf);
	isf=NULL;
      }
    }
    if (!isf) {
      // Need to refetch it
      fprintf(stderr,"Can't open '%s' -- refetching.\n",issue_file);
      fprintf(stderr,"curl -i https://api.github.com/repos/mega65/mega65-core/issues/%d > %s\n",
	      issue,issue_file);
      char cmd[1024];
      snprintf(cmd,1024,"curl -i https://api.github.com/repos/mega65/mega65-core/issues/%d > %s\n",
	      issue,issue_file);
      //system(cmd);
      isf=fopen(issue_file,"r");
      if (!isf) {
	fprintf(stderr,"WARNING: Could not fetch issue #%d\n",issue);
      }
    }

    // Ok, have file, parse it.
    if (isf) {

      
      fclose(isf);
    }
  }

  
}
