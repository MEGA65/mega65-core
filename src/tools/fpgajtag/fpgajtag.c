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
//
// FTDI interface documented at:
//     http://www.ftdichip.com/Documents/AppNotes/AN2232C-01_MPSSE_Cmnd.pdf
// Xilinx Series7 Configuation documented at:
//     ug470_7Series_Config.pdf
// ARM JTAG-DP registers documented at:
//     DDI0314H_coresight_components_trm.pdf
// ARM DPACC/APACC programming documented at:
//     IHI0031C_debug_interface_as.pdf

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <arpa/inet.h>
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include <unistd.h>
#include <dirent.h>
#include "util.h"
#include "fpga.h"

#ifdef USE_LOGGING
#define ENTER() { fflush(stdout); fprintf(stderr,"Entering %s()\n",__FUNCTION__); fflush(stderr); }
#define EXIT() { fflush(stdout); fprintf(stderr,"Exiting %s()\n",__FUNCTION__); fflush(stderr); }
#define LOGNOTE(M) {fflush(stdout); fprintf(stderr,"%s:%d:%s():%s\n",__FILE__,__LINE__,__FUNCTION__,M); fflush(stderr); }
#else
#define ENTER()
#define EXIT()
#define LOGNOTE(M)
#endif  


#define FILE_READSIZE          6464
#define MAX_SINGLE_USB_DATA    4046
#define IDCODE_ARRAY_SIZE        20
#define SEGMENT_LENGTH   256 /* sizes above 256bytes seem to get more bytes back in response than were requested */

extern char *serial_port;

uint8_t *input_fileptr;
int input_filesize, found_cortex = -1, jtag_index = -1, dcount, idcode_count;
int tracep ;//= 1;

static int debug, verbose, skip_idcode, match_any_idcode, trailing_len, first_time_idcode_read = 1, dc2trail, interface;
static USB_INFO *uinfo;
static uint32_t idcode_array[IDCODE_ARRAY_SIZE], idcode_len[IDCODE_ARRAY_SIZE];
static uint8_t *rstatus = DITEM(CONFIG_DUMMY, CONFIG_SYNC, CONFIG_TYPE2(0),
            CONFIG_TYPE1(CONFIG_OP_READ, CONFIG_REG_STAT, 1), SINT32(0));
static int befbits, afterbits;

#ifndef USE_MDM
void access_mdm(int version, int pre, int amatch)
{
  ENTER();
    flush_write(DITEM(TMSW, 2, 0xe7)); /* strange pattern, so we can find in trace log */
    EXIT();
}
#endif

/*
 * Support for GPIOs from Digilent JTAG module to h/w design.
 *
 * SMT1 does not have any external GPIO connections (KC705).
 *
 * SMT2 has GPIO0/1/2 for user use.  In the datasheet for
 * the SMT2, it has an example connecting GPIO2 -> PS_SRST_B
 * on the Zynq-7000. (but the zedboard uses SMT1)
 */
static void pulse_gpio(int adelay)
{
    int delay;
#define GPIO_DONE            0x10
#define GPIO_01              0x01
#define SET_LSB_DIRECTION(A) SET_BITS_LOW, 0xe0, (0xea | (A))

    ENTER();
    ENTER_TMS_STATE('I');
    switch (adelay) {
    case 1250:  delay = CLOCK_FREQUENCY/800; break;
    case 12500: delay = CLOCK_FREQUENCY/80; break;
    default:
           printf("pulse_gpio: unsupported time delay %d\n", adelay);
           exit(-1);
    }
    write_item(DITEM(SET_LSB_DIRECTION(GPIO_DONE | GPIO_01),
                     SET_LSB_DIRECTION(GPIO_DONE)));
    while(delay > 65536) {
        write_item(DITEM(CLK_BYTES, INT16(65536 - 1)));
        delay -= 65536;
    }
    write_item(DITEM(CLK_BYTES, INT16(delay-1)));
    flush_write(DITEM(SET_LSB_DIRECTION(GPIO_DONE | GPIO_01),
                     SET_LSB_DIRECTION(GPIO_01)));
    EXIT();
}
static void set_clock_divisor(void)
{
  ENTER();
    flush_write(DITEM(TCK_DIVISOR, INT16(30000000/CLOCK_FREQUENCY - 1)));
    EXIT();
}

