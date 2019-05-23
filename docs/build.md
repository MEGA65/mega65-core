## This is the 'build' documentation file.

# Table of Contents:

[Introduction](#introduction)
[Downloading Repository](#downloading-repository)
[Compiling](#compiling)
[Modifying the design using ISE](#modifying-the-design-using-ise)
[Programming the FPGA via USB](#programming-the-fpga-via-usb)
[Programming the FPGA via sdcard](#programming-the-fpga-via-sdcard)

## Introduction

Thanks for justburn for his contributions on getting this file started!

The overall process from go-to-whoa takes about 60 minutes.

Basically you:

1. download the repository from github (5 mins),
1. compile the design into a bitstream (10 - 240 mins),
1. copy bitstream onto fpga board (5 mins).

Detailed instructions are below.

## Downloading Repository

The following is assumed:

1. you have linux, say, Ubuntu 18.04
1. you have git installed, if not, use the following:
```
$> sudo apt-get install git
```

Make a working directory for your project, we refer to that working directory as ```$GIT_ROOT```
```
$> cd $GIT_ROOT
```
Clone the following two git repositories into your working directory
```
$GIT_ROOT$> git clone https://github.com/MEGA65/mega65-core.git
$GIT_ROOT$>
```
You should now have a directory in your working directory called ```mega65-core```.

If you have a github account, and use SSH keys to avoid being prompted for your github password,
use the following command to tell git to always use SSH instead of HTTPS when comminicating with
the github.com servers:

```
git config --global url.ssh://git@github.com/.insteadOf https://github.com/
```

Change directory into the ```mega65-core``` working directory.
```
$GIT_ROOT$> cd mega65-core
$GIT_ROOT$/mega65-core>
```

Currently, the ```development``` branch is what you should compile.
So, checkout that branch:
```
$GIT_ROOT$/mega65-core> git checkout development
Branch px100mhz set up to track remote branch development from origin.
Switched to a new branch 'development'
$GIT_ROOT$/mega65-core>
```

If you want to try a different (development) branch, do the following:
e.g., to see/use the example ```banana``` branch, type ```$GIT_ROOT$/mega65-core> git checkout banana```.
To change to the ```MASTER``` branch, type ```git checkout master```.

You may want to type ```git status``` or ```git branch``` to check what branch you have checked out.

To make sure that you have the latest files, if you wish to repeat this after the MEGA65 team have updated the source code, all you have to do is type:
```
$GIT_ROOT$/mega65-core> git pull
```

## Submodules

Previously it was necessary to checkout several sub-modules before building. This is now taken care of by the make file (Makefile).

## 3rd-party programs

You need ```fpgajtag``` installed to make use of the improved tool-chain.
See below for info:
```
$ cd .. (to get out of the $git_root dir)
$ git clone https://github.com/cambridgehackers/fpgajtag.git
$ cd fpgajtag
$ make
```
if the above fails, ```sudo apt-get install libusb-1.0-0-dev``` and ```make```.
```
$ sudo cp src/fpgajtag /usr/local/bin
$ cd ..
$ cd mega65-core
```

If it is correct, you should get a meaningful response from the following command:

```
$ fpgajtag --version
```

See below for other dependencies.

You are now ready to compile the design.

## Compiling

The following is assumed:

1. you have ```gcc``` installed (I have ver 5.2.1) (for compiling c.*)
1. you have ```make``` installed (I have 4.0) (for the makefile)
1. you have ```python``` installed (I have ver 2.7.10) (for some scripts)
1. you have ```libpng12-dev``` installed (for the image manipulation) (alternatively use libpng-dev to install)
1. you have ```cbmconvert``` installed (I have ver 2.1.2) (to make a D81 image) (refer to ./using.md)
1. you have a recent version of Xilinx Vivado WebPACK edition installed, with a valid licence (recommended that you install to directory /opt/Xilinx to prevent issue with makefile)

Overview of the compile process:

1. ```make```,

The following instructions are for running in the fpga.

* As there are many end-use cases, i will not cover them all here, just the one that suits me.
Someone else please document how the simulate function(s) work and what compile options etc.

## Programming the FPGA using fpga-board and the monitor_load command

The monitor_load program is compiled as part of the build process. This can be used to
load a bitstream and/or custom Hyppo/Hypervisor version, among other functions.

A command like the following will load and start the desired bitstream and Hyppo/Hypervisor
files you provide. You must have the USB programming cable connected for this to work. This
procedure works on Nexys4 as well as MEGA65 prototype main boards with the FPGA programming
module attached.  It is much faster (~3 seconds versus ~13 - 30 seconds) than loading a bitstream
from an SD card, and saves you the hassle of removing and inserting SD cards. monitor_load can
also be used to auto-switch to C64 mode on start (-4 option), and/or to load and optionally run
a user-supplied program on boot (see the usage text for monitor_load for details), providing a
greatly simplified work-flow.

```src/tools/monitor_load -b bin/nexys4ddr.bit -k bin/HICKUP.M65```

(This assumes you are running the command from the ```mega65-core``` directory.

## Programming the flash memory on the FPGA board to load the MEGA65 bitstream on power up

XXX - To be completed.

The general gist is to open vivado, and choose the menu item to program a device, and then
choose the appropriate .mcs file from the ```bin/``` directory.  The process takes several
minutes, but after that, if you have your FPGA board to start from [Q]SPI flash, it will
almost immediately (<1 sec delay) begin starting up as a MEGA65 every time that power is
provided or the "program FPGA" button is pressed on your FPGA board, if it has such a button.
