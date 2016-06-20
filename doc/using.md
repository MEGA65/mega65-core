## This is the **using** documentation file.

# Table of Contents:

[Introduction](#introduction)  
[c64 mode](#c64-mode)

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
 1. a list of the files on the SDcard will be listed. Press "Y" to mount the disk image listed, or any other key to keep going through the list.
 1. NOTE: that files that have been written to SDcard, *then deleted*, will still appear, but will be shown with the "|" symbol as the first char of the filename.
 1. NOTE also: that to quit the listing, ```hold RUN-STOP``` and ```tap RESTORE```. You can then re-enter ```sys49152```.
 1. once a "D81" image is mounted, you can then either:
 1. - type ```LOAD"$",8``` followed by ```list``` to display a directory listing of the mounted disk image, or
 1. - type ```LOAD"FILENAME",8,1```, where ```FILENAME``` is a file on the disk, which will load a program you know is on the disk image.
 1. Alternatively, to load the "DONKEYKONG" program, you can ```LOAD"DON*",8,1```, which will load the first file on the disk with matching filename starting with "DON".
 1. Generally when a program is loaded, you can just type ```RUN``` to start the program.
1. To reset/restart the system, press the red "CPU RESET" button on the Nexyx board. This is the button closest to the center of the board.

The End.
