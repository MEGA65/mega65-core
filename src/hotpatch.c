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
#include <sys/mman.h>
#include <fcntl.h>

#ifndef uint16_t
#define uint16_t unsigned
#endif

struct memory_context {
  unsigned char isCode[65536];
  unsigned char initialised[65536];
  unsigned char initialValues[65536];
  unsigned char currentValues[65536];
  unsigned char modified[65536];

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
	if ((strlen(s)==2)&&(s[0]!='|')) {
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

  char line[1024];
  line[0]=0; fgets(line,1024,f);
  while(line[0]) {
    unsigned addr;
    char name[1024];
    if (sscanf(line,"$%x %s",&addr,name)==2) {
      if (c->label_count<65536) {
	c->label_addresses[c->label_count]=addr;
	c->labels[c->label_count]=strdup(name);
	c->label_count++;
      }
    }
    
    line[0]=0; fgets(line,1024,f);
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

  closedir(d);
  return 0;
}

int save_memory(char *file,struct memory_context *c)
{
  int modified=0;
  
  FILE *f=fopen(file,"w");
  if (!f) {
    perror(file); usage("Could not write memory file for updated instance.");
    return -1;
  }

  // Horribly inefficient -- use memory map instead
  for(int i=0;i<65536;i++) {
    if (c->modified[i]) {
      fwrite(&c->currentValues[i],1,1,f);
      modified++;
    } else
      fwrite(&c->initialValues[i],1,1,f);
  }  
  
  fclose(f);

  printf("Wrote new memory data to %s (%d bytes updated from running process)\n",
	 file,modified);
  
  return 0;
}

int load_memory(char *file,struct memory_context *c)
{
  int fd=open(file,O_RDONLY);
  if (fd<0) {
    perror(file); usage("Could not load memory for running instance.");
    return -1;
  }
  unsigned char *mem = mmap(NULL,65536,PROT_READ,MAP_SHARED,fd,0);

  if (mem==MAP_FAILED) {
    perror(file); usage("Could not map memory for running instance.");
    return -1;
  }

  for(int i=0;i<65536;i++) {
    c->currentValues[i]=mem[i];
    if (c->initialised[i]) {
      if (mem[i]!=c->initialValues[i]) c->modified[i]=1;
    }
  }
  close(fd);
  return 0;
}

int find_nearest_label(struct memory_context *c, unsigned addr)
{
  int best_addr=0;
  int best_id=-1;

  for(int i=0;i<c->label_count;i++) {
    if ((c->label_addresses[i]>=best_addr)
	&&(c->label_addresses[i]<=addr)) {
      best_id=i; best_addr=c->label_addresses[i];
    }
  }

  return best_id;
}

int context_report(struct memory_context *c)
{
  int codeBytes=0;
  int initialisedBytes=0;
  for(int i=0;i<65536;i++) {
    if (c->isCode[i]) codeBytes++;
    if (c->initialised[i]) initialisedBytes++;
  }
  
  int modified=0;
  int modifiedCode=0;
  for(int i=0;i<65536;i++) {
    if (c->initialised[i]) {
      if (c->modified[i]) {
	modified++;
	if (c->isCode[i]) modifiedCode++;
      }
    }
  }
      
  printf("%d bytes (%d code), %d labels and symbols.\n",
	 initialisedBytes,codeBytes,c->label_count);
  printf("%d bytes no longer hold their initial value (%d code).\n",
	 modified,modifiedCode);
  
  return 0;
}

int find_label(struct memory_context *c,char *label)
{
  for(int i=0;i<c->label_count;i++)
    if (!strcasecmp(c->labels[i],label)) return i;
  return -1;
}

int update_variables(struct memory_context *old,struct memory_context *new)
{
  int ignored=0;
  int changed=0;
  int code=0;
  
  for(int i=0;i<65536;i++) {
    if (old->initialised[i]) {
      if (old->modified[i]) {
	if (old->isCode[i]) {
	  code++;
	} else {	  
	  // Modified non-code.
	  // Try to describe the location.
	  int old_label_id=find_nearest_label(old,i);
	  if (old_label_id>=0) {
	    int new_label_id=find_label(new,old->labels[old_label_id]);
	    int delta=i-old->label_addresses[old_label_id];
	    if (new_label_id<0) {
	      printf("WARNING: Label %s has disappeared, not propagating changed value at $%04X.\n",
		     old->labels[old_label_id],i);
	      ignored++;
	    } else {
	      int new_addr=new->label_addresses[new_label_id]+delta;
	      int new_nearest_id=find_nearest_label(new,new_addr);
	      if (new_nearest_id!=new_label_id) {
		printf("WARNING: %s+%d ($%04X) : $%02X -> $%02X is ambiguous :$%04X is now best described as %s+%d, not propagating changed value.\n",
		       old->labels[old_label_id],delta,
		       i,
		       old->initialValues[i],
		       old->currentValues[i],
		       i,
		       new->labels[new_nearest_id],
		       (new_addr-new->label_addresses[new_nearest_id])
		       );
		ignored++;
	      } else {
		if (new->isCode[new_addr]) {
		  printf("WARNING: %s+%d ($%04X) : $%02X -> $%02X now points to code ($%04X), not propagating changed value.\n",
			 old->labels[old_label_id],
			 i-old->label_addresses[old_label_id],
			 i,
			 old->initialValues[i],
			 old->currentValues[i],			 
			 new_addr
			 );
		  ignored++;
		  
		} else {
		  printf("Translating %s+%d ($%04X) : $%02X to ($%04X), replacing initial value $%02X\n",
			 old->labels[old_label_id],
			 i-old->label_addresses[old_label_id],
			 i,
			 old->currentValues[i],
			 new_addr,
			 new->initialValues[new_addr]);
		  new->currentValues[new_addr]=old->currentValues[i];
		  new->modified[new_addr]=1;
		  changed++;		  
		}
	      }
	    }
	  } else {
	    printf("WARNING: No information for $%04X : $%02X -> $%02X, not propagating\n",
		   i,
		   old->initialValues[i],
		   old->currentValues[i]);
	    ignored++;
	  }
	}
      }
    }
  }

  printf("%d bytes translated, %d ignored, %d excluded (not data)\n",
	 changed,ignored,code);
  return 0;

}

int main(int argc,char **argv)
{
  struct memory_context old, new;
  bzero(&old,sizeof old);
  bzero(&new,sizeof new);

  if (argc!=7) usage("Incorrect number of arguments");

  // Load old context
  load_memory_context(argv[1],&old);
  // Load memory that is currently loaded, taking note of data bytes
  // that have changed.
  load_memory(argv[2],&old);
  // Print some statistics
  context_report(&old);

  // Load new context
  load_memory_context(argv[4],&new);

  // Translate variables
  update_variables(&old,&new);

  // XXX Update stack & registers

  save_memory(argv[5],&new);

  return 0;
}
