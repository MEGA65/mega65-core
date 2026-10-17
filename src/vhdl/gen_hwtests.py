#!/usr/bin/env python3
"""Build SSNAIL's on-hardware test disk, ssnailhw.d81, in one go.

    python3 gen_hwtests.py [OUTDIR]          (default: ssnail-hwtests)

Then mount OUTDIR/ssnailhw.d81 on the MEGA65 and RUN "00.CPU RAM".  Each
test is a small BASIC 65 program; on success it RUNs the next one, on failure
it stops and says what it saw.  Any of them can also be run on its own:

    00.CPU RAM        finds the SDRAM read timing that works ($D7FE bit 5:
                      one read wait state fewer) and keeps it for the rest;
                      then the CPU writes and reads each RAM directly ($D7FE
                      bit 4 selects HyperRAM or SDRAM), and the two are distinct
    01.REGISTERS      ID, version, capabilities, region registers, load port
    02.LUMP FETCH     SSNAIL fetches a CPU-written HALT, in each RAM
    03.LUMP STR       one LUMP write (LI + STR), in each RAM
    04.LUMP COPY      1 KB COPY within each RAM, and SDRAM -> HyperRAM
    10.SCALAR .. 16.FGEMV
                      the simulation benches' programs: the CPU puts the
                      image in SSNAIL's $8000000 RAM, SSNAIL runs it, the CPU
                      compares the output with the emulator's
    20.GEMV SPEED     Q8_0 and Q4_0 GEMV speed on the real memory
    30.LOAD PORT      load port writes, read back by the CPU, with a dump

and, standalone (not in the chain):

    90.HYPERRAM MODE which HyperRAM controller settings ($BFFFFF2 fast
                      command/read/write and read phase, $BFFFFF5 read time
                      adjust) work on this board: read and write paths
                      tested separately, CPU only
    91.MEM BENCH      DMAgic throughput for SDRAM and each HyperRAM setting
    92.SDRAM TRAIN    the SDRAM read capture training: status, window, and
                      the pass maps; R trains again, +/- steps the phase

The CPU is the trusted reference throughout: it writes jobs and data into
whichever RAM SSNAIL uses and reads the results straight back (CPU attic
prefetch and caches off while the tests run).

Needs: VICE's petcat (BASIC 65 tokenising), the SSNAIL tools (./SSNAIL or
SSNAIL_TOOLS).  Uses VICE's c1541 for the disk image if it is installed,
otherwise writes the .d81 itself.
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.environ.get("SSNAIL_TOOLS") or os.path.join(HERE, "SSNAIL")
sys.path.insert(0, TOOLS)
import ssnail_isa as I                     # noqa: E402
from ssnail_convert import Asm             # noqa: E402
import ssnail_sim as S                     # noqa: E402

B = I.HYPERRAM_BASE

# name, description, generator, package, init bytes, expect offset, bytes, halt pc
TESTS = [
    ("10.scalar", "SCALAR AND CONTROL", "ssn1", "gen_step1.py", "step1_pkg.vhdl",
     0x600, 0x600, 0xC0, 0x80001A0),
    ("11.vector", "DEQROW VADD VMUL CVT16", "ssn2", "gen_step2.py", "step2_pkg.vhdl",
     0x1000, 0x1000, 0x1000, None),
    ("12.gemv", "GEMV Q8_0/Q4_0, ACC, F16 OUT", "ssn3", "gen_step3.py", "step3_pkg.vhdl",
     0x2000, 0x1000, 0x1000, None),     # (MXFP4 / IQ4_NL / Q5_0 weights above $1000)
    ("13.norms", "RMSNORM LAYERNORM SILU GELU MEANROWS", "ssn4", "gen_step4.py", "step4_pkg.vhdl",
     0x1000, 0x1000, 0x1000, None),
    ("14.attn", "ROPE ARGMAX ATTN", "ssn5", "gen_step5.py", "step5_pkg.vhdl",
     0x1000, 0x1000, 0x1000, None),
    ("15.kgemv", "K-QUANT AND IQ GEMV, DEQROW", "ssn6", "gen_step6.py", "step6_pkg.vhdl",
     0x6000, 0x6000, 0xA000, None),
    ("16.fgemv", "F16 BF16 F32 GEMV (FLOAT LANE)", "ssn7", "gen_step7.py", "step7_pkg.vhdl",
     0x6000, 0x6000, 0xA000, None),
]
PERF_ITERS = (300, 500)                 # Q8_0, Q4_0 loop counts
PERF_ROWS, PERF_COLS = 48 * 21, 256

# ---------------------------------------------------------------------------
# Shared BASIC subroutines, appended to every program (lines 9000-9799)

COMMON = r'''
9000 REM ---- SETUP: SSNAIL'S DEFAULT MAP; CPU ATTIC PREFETCH/CACHES OFF
9010 B=$FFD7500:D7=$FFD37FE:X7=PEEK(D7):FA=0
9020 IF PEEK(B)<>$53 THEN PRINT "NO SSNAIL FOUND (ID";PEEK(B);")":END
9030 SD=(PEEK(B+2) AND 2)/2
9040 IF SD THEN HB=$C0:POKE B+$11,$80:POKE B+$12,$40:ELSE HB=$80:POKE B+$11,0:POKE B+$12,0
9050 POKE B+$10,8:POKE B+$13,HB
9060 POKE D7,X7 AND $E2:RETURN
9100 REM ---- CPU SEES RAM K AT $8000000 (1 SDRAM, 0 HYPERRAM); SB = ITS SSNAIL ADDRESS
9110 POKE D7,(X7 AND $E2)+K*16
9120 IF K THEN R$="SDRAM":SB=$8000000:ELSE R$="HYPERRAM":SB=HB*$100000
9130 RETURN
9200 REM ---- RUN THE JOB AT JP; EC = ERROR CODE, PC = PC AT THE END
9210 V=JP:FOR J=8 TO 11:Q=INT(V/256):POKE B+J,V-Q*256:V=Q:NEXT
9220 POKE B+3,1:T=0
9230 IF (PEEK(B+4) AND 1)=0 THEN 9260
9240 T=T+1:IF T<20000 THEN 9230
9250 PRINT "  (JOB TIMED OUT: $FFD7507 = $";RIGHT$(HEX$(PEEK(B+7)),2);")"
9260 EC=PEEK(B+5):PC=PEEK(B+12)+256*PEEK(B+13)+65536*PEEK(B+14)+16777216*PEEK(B+15)
9270 X=PEEK(B+3):POKE B+3,X:RETURN
9300 REM ---- WRITE AN INSTRUCTION AT CPU ADDRESS CA, CA += 16: OP, A1, X=S, Y=D, Z=L
9310 POKE CA,OP:POKE CA+1,A1:POKE CA+2,0:POKE CA+3,0
9320 V=S:FOR J=4 TO 7:Q=INT(V/256):POKE CA+J,V-Q*256:V=Q:NEXT
9330 V=D:FOR J=8 TO 11:Q=INT(V/256):POKE CA+J,V-Q*256:V=Q:NEXT
9340 V=L:FOR J=12 TO 15:Q=INT(V/256):POKE CA+J,V-Q*256:V=Q:NEXT
9350 CA=CA+16:RETURN
9400 REM ---- H$ = V IN HEX, 7 DIGITS
9410 H$="":FOR J=1 TO 7:Q=INT(V/16):H$=MID$("0123456789ABCDEF",V-Q*16+1,1)+H$:V=Q:NEXT:RETURN
9500 REM ---- REPORT ONE CHECK: E = NUMBER OF BAD BYTES
9510 IF E=0 THEN PRINT " PASS":RETURN
9520 PRINT " FAIL (";E;"BYTES)":FA=FA+1:RETURN
9600 REM ---- A SYNC JOB (SSNAIL INVALIDATES THE RAM CACHES) BEFORE THE CPU READS RESULTS
9610 K=SD:GOSUB 9100:CA=$8380000:OP=2:A1=0:S=0:D=0:L=0:GOSUB 9300:OP=1:GOSUB 9300
9620 JP=SB+$380000:GOSUB 9200:RETURN
9700 REM ---- THE END: STOP ON FAILURE, OTHERWISE ON TO THE NEXT TEST
9710 POKE D7,X7:PRINT
9720 IF FA THEN PRINT "FAILED: STOPPING HERE.":END
'''


SDRAM_TIMING = r'''
9800 REM ---- SDRAM READ TIMING: $D7FE BIT 5 = ONE READ WAIT STATE FEWER.  USE THE
9801 REM SETTING THAT READS BACK CLEANLY (BIT 5 CLEAR IF BOTH DO), FROM NOW ON:
9802 REM SSNAIL'S LUMP READS AND DMA FOLLOW THE SAME BIT.  G = THE BIT, -1 = NEITHER.
9810 G=-1:FOR M=0 TO 1:POKE D7,(X7 AND $C2)+16+M*32:PRINT "  SDRAM, $D7FE BIT 5 =";M;":";
9820 FOR I=0 TO 255:POKE $8200000+I,(I*7+M) AND 255:NEXT
9830 E=0:FOR I=0 TO 255:IF PEEK($8200000+I)<>((I*7+M) AND 255) THEN E=E+1
9840 NEXT:IF E=0 THEN PRINT " CLEAN":IF G<0 THEN G=M
9850 IF E THEN PRINT E;"BAD, FIRST 8:";:FOR I=0 TO 7:PRINT " ";RIGHT$(HEX$(PEEK($8200000+I)),2);:NEXT:PRINT
9860 NEXT M:E=0
9870 IF G<0 THEN PRINT "  SDRAM READS FAIL WITH EITHER SETTING":FA=FA+1:RETURN
9880 X7=(X7 AND $DF)+G*32:POKE D7,X7 AND $E2:PRINT "  USING BIT 5 =";G;"FROM NOW ON":RETURN
'''


def common(next_name, standalone=False):
    if standalone:
        tail = '9730 PRINT "DONE.":END\n'
    elif next_name:
        tail = f'9730 PRINT "PASSED.  NEXT: {next_name.upper()}":RUN "{next_name}"\n'
    else:
        tail = '9730 PRINT "ALL TESTS PASSED.":END\n'
    return COMMON + tail + SDRAM_TIMING


P00 = r'''
100 REM 00.CPU RAM: THE CPU WRITES AND READS EACH RAM DIRECTLY (NO SSNAIL)
110 GOSUB 9000:PRINT "00.CPU RAM: CPU WRITE/READ, EACH RAM"
120 IF SD THEN GOSUB 9800:IF G<0 THEN 9700
200 FOR K=SD TO 0 STEP -1:GOSUB 9100:PRINT "  ";R$;":";
210 FOR I=0 TO 255:POKE $8200000+I,(I*7+K*3) AND 255:NEXT
220 E=0:FOR I=0 TO 255:IF PEEK($8200000+I)<>((I*7+K*3) AND 255) THEN E=E+1
230 NEXT:GOSUB 9500:NEXT K
240 IF SD=0 THEN 9700
250 REM WRITING SDRAM MUST NOT HAVE TOUCHED HYPERRAM'S COPY (K=0 PATTERN)
260 K=0:GOSUB 9100:PRINT "  HYPERRAM UNCHANGED BY SDRAM WRITES:";
270 E=0:FOR I=0 TO 255:IF PEEK($8200000+I)<>((I*7) AND 255) THEN E=E+1
280 NEXT:GOSUB 9500:GOTO 9700
'''

P01 = r'''
100 REM 01.REGISTERS: SSNAIL'S ID, CAPABILITIES AND REGION REGISTERS
110 GOSUB 9000:PRINT "01.REGISTERS"
120 PRINT "  ID $";RIGHT$(HEX$(PEEK(B)),2);", VERSION";PEEK(B+1);", CAPABILITIES $";RIGHT$(HEX$(PEEK(B+2)),2)
130 IF SD THEN PRINT "  SDRAM PRESENT: SSNAIL MAP SDRAM $8000000, HYPERRAM $C000000"
140 IF SD=0 THEN PRINT "  NO SDRAM: SSNAIL MAP HYPERRAM $8000000"
150 PRINT "  REGION REGISTERS READ BACK:";:E=0
160 IF PEEK(B+$10)<>8 THEN E=E+1
170 IF PEEK(B+$13)<>HB THEN E=E+1:PRINT " ($13 =";PEEK(B+$13);", WANTED";HB;": OLD BITSTREAM?)";
180 IF SD AND (PEEK(B+$11)<>$80 OR PEEK(B+$12)<>$40) THEN E=E+1
190 GOSUB 9500
200 PRINT "  STATUS $";RIGHT$(HEX$(PEEK(B+4)),2);" (BUSY BIT 0 SHOULD BE CLEAR):";:E=PEEK(B+4) AND 1:GOSUB 9500
210 PRINT "  LOAD PORT READY (BIT 7 OF $17):";:E=1-INT(PEEK(B+$17)/128):GOSUB 9500
220 GOTO 9700
'''

P02 = r'''
100 REM 02.LUMP FETCH: SSNAIL FETCHES ONE CPU-WRITTEN INSTRUCTION, HALT, IN EACH RAM
101 REM THE JOB AREA HOLDS 8 SLOTS OF 16 BYTES, ALL ZERO (NOP) EXCEPT A HALT
102 REM OPCODE AT BYTE K OF SLOT K, THEN A SLOT OF $FF.  A FETCH THAT SKIPS B
103 REM BYTES RUNS B NOPS AND HALTS IN SLOT B, SO THE END PC SHOWS THE SHIFT.
110 GOSUB 9000:PRINT "02.LUMP FETCH: A LONE HALT":F1=0:F0=0
115 PRINT "  HYPERRAM $BFFFFF2=$";RIGHT$(HEX$(PEEK($BFFFFF2)),2);", $D7FE BIT 5 =";(X7 AND 32)/32
120 FOR K=SD TO 0 STEP -1:GOSUB 9100:PRINT "  ";R$;":";
130 GOSUB 400:JP=SB+$300000:GOSUB 9200:GOSUB 450
150 IF W THEN PRINT " PASS":GOTO 170
160 FA=FA+1:GOSUB 300:IF K THEN F1=1:GOSUB 480:ELSE F0=1:GOSUB 760
170 NEXT K
180 IF SD AND F1=0 AND F0 THEN GOSUB 500
190 GOTO 9700
300 REM ---- PROBE: FETCH A COUNTING PATTERN (BYTE I = $80+I, NOT AN OPCODE, SO
301 REM IT STOPS AT ONCE) AND SHOW THE BYTES SSNAIL GOT ($FFD7518-F, DEBUG)
310 FOR I=0 TO 47:POKE $82FFFF0+I,$70+I:NEXT:GOSUB 9200
320 PRINT "   PROBE: WROTE";:FOR I=0 TO 7:PRINT " ";RIGHT$(HEX$($80+I),2);:NEXT:PRINT
330 PRINT "        FETCHED";:GOSUB 360:RETURN
350 PRINT "   FETCHED";
360 FOR I=0 TO 7:PRINT " ";RIGHT$(HEX$(PEEK(B+24+I)),2);:NEXT
370 IF PEEK(B+24)=255 AND PEEK(B+25)=255 THEN PRINT " (NO DEBUG REGISTERS?)":RETURN
380 PRINT:RETURN
400 REM ---- PLANT THE SLOTS AT CPU $8300000
410 FOR I=0 TO 127:POKE $8300000+I,0:NEXT:FOR I=128 TO 143:POKE $8300000+I,255:NEXT
420 FOR I=0 TO 7:POKE $8300000+I*17,1:NEXT:RETURN
450 REM ---- W = 1 IF THE JOB HALTED IN SLOT 0; OTHERWISE SAY WHAT HAPPENED
455 W=0:IF EC=0 AND PC=JP THEN W=1:RETURN
460 V=PC:GOSUB 9400:PRINT " FAIL: ERROR";EC;" PC $";H$:Q=PC-JP:GOSUB 350
462 IF EC=4 THEN V=PEEK(B+7):PRINT "   TIMED OUT: $FFD7507 = $";RIGHT$(HEX$(V),2);", WORDS RECEIVED";V AND 15
465 IF EC=0 AND Q>0 AND Q<128 THEN IF INT(Q/16)*16=Q THEN PRINT "   FETCH SKIPPED THE FIRST";Q/16;"BYTES (DATA TAKEN TOO LATE)":RETURN
470 IF EC=1 AND Q=128 THEN PRINT "   OPCODE BYTE NEVER FROM THE SLOTS: STALE DATA FIRST (TAKEN TOO EARLY?)":RETURN
475 PRINT "   NOT A SIMPLE SHIFT":RETURN
480 REM ---- SDRAM FAILED: FORCE EACH READ CYCLE ($C000014) ON THE PATH IN USE, AND
481 REM CHECK THE CPU AND A LUMP FETCH AT EACH.  THEN TRAIN AGAIN ($C000010).
482 R=$C000000:S=PEEK(R+8):H=PEEK(R+20) AND 1
483 PRINT "  SDRAM TRAINING STATUS $";RIGHT$(HEX$(S),2);", PATH";H;", READ CYCLE";INT(S/4) AND 3
484 FOR CC=0 TO 3:POKE R+20,H*4+CC:PRINT "   READ CYCLE";CC;": CPU";:GOSUB 800
485 PRINT ", LUMP";:GOSUB 400:JP=SB+$300000:GOSUB 9200
486 IF EC=0 AND PC=JP THEN PRINT " PASS":GOTO 489
487 PRINT " ERROR";EC;:IF EC=4 THEN PRINT " (WORDS";PEEK(B+7) AND 15;")";
488 GOSUB 360
489 NEXT:POKE R+16,0:FOR I=1 TO 500:NEXT:RETURN
500 REM ---- HYPERRAM FAILED, SDRAM WORKS: PROBE HYPERRAM WITH JOBS RUN FROM SDRAM
510 PRINT:PRINT "  PROBE 1, LUMP READ: CPU PATTERN IN HYPERRAM, COPIED TO SDRAM BY SSNAIL"
520 K=0:GOSUB 9100:HS=SB:FOR I=0 TO 63:POKE $8304000+I,(I*3+1) AND 255:NEXT
530 K=1:GOSUB 9100:FOR I=0 TO 63:POKE $8305000+I,0:NEXT
540 CA=$8300200:OP=3:A1=0:S=HS+$304000:D=$8305000:L=64:GOSUB 9300
550 OP=2:S=0:D=0:L=0:GOSUB 9300:OP=1:GOSUB 9300
560 JP=$8300200:GOSUB 9200:IF EC THEN PRINT "  PROBE JOB FAILED, ERROR";EC:GOTO 600
570 A0=$8305000:M=3:N=1:GOSUB 700
600 PRINT "  PROBE 2, LUMP WRITE: SDRAM PATTERN COPIED INTO HYPERRAM BY SSNAIL"
610 K=0:GOSUB 9100:FOR I=0 TO 63:POKE $8307000+I,0:NEXT
620 K=1:GOSUB 9100:FOR I=0 TO 63:POKE $8306000+I,(I*5+2) AND 255:NEXT
630 CA=$8300200:OP=3:A1=0:S=$8306000:D=HS+$307000:L=64:GOSUB 9300
640 OP=2:S=0:D=0:L=0:GOSUB 9300:OP=1:GOSUB 9300
650 JP=$8300200:GOSUB 9200:IF EC THEN PRINT "  PROBE JOB FAILED, ERROR";EC:RETURN
660 K=0:GOSUB 9100:A0=$8307000:M=5:N=2:GOSUB 700:GOSUB 760:RETURN
700 REM ---- SHOW 32 BYTES AT CPU A0 AGAINST THE PATTERN (I*M+N), AND COUNT ALL 64
710 E=0:FOR I=0 TO 63:IF PEEK(A0+I)<>((I*M+N) AND 255) THEN E=E+1
720 NEXT
730 FOR R=0 TO 3:PRINT "   GOT ";:FOR J=0 TO 7:PRINT " ";RIGHT$(HEX$(PEEK(A0+R*8+J)),2);:NEXT
740 PRINT "  WANT";:FOR J=0 TO 7:PRINT " ";RIGHT$(HEX$(((R*8+J)*M+N) AND 255),2);:NEXT:PRINT:NEXT
750 PRINT "  ";E;"OF 64 BYTES WRONG":RETURN
760 REM ---- HYPERRAM CONTROLLER'S LUMP DEBUG CAPTURE ($B0000A0-BA; HYPERRAM SELECTED)
765 D=$B0000A0:PRINT "   LUMP DEBUG: MODE BITS $";RIGHT$(HEX$(PEEK(D+25)),2);", READ ADJ";PEEK(D+26);", BURSTS R";PEEK(D+23);"W";PEEK(D+24)
770 PRINT "   LAST READ: WORDS";PEEK(D+19);", FIRST BYTE AFTER";PEEK(D+18);"CYCLES"
775 PRINT "   BUS:";:FOR I=0 TO 15:PRINT " ";RIGHT$(HEX$(PEEK(D+I)),2);:NEXT:PRINT
780 V=PEEK(D+16)+256*PEEK(D+17):PRINT "   RWDS: ";:FOR I=0 TO 15:PRINT CHR$(48+(V AND 1));:V=INT(V/2):NEXT:PRINT
785 PRINT "   LAST WRITE: WORDS ASKED";PEEK(D+20);", BYTES";PEEK(D+21);", FIRST AFTER";PEEK(D+22):RETURN
800 REM ---- CPU CHECK: 16 BYTES AT CPU $8310000, WRITTEN AND READ BACK
810 FOR I=0 TO 15:POKE $8310000+I,(I*7+3) AND 255:NEXT:E=0
820 FOR I=0 TO 15:IF PEEK($8310000+I)<>((I*7+3) AND 255) THEN E=E+1
830 NEXT:IF E THEN PRINT E;"BAD";:RETURN
840 PRINT " OK";:RETURN
'''

P03 = r'''
100 REM 03.LUMP STR: LI R1,$12345678 / STR R1 / SYNC / HALT, IN EACH RAM
110 GOSUB 9000:PRINT "03.LUMP STR: ONE LUMP WRITE"
120 FOR K=SD TO 0 STEP -1:GOSUB 9100:PRINT "  ";R$;":";
130 FOR I=0 TO 7:POKE $8300100+I,0:NEXT
140 CA=$8300000:OP=8:A1=1:S=0:D=0:L=$12345678:GOSUB 9300
150 OP=10:A1=1:S=SB+$300100:D=0:L=0:GOSUB 9300
160 OP=2:A1=0:S=0:L=0:GOSUB 9300:OP=1:GOSUB 9300
170 JP=SB+$300000:GOSUB 9200
180 IF EC THEN V=PC:GOSUB 9400:PRINT " FAIL: ERROR";EC;" PC $";H$:FA=FA+1:GOTO 230
190 E=0:RESTORE 250:FOR I=0 TO 7:READ X:IF PEEK($8300100+I)<>X THEN E=E+1
200 NEXT:IF E=0 THEN 220
210 PRINT " GOT";:FOR I=0 TO 7:PRINT " ";RIGHT$(HEX$(PEEK($8300100+I)),2);:NEXT:PRINT ",";
220 GOSUB 9500
230 NEXT K:GOTO 9700
250 DATA 120,86,52,18,0,0,0,0
'''

P04 = r'''
100 REM 04.LUMP COPY: 1 KB COPY WITHIN EACH RAM, THEN SDRAM -> HYPERRAM
110 GOSUB 9000:PRINT "04.LUMP COPY: 1 KB BURSTS"
120 FOR K=SD TO 0 STEP -1:GOSUB 9100:PRINT "  ";R$;" -> ";R$;":";
130 FOR I=0 TO 1023:POKE $8301000+I,(I*11+K) AND 255:POKE $8302000+I,0:NEXT
140 CA=$8300000:OP=3:A1=0:S=SB+$301000:D=SB+$302000:L=1024:GOSUB 9300
150 OP=2:S=0:D=0:L=0:GOSUB 9300:OP=1:GOSUB 9300
160 JP=SB+$300000:GOSUB 9200
170 IF EC THEN V=PC:GOSUB 9400:PRINT " FAIL: ERROR";EC;" PC $";H$:FA=FA+1:GOTO 190
180 A0=$8302000:GOSUB 400:GOSUB 9500
190 NEXT K
200 IF SD=0 THEN 9700
210 REM ACROSS: THE SDRAM PATTERN (K=1) COPIED INTO HYPERRAM
220 K=0:GOSUB 9100:HS=SB:FOR I=0 TO 1023:POKE $8303000+I,0:NEXT
230 CA=$8300000:OP=3:A1=0:S=$8301000:D=HS+$303000:L=1024:GOSUB 9300
240 OP=2:S=0:D=0:L=0:GOSUB 9300:OP=1:GOSUB 9300
250 PRINT "  SDRAM -> HYPERRAM:";:JP=HS+$300000:GOSUB 9200
260 IF EC THEN V=PC:GOSUB 9400:PRINT " FAIL: ERROR";EC;" PC $";H$:FA=FA+1:GOTO 9700
270 K=0:GOSUB 9100:A0=$8303000:K=1:GOSUB 400:GOSUB 9500:GOTO 9700
400 REM ---- CHECK 1 KB AT CPU A0 AGAINST PATTERN (I*11+K)
410 E=0:FOR I=0 TO 1023:Y=PEEK(A0+I):X=(I*11+K) AND 255
420 IF Y<>X THEN E=E+1:IF E<4 THEN PRINT:PRINT "    +$";HEX$(I);" =";Y;", EXPECTED";X;
430 NEXT:IF E THEN PRINT
440 RETURN
'''

PTEST = r'''
100 REM {NAME}: {DESC} -- THE SIMULATION BENCH'S PROGRAM, ON THE HARDWARE
110 GOSUB 9000:PRINT "{NAMEU}: {DESC}"
120 IL={IL}:EO={EO}:EN={EN}:HP={HP}
130 PRINT "  LOADING ";:BLOAD "{FILE}.bin",B4,P0
140 K=SD:GOSUB 9100:PRINT "INTO ";R$;" ";
150 FOR I=0 TO EO+EN-1:V=0:IF I<IL THEN V=PEEK($40000+I)
160 POKE $8000000+I,V:NEXT:PRINT
170 JP=$8000000:GOSUB 9200
180 IF EC=0 AND PC=HP THEN 220
190 V=PC:GOSUB 9400:PRINT "  RUN: FAIL, ERROR";EC;" PC $";H$;
200 V=HP:GOSUB 9400:PRINT " (EXPECTED ERROR 0, PC $";H$;")":FA=FA+1:GOTO 9700
220 PRINT "  RUN: PASS (ERROR 0, HALTED AT THE RIGHT PLACE)"
230 GOSUB 9600:BLOAD "{FILE}.exp",B5,P0
240 K=SD:GOSUB 9100:PRINT "  OUTPUT (";EN;"BYTES) MATCHES THE EMULATOR:";
250 E=0:FOR I=0 TO EN-1:Y=PEEK($8000000+EO+I):X=PEEK($50000+I)
260 IF Y<>X THEN E=E+1:IF E<4 THEN PRINT:PRINT "    +$";HEX$(EO+I);" =";Y;", EXPECTED";X;
270 NEXT:IF E THEN PRINT
280 GOSUB 9500:GOTO 9700
'''

P20 = r'''
100 REM 20.GEMV SPEED: Q8_0 AND Q4_0 GEMVS OF {RW} X {CL}, LOOPED, TIMED
110 GOSUB 9000:PRINT "20.GEMV SPEED"
120 PRINT "  CALIBRATING TI AGAINST TI$...";:X$=TI$
130 IF TI$=X$ THEN 130
140 X$=TI$:T0=TI:FOR N=1 TO 3
150 IF TI$=X$ THEN 150
160 X$=TI$:NEXT:TR=(TI-T0)/3:PRINT TR;"PER SECOND"
170 PRINT "  LOADING":BLOAD "ssnp.bin",B4,P0
180 K=SD:GOSUB 9100:FOR I=0 TO $71FF:POKE $8000000+I,PEEK($40000+I):NEXT
190 JP=$8000000:GOSUB 9200:IF EC THEN PRINT "  SETUP JOB FAILED, ERROR";EC:FA=FA+1:GOTO 9700
200 FOR N=0 TO 1:JP=$8007000+N*$100:IT={A8}:IF N THEN IT={A4}
210 T0=TI:GOSUB 9200:T1=TI
220 IF EC THEN PRINT "  GEMV LOOP FAILED, ERROR";EC:FA=FA+1:GOTO 9700
230 W=(T1-T0)/TR:CW=W*162E6/(IT*{RW}*{CL}):F$="Q8_0":IF N THEN F$="Q4_0"
240 PRINT "  ";F$;":";IT;"GEMVS IN";INT(W*100+.5)/100;"S =";INT(CW*100+.5)/100;"CYCLES/WEIGHT"
250 NEXT N:PRINT "  (SIMULATION: ~0.59 Q8_0, ~0.34 Q4_0 FROM SDRAM)":GOTO 9700
'''

P30 = r'''
100 REM 30.LOAD PORT: 1 KB OF $AA, THEN 700 PATTERN BYTES AT +$30 (PARTIAL BLOCKS,
101 REM BYTE MASKS), ALL THROUGH THE LOAD PORT; THE CPU READS IT BACK
110 GOSUB 9000:PRINT "30.LOAD PORT"
120 FOR K=SD TO 0 STEP -1:GOSUB 9100:PRINT "  ";R$;":";
130 V=SB+$303000:GOSUB 500:FOR I=0 TO 1023:IF (I AND 511)=0 THEN GOSUB 550
140 POKE B+$18,$AA:NEXT
150 V=SB+$303030:GOSUB 500:FOR I=0 TO 699:IF (I AND 511)=0 THEN GOSUB 550
160 POKE B+$18,(I*11+K) AND 255:NEXT
170 V=SB+$303030:GOSUB 500:IF PEEK(B+$17) AND 64 THEN PRINT " (ERROR BIT SET)";
180 E=0:FOR I=0 TO 1023:X=$AA:IF I>=48 AND I<748 THEN X=((I-48)*11+K) AND 255
190 IF PEEK($8303000+I)<>X THEN E=E+1
200 NEXT:GOSUB 9500:IF E=0 THEN 260
210 FOR R=0 TO 3:PRINT "    GOT +$";HEX$($28+R*8);":";
220 FOR J=0 TO 7:I=$28+R*8+J:PRINT " ";RIGHT$(HEX$(PEEK($8303000+I)),2);:NEXT:PRINT
230 PRINT "    WANTED   :";:FOR J=0 TO 7:I=$28+R*8+J:X=$AA:IF I>=48 THEN X=((I-48)*11+K) AND 255
240 PRINT " ";RIGHT$(HEX$(X),2);:NEXT:PRINT:NEXT
260 NEXT K:GOTO 9700
500 REM ---- LOAD POINTER = V, COMMIT (BIT 6: CLEAR ERROR), WAIT FOR READY
510 FOR J=0 TO 2:Q=INT(V/256):POKE B+$14+J,V-Q*256:V=Q:NEXT:POKE B+$17,V OR $40
550 T=0
560 IF PEEK(B+$17) AND 128 THEN RETURN
570 T=T+1:IF T<20000 THEN 560
580 PRINT " (LOAD PORT NOT READY)";:RETURN
'''


P90 = r'''
100 REM 90.HYPERRAM MODE (STANDALONE): WHICH $BFFFFF2/$BFFFFF5 SETTINGS WORK?
101 REM CPU ONLY.  REFERENCE = THE BOARD'S MODE WITH PREFETCH AND THE CURRENT
102 REM CACHE LINE OFF (SO NOTHING IS ANSWERED FROM A CACHE).  READ PATH = WRITE
103 REM IN THE REFERENCE MODE, READ IN THE TEST MODE; WRITE PATH = THE REVERSE.
110 GOSUB 9000:H2=$BFFFFF2:O2=PEEK(H2):O5=PEEK(H2+3)
120 PRINT "90.HYPERRAM MODE":PRINT "  $BFFFFF0-9:";
130 FOR I=0 TO 9:PRINT " ";RIGHT$(HEX$(PEEK($BFFFFF0+I)),2);:NEXT:PRINT
140 PRINT "  $BFFFFF2 BITS: 0 FAST CMD, 1 FAST READ, 2 FAST WRITE, 3 READ PHASE"
150 PRINT "  $BFFFFF5 = READ TIME ADJUST"
160 K=0:GOSUB 9100:BS=O2 AND $90:C=0
165 PRINT "  REFERENCE MODE $";RIGHT$(HEX$(BS),2);", ADJ";O5
170 READ MB,RT:IF MB<0 THEN POKE H2,O2:POKE H2+3,O5:GOTO 9700
180 IF RT<0 THEN RT=O5
190 A=$8310000+C*$1000:C=C+1
200 REM READ PATH: WRITE IN THE REFERENCE MODE, READ IN THE TEST MODE
210 POKE H2,BS:POKE H2+3,O5:FOR I=0 TO 63:POKE A+I,(I*5+C) AND 255:NEXT:GOSUB 500
220 POKE H2+3,RT:POKE H2,BS+MB:E=0
230 FOR I=0 TO 63:IF PEEK(A+I)<>((I*5+C) AND 255) THEN E=E+1
240 NEXT:RE=E:POKE H2,BS:POKE H2+3,O5
250 REM WRITE PATH: WRITE IN THE TEST MODE, READ IN THE REFERENCE MODE
260 POKE H2+3,RT:POKE H2,BS+MB
270 FOR I=0 TO 63:POKE A+$800+I,(I*7+C) AND 255:NEXT
280 POKE H2,BS:POKE H2+3,O5:GOSUB 500:E=0
290 FOR I=0 TO 63:IF PEEK(A+$800+I)<>((I*7+C) AND 255) THEN E=E+1
300 NEXT:POKE H2,O2:POKE H2+3,O5
310 PRINT "  $";RIGHT$(HEX$(BS+MB),2);" ADJ";RT;": READ";
320 IF RE THEN PRINT RE;"BAD";:ELSE PRINT " OK";
330 PRINT ", WRITE";:IF E THEN PRINT E;"BAD":ELSE PRINT " OK"
340 GOTO 170
400 REM MODE BITS, READ TIME ADJUST (-1 = AS FOUND); -1,-1 ENDS
410 DATA 0,-1, 1,-1, 2,-1, 4,-1, 8,-1, 10,-1
420 DATA 2,0, 2,1, 2,2, 2,3, 10,0, 10,1, 10,2, 10,3
430 DATA 3,-1, 11,-1, 5,-1, 7,-1, 15,-1
440 DATA -1,-1
500 REM ---- PUSH RECENT LINES OUT OF THE CONTROLLER'S CACHE ROWS
510 FOR J=0 TO 7:X=PEEK($8380000+J*$100):NEXT:RETURN
'''


P91 = r'''
100 REM 91.MEM BENCH (STANDALONE): DMAGIC THROUGHPUT FOR EACH RAM SETTING.
101 REM 2 MB OF 32 KB DMA JOBS PER TEST, REPEATED FOR 3 S, TIMED WITH THE CIA
102 REM TOD CLOCK (THE CPU IS HALTED DURING DMA, SO TI WOULD UNDERCOUNT).
103 REM WRITE = CHIP RAM -> RAM, READ = RAM -> CHIP RAM, COPY = RAM -> RAM,
104 REM FILL = DMA FILL OF RAM.  EACH RESULT IS SPOT-CHECKED BY THE CPU.
110 GOSUB 9000:H2=$BFFFFF2:O2=PEEK(H2):O8=PEEK(H2+6):O9=PEEK(H2+7):O3=PEEK(H2+1):O4=PEEK(H2+2)
115 IF SD THEN GOSUB 9800:IF G<0 THEN 9700
120 DM=$FFD3700:TD=$FFD3C08:PRINT "91.MEM BENCH"
130 PRINT "  HYPERRAM $BFFFFF2=$";RIGHT$(HEX$(O2),2);" CR0=$";RIGHT$(HEX$(O8),2);RIGHT$(HEX$(O9),2);
140 PRINT " WRITE LATENCY";PEEK(H2+1);"/";PEEK(H2+2)
150 REM THE TOD CLOCK MUST BE RUNNING
160 GOSUB 8000:X$=TI$
170 IF TI$=X$ THEN 170
180 X$=TI$
190 IF TI$=X$ THEN 190
200 GOSUB 8100:IF TE<5 THEN PRINT "  CIA TOD CLOCK IS NOT RUNNING: CANNOT TIME":GOTO 9700
210 REM 32 KB PATTERN IN CHIP RAM AT $50000 (1 KB BY THE CPU, THEN DOUBLED)
220 PRINT "  MAKING THE PATTERN AND DMA LISTS"
230 FOR I=0 TO 1023:POKE $50000+I,(I*7+INT(I/256)*3) AND 255:NEXT
240 P=$F000:FOR N=0 TO 4:CN=1024*2^N:CM=4:IF N=4 THEN CM=0
245 SA=$50000:DA=$50000+CN:GOSUB 6000:NEXT
250 LA=$F000:GOSUB 7000
260 REM FOUR LISTS OF 64 CHAINED JOBS: WRITE $0000, READ $0800, COPY $1000, FILL $1800
270 FOR N=0 TO 63:CM=4:IF N=63 THEN CM=0
280 CN=32768:P=N*18
290 SA=$50000:DA=$8100000+N*CN:GOSUB 6000
300 P=$800+N*18:SA=$8100000+N*CN:DA=$58000:GOSUB 6000
310 P=$1000+N*18:DA=$8400000+N*CN:GOSUB 6000
320 P=$1800+N*18:CM=CM+3:SA=$5A:DA=$8100000+N*CN:GOSUB 6000
330 NEXT
340 PRINT:PRINT "  SETTING          WRITE  READ  COPY  FILL  (MB/S)"
350 READ C$,K,MO,LT:IF C$="END" THEN 500
360 IF K=1 AND SD=0 THEN 350
370 GOSUB 9100:IF MO>=0 THEN POKE H2,(O2 AND $F0)+MO
380 IF LT THEN GOSUB 650
390 PRINT "  ";LEFT$(C$+"               ",15);
400 NB=2097152:LA=0:GOSUB 7000:W1=RT
410 LA=$800:GOSUB 7000:W2=RT:A0=$58000:GOSUB 700
420 LA=$1000:GOSUB 7000:W3=RT:FOR N=0 TO 63 STEP 21:A0=$8400000+N*32768:GOSUB 700:NEXT
430 LA=$1800:GOSUB 7000:W4=RT:FOR N=0 TO 63 STEP 21:IF PEEK($8100000+N*32768+N)<>$5A THEN E=E+1
440 NEXT
450 FOR I=1 TO 4:W=W1:IF I=2 THEN W=W2
460 IF I=3 THEN W=W3
470 IF I=4 THEN W=W4
480 PRINT RIGHT$("     "+STR$(INT(W*10+.5)/10),6);:NEXT
490 IF E THEN PRINT " BAD";E:FA=FA+1:ELSE PRINT " OK"
495 GOSUB 520:E=0:GOTO 350
500 GOSUB 520:PRINT:PRINT "  * 3 CLOCKS AT 81 MHZ IS BELOW THE PART'S 40 NS ACCESS TIME:"
505 PRINT "    OUT OF SPEC, FOR COMPARISON ONLY.  (SETTINGS RESTORED)":GOTO 9700
520 POKE H2,O2:POKE H2+6,O8:POKE H2+7,O9:POKE H2+1,O3:POKE H2+2,O4:RETURN
600 REM ---- SETTINGS: NAME, RAM (1 SDRAM, 0 HYPERRAM), $BFFFFF2 LOW BITS (-1 =
601 REM AS FOUND), CR0 INITIAL LATENCY IN CLOCKS (0 = AS FOUND)
610 DATA "SDRAM",1,-1,0
620 DATA "HR AS FOUND",0,-1,0, "HR SLOW",0,0,0, "HR FAST READ",0,2,0
630 DATA "HR FAST CMD+RD",0,3,0, "HR ALL FAST",0,7,0
640 DATA "HR SLOW LAT 3",0,0,3, "HR FAST RD L3*",0,2,3, "HR ALL FAST L3*",0,7,3, "END",0,0,0
650 REM ---- CR0 LATENCY LT CLOCKS: HIGH BYTE AS FOUND, THEN THE LOW BYTE SENDS IT
660 X=$F:IF LT=3 THEN X=$E
670 IF LT=5 THEN X=0
680 IF LT=6 THEN X=1
690 POKE H2+6,O8:POKE H2+7,X*16+(O9 AND 15):RETURN
700 REM ---- SPOT CHECK: 256 BYTES AT A0 AGAINST THE PATTERN; E COUNTS MISMATCHES
710 FOR I=0 TO 255:IF PEEK(A0+I)<>((I*7) AND 255) THEN E=E+1
720 NEXT:RETURN
6000 REM ---- DMA JOB AT BANK 4 + P: ENHANCED OPTIONS (F018B, SOURCE AND DEST MB),
6001 REM THEN COMMAND CM, COUNT CN, SOURCE SA, DESTINATION DA (28-BIT ADDRESSES)
6010 Q=$40000+P:POKE Q,$0B:POKE Q+1,$80:POKE Q+2,INT(SA/1048576):POKE Q+3,$81
6020 POKE Q+4,INT(DA/1048576):POKE Q+5,0:POKE Q+6,CM
6030 POKE Q+7,CN-INT(CN/256)*256:POKE Q+8,INT(CN/256)-INT(CN/65536)*256
6040 V=SA:GOSUB 6100:POKE Q+9,V1:POKE Q+10,V2:POKE Q+11,V3
6050 V=DA:GOSUB 6100:POKE Q+12,V1:POKE Q+13,V2:POKE Q+14,V3
6060 POKE Q+15,0:POKE Q+16,0:POKE Q+17,0:P=P+18:RETURN
6100 REM ---- V1, V2, V3 = BITS 0-7, 8-15, 16-19 OF V
6110 V=V-INT(V/1048576)*1048576:V3=INT(V/65536):V=V-V3*65536
6120 V2=INT(V/256):V1=V-V2*256:RETURN
7000 REM ---- RUN THE LIST AT BANK 4 + LA FOR AT LEAST 3 S; RT = MB/S FOR NB BYTES A RUN
7010 GOSUB 8000:N=0
7020 POKE DM+2,4:POKE DM+4,0:POKE DM+1,INT(LA/256):POKE DM+5,LA-INT(LA/256)*256:N=N+1
7030 IF NB=0 THEN RETURN
7040 GOSUB 8100:IF TE<30 THEN 7020
7050 RT=N*NB/(TE/10)/1E6:RETURN
8000 REM ---- TOD := 0 (WRITING HOURS STOPS IT, WRITING TENTHS STARTS IT)
8010 POKE TD+3,0:POKE TD+2,0:POKE TD+1,0:POKE TD,0:RETURN
8100 REM ---- TE = TENTHS SINCE 8000 (READING HOURS LATCHES, READING TENTHS RELEASES)
8110 X=PEEK(TD+3):M=PEEK(TD+2):S2=PEEK(TD+1):X=PEEK(TD)
8120 TE=((INT(M/16)*10+(M AND 15))*60+INT(S2/16)*10+(S2 AND 15))*10+(X AND 15):RETURN
'''


P92 = r'''
100 REM 92.SDRAM TRAIN (STANDALONE): THE SDRAM CONTROLLER'S READ CAPTURE TRAINING.
101 REM AFTER EVERY RESET IT TRIES THE SDRAM READ CLOCK AT 8 PHASES 45 DEGREES APART,
102 REM READING A TEST PATTERN THROUGH BOTH CROSSING PATHS.  THE PATH WITH THE LONGER
103 REM RUN OF PHASES CLEAN AT ONE READ CYCLE IS USED: ITS EDGES ARE FOUND IN 22 PS
104 REM STEPS AND THE CLOCK IS CENTRED BETWEEN THEM.  REGISTERS AT $C000008+.
105 REM (02 FORCES READ CYCLES FOR TESTS: AFTER STOPPING IT, PRESS R TO RETRAIN.)
110 GOSUB 9000:PRINT "92.SDRAM TRAIN":IF SD=0 THEN PRINT "  NO SDRAM ON THIS BOARD":GOTO 9700
120 K=1:GOSUB 9100:R=$C000000
130 GOSUB 300
140 PRINT "  R: TRAIN AGAIN  +/-: ONE STEP LATER/EARLIER  OTHER KEY: END"
150 GET A$:IF A$="" THEN 150
160 IF A$="R" THEN POKE R+16,0:FOR I=1 TO 500:NEXT:GOSUB 300:GOTO 140
170 IF A$="+" THEN POKE R+17,0:GOSUB 400:GOTO 150
180 IF A$="-" THEN POKE R+18,0:GOSUB 400:GOTO 150
190 GOTO 9700
300 REM ---- STATUS, WINDOW, AND THE COARSE MAP
310 S=PEEK(R+8):W=PEEK(R+9)+256*PEEK(R+10):CE=PEEK(R+11)+256*PEEK(R+12)
320 PRINT "  STATUS $";RIGHT$(HEX$(S),2);:IF S AND 128 THEN PRINT " TRAINED";
330 IF S AND 32 THEN PRINT " NO PHASE SHIFTER (OLD BEHAVIOUR, $D7FE BIT 5)";
340 IF S AND 16 THEN PRINT " WEAK";
350 IF (S AND 160)=0 THEN PRINT " NO CLEAN WINDOW FOUND";
360 PRINT:PRINT "  WINDOW";W;"STEPS =";INT(W*22.05+.5);"PS, FROM";PEEK(R+16)+256*PEEK(R+17);
365 PRINT "TO";PEEK(R+18)+256*PEEK(R+19)
370 PRINT "  CENTRE";CE;", PATH";PEEK(R+20) AND 1;", READ CYCLE";S AND 3;", RUN";PEEK(R+15)
380 PRINT "  COARSE PHASES 0-7 (EACH 45 DEG): PATH 0 / PATH 1 READ CYCLE, . = NOT CLEAN"
385 PRINT "   ";:FOR P=0 TO 7:V=PEEK(R+24+P):PRINT " ";:N=V:GOSUB 390:PRINT "/";:N=INT(V/16):GOSUB 390:NEXT:PRINT
386 PRINT "  CAPTURE CLOCK MMCM LOCKED:";PEEK(R+22) AND 1
387 PRINT "  CPU PATH: FLAGS $";RIGHT$(HEX$(PEEK(R+23)),2);", READ HITS";PEEK(R+32)+256*PEEK(R+33);", MISSES";PEEK(R+34)+256*PEEK(R+35):RETURN
390 IF N AND 4 THEN PRINT CHR$(48+(N AND 3));:RETURN
395 PRINT ".";:RETURN
400 REM ---- AFTER A MANUAL STEP
410 PRINT "  POSITION";PEEK(R+13)+256*PEEK(R+14):RETURN
'''

STANDALONE = [("90.hyperram mode", P90), ("91.mem bench", P91), ("92.sdram train", P92)]


def programs():
    """[(disk name, BASIC text)] in chain order."""
    out = [("00.cpu ram", P00), ("01.registers", P01), ("02.lump fetch", P02),
           ("03.lump str", P03), ("04.lump copy", P04)]
    for name, desc, f, gen, pkg, il, eo, en, halt in TESTS:
        out.append((name, PTEST.replace("{NAME}", name.upper()).replace("{NAMEU}", name.upper())
                    .replace("{DESC}", desc).replace("{FILE}", f).replace("{IL}", str(il))
                    .replace("{EO}", str(eo)).replace("{EN}", str(en)).replace("{HP}", "{HP_" + f + "}")))
    out.append(("20.gemv speed", P20.replace("{RW}", str(PERF_ROWS)).replace("{CL}", str(PERF_COLS))
                .replace("{A8}", str(PERF_ITERS[0])).replace("{A4}", str(PERF_ITERS[1]))))
    out.append(("30.load port", P30))
    return out


# ---------------------------------------------------------------------------
# Test data (programs, data and emulator-expected results from the benches)

def pkg_words(text, name):
    body = text.split(f"constant {name}")[1].split(");")[0]
    w = [int(v, 16) for v in re.findall(r'x"([0-9A-F]{4})"', body)]
    return b"".join(struct.pack("<H", v) for v in w)


def make_perf(perf_pkg_text):
    """Setup job at $8000000: build 1008-row matrices by copying the 48-row
    blocks; Q8_0 loop job at $8007000, Q4_0 loop job at $8007100."""
    init = bytearray(pkg_words(perf_pkg_text, "INIT")) + bytes(0x1200)
    n8, n4, reps = 48 * 8 * 34, 48 * 8 * 18, 21
    W8, W4 = B + 0x100000, B + 0x180000
    A = Asm()
    for k in range(reps):
        A(I.COPY, x=B + 0x0400, y=W8 + k * n8, z=n8)
        A(I.COPY, x=B + 0x3800, y=W4 + k * n4, z=n4)
    A(I.SYNC)
    A(I.HALT)
    setup = A.assemble(B)
    assert len(setup) <= 0x400
    init[0:len(setup)] = setup

    def loop(addr, fmt, w, count):
        A = Asm()
        A(I.LI, 1, z=count)
        A.label("top")
        A(I.SETN, x=256, y=48 * reps)
        A(I.GEMV, fmt, x=w, y=B + 0x5800, z=B + 0x6000)
        A(I.ADDI, 1, 1, z=0xFFFFFFFF)
        A(I.BNE, 1, I.RZERO, "top")
        A(I.HALT)
        code = A.assemble(addr)
        init[addr - B:addr - B + len(code)] = code

    loop(B + 0x7000, I.FMT_Q8_0, W8, PERF_ITERS[0])
    loop(B + 0x7100, I.FMT_Q4_0, W4, PERF_ITERS[1])
    assert len(init) == 0x7200
    return bytes(init)


def check_perf(perf):
    m = S.Machine.__new__(S.Machine)
    m.mem = bytearray(8 << 20)
    m.mem[:len(perf)] = perf
    m.R, m.A, m.N, m.pc = [0] * 16, [0] * 16, [0] * 3, 0
    m.stats = dict(instructions=0, bytes_read=0, bytes_written=0)
    m.on_argmax = m.on_sync = None
    m.trace = False
    m.temperature, m.top_k, m.rep_penalty, m.rep_window = 0.0, 0, 1.0, 64
    m.hw = True
    m.run(B)
    for addr in (B + 0x7000, B + 0x7100):
        struct.pack_into("<I", m.mem, addr - B + 12, 1)            # LI R1, 1
        m.run(addr)


# ---------------------------------------------------------------------------
# BASIC checks (BASIC 65 keeps 2 significant characters of a variable name)

KEYWORDS = {"IF", "THEN", "ELSE", "PRINT", "POKE", "PEEK", "FOR", "TO", "NEXT", "GOTO", "GOSUB",
            "RETURN", "READ", "DATA", "END", "AND", "OR", "INT", "HEX", "MID", "RIGHT", "TI",
            "BLOAD", "STEP", "NOT", "INPUT", "RESTORE", "RUN"}
RESERVED = {"ST", "TI", "DS", "ER", "EL"}


def basic65_keywords():
    """BASIC 65's keywords, from petcat -k65 (empty if petcat is missing)."""
    exe = shutil.which("petcat")
    if not exe:
        return set()
    out = subprocess.run([exe, "-k65"], capture_output=True, text=True, errors="replace").stdout
    words = set()
    for w in re.split(r"\s+", out.split("\n", 2)[-1]):
        w = re.sub(r"[^a-z]", "", w.lower())
        if len(w) >= 2:
            words.add(w.upper())
    return words