static char current_state, *lasttail;
static int match_state(char req)
{
    return req == 'X' || !current_state || current_state == req
       || (current_state == 'S' && req == 'D')
       || (current_state == 'D' && req == 'S');
}
void write_tms_transition(char *tail)
{
  ENTER();
    char *p = tail+2;
    uint8_t temp[] = {TMSW, 0, 0};
    int len = 0;

    if (!match_state(tail[0]))
        printf("fpgajtag: TMS Error: current %c target %s last %s\n", current_state, tail, lasttail);
    lasttail = tail;
    current_state = tail[1];
    while (*p) {
        len++;
        temp[2] = (temp[2] >> 1) | ((*p++ << 7) & 0x80);
    }
    temp[1] = len-1;
    temp[2] >>= 8 - len;
    write_data(temp, sizeof(temp));
    EXIT();
}
void ENTER_TMS_STATE(char required)
{
  ENTER();
    char temp = current_state == 'D' ? 'S' : current_state;
    static char *tail[] = {"PS10", /* Pause-DR -> Shift-DR */
        "EI10",  /* Exit1/Exit2 -> Update -> Idle */"RI0", /* Reset -> Idle */
        "SI110", /* Shift-DR -> Update-DR -> Idle */"SP10",/* Shift-IR -> Pause-IR */
        "SE1",   /* Shift-IR -> Exit1-IR */ "SU11", /* Shift-DR -> Update-DR */
        "UD100", /* Update -> Shift-DR */   "ID100",/* Idle -> Shift-DR */
        "RD0100",/* Reset -> Shift-DR */    "IR111",/* Idle -> Reset */
        "PR11111",/* Pause -> Reset */      "IS1100", /* Idle -> Shift-IR */
			   "ED1100", /* Exit1-IR ->  -> Shift-DR */
			   NULL};
    char **p = tail; 
    while(*p) {
        if (temp == (*p)[0] && required == (*p)[1])
            write_tms_transition(*p);
        p++;
    }
    if (!match_state(required))
        printf("[%s:%d] %c should be %c\n", __FUNCTION__, __LINE__, current_state, required);
    EXIT();
}
void tmsw_delay(int delay_time, int extra)
{
  ENTER();
#define SEND_IDLE(A) write_item(DITEM(TMSW, (A), 0))
    int i;
    ENTER_TMS_STATE('I');
    if (extra)
        SEND_IDLE(0);
    for (i = 0; i < delay_time; i++)
        SEND_IDLE(6);
    if (extra)
        SEND_IDLE(extra);
    EXIT();
}
static void marker_for_reset(int stay_reset)
{
  ENTER();
    ENTER_TMS_STATE('R');
    flush_write(DITEM(TMSW, stay_reset, 0x7f));
    EXIT();
}
static void reset_mark_clock(int clock)
{
  ENTER();
    if (clock)
        access_mdm(2, 0, 1);
    else
        access_mdm(0, 1, 0);
DPRINT("[%s:%d]\n", __FUNCTION__, __LINE__);
    marker_for_reset(0);
    if (clock)
        set_clock_divisor();
    write_tms_transition("RR1");
    flush_write(NULL);
    EXIT();
}
void write_bit(int read, int bits, int data, char target_state)
{
  ENTER();
    int extrabit = 0;
    ENTER_TMS_STATE('S');
    if (bits >= 0) {
        if (bits)
            write_item(DITEM(DATAWBIT | read, bits-1, M(data)));
        extrabit = (data << (7 - bits)) & 0x80;
    }
    if (target_state) {
        uint8_t *cptr = buffer_current_ptr();
        ENTER_TMS_STATE(target_state);
        cptr[0] |= read; // this is a TMS instruction to shift state
        cptr[2] |= extrabit; // insert 1 bit of data here
    }
    EXIT();
}
static void write_req(int read, uint8_t *req, int opttail)
{
  ENTER();
    write_bytes(read, 0, req+1, req[0], SEND_SINGLE_FRAME, opttail, 0, 0);
    EXIT();
}
static void write_fill(int read, int width, int tail)
{
  ENTER();
    static uint8_t ones[] = DITEM(0xff, 0xff, 0xff, 0xff);
    if (width > 7) {
        ones[0] = width/8;
        width -= 8 * ones[0];
        write_req(read, ones, 0);
    }
    write_bit(read, width, 0xff, tail);
    EXIT();
}

void write_bytes(uint8_t read,
    char target_state, uint8_t *ptrin, int size, int max_frame_size, int opttail, int swapbits, int exchar)
{
  ENTER();
    ENTER_TMS_STATE('S');
    while (size > 0) {
        int i, rlen = size;
        if (rlen > max_frame_size)
            rlen = max_frame_size;
        int tlen = rlen;
        if (rlen < max_frame_size && opttail > 0)
            tlen--;                   // last byte is actually loaded with DATAWBIT command
        write_item(DITEM(DATAW(read, tlen)));
        uint8_t *cptr = buffer_current_ptr();
        write_data(ptrin, tlen);
        if (swapbits)
            for (i = 0; i < tlen; i++)
                cptr[i] = bitswap[cptr[i]];
        ptrin += tlen;
        if (rlen < max_frame_size) {
            if (opttail > 0) {
                exchar = *ptrin++;
                if (swapbits)
                    exchar = bitswap[exchar];
                opttail = -7;
            }
            if (target_state == 'E')
                write_fill(0, dc2trail, 0);
            write_bit(read, -opttail, exchar, target_state);
        }
        size -= max_frame_size;
        if (size > 0)
            flush_write(NULL);
    }
    EXIT();
}

