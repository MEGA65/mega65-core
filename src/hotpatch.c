/*
  MEGA65 Hot-patch system.
  
  This takes old and new memory maps in the form of Ophis .map files, and
  using the differences between them, works out where symbols have moved, and allows
  addresses to be translated between the old and new contexts.  This is combined
  with analysis of the source code to work out where variables are located.  Variables
  are checked for non-initial values, and those are then translated to the new memory
  context.  The result is the building of a new model of memory contents.  This is 
  combined with translating the current PC from the old memory context to the new, to
  allow execution to be resumed in the new memory context without having to restart.
  In short, it allows for hot-patching of software running on the MEGA65, to provide
  for a powerful and fast software development environment.

  XXX - We need to also update the stack, so that return addresses point to where they
  should. This means we need to know where the stack lives.

  
  Eventually this would need to be expanded to support full banked and mapped memory,
  to allow hot-patching of larger programs. Similarly, it should eventually support
  cc65, so that programs written in C, including GEOS programs, can also be 
  hot-patched.

  
*/

#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>

#ifndef uint16_t
#define uint16_t unsigned
#endif

struct memory_context {
  unsigned char isCode[65536];
  unsigned char initialised[65536];
  unsigned char initialValues[65536];
  unsigned char currentValues[65536];

  char *labels[65536];
  uint16_t label_addresses[65536];
  int label_count;
};

int usage(char *m)
{
  if (m) fprintf(stderr,"%s\n\n",m);
  
  fprintf(stderr,"usage: hotpatch olddir oldmem oldregs newdir newmem newregs\n"
	  "  olddir  = directory containing .list and .map files from old memory context.\n"
	  "  newdir  = directory containing .list and .map files from new memory context.\n"
	  "  oldmem  = file containing 64KB memory dump of old memory context.\n"
	  "  newmem  = file which will be created containing the new memory context,\n"
	  "           including variable values translated from the old memory context.\n"
	  "  oldregs = file containing processor register values in old context.\n"
	  "  newregs = file containing processor register values in new context.\n"
	  "\n"
	  "This program will create newmem and newregs based on the inputs, such that\n"
	  "the machine can (hopefully) continue in the new memory context, without\n"
	  "being restarted.\n"
	  "\n"
	  "There are limitations to what it is capable of, however, as it does not do\n"
	  "static analysis, and assumes that only return addresses have been pushed\n"
	  "onto the stack.\n"
	  "\n");
  exit(-1);
}

int load_list_file(char *file,struct memory_context *c)
{
  FILE *f=fopen(file,"r");
  if (!f) {
    perror(file); usage("Could not load .list file");
    return -1;
  }
  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    char *s=strtok(line," ");
    int count=0;
    unsigned address=strtol(s,NULL,16);
    while(s) {
      if (count) {
	if (strlen(s)==2) {
	  c->initialValues[address+count-1]=strtol(s,NULL,16);
	  c->isCode[address+count-1]=1;
	  c->initialised[address+count-1]=1;
	} else {
	  if (s[0]=='|') {
	    // Data block ASCII marker -- so all these bytes we have read are data,
	    // not code.
	    for(int i=0;i<count;i++) c->isCode[address+i]=0;
	    break;
	  } else {
	    // Presumably a code block.  Do nothing.
	    break;
	  }
	}
      }
      s=strtok(NULL," ");
      count++;
    }
    
    line[0]=0; fgets(line,1024,f);
  }

  
  fclose(f);
  return 0;
}

int load_map_file(char *file,struct memory_context *c)
{
  FILE *f=fopen(file,"r");
  if (!f) {
    perror(file); usage("Could not load .map file");
    return -1;
  }

  fclose(f);
  return 0;
}


int load_memory_context(char *dir,struct memory_context *c)
{
  DIR *d=opendir(dir);
  struct dirent *de;
  char filename[1024];
  if (!d) usage("Could not read source directory.");
  while ((de=readdir(d))!=NULL) {
    snprintf(filename,1024,"%s/%s",dir,de->d_name);
    if (strlen(de->d_name)<strlen(".map")) continue;
    if (!strcasecmp(&filename[strlen(filename)-4],".map")) {    
      printf("MAP %s\n",filename);
      load_map_file(filename,c);
    }
    if (strlen(de->d_name)<strlen(".list")) continue;
    if (!strcasecmp(&filename[strlen(filename)-5],".list")) {    
      printf("LIST %s\n",filename);
      load_list_file(filename,c);
    }
  }

  int codeBytes=0;
  int initialisedBytes=0;
  for(int i=0;i<65536;i++) {
    if (c->isCode[i]) codeBytes++;
    if (c->initialised[i]) initialisedBytes++;
  }
  printf("%d bytes (%d code)\n",initialisedBytes,codeBytes);

  closedir(d);
  return 0;
}

int main(int argc,char **argv)
{
  struct memory_context old, new;
  bzero(&old,sizeof old);
  bzero(&new,sizeof new);

  if (argc!=7) usage("Incorrect number of arguments");

  load_memory_context(argv[1],&old);
  load_memory_context(argv[4],&new);
  
}