BASIC65_KEYWORDS = None


def check_basic(name, text):
    global BASIC65_KEYWORDS
    if BASIC65_KEYWORDS is None:
        BASIC65_KEYWORDS = basic65_keywords()
    lines = [l for l in text.strip().split("\n") if l.strip()]
    nums = [int(l.split(" ", 1)[0]) for l in lines]
    problems = []
    if nums != sorted(set(nums)):
        problems.append("line numbers not unique and ascending")
    code = re.sub(r'"[^"]*"', '', text.upper())
    code = re.sub(r'REM.*', '', code)
    if re.search(r'DATA[^"\n]*\$', code):
        problems.append("$ hex in DATA (READ of a number takes decimal only)")
    code = re.sub(r'DATA.*', '', code)
    targets = set()
    for m in re.finditer(r'GO(?:SUB|TO) *(\d+)|THEN *(\d+)|RESTORE *(\d+)', code):
        targets |= {int(g) for g in m.groups() if g}
    if targets - set(nums):
        problems.append(f"missing line(s) {sorted(targets - set(nums))}")
    names = {t for t in re.findall(r'\b([A-Z][A-Z0-9]*\$?)', re.sub(r'\$[0-9A-F]+', '', code))
             if t.rstrip("$") not in KEYWORDS | BASIC65_KEYWORDS and not re.fullmatch(r'[BP][0-9]+', t)}
    # A keyword inside a name is tokenised there (TOD -> TO D): never allowed
    inside = sorted(f"{n} ({k})" for n in names for k in BASIC65_KEYWORDS
                    if k in re.sub(r"[^A-Z]", "", n))
    if inside:
        problems.append(f"names containing a keyword: {inside}")
    by = {}
    for n in names:
        by.setdefault(n[:2] + ("$" if n.endswith("$") else ""), set()).add(n)
    clash = {k: v for k, v in by.items() if len(v) > 1}
    if clash:
        problems.append(f"variables share their first two characters: {clash}")
    bad = [n for n in names if n[:2].rstrip("$") in RESERVED and n != "TI$"]
    if bad:
        problems.append(f"reserved variable names: {bad}")
    for l in lines:
        if len(l) > 159:
            problems.append(f"line too long for the screen editor: {l[:20]}...")
    if problems:
        sys.exit(f"{name}: " + "; ".join(problems))