void idle_to_shift_dr(int idindex)
{
  ENTER();
    ENTER_TMS_STATE('D');
    write_bit(0, idindex, 0xff, 0);
    EXIT();
}
static uint8_t *write_pattern(int idindex, uint8_t *req, int target_state)
{
  ENTER();
   LOGNOTE("Calling idle_to_shift_dr()");
   idle_to_shift_dr(idindex);
   LOGNOTE("Switched to shift_dr");
    write_bytes(DREAD, target_state, req+1, req[0], SEND_SINGLE_FRAME, 1, 0, 0);
    LOGNOTE("Wrote bytes. Now reading...");
    return read_data();
    EXIT();
}

static void write_int32(uint8_t *data)
{
  ENTER();
    if (!data)
        return;
    int size = *data++ / sizeof(uint32_t);
    while (size--) {
        write_bytes(0, 0, data, sizeof(uint32_t), SEND_SINGLE_FRAME, 0, 0, 0);
        data += sizeof(uint32_t);
    }
    EXIT();
}

static uint64_t read_data_int(uint8_t *bufp)
{
  ENTER();
    uint64_t ret = 0;
    uint8_t *backp = bufp + last_read_data_length;
    while (backp > bufp)
        ret = (ret << 8) | bitswap[*--backp];  //each byte is bitswapped
    return ret;
    EXIT();
}

/*
 * Read/validate IDCODE from device to be programmed
 */
#define REPEAT5(A) INT32(A), INT32(A), INT32(A), INT32(A), INT32(A)
#define REPEAT10(A) REPEAT5(A), REPEAT5(A)

#define IDCODE_PPAT INT32(0xff), REPEAT10(0xff), REPEAT5(0xff)
// IDCODE return is 32 bits long according to Xilinx BSDL file
#define IDCODE_VPAT INT32(0xffffffff), REPEAT10(0xffffffff), REPEAT10(0xffffffff), \
            REPEAT10(0xffffffff), INT32(0xffffffff)

static uint8_t idcode_ppattern[] = DITEM(IDCODE_PPAT);
static uint8_t idcode_presult[] = DITEM(IDCODE_PPAT); // filled in with idcode
static uint8_t idcode_vpattern[] = DITEM(IDCODE_VPAT);
static uint8_t idcode_vresult[] = DITEM(IDCODE_VPAT); // filled in with idcode
void read_idcode(int prereset)
{
  ENTER();
  int i, offset = 0;
    uint32_t temp[IDCODE_ARRAY_SIZE];

    if (prereset)
        write_tms_transition("RR1");

    LOGNOTE("Checkpoint pre marker_for_reset()");

    // Send 1 + 4 TMS reset bits?
    marker_for_reset(4);

    // PGS: Try to explicitly send the IDCODE command.
    // Once we get this working, we know we can then adapt for BOUNDARY command.
    // The following seems to work:
    // 1. Switch to idle.
    // 2. Switch to Select IR scan
    // 3. Clock a null bit (maybe to switch to capture IR ?)
    // 4. Send IDCODE command. Not sure why we need 5 instead of 6 for length/
    // 5. Switch to IDLE after done
    ENTER_TMS_STATE('I');
    ENTER_TMS_STATE('S');
    write_bit(0, 0, 0xff, 0);     // Select first device on bus
    write_bit(0, 5, IRREG_IDCODE, 0);     // Send IDCODE command
    ENTER_TMS_STATE('I');
    
    LOGNOTE("Checkpoint pre write-pattern");

    // This sends the transition to Shift-DR, but doesn't seem to actually send
    // the IDCODE command.  Does the FPGA default to IDCODE?
    // Yes: This seems to be the case, according to here:
    // https://forums.xilinx.com/t5/Spartan-Family-FPGAs-Archived/Spartan-3AN-200-JTAG-Idcode-debugging-on-a-new-board/td-p/131792
    uint8_t *rdata = write_pattern(0, idcode_ppattern, 'I');

    LOGNOTE("Checkpoint post write-pattern");

    if (first_time_idcode_read) {    // only setup idcode patterns on first call!
        first_time_idcode_read = 0;
        memcpy(&idcode_presult[1], idcode_ppattern+1, idcode_ppattern[0]);
        memcpy(&idcode_vresult[1], idcode_vpattern+1, idcode_vpattern[0]);
        while (memcmp(idcode_presult+1, rdata, idcode_presult[0]) && offset < sizeof(uint32_t) * (IDCODE_ARRAY_SIZE-1)) {
            memcpy(&temp[idcode_count++], rdata+offset, sizeof(uint32_t));
            memcpy(idcode_presult+offset+1, rdata+offset, sizeof(uint32_t));   // copy 2nd idcode
            memcpy(idcode_vresult+offset+1, rdata+offset, sizeof(uint32_t));   // copy 2nd idcode
            offset += sizeof(uint32_t);
        }
    }
    if (memcmp(idcode_presult+1, rdata, idcode_presult[0])) {
        memdump(idcode_presult+1, idcode_presult[0], "READ_IDCODE: EXPECT");
        memdump(rdata, idcode_presult[0], "READ_IDCODE: ACTUAL");
    }
    for (i = 0; i < idcode_count; i++) {
        idcode_array[i] = temp[idcode_count - 1 - i];
        if (idcode_array[i] == CORTEX_IDCODE) {
            found_cortex = i;
            idcode_len[i] = CORTEX_IR_LENGTH;
        }
        else {
            idcode_array[i] &= 0x0fffffff;  /* Xilinx 7 Series: 4 MSB are 'version': UG470, Fig 5-8 */
            idcode_len[i] = XILINX_IR_LENGTH;
        }
    }
    EXIT();
}

