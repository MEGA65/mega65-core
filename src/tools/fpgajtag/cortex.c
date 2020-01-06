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
#include <string.h>
#include <inttypes.h>
#include "util.h"
#include "fpga.h"

static void loaddr(int aread, uint32_t v, int extra3bits)
{
    uint64_t temp = (((uint64_t)v) << 3) | extra3bits;
    ENTER_TMS_STATE('D');
    write_bit(0, 1, 0, 0);
    write_item(DITEM(DATAW(aread, 4), INT32(temp)));
    write_bit(aread, idcode_count > 3 ? 3 : idcode_count, (v>>29) & 0x3f, idcode_count > 2 ? 0 : 'I');
    if (idcode_count > 3)
        write_bit(0, idcode_count - 3, 0, 0);
    ENTER_TMS_STATE('I');
}

static void read_rdbuff(void)
{
    loaddr(DREAD, 0, DPACC_RDBUFF | DPACC_WRITE);
}
/*
 * Functions used in testing Cortex core
 */
static void check_read_cortex(int linenumber, uint32_t *buf, int load)
{
    int i;
    uint8_t *rdata;
    uint32_t *testp = buf+1;

    if (load)
        write_creg(IRREGA_DPACC);
    loaddr(DREAD, 0, DPACC_CTRL | DPACC_WRITE);
    read_rdbuff();
    rdata = read_data(); /* each item read is 35 bits -> 5 bytes */
    for (i = 0; i < last_read_data_length/6; i++) {
        uint64_t ret = 0;              // Clear out MSB before copy
        memcpy(&ret, rdata, 5);        // copy into bottom of uint64 data target
        if ((ret & 7) != DPACC_RESPONSE_OK)       /* IHI0031C_debug_interface_as.pdf: 3.4.3 */
            printf("fpgajtag:%d Info in cortex response %x \n", linenumber, (int)(ret & 7));
        uint32_t ret32 = ret >> 3;
        if ((ret32 & 0x1fffffff) != (*testp & 0x1fffffff)) {
            printf("fpgajtag:%d Info [%ld] act %x expect %x\n", linenumber, (long)(testp - buf), ret32, *testp);
            memdump(rdata, 5, "RX");
        }
        testp++;
        rdata += 5;
    }
}

#define DEBUGID_VAL1  0x0310c002   /* DebugID output? */
#define DEBUGID_VAL2  0x03008002   /* DebugID output? */

static void cortex_pair(uint32_t v)
{
    loaddr(0, DEBUG_REGISTER_BASE | v, AP_TAR);
    loaddr(DREAD, 0x0300c002, AP_DRW);     /* ARM instruction: MOVW R12, #2 */
    loaddr(DREAD, 0x0310c002, AP_DRW);
}

static void write_select(int bus)
{
    write_creg(IRREGA_DPACC);
    loaddr(0,      // Coresight: Table 2-11
        bus ? SELECT_DEBUG/*dedicated Debug Bus*/ : 0/*main system bus*/,
        DPACC_SELECT);
    write_creg(IRREGA_APACC);
}

static void cortex_csw(int wait, int clear_wait)
{
    uint32_t *cresp[2];
    int i;

    write_creg(IRREGA_ABORT);
    loaddr(0, 1, 0);
    write_creg(IRREGA_DPACC);
    loaddr(0, 0x50000033, DPACC_CTRL);
    // in Debug, 2.3.2: CTRL/STAT, Control/Status register
    //CSYSPWRUPREQ,CDBGPWRUPREQ,STICKYERR,STICKYCMP,STICKYORUN,ORUNDETECT
    if (!clear_wait)
        cresp[0] = (uint32_t[]){2, CORTEX_DEFAULT_STATUS, CORTEX_DEFAULT_STATUS,};
    else {
        write_creg(IRREGA_APACC);
        cortex_pair(0x2000 | DBGDSCRext);
        cresp[0] = (uint32_t[]){5, 0, 0, 0, CORTEX_DEFAULT_STATUS, CORTEX_DEFAULT_STATUS,};
    }
    cresp[1] = (uint32_t[]){3, 0, 0x00800042/*SPIStatus=High*/, CORTEX_DEFAULT_STATUS};
    write_creg(IRREGA_DPACC);
    loaddr(clear_wait?DREAD:0, 0, DPACC_CTRL | DPACC_WRITE);
    for (i = 0; i < 2; i++) {
        if (trace)
            printf("[%s:%d] wait %d i %d\n", __FUNCTION__, __LINE__, wait, i);
        check_read_cortex(__LINE__, cresp[i], i);
        write_select(i);
        loaddr(DREAD, 0, AP_CSW | DPACC_WRITE);
        if (wait)
           tmsw_delay(3, 3 - i);
    }
    check_read_cortex(__LINE__, (uint32_t[]){3, SELECT_DEBUG, DEFAULT_CSW, CORTEX_DEFAULT_STATUS,}, 1);
}

