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

#include <stdio.h>
#include <sys/select.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <zlib.h>
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include "util.h"
#include "elfdef.h"
#ifdef __arm__
#define NO_LIBUSB
#else
#include <libusb.h>
#endif

// for using libftdi.so
//#define USE_LIBFTDI

int ftdi_interface;

#define BUFFER_MAX_LEN    100000000
#define USB_TIMEOUT     5000
#define ENDPOINT_IN     ((ftdi_interface == 0) ? 0x02 : 0x04)
#define ENDPOINT_OUT    ((ftdi_interface == 0) ? 0x81 : 0x83)
#define USB_CHUNKSIZE   4096
#define USB_INDEX       ((ftdi_interface == 0) ? 1 : 2)

#define USBSIO_RESET                     0 /* Reset the port */
#define USBSIO_RESET_PURGE_RX            1
#define USBSIO_RESET_PURGE_TX            2
#define USBSIO_SET_BAUD_RATE             3 /* Set baud rate */
#define USBSIO_SET_LATENCY_TIMER_REQUEST 9
#define USBSIO_SET_BITMODE_REQUEST       11
#define MAX_ITEM_LENGTH 2000
#define MAX_USB_DEVICECOUNT 100

static int logall = 1;
static int datafile_fd = -1;
static void openlogfile(void);

#include "dumpdata.h"

FILE *logfile;
int usb_bcddevice;
uint8_t bitswap[256];
int last_read_data_length;
struct ftdi_context *global_ftdi;
#if defined(USE_TRACING)
int trace = 1;
#else
int trace;
#endif

#if defined(USE_LOGGING)
static int logging = 1;
#else
static int logging;
#endif
#ifndef NO_LIBUSB
static libusb_device_handle *usbhandle = NULL;
static struct libusb_context *usb_context;
static libusb_device **device_list;
#endif
static USB_INFO usbinfo_array[MAX_USB_DEVICECOUNT];
static int usbinfo_array_index;
static uint8_t usbreadbuffer[USB_CHUNKSIZE];
static uint8_t *usbreadbuffer_ptr = usbreadbuffer;
static int read_size[MAX_ITEM_LENGTH];
static int read_size_ptr;

static void openlogfile(void)
{
    if (!logfile)
        logfile = fopen("/tmp/xx.logfile2", "w");
    if (datafile_fd < 0)
        datafile_fd = creat("/tmp/xx.datafile2", 0666);
}

void memdump(const uint8_t *p, int len, char *title)
{
int i;

    i = 0;
    while (len > 0) {
        if (title && !(i & 0xf)) {
            if (i > 0)
                printf("\n");
            printf("%s: ",title);
        }
        printf("0x%02x, ", *p++);
        i++;
        len--;
    }
    if (title)
        printf("\n");
}

#ifndef USE_LIBFTDI
static int ftdi_write_data(struct ftdi_context *ftdi, const unsigned char *buf, int size)
{
    int actual_length = -1;
    int ret = -1;
    if (logging)
        formatwrite(1, buf, size, "WRITE");
#ifndef NO_LIBUSB
    ret = libusb_bulk_transfer(usbhandle, ENDPOINT_IN, (unsigned char *)buf, size, &actual_length, USB_TIMEOUT);
#endif
    if (ret < 0) {
        fprintf(stderr, "fpgajtag: usb bulk write failed: ret %d req size %d act %d\n", ret, size, actual_length);
        exit(-1);
    }
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 100;
    select(0, NULL, NULL, NULL, &timeout);
    return actual_length;
}
static int ftdi_read_data(struct ftdi_context *ftdi, unsigned char *buf, int size)
{
    int actual_length = 1;
    int count = 0, ret = -1;
    do {
        count++;
#ifndef NO_LIBUSB
        ret = libusb_bulk_transfer (usbhandle, ENDPOINT_OUT, usbreadbuffer, USB_CHUNKSIZE, &actual_length, USB_TIMEOUT);
#endif
        if (ret < 0) {
            fprintf(stderr, "fpgajtag: usb bulk read failed: rc %d\n", ret);
            fprintf(stderr, "size %d act %d count %d\n", size, actual_length, count);
            //exit(-1);
            return -1;
        }
        actual_length -= 2;
        struct timeval timeout;
        timeout.tv_sec = 0;
        timeout.tv_usec = 100;
        select(0, NULL, NULL, NULL, &timeout);
    } while (actual_length == 0);
    if (actual_length > 0) {
        memcpy (buf, usbreadbuffer+2, actual_length);
        if (actual_length != size) {
            fprintf(stderr, "[%s] actual_length %d does not match request size %d\n", __FUNCTION__, actual_length, size);
            //if (!trace)
                //exit(-1);
            }
        if (logging)
            memdumpfile(buf, actual_length, "READ");
    }
    return actual_length;
}
#endif //end if not USE_LIBFTDI

