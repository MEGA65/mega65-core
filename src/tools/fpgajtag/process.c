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
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "util.h"
#include "fpga.h"

#define BUFFER_MAX_LEN    100000000
#define TOHEX(A) (((A) >= '0' && (A) <= '9') ? (A) - '0' : \
                  ((A) >= 'A' && (A) <= 'F') ? (A) - 'A' + 10: \
                  ((A) >= 'a' && (A) <= 'f') ? (A) - 'a' + 10: -1)

void process_command_list(void)
{
    static uint8_t tempbuf[BUFFER_MAX_LEN];
    static uint8_t tempbuf2[BUFFER_MAX_LEN];
    int i, mode = -1;
    char *str = NULL;
    
    while (*input_fileptr) {
        uint8_t *bufp = tempbuf;
        char * stro = NULL;
        int len = 0;
        uint8_t ch = *input_fileptr;
        if (ch == '#' || ch == '\n' || ch == ' ' || ch == '\t' || ch == '\r') {
            *input_fileptr++ = 0;
            while(ch == '#' && *input_fileptr && *input_fileptr != '\n')
                input_fileptr++;
            if (!str)
                continue;
        }
        else {
            if (!str)
                str = (char *)input_fileptr;
            input_fileptr++;
            continue;
        }
        if (trace)
            printf("[%s:%d] %s\n", __FUNCTION__, __LINE__, str);
        if (!strcmp(str, "IR")) {
            mode = 0;
        }
        else if (!strcmp(str, "DR")) {
            mode = 1;
        }
        else {
        if (strlen(str) > 2 && !memcmp(str, "0x", 2)) {
            stro = (char *)str + 2;
            while (stro[0] && stro[1]) {
                uint8_t temp = TOHEX(stro[0]) << 4 | TOHEX(stro[1]);
                stro += 2;
                *bufp++ = temp;
            }
        }
        else { /* decimal */
            *((int32_t *)bufp) = strtol(str, &stro, 10);
            bufp += sizeof(int32_t);
        }
        len = bufp - tempbuf;
        if (trace)
            memdump(tempbuf, len, "VAL");
        if (*stro)
            printf("fpgajtag: didn't parse entire number '%s'\n", str);
        else if (mode == -1)
            printf("fpgajtag: mode not set!\n");
        else if (mode == 0) {
            int t = tempbuf[0];
            t |= (t & 0xe0) << 3;  /* high order byte contains bits 5 and higher */
            write_irreg(0, t, 0, 'I');
            flush_write(NULL);
        }
        else {
            idle_to_shift_dr(0);
            for (i = 0; i < len; i++)
                tempbuf2[i] = tempbuf[len-1-i];
            write_bytes(DREAD, 'E', tempbuf2, len, SEND_SINGLE_FRAME, 1, 0, 1);
            if (found_cortex != -1)
                 write_tms_transition("EE0101");
            ENTER_TMS_STATE('I');
            uint8_t *rdata = read_data();
            int i = 0;
            while(i < len) {
                uint8_t t = rdata[len-1-i];
                printf("%02x", t);
                i++;
            }
            printf("\n");
            //memdump(rdata, len, "           RVAL");
        }
        }
        str = NULL;
    }
    flush_write(NULL);
}