# ---------------------------------------------------------------------------
# D81 writing (used when c1541 is not installed)

def petscii_name(name):
    out = bytearray()
    for ch in name:
        c = ord(ch)
        if 0x61 <= c <= 0x7A:
            c -= 0x20                       # lower-case ASCII = unshifted PETSCII
        out.append(c)
    return bytes(out[:16]).ljust(16, b"\xa0")


def write_d81(path, files, disk_name="ssnail hw", disk_id=b"sn"):
    """files: [(name, data)] written as PRG files, in order."""
    img = bytearray(80 * 40 * 256)

    def off(t, s):
        return ((t - 1) * 40 + s) * 256

    used = {(40, s) for s in range(0, 3)}
    nd = (len(files) + 7) // 8                      # directory sectors
    used |= {(40, 3 + k) for k in range(nd)}
    free = [(t, s) for t in list(range(39, 0, -1)) + list(range(41, 81)) for s in range(40)]
    entries = []
    for name, data in files:
        chunks = [data[i:i + 254] for i in range(0, len(data), 254)] or [b""]
        blocks = [free.pop(0) for _ in chunks]
        used |= set(blocks)
        for k, (chunk, (t, s)) in enumerate(zip(chunks, blocks)):
            o = off(t, s)
            if k + 1 < len(blocks):
                img[o], img[o + 1] = blocks[k + 1]
            else:
                img[o], img[o + 1] = 0, len(chunk) + 1
            img[o + 2:o + 2 + len(chunk)] = chunk
        entries.append((petscii_name(name), blocks[0], len(blocks)))
    # header
    o = off(40, 0)
    img[o:o + 3] = bytes([40, 3, 0x44])
    img[o + 4:o + 20] = petscii_name(disk_name)
    img[o + 20:o + 22] = b"\xa0\xa0"
    img[o + 22:o + 24] = disk_id
    img[o + 24] = 0xA0
    img[o + 25:o + 27] = b"3D"
    img[o + 27:o + 29] = b"\xa0\xa0"
    # BAM: 40/1 tracks 1-40, 40/2 tracks 41-80
    for half, (t0, link) in enumerate(((1, (40, 2)), (41, (0, 0xFF)))):
        o = off(40, 1 + half)
        img[o], img[o + 1] = link
        img[o + 2:o + 8] = bytes([0x44, 0xBB]) + disk_id + bytes([0xC0, 0])
        for k in range(40):
            t = t0 + k
            bits = [0] * 5
            nfree = 0
            for s in range(40):
                if (t, s) not in used:
                    bits[s // 8] |= 1 << (s % 8)
                    nfree += 1
            img[o + 0x10 + 6 * k:o + 0x16 + 6 * k] = bytes([nfree] + bits)
    # directory
    for d in range(nd):
        o = off(40, 3 + d)
        if d + 1 < nd:
            img[o], img[o + 1] = 40, 4 + d
        else:
            img[o], img[o + 1] = 0, 0xFF
        for k, (pname, (t, s), nblocks) in enumerate(entries[8 * d:8 * d + 8]):
            e = o + 32 * k
            img[e + 2] = 0x82                       # PRG, closed
            img[e + 3], img[e + 4] = t, s
            img[e + 5:e + 21] = pname
            img[e + 30:e + 32] = struct.pack("<H", nblocks)
    open(path, "wb").write(img)


def build_disk(out, files):
    """files: [(disk name, host path)] -> out/ssnailhw.d81"""
    d81 = os.path.join(out, "ssnailhw.d81")
    if os.path.exists(d81):
        os.remove(d81)
    c1541 = shutil.which("c1541")
    if c1541:
        cmd = [c1541, "-format", "ssnail hw,sn", "d81", d81]
        for name, path in files:
            cmd += ["-write", path, name]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(d81):
            return d81, "c1541"
        print(f"c1541 failed ({r.stderr.strip()[-200:]}); writing the image myself")
    write_d81(d81, [(name, open(path, "rb").read()) for name, path in files])
    return d81, "built in"


# ---------------------------------------------------------------------------

def main():
    out = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "ssnail-hwtests")
    os.makedirs(out, exist_ok=True)
    petcat = shutil.which("petcat")
    if not petcat:
        sys.exit("petcat (from VICE) is needed to tokenise the BASIC 65 programs")
    env = dict(os.environ, SSNAIL_TOOLS=TOOLS)
    data_files, halts = [], {}
    with tempfile.TemporaryDirectory() as tmp:
        for name, desc, f, gen, pkg, il, eo, en, halt in TESTS:
            r = subprocess.run([sys.executable, os.path.join(HERE, gen)], cwd=tmp, env=env,
                               capture_output=True, text=True)
            if r.returncode:
                sys.exit(f"{gen} failed:\n{r.stdout}{r.stderr}")
            text = open(os.path.join(tmp, pkg)).read()
            full = pkg_words(text, "INIT")
            if any(full[il:]):
                sys.exit(f"{name}: the bench's data has non-zero bytes from ${il:X}, "
                         f"past the {il:#x} bytes the test loads (raise its init bytes)")
            init = full[:il]
            expect = pkg_words(text, "EXPECT")[:en]
            if halt is None:
                halt = int(re.search(r"HALT_PC : natural := (\d+);", text).group(1))
            halts[f] = halt
            # PRG-style: BLOAD skips a 2-byte load address even with ,P
            for ext, blob in ((".bin", init), (".exp", expect)):
                p = os.path.join(out, f + ext)
                open(p, "wb").write(b"\0\0" + blob)
                data_files.append((f + ext, p))
        r = subprocess.run([sys.executable, os.path.join(HERE, "gen_perf.py")], cwd=tmp, env=env,
                           capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"gen_perf.py failed:\n{r.stdout}{r.stderr}")
        perf = make_perf(open(os.path.join(tmp, "perf_pkg.vhdl")).read())
    check_perf(perf)
    p = os.path.join(out, "ssnp.bin")
    open(p, "wb").write(b"\0\0" + perf)
    data_files.append(("ssnp.bin", p))

    progs = programs()
    prg_files = []
    for n, _ in progs + STANDALONE:
        if len(n) > 16:
            sys.exit(f"program name '{n}' is longer than 16 characters (CBM file names)")
    allp = [(n, b, False) for n, b in progs] + [(n, b, True) for n, b in STANDALONE]
    for k, (name, body, alone) in enumerate(allp):
        nxt = progs[k + 1][0] if (not alone and k + 1 < len(progs)) else None
        text = body.strip("\n") + common(nxt, alone)
        for f, h in halts.items():
            text = text.replace("{HP_" + f + "}", str(h))
        check_basic(name, text)
        stem = name.replace(" ", "_").replace(".", "_")
        bas = os.path.join(out, stem + ".bas")
        prg = os.path.join(out, stem + ".prg")
        open(bas, "w").write(text.strip("\n").lower() + "\n")
        r = subprocess.run([petcat, "-w65", "-o", prg, "--", bas], capture_output=True, text=True)
        if r.returncode or not os.path.exists(prg):
            sys.exit(f"petcat failed on {bas}:\n{r.stdout}{r.stderr}")
        prg_files.append((name, prg))
    d81, how = build_disk(out, prg_files + data_files)
    print(f"{len(prg_files)} test programs, {len(data_files)} data files -> {d81} ({how})")
    print('On the MEGA65: mount it, then  RUN "00.CPU RAM"')


if __name__ == "__main__":
    main()