/*
 * Write utility functions
 */
void write_data(uint8_t *buf, int size)
{
    memcpy(usbreadbuffer_ptr, buf, size);
    usbreadbuffer_ptr += size;
}

void write_item(uint8_t *buf)
{
    write_data(buf+1, buf[0]);
}

int buffer_current_size(void)
{
    return usbreadbuffer_ptr - usbreadbuffer;
}
uint8_t *buffer_current_ptr(void)
{
    return usbreadbuffer_ptr;
}

void flush_write(uint8_t *req)
{
    if (req)
        write_item(req);
    int write_length = buffer_current_size();
    usbreadbuffer_ptr = usbreadbuffer;
    if (!write_length)
        return;
    ftdi_write_data(global_ftdi, usbreadbuffer, write_length);
    read_size_ptr = 0;

    const uint8_t *p = usbreadbuffer;
    while (write_length > 0) {
        int plen = 1;
        uint8_t ch = *p;
        unsigned tlen = (p[2] << 8 | p[1]) + 1;
        switch(ch) {
        case 0x85: case 0x87: case 0x8a: case 0xaa: case 0xab:
            break;
        case 0x2e:
            plen = 2;
            break;
        case 0x19: case 0x1b: case 0x2c: case 0x3d: case 0x3f: case 0x4b:
        case 0x6f: case 0x80: case 0x82: case 0x86: case 0x8f:
            plen = 3;
            break;
        default:
            memdump(p-1, write_length, "UNABLE TO PARSE OUTPUT COMMAND");
            exit(-1);
        }
        if (ch & MPSSE_DO_READ) {
            if (ch & MPSSE_BITMODE) {
                int bitsize = *(p+1)+1;
                if (ch & MPSSE_WRITE_TMS)
                    bitsize = 1;
                read_size[read_size_ptr] = -bitsize; /* number of bits */
            }
            else if (ch == 0x2c || ch == 0x3d)       /* DATAR or DATARW */
                read_size[read_size_ptr] = tlen;     /* number of bytes */
            else
                read_size[read_size_ptr] = *(p+1);   /* number of bytes */
            read_size_ptr++;
        }
        p += plen;
        write_length -= plen;
        if (ch == 0x19 || ch == 0x3d) {
            p += tlen;
            write_length -= tlen;
        }
    }
}

/*
 * Read utility functions
 */
uint8_t *read_data(void)
{
    static uint8_t last_read_data[10000];
    int i, j, expected_len = 0, extra_bytes = 0;

    if (trace)
        printf("[%s]\n", __FUNCTION__);
    if (buffer_current_size())
        *usbreadbuffer_ptr++ = SEND_IMMEDIATE; /* tell the FTDI that we are waiting... */
    flush_write(NULL);
    last_read_data_length = 0;
    for (i = 0; i < read_size_ptr; i++) {
        if (read_size[i] > 0)
            expected_len += read_size[i];
        else {
            if (i > 0 && read_size[i-1] < 0)
                extra_bytes++; /* we will squeeze out partial bytes in the processing below */
            else
                expected_len++;
        /* When there are 2 bit operations in a row, this is just accumulating
         * shifted bits into a register for return to user.  When exiting
         * Shift-DR/IR state, the last bit shifted is not performed with DATAWBITS,
         * but with a TMS operation.  For this reason, the combo of 2 bit ops
         * in a row is quite common.
         */
        }
    }
    if (expected_len + extra_bytes)
        ftdi_read_data(global_ftdi, last_read_data, expected_len + extra_bytes);
    last_read_data_length = expected_len;
    if (expected_len) {
        uint8_t *p = last_read_data;
        int validbits = 0;
        for (i = 0; i < read_size_ptr; i++) {
            if (read_size[i] < 0) {
                validbits -= read_size[i];
                if (validbits < 0 || validbits > 8) {
                    printf("[%s] validbits %d big\n", __FUNCTION__, validbits);
                    validbits = 8;
                    //exit(-1);
                }
                *p &= (0xff << (8-validbits));
                /* NOTE: when trying to combine back data bits that result from a TMS
                 * shift with > 1 bit, be aware that the number of bits shifted in reflects the
                 * _number of TMS bits shifted_, not the number of valid data bits (which is
                 * always only 1).
                 */
                if (i > 0 && read_size[i-1] < 0) {
                    *(p-1) = *p >> (8-validbits);    /* put result into LSBs */
                    /* Note: union datatypes work correctly, but int needs the data as MSBs! */
                    for (j = 0; j < expected_len; j++)  /* copies too much, but... */
                        *(p+j) = *(p+j+1);  /* move the data down in the buffer 1 byte */
                }
                else
                    p++;
            }
            else {
                p += read_size[i];
                validbits = 0;
            }
        }
    }
    read_size_ptr = 0;
    return last_read_data;
}

