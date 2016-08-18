## This is the 'using' documentation file.

# Table of Contents:

[Introduction](#introduction)  
[c64 mode - general](#c64-mode---general)  
[c64 mode - loading from SDcard](#c64-mode---loading-from-sdcard)  
[General Usage](#general-usage)  
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

## c64 mode - general

When in c64 mode, you can generally do a number of things:

1. you can write a BASIC program and RUN it.
 1. Details to be provided later [ ].
1. you can load a program from the SDcard.
 1. first you need to mount the SDcard, then run a "disk-load" program (see [below](#c64-mode---loading-from-sdcard))
1. you can use the serial-monitor from a PC to talk with the mega65.
 1. the serial monitor allows you to disassemble memory, assemble a machine language (ML) program, execute the ML program, step through the ML program, etc (see [below](#serial-monitor)).

## c64 mode - loading from SDcard

Basically: to load from SDcard, you first need to mount a disk-image of file-format "*.D81".
Once that disk-image is mounted, then you just as-per-normal ```load"$",8```, ```list``` and ```load...```.
Details of this are below.

NOTE: that to mount a disk-image, the current design supports two different methods.
These two different methods are selectable when compiling the design.
Please refer to ```kickstart.a65``` and see the section:
```
diskchooserstart:
        ; Pre-compiled disk chooser
        .incbin "diskchooser"
        ;  .incbin "diskmenu_c000.bin"
diskchooserend:
```
In the above code-snippet, you can comment out the ```diskchooser``` line and uncomment the ```diskmenuc000.bin``` line to select the alternate disk-mount code.

Currently, "diskchooser" is simple and seems to work, and is therefore the default in this git-repo.  

The "diskmenu_c000.bin" is not currently working. This alternate version uses a much nicer interface.

So, assuming you have the diskchooser compiled in, and you are in c64 mode,  

1. To LOAD files from the SDcard, first mount a disk-image:
 1. type ```sys49152``` and press enter. This executes code at $c000.
 1. a list of the files on the SDcard will be listed. Press "Y" to mount the [diskimage](#disk-image) listed, or any other key to keep going through the list.
 1. NOTE: that files that have been written to SDcard, *then deleted*, will still appear, but will be shown with the "|" symbol as the first char of the filename.
 1. NOTE also: that to quit the listing, ```hold RUN-STOP``` and ```tap RESTORE```. You can then re-enter ```sys49152```.  

1. Once a "D81" disk-image is mounted, you can then either:
 1. - hold ```<shift>``` and tap ```<run-stop>``` to load the first file on the mounted disk-image, or
 1. - type ```LOAD"$",8``` followed by ```list``` to display a directory listing of the mounted disk image, or
 1. - type ```LOAD"FILENAME",8,1```, where ```FILENAME``` is a file located within the mounted disk-image, which will load a program that you know is on the disk-image.
 1. Alternatively, to load the "DONKEYKONG" program, you can ```LOAD"DON*",8,1```, which will load the first file on the disk with matching filename starting with "DON".
 1. Generally when a program is loaded, you can just type ```RUN``` to start the program.

## general usage

1. To reset/restart the system, press the red "CPU RESET" button on the Nexyx board. This is the button closest to the center of the board.
1. The [serial-monitor](#serial-monitor) allows a serial communication between PC and FPGA, to debug/monitor the CPU.
1. Switch 15 can be asserted to disable interrupts. This is especially useful when stepping/tracing through a program using the serial-monitor and you want to ignore interrupts.
1. Switch 14 can be used to do something strange with the video colours. This is yet to be determined.


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
or for unix:  
 ```
tar xvfz cbm...
cd cbm...
make -f Makefile.unix
sudo make -f Makefile.unix install
```
you can now run cbmconvert from any directory.

1. converting a D64 image to D81 format, verbosely, you can do:  
```./cbmconvert -v2 -D8 crest-2_years_crest.d81 -d crest-2_years_crest.d64```  
1. then put the D81 file on the SDcard of the c65gs and enjoy.  

* NOTE that I had 'defrag' problems when mounting some D81 files. It seems the SDcard reader can only mount the image if the D81-file is contiguous, IE: if the SDcard is fragmented, it cannot load.  
* So, ensure that the SDcard is defragmented, either ```defrag``` on windows, or format the card, then copy on all files required.

## Files required on SDcard

This info sourced from the youtube [video](https://www.youtube.com/watch?v=f_0QCLBKfpc) titled "First Steps".  
Seems the video may be outdated with the github-repo, ie: all references to "c65gs" should be replaced with "mega65", i thinks.  
Unsure if UPPER/LOWER case of filenames is important, to do [  ].  
Unsure if we need "G65" or "M65", to do [  ].  

* ```MEGA65.ROM``` -- c65 kernal ROM, renamed from 911001.bin (or 910111 ???) which is the original ROM file extracted from one of the real c65 machines. Search for it on the internet.
* ```C65GS.ROM``` -- as above, but unsure which needs to get loaded, need to look into the kickstart.a65 code to see which ROM is required.
* ```C65GSx.ROM``` -- (optional) as above, but with ```x``` in the filename where ```x``` is a digit, unsure if this is still implemented, need to look into the kickstart.a65 code to see.
* ```KICKUP.G65``` -- (optional) an updated version of the kickup-code (ie kickup.a65, which is compiled into the bitstream), but this ```kickup.G65``` is loaded at boot-up and replaces the code in the bitstream. This is useful for developing the kickup-code without having to recompile the entire design/bitstream.
* ```CHARROM.M65``` -- (optional) the proprietary CBM character ROM, which is the original ROM file, cannot determine how this is built or sourced  
* ```BOOTLOGO.G65``` -- (optional) image displayed on kickstart screen, refer ```/precomp/Makefile```   
* ```MEGA65.D81``` -- (optional) disk-image automatically mounted at boot-up
* ```user.bit``` -- (optional) place a bitstream on the SDcard as a fallback when no "*.bit" file is found on the USB

## Files required on USBstick

NOTE: that at least one bitstream (```"*.bit"```) needs to either be on the USB-stick (see below), SD-card (see above), or EEPROM (to be do'ed).  
NOTE: that a jumper on the NexysDDR board determines where to look for the bitstream.

* ```user.bit``` -- (optional) bitstream to load when FPGA is powered ON.  

## Serial Monitor
The monitor can be used to gain a closer look at what the CPU (and other parts of the design) are doing. If you are familiar with a debugger or machine-code-monitor, then the Serial Monitor will be familiar to you.  

The monitor allows a user to interface within a serial port program on a PC, to the internals of the FPGA.  
Refer to the [monitor](./monitor.md) page for detailled instructions on how to use it.  

Basically, with the MEGA65 running in either c65/c64 mode:

1. connect USB cable between PROG/UART header of the FPGA-board and a USB port of the PC.
1. the PC should detect that there is a USB-device on the FPGA-end of the cable.
1. using a terminal window, open/connect communication to the serial-port.
1. now send commands to the FPGA-board to tell it what to do, or
1. receive status information from the FPGA-board.

The End.
