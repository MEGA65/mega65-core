#include <stdio.h>
#include <strings.h>
#include <string.h>
#include <stdlib.h>

#define MAX_STATES 1024
char *state_names[MAX_STATES];
int state_transitions[MAX_STATES][MAX_STATES];
int sdio_busy_set[MAX_STATES]={0};
int sdio_busy_cleared[MAX_STATES]={0};
int sdcard_busy_set[MAX_STATES]={0};
int sdcard_busy_cleared[MAX_STATES]={0};
int state_count = 0;

int state_name_lookup(char *name)
{
  for(int i=0;i<state_count;i++)
    if (!strcasecmp(name,state_names[i])) return i;

  state_names[state_count++]=strdup(name);
  return state_count-1;
}

int main(int argc,char **argv)
{
  for(int i=0;i<MAX_STATES;i++)
    for(int j=0;j<MAX_STATES;j++)
      state_transitions[i][j]=0;

  char line[1024];

  int active=0;

  int current_state_count = 0;
  int current_states[MAX_STATES];

  int if_depth=0;
  
  fgets(line,1024,stdin);
  while(line[0]) {

    // Trim trailing CRLF and spaces
    while(line[0]&&(line[strlen(line)-1]=='\n'||line[strlen(line)-1]=='\r'||line[strlen(line)-1]==' '))
      line[strlen(line)-1]=0;
    char *s=line;
    while(s[0]==' '||s[0]=='\t') s++;
    
    if (strstr(s,"case sd_state is")) active=1;
    else if (strstr(s,"case ")&&strstr(line," is")) {
      if (active>0) {
	active++;
	fprintf(stderr,"INFO: Ignoring '%s' block\n",s);
      }
    }
    else if (strstr(line,"end case")) {
      if (active>1) fprintf(stderr,"INFO: Reached end of ignored block.\n");
      if (active>0) active--;
    }
    if (active==1) {
      char state_name[1024];
      if (strncmp(s,"if",2)) {
	if_depth++;
	// fprintf(stderr,"INFO: IF++: %d\n",if_depth);
      }
      if (strncmp(s,"end if",6)) {
	if (if_depth>0) if_depth--;
	// fprintf(stderr,"INFO: IF--: %d\n",if_depth);
      }
      if (strstr(s,"sd_state <=")) {
	char new_state[1024];
	if (sscanf(s,"sd_state <= %[^;]",new_state)!=1) {
	  fprintf(stderr,"ERROR: Could not parse sd_state assignment '%s'\n",s);
	  exit(-1);
	}
	int new_state_id=state_name_lookup(new_state);
	fprintf(stderr,"INFO: Selects a different state: '%s' (%d)\n",new_state,new_state_id);
	// Record state transitions
	for(int i=0;i<current_state_count;i++)
	  state_transitions[current_states[i]][new_state_id]=1;
      }
      if (strstr(s,"sdio_busy <= '0'")) {
	if (if_depth) {
	  fprintf(stderr,"INFO: State clears sdio_busy CONDITIONALLY\n");
	  for(int i=0;i<current_state_count;i++) sdio_busy_cleared[current_states[i]]|=2;
	}
	else {
	  fprintf(stderr,"INFO: State clears sdio_busy\n");
	  for(int i=0;i<current_state_count;i++) sdio_busy_cleared[current_states[i]]|=1;
	}
      }
      else if (strstr(s,"sdio_busy <= '1'")) {
	if (if_depth) {
	  fprintf(stderr,"INFO: State sets sdio_busy CONDITIONALLY\n");
	  for(int i=0;i<current_state_count;i++) sdio_busy_set[current_states[i]]|=2;
	}
	else {
	  fprintf(stderr,"INFO: State sets sdio_busy (%d states)\n",current_state_count);		
	  for(int i=0;i<current_state_count;i++) sdio_busy_set[current_states[i]]|=1;
	}
      }
      else if (strstr(s,"sdcard_busy <= '0'")) {
	if (if_depth) {
	  fprintf(stderr,"INFO: State clears sdcard_busy CONDITIONALLY\n");		
	  for(int i=0;i<current_state_count;i++) sdcard_busy_cleared[current_states[i]]|=2;
	}
	else {
	  fprintf(stderr,"INFO: State clears sdcard_busy\n");		
	  for(int i=0;i<current_state_count;i++) sdcard_busy_cleared[current_states[i]]|=1;
	}
      }
      else if (strstr(s,"sdcard_busy <= '1'")) {
	if (if_depth) {
	  fprintf(stderr,"INFO: State sets sdcard_busy CONDITIONALLY\n");		
	  for(int i=0;i<current_state_count;i++) sdcard_busy_set[current_states[i]]|=2;	  
	}
	else {
	  fprintf(stderr,"INFO: State sets sdcard_busy\n");		
	  for(int i=0;i<current_state_count;i++) sdcard_busy_set[current_states[i]]|=1;
	}
      }
      else if (strstr(s,"sdio_busy <= ")) {
	fprintf(stderr,"INFO: State does something I don't recognise to sdio_busy: '%s'\n",s);
	exit(-1);
      }
      else if (strstr(s,"sdcard_busy <= ")) {
	fprintf(stderr,"INFO: State does something I don't recognise to sdcard_busy: '%s'\n",s);
	exit(-1);
      }
      if (sscanf(s,"when %s =>",state_name)==1) {
	fprintf(stderr,"INFO: Found state '%s'\n",state_name);
	// XXX - Split multi-case selections via | char
	current_state_count=0;
	if_depth=0;
	char *sn=state_name;
	char *ss;
	while((ss=strsep(&sn,"|"))) {
	  current_states[current_state_count++]=state_name_lookup(ss);
	  fprintf(stderr,"INFO: Extracted state name '%s', index = %d\n",
		  ss,current_states[current_state_count-1]);
	}
      }
    }
      
    fgets(line,1024,stdin);
  }

  /*
    Work out the worst-case propagation of sdio_busy status.
   */
  int worst_set_status[MAX_STATES];
  int worst_cleared_status[MAX_STATES];

  #define ALWAYS 2
  #define MAYBE 1
  #define NEVER 0
  for(int i=0;i<state_count;i++) {
    worst_set_status[i]=NEVER;
    worst_cleared_status[i]=ALWAYS;
  }
  
  for(int l=0;l<state_count;l++) {
    for(int i=0;i<state_count;i++) {
      
      for(int s=0;s<state_count;s++) {
	int maybe_set=0;
	int always_set=0;
	int maybe_cleared=0;
	int always_cleared=0;
	if (state_transitions[s][i]) {
	  // State s transitions to state i.
	  if (sdio_busy_set[s]&2) maybe_set=1;
	  if (sdio_busy_set[s]&1) always_set=1;
	  if (sdio_busy_set[s]&2) maybe_cleared=1;
	  if (sdio_busy_set[s]&1) always_cleared=1;	  

	  if (!always_cleared) {
	    if (worst_cleared_status[s]<worst_cleared_status[i]) worst_cleared_status[i]=worst_cleared_status[s];
	    else worst_cleared_status[i]=ALWAYS;
	  }
	  if (!maybe_cleared) {
	    if (worst_cleared_status[s]<worst_cleared_status[i]) worst_cleared_status[i]=worst_cleared_status[s];
	    else worst_cleared_status[i]=MAYBE;
	  }

	  if (maybe_set && worst_set_status[i]==NEVER) worst_set_status[i]=MAYBE;
	  if (always_set && worst_set_status[i]==NEVER) worst_set_status[i]=ALWAYS;
	  if (worst_set_status[i]<worst_set_status[s]) worst_set_status[i] = worst_set_status[s];
	}
      }
    }
  }

  
  printf("digraph {\n");
  
  for(int i=0;i<state_count;i++) {
    char fillcolour[1024]="white";
    if (worst_cleared_status[i]==ALWAYS) strcpy(fillcolour,"green");
    else if (worst_set_status[i]==NEVER) strcpy(fillcolour,"blue");
    else if (worst_cleared_status[i]==MAYBE&&worst_set_status[i]!=NEVER) strcpy(fillcolour,"yellow");
    else if (worst_cleared_status[i]==MAYBE&&worst_set_status[i]==ALWAYS) strcpy(fillcolour,"orange");
    else if (worst_cleared_status[i]==NEVER&&worst_set_status[i]==ALWAYS) strcpy(fillcolour,"red");
    else { fprintf(stderr,"ERROR: Don't know what colour to set for %d,%d\n",
		 worst_cleared_status[i],worst_set_status[i]);
      exit(-1);
    }
    
    printf("%s [style=filled; fillcolor=%s];\n",state_names[i],fillcolour);
  }

  for(int i=0;i<state_count;i++)
    for(int j=0;j<state_count;j++)
      {
	if (state_transitions[i][j]) {
	  printf("%s -> %s ",state_names[i],state_names[j]);
	  char annotation[1024];
	  char colour[1024]="black";
	  annotation[0]=0;
	  if (sdio_busy_set[i]&2) strcat(annotation,"sdio_busy SET? ");
	  else if (sdio_busy_set[i]&1) strcat(annotation,"sdio_busy SET ");
	  if (sdio_busy_cleared[i]&2) { strcat(annotation,"sdio_busy CLEARED? "); strcpy(colour,"purple"); }
	  else if (sdio_busy_cleared[i]&1) { strcat(annotation,"sdio_busy CLEARED "); strcpy(colour,"blue"); }
	  if (sdcard_busy_set[i]&2) strcat(annotation,"sdcard_busy SET? ");
	  else if (sdcard_busy_set[i]&1) strcat(annotation,"sdcard_busy SET ");
	  if (sdcard_busy_cleared[i]&2) { strcat(annotation,"sdcard_busy CLEARED? "); strcpy(colour,"purple"); }
	  else if (sdcard_busy_cleared[i]&1) { strcat(annotation,"sdcard_busy CLEARED "); strcpy(colour,"blue"); }
	  printf(" [ label=\"%s\";color=%s;];\n",annotation,colour);
	}
      }

  printf("}\n");
  
  return 0;
}
