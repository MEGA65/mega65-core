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
  if (!r_estimate) r_estimate=1;

  int iter_count=0;

  q=r_estimate*n;
  
  while(1)
    {
      unsigned long estimate_1=r_estimate*d;

      iter_count++;      

      printf("%d: %u/%u = %f : current estimate is %f, estimate_1=%08x.%08x, estimate_r=%08x\n",
	     iter_count,
	     n,d,(double)n/d,
	     ((double)q/(double)(1LL<<32)),
	     (unsigned int)(estimate_1>>32),(unsigned int)estimate_1,
	     r_estimate
	     );

      if (0)
      while(estimate_1<(0x80000000)) {
	estimate_1<<=1;
	r_estimate>>=1;
      }
      
      if (estimate_1==0x0000000100000000) {
	// Exact result.
	printf("Exact result. Stopping.\n");
	break;
      }	else if ((estimate_1&0xffffffff)<d) {
	// Nearly exact result.
	printf("Almost Exact result. Stopping.\n");
	break;	  
      }	else if ((((~estimate_1)&0xffffffff))<d) {
	// Nearly exact result.
	printf("Almost Exact result. Stopping.\n");
	break;	  
      } else if ((estimate_1>>32)) {
	if (!(estimate_1&0xffffffff)) {
	} else {
	  // Result is too big

	// Work out roughly what fraction of the correct value we currently
	// have, so that we can add the missing piece on.
	int a=(estimate_1>>(32-iter_count*4));
	a&=0xf;
	unsigned int r=r_estimate;

	printf("%d: Result is too big. Subtracting something. a=%d, r=$%08x\n",
	       iter_count,a,r);
	
	// Reduce r to a fraction of the current radix zone
	r=r>>(iter_count-1)*4;
	
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
	r_estimate-=r;
	printf("Subtracting $%08x from r = $%08x\n",r,r_estimate);
	return -1;
	  
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
	
	printf("%d: Result is too small. Adding something. a=%d, r=$%08x\n",iter_count,a,r);

	// We add on the factor, as though the lower bits of the remaining part were all zeroes.
	// Thus while we slightly under-estimate the factors due to limited precision, we also
	// can over-estimate the final result, by having neglected to consider the lower bits.
	// This is why we have the subtraction due to overestimation case.
	switch(a) {
	case 0: r=(r<<3)+(r<<2)+(r<<1)+r; break; // 16x = + 15x
	case 1: r=(r<<3)+(r<<2)+(r<<1); break; // 15x = + 14x
	case 2: r=(r<<2)+(r<<1)+r; break; // 8x = + 7x
	case 3: r=(r<<2)+(r>>2)+(r>>4); break; // 5.3333x = + 4.3333x
	case 4: r=(r<<1)+r; break; // 4x = + 3x
	case 5: r=(r<<1)+(r>>3)+(r>>4); break; // 3.2x = + 2.2x
	case 6: r=r+(r>>1)+(r>>3); break; // 2.6666x = + 1.6666x
	case 7: r=r+(r>>2)+(r>>5); break; // 2.2856x = + 1.2857x
	case 8: r=r; break;   // 2x = + 1x
	case 9: r=(r>>1)+(r>>2); break;  // 1.77777x = +.777x
	case 10: r=(r>>1)+(r>>4)+(r>>5); break; // 1.6x = + 0.6x
	case 11: r=(r>>2)+(r>>3)+(r>>4)+(r>>6); break; // 1.45x = + 0.4545x
	case 12: r=(r>>2); break; // 1.25x = + 0.x25
	case 13: r=(r>>4)+(r>>3)+(r>>5); break; // 1.2308x = +0.23x
	case 14: r=(r>>3)+(r>>6); break; // 1.14x = + 0.14x
	case 15: r=(r>>4)+(r>>8); break; // 1.06667x = + 0.066667x
	}
	r_estimate+=r;
	printf("Adding $%08x to r = $%08x\n",r,r_estimate);

      }

      q=r_estimate*n;      
    }
  
  
}
