#include <stdio.h>
#include <stdlib.h>

int main(int argc,char **argv)
{
  unsigned int n=atoi(argv[1]);
  unsigned int d=atoi(argv[2]);

  unsigned long q=0;

  if (!d) {
    printf("Division by zero\n");
    return;
  }

  printf("Calculating %u/%u\n",n,d);
  while (!((n|d)&1)) {
    n>>=1;
    d>>=1;
    printf("Normalising to %u/%u\n",n,d);
  }
  printf("Normalised to %u/%u\n",n,d);
  
  int bits_in_n=0;
  unsigned int nn=n;
  while(nn) { bits_in_n++; nn=nn>>1; }
  printf("Numerator uses %d bits.\n",bits_in_n);

  int bits_in_d=0;
  unsigned int dd=d;
  while(dd) { bits_in_d++; dd=dd>>1; }
  printf("Numerator uses %d bits.\n",bits_in_d);

  unsigned long r_estimate = 1<<(32-bits_in_d);
  if (!r_estimate) r_estimate=0xffffffff;

  int iter_count=0;
  
  while(1)
    {
      unsigned long estimate_1=r_estimate*d;

      iter_count++;      

      printf("%d: %u/%u = %f : current estimate is %f, estimate_1=%08x.%08x, estimate_r=%08x\n",
	     iter_count,
	     n,d,(double)n/d,((double)q/(double)(1LL<<32)),
	     (unsigned int)(estimate_1>>32),(unsigned int)estimate_1,
	     r_estimate
	     );

      if (estimate_1==0x0000000100000000) {
	// Exact result.
	printf("Exact result. Stopping.\n");
	break;
      } else if ((estimate_1>>32)) {
	if (!(estimate_1&0xffffffff)) {
	} else {
	  // Result is too big
	  printf("Result is too big. Subtracting something.\n");
	  
	}
      } else {
	// Result is too small
	
	// Work out roughly what fraction of the correct value we currently
	// have, so that we can add the missing piece on.
	int a=(estimate_1>>(32-iter_count*4));
	a&=0xf;
	unsigned int r=r_estimate;

	// Reduce r to a fraction of the current radix zone
	r=r>>(iter_count-1)*4;
	
	printf("Result is too small. Adding something. a=%d, r=$%08x\n",a,r);

	switch(a) {
	case 0: r=r;	break;
	case 1: r=r-(r>>4); break;
	case 2: r=r-(r>>3); break;
	case 3: r=r-(r>>3)-(r>>4); break;
	case 4: r=r-(r>>2); break;
	case 5: r=r-(r>>2)-(r>>4); break;
	case 6: r=r-(r>>2)-(r>>3); break;
	case 7: r=r-(r>>2)-(r>>3)-(r>>4); break;
	case 8: r=r>>2; break;
	case 9: r=(r>>2)+(r>>4); break;
	case 10: r=(r>>2)+(r>>3); break;
	case 11: r=(r>>2)+(r>>4); break;
	case 12: r=(r>>2); break;
	case 13: r=(r>>4)+(r>>3)+(r>>1); break;
	case 14: r=(r>>3); break;
	case 15: r=(r>4); break;
	}
	r_estimate+=r;
	printf("Adding $%08x to r = $%08x\n",r,r_estimate);

      }
    }
  
  
}
