/*
  Routines to test C64 floating point conversion

*/

#include <stdio.h>

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
  d=man|0x80000000;
  int exp=f->f.exp;
  while(exp>0x81) { d=d*2.0; exp--; }
  while(exp<0x81) { d=d/2.0; exp++; }

  d=d/0x80000000;

  if (man&0x80000000) d=-d;
  
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
			{ .f={{{0x00,0x00,0x00,0x00,0x00}}},0.0}
  };

int main(int argc,char **argv)
{
  double d;
  c64float f;
  int errors=0;
  
  for(int i=0;test_cases[i].f.f.exp||test_cases[i].f.f.man0||test_cases[i].d;i++) {
    f.f=test_cases[i].f.f;
    d=c64float_to_double(&f);
    printf("C64 float %s = %g\n",c64float_to_string(&f),d);

    double err= ((test_cases[i].d-d)/test_cases[i].d);
    if (err<0) err=-err;
    
    if (err>=0.000000003) {
      printf("ERROR: Result was %g, but should have been %g (difference = %g, error fraction=%g)\n",
	     d,test_cases[i].d,test_cases[i].d-d,err);
      errors++;
    }

  }

  printf("%d errors encountered.\n",errors);

  return 0;
}
