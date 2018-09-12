Introduction
----------

The 65GS02 is the fast CPU core of the C65GS computer.  It is
basically a fast 6502 with increased IPC through the use of a 64bit
memory bus.  The memory bus is separated into eight separately
addressable columns, allowing the fetching of instructions in a single
cycle, regardless of length.  This, combined with pipelining the
writing of operands back to registers or memory while fetching the
next instruction, and the removal of all page-crossing penalties
allows for an increased IPC compared with an identically clocked
6502/6510 or even 65C02/4510.

C64 Compatability
---------------

Any CPU with altered cycle timing cannot be 100% C64 compatible. That
said, care can be taken to reduce difference in the effects of
instructions, regardless of the time they take to execute.  The 65GS02
design takes some care in this matter, as differences in the
read-modify-write instructions on the 4510 were a source of
considerable incompatibility of C64 software with the
C65. Specifically, the 4510 did not write the original operand before
writing the final value of the operand when executing
read-modify-write instructions. This prevented the common idiom of
using DEC $D019 or LSR $D019 to acknowledge interrupts from the
VIC-II.

When the 45GS10 is operating at 1MHz, 2MHz or 3.5MHz modes, it counts
the cycles that would have been taken on a 6502 (or 65CE02 when at 3.5MHz),
and introduces pauses after each instruction until the appropriate period
of time has elapsed. Timing is based on either the PAL or NTSC CPU speed
depending on the state of the PAL/NTSC configuration bit of the VIC-IV.

Memory Write Pipelining
-------------------

Memory write pipelining has been removed from the processor.

Instruction cycle counts
-------------------

The primary driver for cycle counts are the addressing mode
concerned. The following table is for normal instructions.  Notes
following the table describe deviations from this table.

This table may not be completely accurate, and is subject to change.
It is best to verify on the machine itself.

Cycles Addressing Mode
----- --------------
1     Implied
1     Accumulator
2     Immediate
2     Relative (8-bit operand) (branch not taken)
3     Relative (8-bit operand) (branch taken)
3     Relative (16-bit operand) (branch not taken)
4     Relative (16-bit operand) (branch taken)
2     Zero Page
2     Zero Page,X
2     Zero Page,Y
3     Absolute (including JMP)
3     Absolute,X
3     Absolute,Y
5     (ZP,X)
5     (ZP,Y)
5     (Absolute)

Notes:
* All read instructions incur a one cycle address setup penalty.
  e.g. STA $1234 requires 4 cycles, but LDA $1234 requires 5.
* For read-modify-write instructions, one additional cycle is required
to accommodate the memory read.
* Read-modify-write instructions that have $D019 as the 16-bit address
operand (regardless of where that address is currently mapped) incur
a one cycle penalty to emulate the dummy write of the NMOS 6502.
* For all instructions fetched from I/O memory add 1 cycle.
* BRK takes how many cycles?
* For accesses to expansion memory substantial delays may be incurred,
  depending on the type of memory, whether it is from the cartridge port
  (and if so, where we are in the current ~1MHz C64 clock cycle we are,
   and whether the cartridge supports operating at >1MHz).
* Interrupts take how many cycles?
* Trapping into or out of the Hypervisor is performed by writing to a
  trap register ($D640-$D67F) and incurrs 1 cycle penalty.
* Trapping into the Hypervisor may, depending on the processor speed
  setting result in a delay slot following the instruction that caused
  the trap.  Therefore the correct method for triggering a trap is:
  STA $D6xx + NOP.






