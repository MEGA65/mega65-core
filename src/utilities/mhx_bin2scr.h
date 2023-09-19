#ifndef MHX_BIN2SCR_H
#define MHX_BIN2SCR_H

#include <stdint.h>

#define MHX_RDX_DEC 0
#define MHX_RDX_BIN 1
#define MHX_RDX_OCT 2
#define MHX_RDX_HEX 3
#define MHX_RDX_UPPER 0x80
extern uint8_t cdecl mhx_bin2scr(uint8_t radix, uint8_t length, uint32_t bin, char *strbuf);

#endif /* MHX_BIN2SCR_H */