/*
  Routines to test C64 floating point conversion

*/

#include <stdio.h>
#include <string.h>
#include <strings.h>

#pragma pack(1)
struct c64float_struct {
  unsigned char exp;
  unsigned char man0;
  unsigned char man1;
  unsigned char man2;
  unsigned char man3;
};

typedef struct c64float {
  union {
    struct c64float_struct f;
    unsigned char bytes[5];
  };
} c64float;

typedef struct test_case {
  c64float f;
  double d;
} test_case;

double c64float_to_double(c64float *f)
{
  double d=0;

  if (!f->f.exp) return 0;
  
  unsigned int man=(f->f.man0<<24)+(f->f.man1<<16)+(f->f.man2<<8)+(f->f.man3<<0);
  man|=0x80000000;
  d=man;
  int exp=f->f.exp;
  while(exp>0x81) { d=d*2.0; exp--; }
  while(exp<0x81) { d=d/2.0; exp++; }

  d=d/(1.0*0x80000000);

  if (f->f.man0&0x80) d=-d;
  
  return d;
}

char c64fstrbuf[80];
char *c64float_to_string(c64float *f)
{
  snprintf(c64fstrbuf,80,"%02X:%02X.%02X.%02X.%02X", // (= 0x%x*2^0x%x)",
	   f->bytes[0],f->bytes[1],f->bytes[2],f->bytes[3],f->bytes[4]
	   
	   //  , 0x80000000|f->f.man,f->f.exp=0x81

	   );
  return c64fstrbuf;
}

test_case test_cases[]={
			{ .f={{{0x00,0x12,0x34,0x56,0x78}}},0.0},
			{ .f={{{0x01,0x00,0x00,0x00,0x00}}},2.93873588E-39},
			{ .f={{{0x81,0x00,0x00,0x00,0x00}}},1.0},
			{ .f={{{0x81,0x80,0x00,0x00,0x00}}},-1.0},
			{ .f={{{0x80,0x00,0x00,0x00,0x00}}},0.5},
			{ .f={{{0xFF,0x7F,0xFF,0xFF,0xFF}}},1.70141183e+38},
			{ .f={{{0xFF,0xFF,0xFF,0xFF,0xFF}}},-1.70141183e+38},
			{ .f={{{0x98,0x35,0x44,0x7A,0x00}}},11879546.0},
			{ .f={{{0x81,0x40,0x0,0x0,0x0}}},1.5},
			{ .f={{{0x82,0x40,0x0,0x0,0x0}}},3},
			{ .f={{{0x82,0x49,0x0F,0xDA,0xA1}}},3.14159265}, // PI
			{ .f={{{0x90,0x80,0x0,0x0,0x0}}},-32768},
			{ .f={{{0x7F,0x5E,0x56,0xCB,0x79}}},.434255942},  // 7F 5E 56 CB 79 = .434255942
			{ .f={{{0x82,0x38,0xAA,0x3B,0x20}}},2.88539007}, // 82 38 AA 3B 20 = 2.88539007
			{ .f={{{0x80,0x35,0x04,0xF3,0x34}}},.707106781}, // 80 35 04 F3 34 = .707106781 = 1/SQR(2)
			{ .f={{{0x80,0x31,0x72,0x17,0xf8}}},.693147181}, // 80 31 72 17 F8 = ln(2)
			{ .f={{{0x9B,0x3E,0xBC,0x1F,0xFD}}},99999999.9}, // 9B 3E BC 1F FD = 99999999.9
			{ .f={{{0x9e,0x6e,0x6b,0x27,0xfd}}},999999999}, // 9E 6E 6B 27 FD = 999999999
			{ .f={{{0x9e,0x6e,0x6b,0x28,0x0}}},1e9}, // 9E 6E 6B 28 00 = 1E9
			//			{ .f={{{0x,0x,0x,0x,0x}}},},
			{ .f={{{0x00,0x00,0x00,0x00,0x00}}},0.0}
  };

