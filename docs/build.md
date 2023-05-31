## This is the 'build' documentation file.

# Table of Contents:

[Introduction](#introduction)
[Downloading Repository](#downloading-repository)
[Compiling](#compiling)
[Modifying the design using ISE](#modifying-the-design-using-ise)
[Programming the FPGA via USB](#programming-the-fpga-via-usb)
[Programming the FPGA via sdcard](#programming-the-fpga-via-sdcard)

## Introduction

*Thanks for justburn for his contributions on getting this file started!*

The overall process from go-to-whoa takes about 60 minutes.

Basically you:

1. download the repository from github (5 mins),
1. compile the design into a bitstream (10 - 240 mins),
1. copy bitstream onto fpga board (5 mins).

## Downloading Repository

The following is assumed:

1. you have linux, say, Ubuntu 20.04
1. you have git installed, if not, use the following:
```
$> sudo apt-get install git
```

Make a working directory for your project, we refer to that working directory as `$GIT_ROOT`
```
$> cd $GIT_ROOT
```
Clone the following two git repositories into your working directory
```
$GIT_ROOT$> git clone https://github.com/MEGA65/mega65-core.git
```
You should now have a directory in your working directory called `mega65-core`.

(If you have a github account, and use SSH keys to avoid being prompted for your github password, use `git@github.com:MEGA65/mega65-core.git` instead of the https URL above. But if you have that we probably don't need to tell you...)

Change directory into the `mega65-core` working directory.
```
$GIT_ROOT$> cd mega65-core
$GIT_ROOT$/mega65-core>
```

The `master` branch is the latest release core. But you probably don't want to
build that, as the release is always available on [filehost](https://files.mega65.org/) (search for `core release`).

So you probably want to checkout the `development` branch.
```
$GIT_ROOT$/mega65-core> git checkout development
```

If it is a different branch you are interested in (perhaps someone on discord asked for a specific branch to test), just replace `development` with the respective branch name.

To get back to the release branch, use `master` as the branch name.

You may want to type `git status` or `git branch` to check what branch you have checked out.

To make sure that you have the latest files, if you wish to repeat this after the MEGA65 team have updated the source code, all you have to do is type:
```
$GIT_ROOT$/mega65-core> git pull
```

## Submodules

Previously it was necessary to checkout several sub-modules before building. This is now taken care of by the make file (Makefile).

Some of the submodules can be disabled by setting various `USE_LOCAL_` variables. Check the Makefile for them.

## 3rd-party programs

### exomizer

You need `exomizer` installed to be able to pack programs for the
MEGA65.

Get the software or sourcecode from the
[Exomizer Project Homepage](https://bitbucket.org/magli143/exomizer/wiki/Home).
Follow the instructions on the project page how to build and/or install.

### cbmconvert



### cc65

The Makefile can compile a `cc65` version automatically, but if you are planning
to work on the core, it is recommended to install `cc65` into your system.

You can then set the environment variable `USE_LOCAL_CC65` to 1 or call make with
```
make USE_LOCAL_CC65=1 TARGETNAME
```

## Compiling

The following is assumed:

1. you have `gcc` installed (6.0+) (for compiling c.*)
1. you have `make` installed (4.0+) (for the makefile)
1. you have `python` installed (3.6+) (for some scripts)
1. you have `libpng12-dev` installed (for the image manipulation) (alternatively use libpng-dev to install)
1. you have `libusb-1.0-0-dev` installed (for communicationg with JTAG)
1. you have `cbmconvert` installed (2.1.4+) (to make a D81 image) (refer to ./using.md)
1. you have `gnat` installed (for compiling the GHDL submodule)
1. you have `libgtest-dev` and `libgmock-dev` installed
1. you have a recent version of Xilinx Vivado WebPACK edition installed, with a valid licence (recommended that you install to directory /opt/Xilinx to prevent issue with makefile)

Overview of the compile process. Choose the specific make target to suit the device that you are targetting:

__MEGA65 Rev3 boards__:
Aka dev kits and final release model:
1. Bitstream: `make bin/mega65r3.bit`
2. MCS file for Vivado: `make bin/mega65r3.mcs`

__MEGA65 Rev2 boards__:
1. Bitstream: `make bin/mega65r2.bit`
2. MCS file for Vivado: `make bin/mega65r2.mcs`

__Nexys4DDR (A7) boards__:
1. Bitstream: `make bin/nexys4ddr-widget.bit`
2. MCS file for Vivado: `make bin/nexys4ddr-widget.mcs`

__Nexys4 boards__:
1. Bitstream: `make bin/nexys4.bit`
2. MCS file for Vivado: `make bin/nexys4.mcs`

## Programming the FPGA JTAG and the m65 cli tool

The `m65` program is part of the
[mega65-tools](https://github.com/MEGA65/mega65-tools/)
repository. Precompiled version are available.

With this tool and a JTAG adapter it is very easy to push the bitstream onto your device. Consult the [tutorial](https://files.mega65.org?ar=280a57a6-fb84-40fc-96ac-6da603302aa7) for more help.

The short version:
```
m65 --bit bin/nexys4ddr.bit
```
(This assumes that you have the mega65-tools in your search path)

## Programming the flash memory on the FPGA board

Please consult the [tutorial](https://files.mega65.org?ar=280a57a6-fb84-40fc-96ac-6da603302aa7) how to do this.
