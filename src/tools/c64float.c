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
	mantissa*=10;
	mantissa+=(*s)-'0';
	if (decimal_places_plus_one) decimal_places_plus_one++;
      }
    }
    else if ((*s=='E')||(*s=='e')) {
      if (exp_mode) return -1;
      exp_mode=1;
    }

    s++;
  }

  printf("sign=%d, exp_sign=%d, exp=%d, man=%ld,decimal_places=%d\n",
	 sign,exp_sign,exp,mantissa,decimal_places_plus_one);
  
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
      printf("ERROR parsing string to C64 floating point format: Result was %s\n",c64float_to_string(&f));
      errors++;
    }

    

  }

  printf("%d errors encountered.\n",errors);

  return 0;
}
