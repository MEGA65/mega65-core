#ifndef S25FLXXXS_H
#define S25FLXXXS_H

extern void * const s25flxxxs;

// char write_dynamic_protection_bits(unsigned int sector_number, BOOL protect);
char write_dynamic_protection_bits(unsigned long address, BOOL protect);

#endif
