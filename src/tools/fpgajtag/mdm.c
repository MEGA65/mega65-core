// Copyright (c) 2014 Quanta Research Cambridge, Inc.

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
// Xilinx MicroBlaze Debug Module(MDM) v3.1 documented in: pg115-mdm.pdf
// and in data/ip/xilinx/mdm_v3_1/hdl/vhdl/jtag_control.vhd

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <arpa/inet.h>
#define __STDC_FORMAT_MACROS
#include <inttypes.h>
#include "util.h"
#include "fpga.h"

/*
 * MicroBlaze Debug Module support
 * PG115 MDM v3.1
 */
#define MDM_ID_LENGTH      6
#define MDM_SYNC_CONST  0x69 /* 01101001 */
#define MDM_READ_CONFIG 0x0c /* 00001100 */
static int device_type, idgt2, idcogt3, idmult2;

void access_mdm(int version, int pre, int amatch)
{
    int toploop, loop_count, match = amatch;
    int shift_enable = 0;
    switch (version) {
    case 0:
        ENTER_TMS_STATE('R');
        loop_count = above2
            + (device_type == DEVICE_VC707 || device_type == DEVICE_AC701
              || (jtag_index && (device_type != DEVICE_ZEDBOARD)));
        if (!amatch) {
            shift_enable = dcount != 0;
            loop_count = 1;
        }
        break;
    case 1:
        loop_count = 4;
printf("[%s:%d] device %x idcode_count %d jtag_index %d\n", __FUNCTION__, __LINE__, device_type, idcode_count, jtag_index);
        if (device_type == DEVICE_AC701)
            loop_count = 3;
        if (device_type == DEVICE_VC707 && idcode_count == 1)
            loop_count = 6;
        if (device_type == DEVICE_VC707 && idcode_count == 2 && jtag_index == 0)
            loop_count = 6;
        if (device_type == DEVICE_VC707 && idcode_count == 3)
            loop_count = 5;
        if (device_type == DEVICE_ZEDBOARD)
            loop_count = 2;
        if (device_type == DEVICE_ZC702)
            loop_count = 1;
        break;
    case 2:
        loop_count = 2; 
        match = (device_type != DEVICE_ZC702 && (!dcount || jtag_index)) + 10 * (idcogt3);
        break;
    }
    for (toploop = 0; toploop < loop_count; toploop++) {
        int idindex = (!version && toploop) * amatch * (toploop+1); // this is 2nd time calling w/ version == 0!
        int innerl, testi, flip = 0;
        int btemp = !version && toploop == 1;
        int top_wait = toploop || version != 2;
        int izero = 1;
flush_write(NULL);
DPRINT("[%s:%d] version %d toploop %d/%d pre %d match %d loop_count %d shift_enable %d\n", __FUNCTION__, __LINE__, version, toploop, loop_count, pre, match, loop_count, shift_enable);
        if (version || !toploop) {
            ENTER_TMS_STATE('R');
            read_idcode(version != 2 && toploop == pre);
        }
int inmax = (1 + (version != 0) * above2) * idmult2;
        for (innerl = 0; innerl < inmax; innerl++) {
            int ione = idcogt3 && innerl/idmult2 == 1;
            int intwo = idcogt3 && innerl/idmult2 != 2;
            int v0_3 = idcogt3 && version == 0;
            int nonfirst = flip != 0;
            int address_last = (idcode_count - 1) == idindex;
            int fillwidth = dcount + 1 - v0_3 * izero * (!address_last)
                - (version == 2) * intwo - (version == 1) * ione;
            int extracond = v0_3 && address_last;
            int bcount = (!btemp && idgt2) * above2;
            int indl;
            for (indl = 0; indl < 3 + !top_wait; indl++) {
                for (testi = 0; testi < 4; testi++) {
DPRINT("[%s:%d] version %d innerl %d inmax %d j %d/%d testi %d idindex %d address_last %d\n", __FUNCTION__, __LINE__, version, innerl, inmax, indl, 3 + !top_wait, testi, idindex, address_last);
                    write_cbypass(0, idindex);
DPRINT("[%s:%d] idindex %d j %d testi %d\n", __FUNCTION__, __LINE__, idindex, indl, testi);
                    write_dirreg(IRREG_USER2, idindex);
DPRINT("[%s:%d] btemp %d flip %d izero %d extracond %d fillwidth %d\n", __FUNCTION__, __LINE__, btemp, flip, izero, extracond, fillwidth);
                    write_bit(0,((btemp && !(idcogt3 && version == 1 && izero))
                             || extracond) * fillwidth, 0, 0);
                    if (testi > 1) {
                        write_bit(0, MDM_ID_LENGTH - address_last, MDM_READ_CONFIG, 0);
DPRINT("[%s:%d] j %d testi %d\n", __FUNCTION__, __LINE__, indl, testi);
                        write_bit(0, (!extracond) * bcount, 0, 0);
                        idle_to_shift_dr(0);
                        write_bit(0, (nonfirst != 0) * (idcode_count - nonfirst), 0, 0);
DPRINT("[%s:%d] j %d testi %d\n", __FUNCTION__, __LINE__, indl, testi);
                        write_bit(0, (btemp
                                     || extracond) * fillwidth, 0, 0);
                    }
                    if (testi) {
                        int bcond4 = ione || (intwo && btemp);
                        static uint8_t data = MDM_SYNC_CONST;
                        write_bytes(0, 0, &data, 1, SEND_SINGLE_FRAME, 0, 0, 1);
DPRINT("[%s:%d] j %d testi %d\n", __FUNCTION__, __LINE__, indl, testi);
                        write_bit(0, 2, 0, 0);
DPRINT("[%s:%d] j %d testi %d\n", __FUNCTION__, __LINE__, indl, testi);
                        write_bit(0, bcond4, 0, 0);
DPRINT("[%s:%d] ione %d intwo %d btemp %d bcond4 %d\n", __FUNCTION__, __LINE__, ione, intwo, btemp, bcond4);
                        write_bit(0, idcode_count - 1 - bcond4, 0, 0);
                    }
DPRINT("[%s:%d] idindex %d j %d testi %d bcount %d dcount %d address_last %d\n", __FUNCTION__, __LINE__, idindex, indl, testi, bcount, dcount, address_last);
                    uint32_t ret = fetch_result(-1, 0, sizeof(uint32_t), -1);
DPRINT("[%s:%d] bottom toploop %d/%d match %d izero %d version %d innerl %d/%d flip %d/%d j %d testi %d\n", __FUNCTION__, __LINE__, toploop, loop_count, match, izero, version, innerl, inmax, flip, idmult2, indl, testi);
                    if (ret != 0)
                        printf("[%s:%d] nonzero USER2 %x\n", __FUNCTION__, __LINE__, ret);
                }
            }
            if (++flip >= idmult2) {
                flip = 0;
                if (izero && found_cortex != -1) {
                    if (!shift_enable)
                        cortex_bypass(top_wait);
                    idindex++;
                }
                btemp |= idcogt3 || version;
                izero = 0;
            }
            idindex++;
        }
flush_write(NULL);
DPRINT("[%s:%d] bottomt toploop %d/%d match %d version %d pre %d dcount %d\n", __FUNCTION__, __LINE__, toploop, loop_count, match, version, pre, dcount);
        if (!version) {
            shift_enable |= 1;
            pre |= idcogt3;
            match += amatch;
        }
    }
}