static void tar_read(uint32_t v)
{
    loaddr(DREAD, DEBUG_REGISTER_BASE | v, AP_TAR);
    read_rdbuff();
}
static void tar_write(uint32_t v)
{
    write_creg(IRREGA_APACC);
    loaddr(0, v, AP_TAR);
    read_rdbuff();
}

static void read_csw(int wait, uint32_t val3)
{
#define VALC          0x15137030
uint32_t *creturn[] = {(uint32_t[]){10, SELECT_DEBUG, val3,
        VALC, VALC, 1, 1, DEBUGID_VAL1, DEBUGID_VAL1, 0, CORTEX_DEFAULT_STATUS,},
                       (uint32_t[]){12, 0, 0, 0, 0,
        VALC, VALC, 1, 1, DEBUGID_VAL1, DEBUGID_VAL1, 0, CORTEX_DEFAULT_STATUS,}};
int i;
static uint32_t cread[] = {2, 0x80000002};
static uint32_t address_table[] = {ADDRESS_SLCR_ARM_PLL_CTRL, ADDRESS_SLCR_ARM_CLK_CTRL};
uint32_t *cresp[] = {(uint32_t[]){3, 0, DEFAULT_CSW, CORTEX_DEFAULT_STATUS,},
          (uint32_t[]){3, SELECT_DEBUG, DEFAULT_CSW, CORTEX_DEFAULT_STATUS,}};

    for (i = 0; i < 2; i++) {
        write_select(i);
        loaddr(DREAD, cread[i], AP_CSW);
        if (wait)
            tmsw_delay(3, 3 - i);
        check_read_cortex(__LINE__, cresp[i], 1);
    }
    write_select(0);
#define VAL3          0x1f000200
#define VAL5          0x00028000
    for (i = 0; i < 2; i++) {
        loaddr(DREAD, address_table[i], AP_TAR);
        if (wait)
            tmsw_delay(3, 3);
        read_rdbuff();
        if (wait)
            tmsw_delay(3, 3);
        else
            tmsw_delay(0, 1);
    }
    check_read_cortex(__LINE__, (uint32_t[]){6, 0, DEFAULT_CSW,
          VAL5, VAL5, VAL3, CORTEX_DEFAULT_STATUS,}, 1);
    if (wait) {
        tar_write(ADDRESS_DEVCFG_MCTRL);
        tmsw_delay(0, 1);
        check_read_cortex(__LINE__, (uint32_t[]){3, VAL3, 0, CORTEX_DEFAULT_STATUS,}, 1);
    }
    write_select(1);
    for (i = 0; i < 2; i++) {
        if (i == 1) {
            write_creg(IRREGA_APACC);
            cortex_pair(DBGDSCRext);
        }
        tar_read((i * 0x2000) | DBGDIDR);
        tar_read((i * 0x2000) | DBGPRSR);
        tar_read((i * 0x2000) | DBGDSCRext);
        tar_read((i * 0x2000) | DBGPCSR);
        check_read_cortex(__LINE__, creturn[i], 1);
    }
}

void cortex_bypass(int cortex_nowait)
{
    cortex_csw(1-cortex_nowait, 0);
    if (!cortex_nowait) {
        read_csw(1, 0);
        cortex_csw(0, 1);
    }
    read_csw(0, VAL3);
    write_creg(IRREGA_APACC);
    cortex_pair(0x2000 | DBGDSCRext);
    tar_read(DBGPRSR);
    tar_read(DBGDSCRext);
    check_read_cortex(__LINE__, (uint32_t[]){8, 0, 0, 0, 0, 1, 1,
            DEBUGID_VAL1, CORTEX_DEFAULT_STATUS,}, 1);
#define VAL6          0xe001b400
    tar_write(DEBUG_REGISTER_BASE | DBGITR);
    check_read_cortex(__LINE__, (uint32_t[]){3, DEBUGID_VAL1, VAL6, CORTEX_DEFAULT_STATUS,}, 1);
    tar_write(DEBUG_REGISTER_BASE | 0x2000 | DBGPRSR);
    tar_read(0x2000 | DBGDSCRext);
    check_read_cortex(__LINE__, (uint32_t[]){5, VAL6, 1, 1, DEBUGID_VAL1, CORTEX_DEFAULT_STATUS,}, 1);
    tar_write(DEBUG_REGISTER_BASE | 0x2000 | DBGITR);
    check_read_cortex(__LINE__, (uint32_t[]){3, DEBUGID_VAL1, VAL6, CORTEX_DEFAULT_STATUS,}, 1);
}