int string_to_c64float(char *s,c64float *f)
{
  unsigned char decimal_places_plus_one=0;
  unsigned char sign=0;
  unsigned long mantissa=0;
  unsigned char exp=0;
  unsigned char exp_mode=0;
  unsigned char exp_sign=0;
  unsigned char extra_exp=0;
  
  bzero(f,sizeof(c64float));

  while(*s) {
    if (*s=='-') {
      if (exp_mode) {
	if (!exp_sign) exp_sign=-1;
	else return -1;
      } else {
	if (!sign) sign=-1;
	else return -1;
      }
    }
    else if (*s=='+') {
      if (exp_mode) {
	if (!exp_sign) exp_sign=+1;
	else return -1;
      } else {
	if (!sign) sign=+1;
	else return -1;
      }
    }
    else if (*s=='.') {
      if (exp_mode) return -1;
      if (decimal_places_plus_one) return -1;
      decimal_places_plus_one=1;
    }
    else if (isdigit(*s)) {
      if (exp_mode) {
	exp*=10;
	exp+=(*s)-'0';
      } else {

	// We need to check for mantissa overflow here, since
	// it is legal to enter numbers like 1000000000000000
	// This means that if the mantissa is greater than
	// a certain threshold, then we need to stop accumulating
	// in it, and instead add one to the "extra exponent"

	if (mantissa<(0xFFFFFFFF/10)) {
	  mantissa*=10;
	  
	  mantissa+=(*s)-'0';
	  if (decimal_places_plus_one) decimal_places_plus_one++;
	} else extra_exp++;
      }
    }
    else if ((*s=='E')||(*s=='e')) {
      if (exp_mode) return -1;
      exp_mode=1;
    }

    s++;
  }

  printf("sign=%d, exp_sign=%d, exp=%d, extra_exp=%d, man=%ld,decimal_places=%d\n",
	 sign,exp_sign,exp,extra_exp,mantissa,decimal_places_plus_one);

  // Normalise the mantissa
  unsigned char exp_minus2=0;
  if (!mantissa) {
    // Result is zero.
    f->f.exp=0x00;
    f->f.man0=0; f->f.man1=0; f->f.man2=0; f->f.man3=0;
    return 0;
  }
  
  while(mantissa<0x80000000) {
    printf("  shifting mantissa of 0x%08llx = %lld\n",mantissa,mantissa);
    mantissa<<=1;
    exp_minus2++;
  }
  printf("  mantissa after shifting = 0x%08llx = %llu\n",mantissa,mantissa);

  int exp_total=exp;
  
  if (exp_sign&0x80) {
    exp_total=-exp_total;
  }
  exp_total+=extra_exp;
  if (decimal_places_plus_one) exp_total-=decimal_places_plus_one-1;
  while(exp_total>0) {

    printf("  exponent to apply to mantissa is 10^%d (exp_minus2=%d)\n",exp_total,exp_minus2);
    printf("    manitssa=%ld, exp=2^%d, interim=%.9g\n",mantissa,exp_minus2,pow(2,exp_minus2)*mantissa);
    
    // Multiply by 10

    // multiply by 8 by adding 3 to exp_minus2
    exp_minus2+=3;

    // Then multiply by 5/4 by adding mantissa >>2  to mantissa
    mantissa=mantissa+(mantissa>>2);

    while(mantissa>0xFFFFFFFF) {
      mantissa>>=1;
      exp_minus2++;
    }

    exp_total--;
  }
  
  // Start with this value, then apply x10 or /10 repeatedly and set the sign to
  // complete the process.
  f->f.exp=0x81+(32-1)-exp_minus2;
  if (f->f.exp<0x81) f->f.exp--; // skip exponent = 0x80 for zero
 
  f->f.man0=(mantissa>>24);
  f->f.man0&=0x7f;
  if (sign<0) f->f.man0|=0x80;
  f->f.man1=(mantissa>>16);
  f->f.man2=(mantissa>>8);
  f->f.man3=(mantissa>>0);
  
  return 0;
  
}

int main(int argc,char **argv)
{
  double d;
  c64float f;
  int errors=0;
  
  for(int i=0;test_cases[i].f.f.exp||test_cases[i].f.f.man0||test_cases[i].d;i++) {
    f.f=test_cases[i].f.f;
    d=c64float_to_double(&f);
    printf("C64 float %s = %.9g\n",c64float_to_string(&f),d);

    double err= ((test_cases[i].d-d)/test_cases[i].d);
    if (err<0) err=-err;

    // Allow 3 parts per billion error
    if (err>=0.000000003) {
      printf("ERROR converting from C64 floating point format to double: Result was %.9g, but should have been %.9g (difference = %.9g, error fraction=%.9g)\n",
	     d,test_cases[i].d,test_cases[i].d-d,err);
      errors++;
    }

    char str[80];
    snprintf(str,80,"%.9g",test_cases[i].d);
    string_to_c64float(str,&f);
    
    // Allow 3 parts per billion error
    if (memcmp(&f,&test_cases[i].f,sizeof(c64float))) {
      printf("ERROR parsing string to C64 floating point format: Result was %s (= %.9g)\n",
	     c64float_to_string(&f),c64float_to_double(&f));
      errors++;
    }

    

  }

  printf("%d errors encountered.\n",errors);

  return 0;
}
