
void m65_io_enable(void);
unsigned char lpeek(long address);
void lpoke(long address, unsigned char value);
void lcopy(long source_address, long destination_address,
	   unsigned int count);
void lfill(long destination_address, unsigned char value,
	   unsigned int count);
#define POKE(X,Y) (*(unsigned char*)(X))=Y
#define PEEK(X) (*(unsigned char*)(X))
