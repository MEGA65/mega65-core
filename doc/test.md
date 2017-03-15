## This is the 'test' documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Test Procedure](#test-procedure)  


## Introduction

This document describes a number of tests that can be performed to verify that the design works as it should.

Within each test procedure, the tests are denoted as a bullet-points, with text describing what to do.  
Results are denoted as "-> something", where something is the expected result.

A description of the hardware is shown below:  
![alt tag](https://raw.githubusercontent.com/Ben-401/mega65pics/master/board.jpg)  
The above image shows:  
* Nexys4DDR development board,  
* VGA port connected to a vga monitor capable of 1920x1200@60hz,  
* USB port connected to a simple USB keyboard,  
* PROG/UART port connected to host-PC, for two reasons:  
 * to provide power to the Nexys board, and  
 * to allow serial comms between Nexys and host-PC.  
The host-PC should have the m65dbg running or a suitable serial-port program. I use picocom.
* SDMICRO port has a SDcard inserted, SDcard should contain the following files at a minimum:
 * ``bit03141732_dev..._1541f08~.bit (or similar)``  
``BOOTLOGO.M65 (optional)``  
``C000UTIL.BIN``  
``CHARROM.M65``  
``MEGA65.D81``  
``MEGA65.ROM``  
* FPGA-Switches (SW-x) all in their OFF position, which is DOWN.

## Test Procedure

All tests, unless otherwise noted, begin with the hardware as described above in the "Introduction" section above.  

For the individual tests, please see below.
* [Power and BOOT-up](./test-powerandbootup.md) - applies power and describes what should happen when the buttons/switches are manipulated.  

The End.
