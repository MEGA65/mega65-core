#include <stdio.h>
#include <string.h>
#include <stdint.h>

#define POKE(a,v) *((uint8_t *)a)=(uint8_t)v
#define PEEK(a) ((uint8_t)(*((uint8_t *)a)))


unsigned short mdio_read_register(unsigned char addr,
				  unsigned char reg)
{
  unsigned short result=0;
  unsigned char i;

  // Use new MIIM interface
  POKE(0xD6e6L,(reg&0x1f)+((addr&7)<<5));
  // Reading takes a little while...
  for(result=0;result<32000;result++) continue;
  result=PEEK(0xD6E7L);
  result|=PEEK(0xD6E8L)<<8;  

  return result;
  
}


#define TEST(reg,v,bit,msg) { if (v&(1<<bit)) printf("$%x.%x : %s\n",reg,bit,msg); }

int main(void)
{
  unsigned char x=0,v,a;

  unsigned short vv;
  
  POKE(0xd02f,0x47);
  POKE(0xd02f,0x53);
  POKE(0,65); // make sure we don't go too fast

  POKE(0xd6e0,0x01);

  for(a=0;a!=0x20;a++)
    if (mdio_read_register(a,0)!=0xffff)
      break;
  if (a==0x20) {
    printf("Could not find PHY address.\n");
    return 0;
  }
  printf("PHY is address $%x\n",a);

  // Parse register 0
  x=0; vv=mdio_read_register(a,x);
  printf("Reg $%x = $%x\n",x,vv);
  TEST(0,vv,15,"Software Reset");
  TEST(0,vv,14,"Loopback mode");
  TEST(0,vv,13,"100Mbps (if not auto-neg)");
  TEST(0,vv,12,"Auto-neg enabled");
  TEST(0,vv,11,"Power-Down");
  TEST(0,vv,10,"Isolate");
  TEST(0,vv,9,"Restart auto-neg");
  TEST(0,vv,8,"Full-duplex");
  TEST(0,vv,7,"Enable COL test");

  x=1; vv=mdio_read_register(a,x);
  printf("Reg $%x = $%x\n",x,vv);
  TEST(1,vv,15,"T4 capable");
  TEST(1,vv,14,"100TX FD capable");
  TEST(1,vv,13,"100TX HD capable");
  TEST(1,vv,12,"10T FD capable");
  TEST(1,vv,11,"10T HD capable");
  TEST(1,vv,6,"Preamble suppression");
  TEST(1,vv,5,"Auto-neg complete");
  TEST(1,vv,4,"Remote fault");
  TEST(1,vv,3,"Can auto-neg");
  TEST(1,vv,2,"Link is up");
  TEST(1,vv,1,"Jabber detected");
  TEST(1,vv,0,"Supports ex-cap regs");

  for(x=0x10;x<0x20;x++) {
    vv=mdio_read_register(a,x);
    printf("Reg $%x = $%x",x,vv);
    if (x&1) printf("\n"); else printf(",    ");
   }
  
  return 0;
}
