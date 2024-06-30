#include "mf_buffers.h"

// used by QSPI routines
unsigned char data_buffer[512];

// used by SD card routines
unsigned char buffer[512];

unsigned char cfi_data[512];
