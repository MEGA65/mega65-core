## This is the **build** documentation file.

# Table of Contents:

[Introduction](#Introduction)

[Downloading Repository](#Downloading-Repository)

[Patching](#Patching)

[Pre-Compiling](#Pre-Compiling)

[Generating the Bitstream](#Generating-the-Bitstream)

[Programming the FPGA](#Programming-the-FPGA)


## Introduction

Thanks for justburn for his contributions

The overall process from go-to-whoa takes about 90 minutes.
Basically you:

1. download the repository from github (5 mins),
1. make the nessessary pre-compiling (5 mins)
1. use Xilinx ISE to compile the design into a bitstream (60 mins)
1. copy bitstream onto fpga board

Detailed instructions are below.

## Downloading Repository

The following is assumed:

1. you have linux, say, Ubuntu 15
1. you have git installed
```bash
$> sudo apt-get install git
```

Make a working directory for your project, we refer to that working directory as ```$GIT_ROOT```
```
$> cd $GIT_ROOT
```
Clone the following two git repositories into your working directory
```
$GIT_ROOT$> git clone https://github.com/gardners/c65gs.git
$GIT_ROOT$> 
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
To make sure that you have the latest files, all you have to type is:
``` 
$GIT_ROOT$/c65gs> git pull
```
You are now ready to pre-compile some files.

## Patching

Currently two files are required to be used as an offline patch. Unzip both files and overwrite all changes.
```
$GIT_ROOT$/c65gs> unzip ddr.tgz .
$GIT_ROOT$/c65gs> unzip xco.tgz .
```
Download two files from online, into your working directory.
```
$GIT_ROOT$/c65gs> wget --no-check-certificate https://raw.githubusercontent.com/Digilent/Nexys4/master/Projects/User_Demo/src/hdl/FPGAMonitor.vhd
$GIT_ROOT$/c65gs> wget --no-check-certificate https://raw.githubusercontent.com/Digilent/Nexys4/master/Projects/User_Demo/src/hdl/LocalRst.vhd
```

We are done patching!

## Pre-Compiling

The following is assumed:

1. you have ```gcc``` installed (i have ver 5.2.1) (for compiling c.*)
1. you have ```make``` installed (i have 4.0) (for the makefile)
1. you have ```python``` installed (I have ver 2.7.10) (for some scripts ???)
1. you have ```libpng12-dev``` installed (for the image manipulation)

In your working directory: type "make" a few times
```
$GIT_ROOT$/c65gs> make
$GIT_ROOT$/c65gs> make
$GIT_ROOT$/c65gs> make
```
The following warnings may appear, but Paul says this is OK.
```
etherload.a65
diskchooser.a65 
c65gs/diskmenu.a65
c65gs/kickstart_dos.a65
kickstart.a65
WARNING: branch out of range, replacing with 16-bit relative branch
```
Now create the charrom by typing:
```
$GIT_ROOT$/c65gs> make charrom.vhdl
```
All pre-compiling should bow be done.

## Generating the Bitstream

The following is assumed:

1. you have Xilinx ISE 14.7 WebPACK installed, with a valid licence

Open ISE and ```Project -> Open``` and choose the ```"reboot65"``` project.

You should be able to double-click on the ```"Generate Programming File"``` and a bit-stream should be created.

## Programming the FPGA

We Load the bitstream into the Nexys 4 DDR board via USB stick:

1. you need a USB stick formatted as FAT32
1. copy the bitstream to the root directory of the USB stick
```
$GIT_ROOT$/c65gs> cp container.bit /media/sdc1
```

1. power OFF nexys board
1. place USB stick into the USB_HOST header
1. set jumper JP2 to USB
1. set jumper MODE to USB/SD
1. power ON nexys

Upon powerup, the bitstream is copied from USB into FPGA, then the FPGA executes it.

The End.
