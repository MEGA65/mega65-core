#include <stdio.h>
#include <stdlib.h>
#include <strings.h>
#include <string.h>
#include <ctype.h>

int max_issue=0;

int parse_string(char *in,char *out)
{
  int outlen=0;
  for(int i=0;in[i];i++) {
    if (in[i]=='\\') {
      i++;
      switch(in[i]) {
      case 'r':	out[outlen++]='\r'; break;
      case 'n':	out[outlen++]='\r'; break;
      case 't':	out[outlen++]='\t'; break;
      case '\"':	out[outlen++]='\"'; break;
      case '\'':	out[outlen++]='\''; break;
      default:
	fprintf(stderr,"WARNING: Unknown \\ escape \\%c\n",in[i]);
	i--;
	out[outlen++]='\\';
      }
    } else {
	out[outlen++]=in[i];
    }
  }
  out[outlen]=0;
}

#define MAX_PROBLEMS 8192
int problem_issues[MAX_PROBLEMS];
char *problem_titles[MAX_PROBLEMS];
char *problem_descriptions[MAX_PROBLEMS];
int problem_mentioned[MAX_PROBLEMS];
int problem_count=0;

char tex_esc_buff[8192];
char *tex_escape(char *in)
{
  int ol=0;
  for(;*in;in++) {
    switch(*in) {
    case '$':
    case '%':
      tex_esc_buff[ol++]='\\';
      tex_esc_buff[ol++]=*in;      
      break;
    default:
      tex_esc_buff[ol++]=*in;
    }
  }
  tex_esc_buff[ol]=0;
  return tex_esc_buff;
}


int register_breaks(int issue,char *title,char *problem)
{
  int i;
  char problem_msg[8192];
  for(i=0;problem[i]&&problem[i]!='\r';i++) {
    // Also stop when hitting a non-escaped quote
    
    problem_msg[i]=problem[i];
    problem_msg[i+1]=0;
  }

  
  
  fprintf(stderr,"Registering problem: #%d : '%s'\n",
	  issue,problem_msg);
  problem_issues[problem_count]=issue;
  problem_titles[problem_count]=strdup(tex_escape(title));
  problem_descriptions[problem_count]=strdup(tex_escape(problem_msg));
  problem_count++;
  
  return 0;
}