/*
 * USB interface
 */
USB_INFO *fpgausb_init(void)
{
    int i = 0;
#ifndef NO_LIBUSB
    libusb_device *dev;
#define UDESC(A) libusb_get_string_descriptor_ascii(usbhandle, desc.A, \
     usbinfo_array[usbinfo_array_index].A, sizeof(usbinfo_array[usbinfo_array_index].A))

    /*
     * Locate USB interface for JTAG
     */
    if (libusb_init(&usb_context) < 0
     || libusb_get_device_list(usb_context, &device_list) < 0) {
        printf("libusb_init failed\n");
        exit(-1);
    }
    while ((dev = device_list[i++]) ) {
        struct libusb_device_descriptor desc;
        if (libusb_get_device_descriptor(dev, &desc) < 0)
            break;
        if ( desc.idVendor == 0x403 && (desc.idProduct == 0x6001 || desc.idProduct == 0x6010
         || desc.idProduct == 0x6011 || desc.idProduct == 0x6014)) { /* Xilinx */
            usbinfo_array[usbinfo_array_index].dev = dev;
            usbinfo_array[usbinfo_array_index].idVendor = desc.idVendor;
            usbinfo_array[usbinfo_array_index].idProduct = desc.idProduct;
            usbinfo_array[usbinfo_array_index].bcdDevice = desc.bcdDevice;
            usbinfo_array[usbinfo_array_index].bNumConfigurations = desc.bNumConfigurations;
            if (libusb_open(dev, &usbhandle) < 0
             || UDESC(iManufacturer) < 0 || UDESC(iProduct) < 0 || UDESC(iSerialNumber) < 0) {
                printf("Error getting USB device attributes\n");
                exit(-1);
            }
            libusb_close (usbhandle);
            usbhandle = NULL;
            usbinfo_array_index++;
        }
        else if ( desc.idVendor == USB_JTAG_ALTERA && desc.idProduct == 0x6810) { /* Altera */
            usbinfo_array[usbinfo_array_index].dev = dev;
            usbinfo_array[usbinfo_array_index].idVendor = desc.idVendor;
            usbinfo_array[usbinfo_array_index].idProduct = desc.idProduct;
            usbinfo_array[usbinfo_array_index].bcdDevice = desc.bcdDevice;
            usbinfo_array[usbinfo_array_index].bNumConfigurations = desc.bNumConfigurations;
            if (libusb_open(dev, &usbhandle) < 0) {
                printf("Error getting USB device attributes\n");
                exit(-1);
            }
            libusb_close (usbhandle);
            usbhandle = NULL;
            usbinfo_array_index++;
        }
    }
#endif
    return usbinfo_array;
}

