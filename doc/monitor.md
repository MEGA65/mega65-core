## This is the **monitor** documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Breakpoint](#breakpoint)  

## Introduction

The Serial Monitor (monitor) can be used to gain a closer look at what the CPU (and other parts of the design) are doing.  
The VHDL-code for the monitor is located in ```uart_monitor.vhdl```.

Below are some instructions on how to use the monitor:  
(It is assumed that you are connected)

1. tapping ```<enter>``` will print the status-display with the most recent values of the registers.
1. holding ```<enter>``` will continue to print the status-display as above, but notice that many hundreds of clock-cycles would have been traversed between successive prints of the status-display. This can be accepted as the Program-Counter (PC) does not show consecutive addresses.
1. To observe the status-display between consecutive CPU instructions, you should first put the monitor into ```trace``` mode. Trace mode enables the CPU to be stepped one CPU instruction at a time, and displaying the status-display after each CPU instruction.
1. typing ```t1``` followed by ```<enter>``` will put the monitor into trace-mode and you will notice that the c64/c65 display will seem to have become frozen because no CURSOR BLINK. This is because the CPU is halted and is waiting for the monitor to either release it from TRACE-mode or to STEP it one instruction.
 1. pressing ```<enter>``` will STEP the CPU one instruction. This can be seen as the PC is incremented by a couple/few addresses.
 1. Also note that the instruction shown under the ```LAST-OP``` field will display the last instruction processed by the CPU.
 1. holding ```<enter>``` will continue to STEP the CPU one instruction at a time, and if you hold ENTER for long enough, you may see the CURSOR blink ON or OFF.

## Breakpoint 

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
