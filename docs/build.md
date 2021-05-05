## This is the 'build' documentation file.

# Table of Contents:

[Introduction](#introduction)  
[Downloading Repository](#downloading-repository)  
[Submodules](#submodules)  
[Pre-requisites](#pre-requisites)  
[Compiling](#compiling)  
[Programming](#programming)

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

1. you have linux, say, Ubuntu 18.04 (other operating systems are supported, see below)
1. you have ```git``` installed, if not, use the following:
```
$> sudo apt-get install git
```

Make a working directory for your project, we refer to that working directory as ```$GIT_ROOT```
```
$> cd $GIT_ROOT
```
Clone the following git repository into your working directory
```
$GIT_ROOT$> git clone https://github.com/MEGA65/mega65-core.git
$GIT_ROOT$>
```
You should now have a directory in your working directory called ```mega65-core```.

If you have a github account, you can use SSH keys to avoid being prompted for your github password,
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

Currently, the ```stable_base``` branch is what you should compile from.
So, checkout that branch:
```
$GIT_ROOT$/mega65-core> git checkout stable_base
Branch stable_base set up to track remote branch stable_base from origin.
Switched to a new branch 'stable_base'
$GIT_ROOT$/mega65-core>
```

If you want to try a different (development) branch, do the following:
e.g., to see/use the example ```banana``` branch, type ```$GIT_ROOT$/mega65-core> git checkout banana```.
To change to the ```MASTER``` branch, type ```git checkout master```.

You may want to type ```git status``` or ```git branch -a --list``` to check what branch you have checked out.

To make sure that you have the latest files, if you wish to repeat this after the MEGA65 team have updated the source code, all you have to do is type:
```
$GIT_ROOT$/mega65-core> git pull
```

## Submodules

Previously it was necessary to checkout several sub-modules before building.  
This is now taken care of by the make file (Makefile).

## Pre-requisites

(Unsure if ```fpgajtag``` is required anymore).  
-> ==CUT-START
.  
You (may) need ```fpgajtag``` installed to make use of the improved tool-chain.
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
-> ==CUT-END

See below for other dependencies.

The dependencies differ depending on what O/S you are using.  
This is because some more recent O/S have the dependant packages already installed.  
Currently, the following O/S are supported for building this project:
* ubuntu 16 (http://releases.ubuntu.com/16.04.6/ubuntu-16.04.6-desktop-amd64.iso)
* ubuntu 18 (http://releases.ubuntu.com/18.04.4/ubuntu-18.04.4-desktop-amd64.iso)

Generally, when a ubuntu O/S is initially setup, the following is recommended:
```
sudo apt update
sudo apt upgrade
reboot
```

the following packages are required to be installed prior to compiling the mega65-core project:

* you have ```git``` installed (for cloning repositories)  
.  
For ubuntu18, ```git --version``` -> 2.17.1 works.  
.  
For ubuntu16, ```git --version``` -> 2.7.4 works.  
.
* you have ```build-essential```  
.  
For ubuntu18, this will provide:
```
The following NEW packages will be installed:
  build-essential dpkg-dev fakeroot g++ g++-7 gcc gcc-7 libalgorithm-diff-perl
  libalgorithm-diff-xs-perl libalgorithm-merge-perl libasan4 libatomic1
  libc-dev-bin libc6-dev libcilkrts5 libfakeroot libgcc-7-dev libitm1 liblsan0
  libmpx2 libquadmath0 libstdc++-7-dev libtsan0 libubsan0 linux-libc-dev make manpages-dev
```
.  
For ubuntu16, ```build-essential``` is already installed.  
.  
* you have ```gcc``` installed (for compiling c/cpp)  
.  
For ubuntu18, ```gcc --version``` -> 7.5.0 works (which come from build-essential).  
.  
For ubuntu16, the latest version of ```gcc``` from ```build-essential``` is 5.5.4 and **will not work**.  
You need to upgrade ```gcc``` to at least 6.x.y.  
Follow the below commands:  
(sourced from: https://gist.github.com/application2000/73fd6f4bf1be6600a2cf9f56315a2d91)  
```
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update
sudo apt install gcc-6 g++-6
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-6 60 --slave /usr/bin/g++ g++ /usr/bin/g++-6
```
Then, for ubuntu16, ```gcc --version``` -> 6.5.0 works.  
.
* you have ```make``` installed (for the Makefile).  
.  
For ubuntu18, ```make --version``` -> 4.1 works.  
.  
For ubuntu16, ```make --version``` -> 4.1 works.  
.  
* you have ```autoconf``` installed (for iverilog).  
.  
For ubuntu18, ```autoconf --version``` -> 2.69 works.  
.  
For ubuntu16, ```autoconf --version``` -> 2.69 works.  
.
* you have ```gperf``` installed (for iverilog).  
.  
For ubuntu18, ```gperf --version``` -> 3.1 works.  
.  
For ubuntu16, ```gperf --version``` -> 3.0.4 works.  
.
* you have ```flex``` installed (for iverilog).  
.  
For ubuntu18, ```flex --version``` -> 2.6.4 works.  
.  
For ubuntu16, ```flex --version``` -> 2.6.0 works.  
.
* you have ```bison``` installed (for iverilog).  
.  
For ubuntu18, ```bison --version``` -> 3.0.4 works.  
.  
For ubuntu16, ```bison --version``` -> 3.0.4 works.  
.
* you have **java** installed (for KickAss), just the JRE is OK.  
so, ```sudo apt install default-jre```  
.  
For ubuntu18, ```java --version``` -> openjdk v11.0.7 works.  
.  
For ubuntu16, ```java -version``` -> openjdk v1.8.0_252 works.  
.
* you have **python** installed (for some scripts including src/tools/makerom)  
Currently ```makerom``` uses ```python2```.  
.  
For ubuntu18, there is no ```python``` nor ```python2```, but there is ```python3 v3.6.9```.  
For ubuntu18, ```sudo apt install python-minimal``` installs the following:
```The following NEW packages will be installed:
  libpython-stdlib python python-minimal python2.7 python2.7-minimal
```
Now, for ubuntu18, ```python  --version``` -> 2.7.17, and  
Now, for ubuntu18, ```python2 --version``` -> 2.7.17.  
.  
For ubuntu16, python is already installed:  
```
python --version``` -> 2.7.17.  
python2 --version``` -> 2.7.17.  
```
.
* you have ```libpng-dev``` installed (for pngprepare)  
.  
For ubuntu18, ```dpkg -l | grep libpng``` -> 1.6.34 works.  
.  
For ubuntu16, ```libpng12-0``` is already installed but that **does not work**.  
You need ```libpng-dev``` and apt will select ```libpng12-dev``` **which does work**.  
``` dpkg -l | grep libpng``` -> 1.2.54.

1. you have a recent version of Xilinx Vivado installed.  
.
You must either install to directory ```/opt/Xilinx``` (to prevent issue with ```./vivado_wrapper```),  
ie: ```/opt/Xilinx/Vivado/2018.2/```, or  
place a symbolic link in your ```/opt/Xilinx/``` to your base install location for ```Vivado```,  
ie: ```ln -s /my_ssd/Vivado /opt/Xilinx/Vivado```.

## Compiling

Once the above dependencies are installed, you are ready to compile the design.

Overview of the compile process:

1. ```make``` -> downloads submodules, builds all prerequisites, builds all bitstreams.  
or   
```make TARGET```, where TARGET is one of (tested using vivado_v2018.2):  
"```bin/nexys4.bit```",  
"```bin/nexys4ddr.bit```" (currently broken),  
"```bin/nexys4ddr-widget.bit```",  
"```bin/mega65r1.bit```",  
"```bin/mega65r2.bit```",  
"```bin/megaphoner1.bit```",  
etc...  
which will build all dependancies and build just the specified bitstream.
1. ```make USE_LOCAL_CC65=1``` -> as above but does not build the ```./cc65```-submodule.  
This is useful for Continuous Integration (CI).
Instead, your path must locate a pre-built binary from your LOCAL machine.

The following instructions are for running in the fpga.

* As there are many end-use cases, i will not cover them all here, just the one that suits me.
Someone else please document how the simulate function(s) work and what compile options etc.

## Programming

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