static void init_device(int extra)
{
  ENTER();
  LOGNOTE("Disable loopback. Disable divide by 5 of master clock.");
    write_item(DITEM(LOOPBACK_END, DIS_DIV_5));
    LOGNOTE("Set clock divisor");
    set_clock_divisor();
    write_item(DITEM(SET_BITS_LOW, 0xe8, 0xeb, SET_BITS_HIGH, 0x20, 0x30));
    if (extra)
        write_item(DITEM(SET_BITS_HIGH, 0x30, 0x00, SET_BITS_HIGH, 0x00, 0x00));
    LOGNOTE("For TAP to reset state.");
    write_tms_transition("XR11111");       /*** Force TAP controller to Reset state ***/
    EXIT();
}
static void get_deviceid(int device_index, int interface)
{
  ENTER();
    init_ftdi(device_index, interface);
    /*
     * Set JTAG clock speed and GPIO pins for our i/f
     */
    idcode_count = 0;
    init_device(uinfo[device_index].bcdDevice == 0x700); /* not a zedboard */
    first_time_idcode_read = 1;
    ENTER_TMS_STATE('R');
    read_idcode(1);
    EXIT();
}
/*
 * Functions for setting Instruction Register(IR)
 */
void write_irreg(int read, int command, int idindex, char tail)
{
  ENTER();
    int i;
    befbits = 0;
    afterbits = 0;
    for (i = 0; i < idcode_count; i++) {
        if (i < idindex)
            afterbits += idcode_len[i];
        else if (i > idindex)
            befbits += idcode_len[i];
    }
    if(tracep)
      printf("[%s:%d] read %d command %x idindex %d bef %d aft %d\n", __FUNCTION__, __LINE__, read, command, idindex, befbits, afterbits);
    flush_write(NULL);
    ENTER_TMS_STATE('I');
    ENTER_TMS_STATE('S');
    write_fill(0, befbits, 0);
    int trim = (read && idindex != idcode_count);
    if (afterbits && !trim) {
        if (idindex != idcode_count)
            write_bit(0, idcode_len[idindex], command, 0);
        write_fill(read, afterbits - 1, tail);
    }
    else
        write_bit(read, idcode_len[idindex] - 1, command, tail);
    EXIT();
}
static int write_cirreg(int read, int command)
{
  ENTER();
    int ret = 0, target_state = (jtag_index && read ? 'P' : 'E');
    write_irreg(read, command, jtag_index, target_state);
    if (read) {
        ret = read_data_int(read_data());
        if (target_state == 'P')
            write_fill(0, afterbits - 1, 'E');
    }
    ENTER_TMS_STATE('I');
    EXIT();
    return ret;
}
int write_cbypass(int read, int idindex)
{
  ENTER();
    int ret = 0;
    write_irreg(read, IRREG_BYPASS_EXTEND, idindex, 'I');
    if (read)
        ret = read_data_int(read_data());
    ENTER_TMS_STATE('I');
    EXIT();
    return ret;
}
void write_dirreg(int command, int idindex)
{
  ENTER();
    write_irreg(0, EXTEND_EXTRA | command, idindex, 'I');
    idle_to_shift_dr(0);
    write_bit(0, idcode_count - 1 - idindex, 0, 0);
    EXIT();
}
void write_creg(int regname)
{
  ENTER();
    write_irreg(0, regname, found_cortex, 'U');
    EXIT();
}

static void send_data_file(int read, int extra_shift, uint8_t *pdata,
    int psize, uint8_t *pre, uint8_t *post, int opttail, int swapbits)
{
  ENTER();
    static uint8_t zerod[] = DITEM(0, 0, 0, 0, 0, 0, 0);
    int tremain;
    int mid = jtag_index && jtag_index != idcode_count -1;
//1 //count 1/2 cortex 0 dcount 0 trail 0       -7 jf
//1 //count 0/2 cortex -1 dcount 1 trail 1      -7 j
//1 //count 1/2 cortex -1 dcount 1 trail 0      -7 j1
//1 //count 0/3 cortex 1 dcount 1 trail 2       -6 jfa
//1 //count 0/3 cortex -1 dcount 2 trail 2      -6 j_1
//2 //count 1/3 cortex -1 dcount 2 trail 1      -7 j_2
//1 //count 2/3 cortex -1 dcount 2 trail 0      -6 j0_1
//1 //count 0/4 cortex 2 dcount 2 trail 3 ..... -5 jfa2_2
//2 //count 1/4 cortex 2 dcount 2 trail 2 ..... -7 jfa2_1
    write_cirreg(read, IRREG_CFG_IN);
    idle_to_shift_dr(trailing_len);
    write_int32(pre);
    for (tremain = 0; tremain < (1 + mid) && idcode_count > 1; tremain++)
        write_req(0, zerod, idcode_count - 9 + tremain * (found_cortex != -1)
            - mid * (idcode_count - 1 - jtag_index));
    write_int32(post);
    int limit_len = MAX_SINGLE_USB_DATA - buffer_current_size();
    while(psize) {
        int size = FILE_READSIZE;
        if (psize < size)
            size = psize;
        psize -= size;
        write_bytes(0, (!psize && !extra_shift) ? 'E' : 'P', pdata,
            size, limit_len, psize || opttail, swapbits, 1);
        flush_write(NULL);
        limit_len = MAX_SINGLE_USB_DATA;
        pdata += size;
    };
    if (extra_shift)
        write_fill(0, 0, 'E');
    ENTER_TMS_STATE('I');
    EXIT();
}