void fpgausb_open(int device_index, int interface)
{
    int step = 0;
#ifndef NO_LIBUSB
    int cfg, baudrate = 9600;
    static const char frac_code[8] = {0, 3, 2, 4, 1, 5, 6, 7};
    int best_divisor = 12000000*8 / baudrate;
    unsigned long encdiv = (best_divisor >> 3) | (frac_code[best_divisor & 0x7] << 14);
    struct libusb_config_descriptor *config_descrip;

    ftdi_interface = interface;
    libusb_open(usbinfo_array[device_index].dev, &usbhandle);
    if (libusb_get_config_descriptor(usbinfo_array[device_index].dev, 0, &config_descrip) < 0)
        goto error;
    int configv = config_descrip->bConfigurationValue;
    libusb_free_config_descriptor (config_descrip);
    libusb_detach_kernel_driver(usbhandle, interface);
#define USBCTRL(A,B,C) \
    libusb_control_transfer(usbhandle, (LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_RECIPIENT_DEVICE | LIBUSB_ENDPOINT_OUT), \
			    (A), (B), (C) | USB_INDEX, NULL, 0, USB_TIMEOUT)

    if (libusb_get_configuration (usbhandle, &cfg) < 0)
        goto error;
    step++;
    if ((usbinfo_array[device_index].bNumConfigurations > 0 && cfg != configv && libusb_set_configuration(usbhandle, configv) < 0))
        goto error;
    step++;
#ifndef DARWIN // not supported on Mac-OS
    if (libusb_claim_interface(usbhandle, interface) < 0)
        goto error;
#endif
    step++;
    if (USBCTRL(USBSIO_RESET, USBSIO_RESET, 0) < 0)
        goto error;
    step++;
    if (USBCTRL(USBSIO_SET_BAUD_RATE, (encdiv | 0x20000) & 0xFFFF, ((encdiv >> 8) & 0xFF00)) < 0)
        goto error;
    step++;
    if (USBCTRL(USBSIO_SET_LATENCY_TIMER_REQUEST, 255, 0) < 0)
        goto error;
    step++;
    if (USBCTRL(USBSIO_SET_BITMODE_REQUEST, 0, 0) < 0)
        goto error;
    step++;
    if (USBCTRL(USBSIO_SET_BITMODE_REQUEST, 2 << 8, 0) < 0)
        goto error;
    step++;
    if (USBCTRL(USBSIO_RESET, USBSIO_RESET_PURGE_RX, 0) < 0)
        goto error;
    step++;
    if (USBCTRL(USBSIO_RESET, USBSIO_RESET_PURGE_TX, 0) < 0)
        goto error;
    return;
error:
#endif
    printf("Error opening usb interface: %d\n", step);
    exit(-1);
}

void fpgausb_close(void)
{
    flush_write(NULL);
#ifdef USE_LIBFTDI
int i;
for (i = 0; i < 100; i++)
    ftdi_deinit(global_ftdi); /* flush out logfile */
#else
#ifndef NO_LIBUSB
    if (usbhandle)
        libusb_close (usbhandle);
    usbhandle = NULL;
#endif
#endif
    fflush(stdout);
}
void fpgausb_release(void)
{
    fclose(logfile);
    close(datafile_fd);
#ifndef NO_LIBUSB
    libusb_free_device_list(device_list,1);
#ifndef USE_LIBFTDI
    libusb_exit(usb_context);
#endif
#endif
}

void sync_ftdi(int val)
{
    uint8_t illegal_command[] = { val, SEND_IMMEDIATE };
    uint8_t errorcode_ret[] = { 0xfa, val };
    uint8_t retcode[2];

    ftdi_write_data(global_ftdi, illegal_command, sizeof(illegal_command));
    if (ftdi_read_data(global_ftdi, retcode, sizeof(retcode)) != sizeof(retcode)
     || memcmp(retcode, errorcode_ret, sizeof(errorcode_ret))) {
        printf("%s: error in sync %x\n", __FUNCTION__, val);
        memdump(retcode, sizeof(retcode), "ACTUAL");
    }
}
/*
 * FTDI generic initialization
 */
void init_ftdi(int device_index, int interface)
{
    static uint8_t illegal_command[] = { 0xaa, SEND_IMMEDIATE };
    global_ftdi = (struct ftdi_context *)illegal_command;
    int i;

    fpgausb_open(device_index, interface);            /*** Open selected USB interface ***/
#ifdef USE_LIBFTDI
    global_ftdi = ftdi_new();
    global_ftdi_set_usbdev(ftdi, usbhandle);
    global_ftdi->usb_ctx = usb_context;
    global_ftdi->max_packet_size = 512; //5000;
#endif
    /*
     * Generic command synchronization with ftdi chip
     */
    for (i = 0; i < 4; i++)
        sync_ftdi(0xaa);
    sync_ftdi(0xab);
}

/*
 * File support
 */
