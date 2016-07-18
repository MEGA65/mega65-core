## This is the **using** documentation file.

# Table of Contents:

[Introduction](#introduction)  
[c64 mode](#c64-mode)  
[diskimages](#disk-images)  
[converting D64 images to D81 image format](#converting-d64-images-to-d81-image-format)  
[Files required on SDcard](#files-required-on-sdcard)  
[Files required on USBcard](#files-required-on-usbcard)  
[Serial Monitor](#serial-monitor)  

## Introduction

When the bitstream has been loaded into the fpga, the fpga will begin to execute the bitstream.

The following is a basic list of the startup:

1. "MEGA65 KICKSTART Vxx.xx".
 1. insert photo of screen
1. The above kickstart screen:
 1. shows the git-version
 1. SDcard: looks for it, resets it, and mounts it
 1. attempts to load "BOOTLOGO.M65", if so, displays logo in top left
 1. runs the kicked hypervisor (details to be found...)
 1. mounts a disk image (MEGA65.D81) from SDcard
 1. seems to check for a ROM, does not find it so attempts to load it from the SDcard.
1. The system then drops into MEGA65 (c65) mode.
 1. insert photo of c65 screen

NOW is a good time to remoove the USB-stick and put in the USB-keyboard.

From the keyboard, you can now do c65 things. Details to be provided l8r.

I suggest you type "GO64" followed by 'Y'. This will put you into c64 mode.

## c64 mode

1. From here you can write a BASIC program and RUN it. Details to be provided later.
1. To LOAD files from the SDcard:
 1. type ```sys49152``` and press enter
 1. a list of the files on the SDcard will be listed. Press "Y" to mount the [diskimage](#disk-image) listed, or any other key to keep going through the list.
 1. NOTE: that files that have been written to SDcard, *then deleted*, will still appear, but will be shown with the "|" symbol as the first char of the filename.
 1. NOTE also: that to quit the listing, ```hold RUN-STOP``` and ```tap RESTORE```. You can then re-enter ```sys49152```.
 1. once a "D81" image is mounted, you can then either:
 1. - type ```LOAD"$",8``` followed by ```list``` to display a directory listing of the mounted disk image, or
 1. - type ```LOAD"FILENAME",8,1```, where ```FILENAME``` is a file on the disk, which will load a program you know is on the disk image.
 1. Alternatively, to load the "DONKEYKONG" program, you can ```LOAD"DON*",8,1```, which will load the first file on the disk with matching filename starting with "DON".
 1. Generally when a program is loaded, you can just type ```RUN``` to start the program.
1. To reset/restart the system, press the red "CPU RESET" button on the Nexyx board. This is the button closest to the center of the board.
1. The [debugger](#debugger)-mode allows a serial communication between PC and FPGA, to debug/monitor the CPU.
1. Switch 15 can be asserted to disable interrupts.
1. Switch 14 can be used to do something strange with the video colours.


## disk images

The c65gs uses a 1581 disk drive.  
The 1581 drive uses single sided 3.5" disks, holding approx 800kB.  
Refer to the following for more details:
* https://en.wikipedia.org/wiki/Commodore_1581
* https://www.c64-wiki.com/index.php/Commodore_1581

The c64 uses a 1541 (or 1571) disk drive.
The 1541 drive uses double sided 5-1/4" disks, each side holding approx 170kB.
Refer to the following for more details:
* https://en.wikipedia.org/wiki/Commodore_1541
* https://www.c64-wiki.com/index.php/Commodore_1541

Both native disk formats of the 1541 and 1581 can be converted to more recent filesystems. The D41 and D81 are filesystems/fileformats currently used today that allow the original file system to be emulated from a D41/D81 imagefile.

The mega65 'emulates' the 1581 disk drive using the SDcard. The SDcard can be used to hold many diskimages of the original 1581 disk format. These images are commonly called "D81" files. One "D81" file is 819,200 bytes. So a modest side 4GB SDcard can hold over "4000" D81 disk images.

At the time of writing this, there is not much software available for the c65gs.
There is a large amount of c64 files available that are compatible with the c65gs.
Refer to the following websites for D64 imagefiles for emulating the 1541.

## converting D64 images to D81 image format

There are numerous ways to skin a cat, but here is the method I use:

1. Download the ```cmbconvert``` program (i use version 2.1.2).  
http://www.zimmers.net/anonftp/pub/cbm/crossplatform/converters/unix/cbmconvert-2.1.2.tar.gz
1. compile it using the instructions:  
http://www.zimmers.net/anonftp/pub/cbm/crossplatform/converters/unix/cbmconvert.html
1. converting a D64 image to D81 format, verbosely, you can do:  
```./cbmconvert -v2 -D8 crest-2_years_crest.d81 -d crest-2_years_crest.d64```  
1. then put the D81 file on the SDcard of the c65gs and enjoy.  

* NOTE that I had 'defrag' problems when mounting some D81 files. It seems the SDcard reader can only mount the image if the D81-file is contiguous, IE: if the SDcard is fragmented, it cannot load.  \
* So, ensure that the SDcard is defragmented, either ```defrag``` on windows, or format the card, then copy on all files required.

## Files required on SDcard

* ```BOOTLOGO.G65``` -- (not critical) image displayed on kickstart screen, refer ```/precomp/Makefile```   
* ```CHARROM.M65``` -- the proprietary CBM character rom (download at: ...?)  
* ```MEGA65.ROM``` -- unsure...  
* ```user.bit``` -- (optional) place a bitstream on the SDcard as a fallback when USB is unavailable  

## Files required on USBstick

* ```user.bit``` -- bitstream to load on the USBstick when FPGA is powered ON.  

## Serial Monitor
The monitor can be used to gain a closer look at what the CPU (and other parts of the design) are doing. If you are familiar with a debugger or machine-code-monitor, then the Serial Monitor will be familiar to you.  
The monitor allows a user to interface within a serial port program on a PC, to the internals of the FPGA.  
Refer to the [monitor](./monitor.md) page for detailled instructions on how to use it.  

Basically, with the MEGA65 running in either c65/c64 mode:

1. connect USB cable between PROG/UART header of the FPGA-board and a USB port of the PC.
1. the PC should detect that there is a USB-device on the FPGA-end of the cable.
1. using a terminal window, open/connect communication by: ```sudo cu -l /dev/cu.usbserial<???> -s 230400```. If you dont have the program ```cu```, then get it by ```sudo apt-get install cu```.
1. pressing 'return' will bring up the prompt
1. typing ```?<return>``` will provide some help text
1. to close the connection, type ```~.``` at the start of a blank line.

The End.
