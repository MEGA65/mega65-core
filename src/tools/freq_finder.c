#include <stdio.h>

int main(int argc,char **argv)
{
  unsigned long long setting=0;
  float factors[1<<14];
  float uniq_factors[1<<14];
  int uniq_factor_count=0;
  
  // 1 -- 16 in steps of 1/8 = 7 bits of control for each element.
  // Each MMCM has a multiplier and a divider, thus 14-bits of control.
  // So we can calculate all 2^14 adjustment factors
  printf("Calculating set of adjustment factors...\n");
  for(int i=0;i<(1<<14);i++) {
    float m=1+((i>>0)&0x7f)/8;
    float d=1+((i>>7)&0x7f)/8;
    factors[i]=m/d;
    int j;
    for(j=0;j<uniq_factor_count;j++) {
      if (factors[i]==uniq_factors[j]) {
	break;
      }
    }
    if (j==uniq_factor_count)
      uniq_factors[uniq_factor_count++]=factors[i];
  }
  printf("There are %d unique factors.\n",uniq_factor_count);
  
  
  float best_freq=100;
  float best_diff=100-27;
  int best_factor_count=0;
  int best_factors[8]={0,0,0,0,0,0,0,0};

  int this_factors[8]={0,0,0,0,0,0,0,0};
  
  // Start with as few factors as possible, and then progressively search the space
  for (int max_factors=1;max_factors<4;max_factors++)
    {
      printf("Trying %d factors...\n",max_factors);
      for(int i=0;i<max_factors;i++) this_factors[i]=0;
      while(this_factors[0]<uniq_factor_count) {
	float this_freq=27.0833333;
	for(int j=0;j<max_factors;j++) {
	  //	  	  printf(" %.3f",factors[this_factors[j]]);
	  this_freq*=uniq_factors[this_factors[j]];
	}
	//		printf(" = %.3f MHz\n",this_freq);
	float diff=this_freq-27.00; if (diff<0) diff=-diff;
	if (0&&diff<1) {
	  printf("Close freq: ");
	  for(int j=0;j<max_factors;j++) printf(" %.3f",uniq_factors[this_factors[j]]);
	  printf(" = %.3f MHz\n",this_freq);
	}
	if (diff<best_diff) {
	  best_diff=diff;
	  best_freq=this_freq;
	  for(int k=0;k<8;k++) best_factors[k]=this_factors[k];
	  best_factor_count=max_factors;
	  printf("New best: ");
	  for(int j=0;j<max_factors;j++) printf(" %.3f",uniq_factors[this_factors[j]]);
	  printf(" = %.6f MHz\n",this_freq);
	  printf("          ");
	  for(int j=0;j<max_factors;j++) {
	    float uf=uniq_factors[this_factors[j]];
	    int n=0;
	    for(n=0;n<(1<<14);n++) if (uf==factors[n]) break;
	    if (j) printf(" x");
	    printf(" %.3f/%.3f",(1.0+((n>>0)&0x7f)/8),(1.0+((n>>7)&0x7f)/8));
	  }
	  printf("\n\n");	  
	}


	// Now try next possible value
        this_factors[max_factors-1]++;
	int j=max_factors-1;
	while((j>=1)&&(this_factors[j]>=uniq_factor_count)) {
	  this_factors[j]-=(1<<14);
	  this_factors[j-1]++;
	  j--;
	}
      }
    }
}