uint32_t read_inputfile(const char *filename)
{
    static uint8_t bitfile_header[] = {
        0, 9, 0xf, 0xf0, 0xf, 0xf0, 0xf, 0xf0, 0xf, 0xf0, 0, 0, 1, 'a'};
    static uint8_t filebuf[BUFFER_MAX_LEN];
    static uint8_t uncompressbuf[BUFFER_MAX_LEN];
    static uint8_t gzmagic[] = {0x1f, 0x8b};
    static uint8_t elfmagic[] = {0x7f, 'E', 'L', 'F'};
    int inputfd = 0;   /* default input for '-' is stdin */

    if (!filename)
        return -1;
    if (strcmp(filename, "-")) {
        inputfd = open(filename, O_RDONLY);
        if (inputfd == -1) {
            printf("fpgajtag: Unable to open file '%s'\n", filename);
            exit(-1);
        }
    }
    input_filesize = read(inputfd, filebuf, sizeof(filebuf));
    input_fileptr = filebuf;
    close(inputfd);
    if (input_filesize <= 0 || input_filesize >= sizeof(filebuf) - 1)
        goto badlen;
    if (!memcmp(input_fileptr, elfmagic, sizeof(elfmagic))) {
        int found = 0;
        int entry;
        ELF_HEADER *elfh = (ELF_HEADER *)input_fileptr;
#define IS64() (elfh->h32.e_ident[4] == ELFCLASS64)
#define HELF(A) (IS64() ? elfh->h64.A : elfh->h32.A)
#define SELF(ENT, A) (IS64() ? sech->s64[ENT].A : sech->s32[ENT].A)
        printf("fpgajtag: elf input file, len %d class %d\n", input_filesize, elfh->h32.e_ident[4]);
        int shnum = HELF(e_shnum);
        ELF_SECTION *sech = (ELF_SECTION *)&input_fileptr[HELF(e_shoff)];
        uint8_t *stringTable = &input_fileptr[SELF(HELF(e_shstrndx), sh_offset)];
        for (entry = 0; entry < shnum; ++entry) {
            char *name = (char *)&stringTable[SELF(entry, sh_name)];
            if (!strcmp(name, "fpgadata")) {
                input_fileptr = &input_fileptr[SELF(entry, sh_offset)];
                input_filesize = SELF(entry, sh_size);
                found = 1;
                break;
            }
        }
        if (!found) {
            printf("fpgajtag: attempt to use elf file, but no 'fpgadata' section found\n");
            exit(-1);
        }
    }
    if (!memcmp(input_fileptr, gzmagic, sizeof(gzmagic))) {
        printf("fpgajtag: unzip input file, len %d\n", input_filesize);
        z_stream strm;
        strm.zalloc = Z_NULL;
        strm.zfree = Z_NULL;
        strm.opaque = Z_NULL;
        int ret = inflateInit2(&strm, 16+MAX_WBITS); // inflate gzip'ed file
        if (ret != Z_OK)
            goto badlen;
        strm.next_in = input_fileptr;
        strm.avail_in = input_filesize;
        strm.next_out = uncompressbuf;
        strm.avail_out = sizeof(uncompressbuf);
        ret = inflate(&strm, Z_FINISH);
        inflateEnd(&strm);
        input_filesize = sizeof(uncompressbuf) - strm.avail_out;
        if (ret != Z_STREAM_END)
            goto badlen;
        input_fileptr = uncompressbuf;
    }
    if (!memcmp(bitfile_header, input_fileptr, sizeof(bitfile_header))) {
        uint8_t *inputtemp = input_fileptr;
        input_fileptr += sizeof(bitfile_header) - 1;
        while(*input_fileptr++ < 'e') {
            int len = *input_fileptr++;
            len = (len << 8) | *input_fileptr++;
            input_fileptr += len;
        }
        if (*--input_fileptr == 'e')
            input_fileptr += 1 + sizeof(uint32_t); /* skip over 'e' and length */
        input_filesize -= input_fileptr - inputtemp;
    }

    /*
     * Step 5: Check Device ID
     */
    /*** Read device id from file to be programmed           ***/
    uint32_t tempidcode;
    memcpy(&tempidcode, input_fileptr+0x80, sizeof(tempidcode));
    tempidcode = (M(tempidcode) << 24) | (M(tempidcode >> 8) << 16) | (M(tempidcode >> 16) << 8) | M(tempidcode >> 24);
    return tempidcode;
badlen:
    printf("fpgajtag: Input file length exceeds static buffer size %ld.  You must recompile fpgajtag.\n", (long)sizeof(filebuf));
    exit(-1);
}