int show_problem_box(FILE *f,int problem_number)
{
  fprintf(f,"\\begin{table}[H]\n"
	  "\\begin{tabular}{|l|l|l|l|}\n"
	  "\\hline\n"
	  "Issue                                                          & \\href{https://github.com/mega65/mega65-core/issues/%d}{\\#%d} & Resolved? & Y / N / Unsure / Not Applicable \\\\ \\hline\n"
	  "\\begin{tabular}[Hc]{@{}l@{}}Problem\\\\ Description:\\end{tabular} & \\multicolumn{3}{l|}{%s}                           \\\\ \\hline\n"
	  "\\begin{tabular}[Hc]{@{}l@{}}Tester's\\\\ Comments\\end{tabular}    & \\multicolumn{3}{l|}{}                              \\\\ \\hline\n"
	  "\\end{tabular}\n"
	  "\\end{table}\n\n",
	  problem_issues[problem_number],
	  problem_issues[problem_number],
	  problem_descriptions[problem_number]
	  );

  problem_mentioned[problem_number]++;
  
  return 0;
}

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
  char line[8192];
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
      system(cmd);
      isf=fopen(issue_file,"r");
      if (!isf) {
	fprintf(stderr,"WARNING: Could not fetch issue #%d\n",issue);
      }
    }

    // Ok, have file, parse it.
    if (isf) {

      int issue_num;
      char title[8192];
      char body[8192];
      
      char line[8192];
      line[0]=0; fgets(line,8192,isf);
      while(line[0]) {
	while(line[0]&&(line[0]<=' '))
	  bcopy(&line[1],&line[0],strlen(line));
	while(line[0]&&(line[strlen(line)-1]<' '))
	  line[strlen(line)-1]=0;
	//	    printf("> '%s'\n",line);
	sscanf(line,"\"number\": %d",&issue_num);
	if (!strncmp("\"title\": ",line,9)) {
	  parse_string(&line[10],title);
	}
	if (!strncmp("\"body\": ",line,8)) {
	  parse_string(&line[9],body);
	}

	line[0]=0; fgets(line,8192,isf);       
      }
      
      fclose(isf);

      if (0) printf("Issue #%d:\ntitle = %s\nbody = %s\n",
		    issue_num,title,body);
      int problem_count=0;
      for (int i=0;body[i];i++) {
	if (!strncmp("\r##BREAKS ",&body[i],10)) {
	  register_breaks(issue_num,title,&body[i+10]);
	  problem_count++;
	}
      }
      // If no specific problems were registered, then we just need to log the whole
      // issue
      if (!problem_count)
        register_breaks(issue_num,title,"Unspecified problem. Please add \\#\\#BREAKS tags via github issue");
    }
  }

  // Ok, now we have the set of issues and things that the issues broke, so that we can annotate the
  // test procedure document.

  FILE *of=fopen("testprocedure.tex","w");
  FILE *inf=fopen("testprocedure_in.tex","r");
  if (!of||!inf) {
    fprintf(stderr,"ERROR: Could not open testprocedure.tex or testprocedure_in.tex\n");
    exit(-1);
  }

  // Output Latex header
  fprintf(of,
	  "\\documentclass{article}\n"
	  "\n"
	  "\\title{MEGA65 Test Procedure}\n"
	  // XXX include git commit ID in a \\abstract{} block?
	  "\\usepackage{float}\n"
	  "\\usepackage{hyperref}\n"
	  "\\begin{document}\n"
	  "\\maketitle\n"
	  "\\section*{Test Procedure}\n"
	  "\\begin{enumerate}\n"
	  );

  line[0]=0; fgets(line,8192,inf);
  while(line[0]) {
    int queued_problems[MAX_PROBLEMS];

    for(int i=0;line[i];i++) {
      if (line[i]=='#') {
	if (line[i+1]=='[') {
	  // Named problem
	  char *p=&line[i+2];
	  int len=0;
	  int found=0;
	  while(p[len]&&p[len]!=']') len++;
	  printf("named problem at '%s', len=%d\n",
		 p,len);
	  for(int j=0;j<problem_count;j++) {
	    if (!strncmp(problem_descriptions[j],p,len)) {
	      show_problem_box(of,j);
	      found=1;
	    }
	  }
	  if (!found) {
	    int z=p[len]; p[len]=0;
	    fprintf(of,"ERROR: Problem ``%s'' does not appear in issues. Please check spelling and punctuation are exactly matching the text in the \\#\\#BREAKS directive in the issue body.\n",p);
	    p[len]=z;
	  }
	  i+=1+len+1;	  
	  
	} else {
	  // Issue number: Show all problems that the issue references
	  char num[16];
	  int nlen=0;
	  while(isdigit(line[i+1+nlen])&&(nlen<16)) {
	    num[nlen++]=line[i+1+nlen];	    
	  }
	  i+=nlen;
	  num[nlen]=0;
	  int issue_num=atoi(num);
	  for(int j=0;j<problem_count;j++) {
	    if (problem_issues[j]==issue_num)
	      show_problem_box(of,j);
	  }
	}
      }
      else fprintf(of,"%c",line[i]);
    }
    
    line[0]=0; fgets(line,8192,inf);
  }

  fprintf(of,"\\item End of procedure.\n");
  
  fprintf(of,
	  "\\end{enumerate}\n"
	  );


  int missed_count=0;
  for(int i=0;i<problem_count;i++) {
    if (!problem_mentioned[i]) {
      if (!missed_count)
	fprintf(of,"\\section*{Issues not (yet) included in the test procedure}\n");
      show_problem_box(of,i);
      missed_count++;
    }
  }
  
  fprintf(of,
	  "\\end{document}\n"
	  );
  
  fclose(of); fclose(inf);

  system("pdflatex testprocedure");
  
}
