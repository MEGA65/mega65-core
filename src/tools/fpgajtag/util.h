// Copyright (c) 2014 Quanta Research Cambridge, Inc.
// Original author: John Ankcorn

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

#ifdef USE_LIBFTDI
#include "ftdi.h"
#else
#define MPSSE_WRITE_NEG 0x01   /* Write TDI/DO on negative TCK/SK edge*/
#define MPSSE_BITMODE   0x02   /* Write bits, not bytes */
#define MPSSE_READ_NEG  0x04   /* Sample TDO/DI on negative TCK/SK edge */
#define MPSSE_LSB       0x08   /* LSB first */
#define MPSSE_DO_WRITE  0x10   /* Write TDI/DO */
#define MPSSE_DO_READ   0x20   /* Read TDO/DI */
#define MPSSE_WRITE_TMS 0x40   /* Write TMS/CS */
#define SET_BITS_LOW    0x80
#define SET_BITS_HIGH   0x82
#define LOOPBACK_END    0x85
#define TCK_DIVISOR     0x86
#define DIS_DIV_5       0x8a
#define CLK_BYTES       0x8f
#define SEND_IMMEDIATE  0x87
struct ftdi_context;
#endif

#define M(A)               ((A) & 0xff)
#define USB_JTAG_ALTERA     0x9fb  /* idVendor */

extern FILE *logfile;
extern int usb_bcddevice;
extern uint8_t bitswap[256];
extern int last_read_data_length;
extern int trace;
extern uint8_t *input_fileptr;
extern int input_filesize;
extern struct ftdi_context *global_ftdi;

void memdump(const uint8_t *p, int len, char *title);

typedef struct {
    void          *dev;
    int           idVendor;
    int           idProduct;
    int           bcdDevice;
    int           bNumConfigurations;
    unsigned char iSerialNumber[64], iManufacturer[64], iProduct[128];
} USB_INFO;
USB_INFO *fpgausb_init(void);
void fpgausb_open(int device_index, int interface);
void fpgausb_close(void);
void fpgausb_release(void);
void init_ftdi(int device_index, int interface);

void write_data(uint8_t *buf, int size);
void write_item(uint8_t *buf);
void flush_write(uint8_t *req);
int buffer_current_size(void);
uint8_t *buffer_current_ptr(void);

uint8_t *read_data(void);
void tmsw_delay(int delay_time, int extra);
void idle_to_shift_dr(int extra);
uint32_t read_inputfile(const char *filename);
void sync_ftdi(int val);
