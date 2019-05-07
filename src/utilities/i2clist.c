#include <stdio.h>

const volatile unsigned char *i2c_master=(unsigned char *)0xd6d0L;

int main(void)
{
  printf("Hello world\r");
}
