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

static void memdumpfile(const unsigned char *p, int len, const char *title)
{
int i;

    openlogfile();
    i = 0;
    while (len > 0) {
        if (!(i & 0xf)) {
            if (i > 0)
                fprintf(logfile, "\n");
            fprintf(logfile, "%s ",title);
        }
        fprintf(logfile, "0x%02x, ", *p++);
        i++;
        len--;
    }
    fprintf(logfile, "\n");
}
static int started = 0;
static void formatwrite(int submit, const unsigned char *p, int len, const char *title)
{
   static unsigned char bitswap[256];
   static int once = 1;
   static const char *header = "    ";
   static char header_data[200];
   if (logall)
       header = "WRITE";
   strcpy(header_data, header);
   strcat(header_data, "   ");
    openlogfile();
   
    while (len > 0) {
        const unsigned char *pstart = p;
        int plen = 1;
        unsigned char ch = *p;
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
            memdumpfile(p-1, len, title);
            return;
        }
        //if (!submit || accum < ACCUM_LIMIT)
            memdumpfile(pstart, plen, header);
        if (started && p[0] == 0x1b && p[1] == 6)
            write(datafile_fd, &bitswap[p[2]], 1);
        p += plen;
        len -= plen;
        if (ch == 0x19 || ch == 0x3d) {
            unsigned tlen = (pstart[2] << 8 | pstart[1]) + 1;
if (tlen > 1500) {
    started = 1;
}
else
    started = 0;    // shutdown before final writes
            if (!started)
                memdumpfile(p, tlen, header_data);
            //if (submit && tlen > 4) 
            else {
                int i;
                for (i = 0; once && i < sizeof(bitswap); i++)
                    bitswap[i] = ((i &    1) << 7) | ((i &    2) << 5)
                       | ((i &    4) << 3) | ((i &    8) << 1)
                       | ((i & 0x10) >> 1) | ((i & 0x20) >> 3)
                       | ((i & 0x40) >> 5) | ((i & 0x80) >> 7);
                unsigned char *pbuf = (unsigned char *)malloc(tlen);
                for (i = 0; i < tlen; i++)
                    pbuf[i] = bitswap[p[i]];
                write(datafile_fd, pbuf, tlen);
                free(pbuf);
                once = 0;
            }
            p += tlen;
            len -= tlen;
        }
    }
    if (len != 0)
        printf("[%s] ending length %d\n", __FUNCTION__, len);
}