static void write_above2(int read, int idindex)
{
  ENTER();
    write_bit(read, (0 == idcode_count - 1 - idindex) * (idindex - 1), 0, 'I');
    EXIT();
}
uint32_t fetch_result(int idindex, int command, int resp_len, int fd)
{
  ENTER();
    int j;
    uint32_t ret = 0;

    if (idindex >= 0 && resp_len) {
        write_dirreg(command, idindex);
DPRINT("[%s:%d] idindex %d\n", __FUNCTION__, __LINE__, idindex);
        write_bit(0, (dcount - 2) * (idindex && 0 != idcode_count - 1 - idindex), 0, 0);
    }
DPRINT("[%s:%d]\n", __FUNCTION__, __LINE__);
    while (resp_len > 0) {
        int size = resp_len;
        if (size > SEGMENT_LENGTH)
            size = SEGMENT_LENGTH;
        resp_len -= size;
        if (idindex)
            write_item(DITEM(DATAR(size)));
        else
            write_item(DITEM(DATAR(size - 1), DATARBIT, 0x06));
        if (resp_len <= 0)
            write_above2((!idindex) * DREAD, idindex);
        uint8_t *rdata = read_data();
        uint8_t sdata[] = {SINT32(*(uint32_t *)rdata)};
        ret = *(uint32_t *)sdata;
        for (j = 0; j < size; j++)
            rdata[j] = bitswap[rdata[j]];
        if (fd != -1) {
            static int skipsize = BITFILE_ITEMSIZE; /* 1 framebuffer of delay until data is output */
            if (skipsize) {
                int skip = skipsize;
                if (skip > size)
                    skip = size;
                skipsize -= skip;
                size -= skip;
                rdata += skip;
                resp_len += skip;
            }
            if (size)
                write(fd, rdata, size);
        }
    }
    EXIT();
    return ret;
}

/*
 * Read Xilinx configuration status register
 * In ug470_7Series_Config.pdf, see "Accessing Configuration Registers
 * through the JTAG Interface" and Table 6-3.
 */
static uint32_t readout_seq(int idindex, uint8_t *req, int resp_len, int fd)
{
  ENTER();
    write_dirreg(IRREG_CFG_IN, idindex);
    write_req(0, req, !idindex);
DPRINT("[%s:%d] idindex %d\n", __FUNCTION__, __LINE__, idindex);
    write_above2(0, idindex);    
    uint32_t r= fetch_result(idindex, IRREG_CFG_OUT, resp_len, fd);
    EXIT();
    return r;
}

static void readout_status0(void)
{
  ENTER();
    int ret, idindex;

    for (idindex = 0; idindex < idcode_count; idindex++) {
DPRINT("[%s:%d] idindex %d/%d\n", __FUNCTION__, __LINE__, idindex, idcode_count);
        if (idindex != found_cortex)
            if ((ret = fetch_result(idindex, IRREG_USERCODE, sizeof(uint32_t), -1)) != 0xffffffff)
                printf("fpgajtag: USERCODE value %x\n", ret);
        write_cbypass(DREAD, idcode_count);
        if (idindex != found_cortex) {
            write_cbypass(DREAD, idcode_count);
            write_cbypass(DREAD, idcode_count);
            ENTER_TMS_STATE('R');
DPRINT("[%s:%d] idindex %d/%d\n", __FUNCTION__, __LINE__, idindex, idcode_count);
            ret = readout_seq(idindex, rstatus, sizeof(uint32_t), -1);
            uint32_t status = ret >> 8;
            if (verbose && (bitswap[M(ret)] != 2 || status != 0x301900))
                printf("[%s:%d] expect %x mismatch %x\n", __FUNCTION__, __LINE__, 0x301900, ret);
            printf("STATUS %08x done %x release_done %x eos %x startup_state %x\n", status,
                status & 0x4000, status & 0x2000, status & 0x10, (status >> 18) & 7);
            ENTER_TMS_STATE('R');
        }
    }
    EXIT();
}

/*
 * Configuration Register Read Procedure (JTAG), ug470_7Series_Config.pdf,
 * Table 6-4.
 */
