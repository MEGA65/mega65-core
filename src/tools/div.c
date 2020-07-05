#include <stdio.h>
#include <stdlib.h>

int do_divide(unsigned int n,unsigned int d)
{

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

  unsigned long r_estimate = 1LL<<(32-bits_in_d);
  if (!r_estimate) r_estimate=1;

  int steps_taken=0;
  
  int iter_count=0;

  q=r_estimate*n;

  
  iter_count=1;
  while(1)
    {
      unsigned long estimate_1=r_estimate*d;
      printf("$%016lx x $%08x = $%016lx\n",
	     r_estimate,d,estimate_1);

      steps_taken++;
      
      printf("%d: %d: %u/%u = %f : current estimate is %f, estimate_1=%08x.%08x, estimate_r=%08x\n",
	     steps_taken,
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
	printf("RESULT:%d:%d: %d/%d = %f ($%08X) in %d steps.\n",d,steps_taken,n,d,(double)n/d,r_estimate,steps_taken);
	break;
      }	else if ((estimate_1&0xffffffff)<d) {
	// Nearly exact result.
	printf("Almost Exact result. Stopping.\n");
	printf("RESULT:%d:%d: %d/%d = %f ($%08X) in %d steps.\n",d,steps_taken,n,d,(double)n/d,r_estimate,steps_taken);
	break;	  
      }	else if ((((~estimate_1)&0xffffffff))<d) {
	// Nearly exact result.
	printf("Almost Exact result. Stopping.\n");
	printf("RESULT:%d:%d: %d/%d = %f ($%08X) in %d steps.\n",d,steps_taken,n,d,(double)n/d,r_estimate,steps_taken);
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

	// When subtracting, we want to try to approach slowly, as we know we have
	// only gotten here by overshooting.
	r=r*(1+a*2)/31;
	if (0)
	switch(a) {
	case 0: r=r/31;
	  // We are 16/15s of where we should be
	case 1: r=r-(r>>4); break;
	case 2: r=r-(r>>3); break;
	case 3: r=r-(r>>3)-(r>>4); break;
	case 4: r=r-(r>>2); break;
	case 5: r=r-(r>>2)-(r>>4); break;
	case 6: r=r-(r>>2)-(r>>3); break;
	case 7: r=r-(r>>2)-(r>>3)-(r>>4); break;
	case 8: r=r; break;
	case 9: r=(r>>2)+(r>>4); break;
	case 10: r=(r>>2)+(r>>3); break;
	case 11: r=(r>>2)+(r>>4); break;
	case 12: r=(r>>2); break;
	case 13: r=(r>>4)+(r>>3)+(r>>1); break;
	case 14: r=(r>>3); break;
	case 15: r=(r>4); break;
	}
	if (!r) r=1;
	r_estimate-=r;
	printf("Subtracting $%08x from r = $%08lx\n",r,r_estimate);
	  
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
	case 0: // r=(r<<3)+(r<<2)+(r<<1)+r; break; // 16x = + 15x
	  r=r; break;
	  // For the remaining cases, the goal is to bring the value up to a=15 (not a=16)
	  // This should always result in a value which tracks below the required amount,
	  // except perhaps in rare situations.
	case 1: r=(r<<3)+(r<<2)+(r<<1); break; // 15x = + 14x
	case 2: r=(r<<2)+(r<<1)+(r>>1); break; // 7.5x = + 6.5x
	case 3: r=(r<<2); break; // 5x = + 4x
	case 4: r=(r<<1)+(r>>1)+(r>>2); break; // 3.27x = + 2.75x
	case 5: r=(r<<1); break; // 3x = + 2x
	case 6: r=r+(r>>1); break; // 2.5x = + 1.5x
	case 7: r=r+(r>>2)+(r>>5); break; // 2.1429x = + 1.1429x
	case 8: // r=(r>>1)+(r>>2)+(r>>4); break;   // 1.875x = + 0.875x
	  // Exactly double
	  r=r; break;
	case 9: r=(r>>1)+(r>>3)+(r>>5)+(r>>7); break;  // 1.66666x = +.666x
	case 10: r=(r>>1); break; // 1.5x = + 0.5x
	case 11: r=(r>>2)+(r>>4)+(r>>5)+(r>>6); break; // 1.3636x = + 0.3636x
	case 12: r=(r>>2); break; // 1.25x = + 0.x25
	case 13: r=(r>>3)+(r>>6)+(r>>7)+(r>>8); break; // 1.1538x = +0.1538x
	case 14: r=(r>>4)+(r>>7)+(r>>10); // +(r>>13)+(r>>16); break; // 1.0714x = + 0.0714x
	  // If the bits are already all 1s, then we don't need to add anything
	  //	case 15: r=(r>>4)+(r>>8); break; // 1.06667x = + 0.066667x
	  break;
	case 15:
	  iter_count++;
	  r=0;
	}
	if (!r) r=1;
	r_estimate+=r;
	printf("Adding $%08x to r = $%08lx\n",r,r_estimate);
	if (r_estimate>0xfffffffffL) r_estimate=0xffffffff;
	
      }

      q=r_estimate*n;      
    }
  
  
}

int main(int argc,char **argv)
{

  for(int i=1;i<=0xffffffff;i++)
    do_divide(1,i);
}

