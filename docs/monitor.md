## This is the 'monitor' documentation file.

## Introduction

The MEGA65 includes an out-of-band memory and processor state investiation tool which is typically refered to as either
'the monitor' or 'matrix mode'.
The monitor was originally written in VHDL (see uart_monitor.vhdl), but has since been replaced with a Verilog implementation,
making it the only part of the MEGA65 written in Verilog instead of VHDL at the time of writing.

## Access from the MEGA65 Screen and Keyboard

To activate or disactivate matrix mode, and thus the monitor, hold the C=/MEGA key down while pressing TAB (or the
left-pointing arrow key at the top left of the keyboard if using a C64 keyboard).  You will see an animation that is
vaguely reminiscent of the matrix effect of that series of movies.  When activated in this way, the monitor interface
appears as a composited layer over the regular VIC-IV display.  The computer continues to run during this time, unless
the processor is paused from within the monitor interface, and any updates to the screen will be visible on the composited display.

## Remote Access

The monitor can be accessed remotely, using the USB cable on either the Nexys4 series FPGA development boards, or
the MEGA65 r1 PCB, if fitted with the Trenz Electronics USB debuging module.  This can be useful for a variety of
purposes, especially for interacting with the MEGA65 using the monitor_load and monitor_save programs. These programs
allow loading and saving of programs directly from a connected computer, as well as various other useful utility
functions, such as simulating typing on the keyboard.

You need a terminal program on your PC that communicates to the serial port. a number of options exist:

* hyperterminal  (Windows)
should be pre-loaded on Windows XP and similar systems.

* cygwin/picocom  (Windows)
 ```
git clone https://github.com/npat-efault/picocom
cd picocom
make
./picocom.exe
./picocom.exe --help
./picocom.exe --b 2000000 /dev/ttyS3
```
to exit: ```CTRL-a CTRL-x```

* cu (OSX and Linux and UNIX like operating systems)
 ```
sudo apt-get install cu
sudo cu -s 2000000 -fl /dev/cu.usbserial<???>
```
to exit: ```~.```

* use the m65dbg program (suggested option)
refer to [https://github.com/MEGA65/m65dbg](https://github.com/MEGA65/m65dbg) for install instructions
 ```
git clone https://github.com/MEGA65/m65dbg.git
cd m65dbg
make
./m65dbg -d /dev/ttyS3
```

NOTE: The m65dbg program may require updating to cater to the latest changes to the formatting of the output of
the monitor.

For all the above options, the following settings are required:

1. 2000000 baud rate
1. 8 data bits
1. No flow control required
1. 1 stop bit

## How to use

Below are some instructions on how to use the monitor:
(It is assumed that you are connected, using cygwin/picocom)

### Examining and modifying memory

The m command can be used to view the contents of memory.  By default a single line of 16 bytes of memory will be displayed.
Addresses should be given as 28-bit (7-digit hexadecimal) addresses in the MEGA65's address space. For convenience, the address
range $7770000-$777FFFF has the special meaning of showing the contents of memory from the CPU's current memory mapping context,
including any ROMs, IO areas or other special mapping effects that are in force.

To display a page (256 bytes) of memory at a time, use M instead of m.  To display the next block of memory, use M or m without an address,
and it will continue displaying from the last displayed address.  If connected via matrix mode, the F1 and F3 keys, or equivalently
cursor up and down keys, may be used to easily display the memory pages preceeding or following the most recently displayed.

To view a 4502 disassembly of memory, use the d (for one instruction) or D (to show 16 instructions) commands. As with m and M, these can
be followed by a 28-bit address, or used alone, to continue the display from where the previous command left off.

To modify memory, use the s or S command, followed by the first address to modify, and then the values to write.  If s is used, the address must be a 28-bit address. If S is used, then the address should be a 16-bit address, which will be interpreted using the CPU's current memory map.

### Stopping, Resuming and Stepping the Processor

1. tapping ```<enter>``` will print the status-display with the most recent values of the registers.
1. holding ```<enter>``` will continue to print the status-display as above, but notice that many hundreds of clock-cycles would have been traversed between successive prints of the status-display. This can be accepted as the Program-Counter (PC) does not show consecutive addresses.
1. To observe the status-display between consecutive CPU instructions, you should first put the monitor into ```trace``` mode. Trace mode enables the CPU to be stepped one CPU instruction at a time, and displaying the status-display after each CPU instruction.
1. typing ```t1``` followed by ```<enter>``` will put the monitor into trace-mode and you will notice that the c64/c65 display will seem to have become frozen because no CURSOR BLINK. This is because the CPU is halted and is waiting for the monitor to either release it from TRACE-mode or to STEP it one instruction.
 1. pressing ```<enter>``` will STEP the CPU one instruction. This can be seen as the PC is incremented by a couple/few addresses.
 1. Also note that the instruction shown under the ```LAST-OP``` field will display the last instruction processed by the CPU.
 1. holding ```<enter>``` will continue to STEP the CPU one instruction at a time, and if you hold ENTER for long enough, you may see the CURSOR blink ON or OFF.

### Breakpoint

1. SETTING A BREAKPOINT
The following will set a breakpoint at a memory location just before the cursors BLINK-routine. The user can then STEP through the instructions to see the actual BLINK instruction processed by the CPU, followed by resuming the CPU, followed by removing the breakpoint.
1. With the CPU free running (ie: cursor is blinking), set a breakpoint at address $EA5A by typing ```bea5a```. Soon after typing this command, the cursor will stop blinking.
1. Pressing ```<enter>``` will bring up the status-display of the registers showing that the CPU has now just processed the instruction at address ```$EA5E``` which is two addresses after the breakpoint. Why this is two addresses AFTER the breakpoint is not explained here.
1. press ```<enter>``` three more times and you will see on the third time that the cursor will now APPEAR after the instruction at memory location ```$EA20```.
1. holding ```<enter>``` for 30-seconds still does not execute enough instructions to cause the cursor to DISAPPEAR.
1. typing ```t0``` will allow the CPU to exit TRACE-mode and resume FREE-RUNNING. After typing "t0", followed by a short delay, you will see the cursor BLINK-OFF.
1. A short time later, you will notice that the cursor does not BLINK-ON. This is because the CPU will have executed the instruction at the BREAKPOINT again. This is observed by pressing ```<enter>``` again; the PC will be at $EA5E.
1. Similarly, pressing ```<enter>``` three times will cause the cursor to BLINK-ON.
1. Type ```t0``` to resume the CPU free-running. The cursor will dissappear and CPU enter TRACE-MODE at the breakpoint again.
1. This time, instead of pressing "enter" three times, type ```t0```. This will cause the CPU to enter FREE-RUNNING mode, and after executing three instructions the cursor will blink off, etc, then freeze again at the breakpoint.
1. You will notice that when the CPU is in FREE-RUNNING-mode, that LEDs 4 and 2 are ON. When the CPU enters TRACE-MODE (ie at the breakpoint), the LEDs 4 and 2 go OFF.
1. typing ```tc``` seems to STEP the CPU one instruction at a time, and after each instruction, the status-display of the registers are displayed to the screen. Pressing any key will exit from "tc" mode.
1. when in "tc"-mode, you will notice that LEDs 4 and 2 continue to BLINK ON and OFF, and that the CURSOR will BLINK ON and OFF about every 18 seconds.
1. to remove the BREAKPOINT, type ```b``` followed by return.
1. unsure how to display the list of current BREAKPOINTS,
1. unsure if multiple BREAKPOINTS can be set.

The End.