static uint32_t read_config_reg(uint32_t data)
{
  ENTER();
    uint8_t *req = DITEM(CONFIG_SYNC,
        CONFIG_TYPE1(CONFIG_OP_NOP, 0,0),
        CONFIG_TYPE1(CONFIG_OP_READ, data, 1),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0,0),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0,0),
        CONFIG_TYPE1(CONFIG_OP_WRITE, CONFIG_REG_CMD, CONFIG_CMD_WCFG),
        CONFIG_CMD_DESYNC,
        CONFIG_TYPE1(CONFIG_OP_NOP, 0,0));
    uint8_t constant4[] = {INT32(4)};

    send_data_file(0, 0, constant4, sizeof(constant4), DITEM(CONFIG_DUMMY), req, !jtag_index, 0);
    write_cirreg(0, IRREG_CFG_OUT);
    uint64_t ret = read_data_int(
        write_pattern(trailing_len, DITEM(INT32(0)), jtag_index ? 'P' : 'E'));
    if (jtag_index)
        write_fill(0, dc2trail, 'E');
    write_cirreg(0, IRREG_BYPASS);
    EXIT();
    return ret;
}

static void read_config_memory(int fd, uint32_t size)
{
  ENTER();
#if 0
    readout_seq(0, DITEM(CONFIG_DUMMY, CONFIG_SYNC,
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0),
        CONFIG_TYPE1(CONFIG_OP_READ,CONFIG_REG_STAT,1),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0)), sizeof(uint32_t), -1);
    readout_seq(0, DITEM(CONFIG_DUMMY, CONFIG_SYNC,
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0),
        CONFIG_TYPE1(CONFIG_OP_WRITE,CONFIG_REG_CMD,1), CONFIG_CMD_RCRC,
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0)), 0, -1);
#endif
    write_cirreg(0, IRREG_JSHUTDOWN);
    tmsw_delay(6, 0);
    readout_seq(0, DITEM( CONFIG_DUMMY, CONFIG_SYNC,
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0),
        CONFIG_TYPE1(CONFIG_OP_WRITE,CONFIG_REG_CMD,1), CONFIG_CMD_RCFG,
        CONFIG_TYPE1(CONFIG_OP_WRITE,CONFIG_REG_FAR,1), 0,
        CONFIG_TYPE1(CONFIG_OP_READ,CONFIG_REG_FDRO,0),
        CONFIG_TYPE2(size),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0),
        CONFIG_TYPE1(CONFIG_OP_NOP, 0, 0)), size, fd);
    EXIT();
}

void init_fpgajtag(const char *serialno, const char *filename, uint32_t file_idcode)
{
  ENTER();
    int i, j;

    /*
     * Initialize USB, FTDI
     */
    for (i = 0; i < sizeof(bitswap); i++)
        bitswap[i] = BSWAP(i);
    uinfo = fpgausb_init();   /*** Initialize USB interface ***/
    int usb_index = 0;
    for (i = 0; uinfo[i].dev; i++) {
        fprintf(stderr, "fpgajtag: %s:%s:%s; bcd:%x", uinfo[i].iManufacturer,
            uinfo[i].iProduct, uinfo[i].iSerialNumber, uinfo[i].bcdDevice);
        if (!filename) {
            idcode_count = 0;
            if (uinfo[i].idVendor == USB_JTAG_ALTERA) {
                 printf("Altera device");
            }
            else
                get_deviceid(i, interface);  /*** Generic initialization of FTDI chip ***/
            fpgausb_close();
            if (idcode_count)
                fprintf(stderr, "; IDCODE:");
            for (j = 0; j < idcode_count; j++)
                fprintf(stderr, "  %x", idcode_array[j]);
        }
        fprintf(stderr, "\n");
    }
    //    if (!filename)
    //        exit(1);
    while (1) {
        if (!uinfo[usb_index].dev) {
            fprintf(stderr, "fpgajtag: Can't find usable usb interface\n");
            exit(-1);
        }
        if (uinfo[usb_index].idVendor == USB_JTAG_ALTERA) {
        }
        else if (!serialno || !strcmp(serialno, (char *)uinfo[usb_index].iSerialNumber))
	  {
	    // Found the correct interface.
	    // Now extract the real serial port name as well, so that monitor_load can use it.

#if 0
	    fprintf(stderr,"USB device info: dev=%p, idVendor=%x, idProduct=%x, bcdDevice=%x(0d%d)\n",
		    uinfo[usb_index].dev,
		    uinfo[usb_index].idVendor,
		    uinfo[usb_index].idProduct,
		    uinfo[usb_index].bcdDevice,
		    uinfo[usb_index].bcdDevice
		    );
	    fprintf(stderr,"USB bus=%d, port_number=%d\n",
		    libusb_get_bus_number(uinfo[usb_index].dev),
		    libusb_get_port_number(uinfo[usb_index].dev));
#endif
	    int bus=libusb_get_bus_number(uinfo[usb_index].dev);
	    int port=libusb_get_port_number(uinfo[usb_index].dev);
	    
	    // Iterate through /sys/bus/usb-serial/devices to see if any of the entries there have
	    // symlinks that make sense for this device bus and port number.
	    {
	      DIR *d=opendir("/sys/bus/usb-serial/devices");
	      if (d) {
		struct dirent *de=NULL;
		while ((de=readdir(d))!=NULL) {
		  char link[1024]="";
		  char path[1024];
		  snprintf(path,1024,"/sys/bus/usb-serial/devices/%s",de->d_name);
		  int len=readlink(path,link,sizeof(link));
		  link[len]=0;
		  // fprintf(stderr,"  Checking '%s' -> '%s'\n",path,link);
		  char match[1024];
		  snprintf(match,1024,"/%d-%d/%d-%d:1.1",bus,port,bus,port);
		  if (strstr(link,match)) {
		    char serial_path[1024];
		    snprintf(serial_path,1024,"/dev/%s",de->d_name);
		    fprintf(stderr,"Auto-detected serial port '%s'\n",serial_path);
		    serial_port=strdup(serial_path);
		  }
		}
		closedir(d);
	      }
	    }
	    
            break;
	  }
        usb_index++;
    }

    /*
     * Set JTAG clock speed and GPIO pins for our i/f
     */
    get_deviceid(usb_index, interface);          /*** Generic initialization of FTDI chip ***/
    for (i = 0; i < idcode_count; i++)       /*** look for device matching file idcode ***/
        if (idcode_array[i] == file_idcode || file_idcode == 0xffffffff || match_any_idcode) {
            jtag_index = i;
            if (skip_idcode-- <= 0)
                break;
        }
    if (jtag_index == -1) {
        printf("[%s] id %x from file does not match actual id %x\n", __FUNCTION__, file_idcode, idcode_array[0]);
        exit(-1);
    }
    EXIT();
}

