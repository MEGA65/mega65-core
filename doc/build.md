## This is the **build** documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Downloading Repository](#downloading-repository)  
[Compiling](#compiling)  
[Modifying the design using ISE](#modifying-the-design-using-ise)  
[Programming the FPGA](#programming-the-fpga)

## Introduction

Thanks for justburn for his contributions on getting this file started!

The overall process from go-to-whoa takes about 60 minutes.

Basically you:

1. download the repository from github (5 mins),
1. compile the design into a bitstream (40 mins),
1. copy bitstream onto fpga board (5 mins).

Detailed instructions are below.

## Downloading Repository

The following is assumed:

1. you have linux, say, Ubuntu 15
1. you have git installed
```
$> sudo apt-get install git
```

Make a working directory for your project, we refer to that working directory as ```$GIT_ROOT```
```
$> cd $GIT_ROOT
```
Clone the following two git repositories into your working directory
```
$GIT_ROOT$> git clone https://github.com/Ben-401/c65gs.git
$GIT_ROOT$> git clone https://github.com/gardners/Ophis.git
$GIT_ROOT$> 
```
You should now have two directories in your working directory, ie ```c65gs``` and ```Ophis```.

Change directory into the ```c65gs``` working directory.
```
$GIT_ROOT$> cd c65gs
$GIT_ROOT$/c65gs>
```

The current branch that we support is the ```dockit``` branch, so update your files to reflect this branch:
``` 
$GIT_ROOT$/c65gs> git checkout dockit
```
To make sure that you have the latest files, all you have to do is type:
``` 
$GIT_ROOT$/c65gs> git pull
```
You are now ready to compile the design.

## Compiling

The following is assumed:

1. you have ```gcc``` installed (i have ver 5.2.1) (for compiling c.*)
1. you have ```make``` installed (i have 4.0) (for the makefile)
1. you have ```python``` installed (I have ver 2.7.10) (for some scripts ???)
1. you have ```libpng12-dev``` installed (for the image manipulation)
1. you have Xilinx ISE 14.7 WebPACK installed, with a valid licence

In your working directory: type the following
```
$GIT_ROOT$/c65gs> ./compile.sh
$GIT_ROOT$/c65gs> 
```
The ```compile.sh``` script calls the ```make``` command in the ```./precomp``` directory, then issues commands to build the design using ISE commands.

The following warnings may appear, but these are OK:
```
WARNING: branch out of range, replacing with 16-bit relative branch
```

## Modifying the design using ISE

Open ISE, and then ```Project -> Open``` and choose the ```"mega65"``` project.

You should be able to double-click on the ```"Generate Programming File"``` and a bit-stream should be created.

## Programming the FPGA

Then load the bitstream into the Nexys 4 DDR board via USB stick:

1. you need a USB stick formatted as FAT32
1. copy the bitstream to the root directory of the USB stick
```
$GIT_ROOT$/c65gs> cp *.bit /media/sdc1
```

1. power OFF nexys board
1. place USB stick into the USB_HOST header
1. set jumper JP2 to USB
1. set jumper MODE to USB/SD
1. power ON nexys

Upon powerup, the bitstream is copied from USB into FPGA, then the FPGA executes it.

The End.