int min(int a, int b)
{
  if (a < b)
      return a;
  else
      return b;
}

int fpgajtag_main(char *bitstream,char *serialport)
{
  ENTER();
    uint32_t ret;
    int i, rflag = 0, lflag = 0, mflag = 0, cflag = 0, xflag = 0, rescan = 0;
    const char *serialno = serialport;

    match_any_idcode = 1;
    logfile = stdout;
    opterr = 0;

    const char *filename = bitstream;

    /*
     * Read input file
     */
    uint32_t file_idcode = read_inputfile(filename);

    if (mflag)
	setuid( 0 );

    if (xflag || mflag) {
	int magic[2];
	memcpy(&magic, input_fileptr+32, 8);
	if (magic[0] != 0x000000bb || magic[1] != 0x11220044) {
	    uint8_t *buffer = (uint8_t *)malloc(input_filesize);
	    int i;
	    if (debug) fprintf(stderr, "mismatched magic: %08x.%08x expected %08x.%08x\n", magic[0], magic[1], 0x000000bb, 0x11220044);
	    memcpy(buffer, input_fileptr, input_filesize);
	    for (i = 0; i < input_filesize/4; i++) {
		int *bufl = (int *)buffer;
		int *inputl = (int *)input_fileptr;
		bufl[i] = ntohl(inputl[i]);
	    }
	    memcpy(&magic, buffer+32, 8);
	    if (debug) fprintf(stderr, "updated magic: %08x.%08x expected %08x.%08x\n", magic[0], magic[1], 0x000000bb, 0x11220044);
	    input_fileptr = buffer;
	}
	 int rc = setuid(0);
	 const char *filename = (mflag) ? "/lib/firmware/fpga.bin" : "/dev/xdevcfg";
	 if (rc != 0)
	 fprintf(stderr, "setuid status %d uid %d euid %d\n",
		 rc, getuid(), geteuid());
        int fd = open(filename, (mflag) ? (O_WRONLY|O_CREAT) : O_WRONLY);
	if (fd < 0) {
	  fprintf(stderr, "[%s:%d] failed to open %s: fd=%d errno=%d %s\n", __FUNCTION__, __LINE__, filename, fd, errno, strerror(errno));
	  exit(-1);
	}
	while (input_filesize) {
	  int len = write(fd, input_fileptr, min(input_filesize, 4096));
	  if (len <= 0) {
	    fprintf(stderr, "[%s:%d] failed to write to %s: len=%d errno=%d %s\n", __FUNCTION__, __LINE__, filename, len, errno, strerror(errno));
	    exit(-1);
	  }
	  input_filesize -= len;
	  input_fileptr += len;
	}
        close(fd);
	if (mflag) {
	    filename = "/sys/class/fpga_manager/fpga0/firmware";
	    fd = open(filename, O_WRONLY);
	    if (fd < 0) {
		fprintf(stderr, "[%s:%d] failed to open %s: fd=%d errno=%d %s\n", __FUNCTION__, __LINE__, filename, fd, errno, strerror(errno));
		exit(-1);
	    }
	    filename = "fpga.bin";
	    write(fd, filename, strlen(filename));
	    close(fd);
	}
        exit(0);
    }

    dcount = idcode_count - (found_cortex != -1) - 1;
    trailing_len = idcode_count - 1 - jtag_index;
    dc2trail = dcount == 2 && !trailing_len;
printf("count %d/%d cortex %d dcount %d trail %d\n", jtag_index, idcode_count, found_cortex, dcount, trailing_len);

    /*
     * See if we are reading out data
     */
    if (rflag) {
        fprintf(stderr, "fpgajtag: readout fpga config into xx.bozo\n");
        /* this size was taken from the TYPE2 record in the original bin file
         * (and must be converted to bits)
         */
        int fd = creat("xx.bozo", 0666);
        uint32_t header = {CONFIG_TYPE2_RAW(0x000f6c78)};
        header = htonl(header);
        write(fd, &header, sizeof(header));
        read_config_memory(fd, 0x000f6c78 * sizeof(uint32_t));
        close(fd);
        return 0;
    }
    /*
     * See if we are in 'command' mode with IR/DR info on command line
     */
    if (cflag) {
        process_command_list();
        goto exit_label;
    }

    reset_mark_clock(1);
    marker_for_reset(0);
    write_tms_transition("RR1");

    /*
     * Use a pattern of 0xffffffff to validate that we actually understand all the
     * devices in the JTAG chain.  (this list was set up in read_idcode()
     * on the first call
     */
    marker_for_reset(0);
    ENTER_TMS_STATE('I');
    uint8_t *rdata = write_pattern(0, idcode_vpattern, 'P');
    if (last_read_data_length != idcode_vresult[0]
     || memcmp(idcode_vresult+1, rdata, idcode_vresult[0])) {
        memdump(idcode_vresult+1, idcode_vresult[0], "IDCODE_VALIDATE: EXPECT");
        memdump(rdata, last_read_data_length, "IDCODE_VALIDATE: ACTUAL");
    }

    marker_for_reset(0);
    readout_status0();
    access_mdm(1, 0, 99999);

    /*
     * Step 2: Initialization
     */
    marker_for_reset(0);
    write_cirreg(0, IRREG_JPROGRAM);
    write_cirreg(0, IRREG_ISC_NOOP);
    pulse_gpio(12500 /*msec*/);
    if ((ret = write_cirreg(DREAD, IRREG_ISC_NOOP)) != INPROGRAMMING)
        printf("[%s:%d] NOOP/INPROGRAMMING mismatch %x\n", __FUNCTION__, __LINE__, ret);

    /*
     * Step 6: Load Configuration Data Frames
     */
    printf("fpgajtag: Starting to send file\n");
    send_data_file(DREAD, !dcount && jtag_index, input_fileptr, input_filesize,
        NULL, DITEM(INT32(0)), !(jtag_index && dcount), 1);
    printf("fpgajtag: Done sending file\n");

    /*
     * Step 8: Startup
     */
    pulse_gpio(1250 /*msec*/);
    if ((ret = read_config_reg(CONFIG_REG_BOOTSTS)) != (jtag_index ? 0x03000000 : 0x01000000))
        printf("[%s:%d] CONFIG_REG_BOOTSTS mismatch %x\n", __FUNCTION__, __LINE__, ret);
    write_cirreg(0, IRREG_JSTART);
    tmsw_delay(14, 1);
    if ((ret = write_cirreg(DREAD, IRREG_BYPASS)) != FINISHED)
        printf("[%s:%d] mismatch %x\n", __FUNCTION__, __LINE__, ret);
    if ((ret = read_config_reg(CONFIG_REG_STAT)) !=
            (found_cortex != -1 ? 0xf87f1046 : 0xfc791040))
        if (verbose)
            printf("[%s:%d] CONFIG_REG_STAT mismatch %x\n", __FUNCTION__, __LINE__, ret);

    marker_for_reset(0);
    ret = write_cbypass(DREAD, idcode_count) & 0xff;
    if (ret == FIRST_TIME)
        printf("fpgajtag: bypass first time %x\n", ret);
    else if (ret == PROGRAMMED)
        printf("fpgajtag: bypass already programmed %x\n", ret);
    else
        printf("fpgajtag: bypass unknown %x\n", ret);

    reset_mark_clock(0);
    ret = readout_seq(jtag_index, rstatus, sizeof(uint32_t), -1);
    int status = ret >> 8;
    if (verbose && (bitswap[M(ret)] != 2 || status != 0xf07910))
        printf("[%s:%d] expect %x mismatch %x\n", __FUNCTION__, __LINE__, 0xf07910, ret);
    printf("STATUS %08x done %x release_done %x eos %x startup_state %x\n", status,
        status & 0x4000, status & 0x2000, status & 0x10, (status >> 18) & 7);
    access_mdm(0, 0, 1);
    rescan = 1;

    /*
     * Cleanup and free USB device
     */
exit_label:
    fpgausb_close();
    fpgausb_release();
    if (rescan) {
	int rc = execlp("pciescanportal", "arg", (char *)NULL); /* rescan pci bus to discover device */
	fprintf(stderr, "fpgajtag: ERROR failed to run pciescanportal: %s\n", strerror(errno));
	return rc;
    }
    EXIT();
    return 0;
}

#include "boundary_scan.c"
