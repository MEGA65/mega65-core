## This is the **build** documentation file.

# Table of Contents:

[Introduction](#Introduction)

[Downloading Repository](#Downloading-Repository)

[Pre-Compiling](#Pre-Compiling)

[Generating the Bitastream](#Generating-the-Bitastream)

[Programming the FPGA](#Programming-the-FPGA)


## Introduction

The overall process from go-to-whoa takes about 90 minutes.
Basically you:

1. download the repository from github (5 mins),
1. make the nessessary pre-compiling (5 mins)
1. use Xilinx ISE to compile the design into a bitstream (60 mins)
1. copy bitstream onto fpga board

Detailled instructions are below.

## Downloading Repository

The following is assumed:
1. you have linux, say, Ubuntu 15
1. ...

either download the ZIP and unpack, or checkout via GIT


## Pre-Compiling

The following is assumed:
1. you have "make", "gcc", etc installed

in your working directory: type "make" a few times


## Generating the Bitastream

The following is assumed:
1. you have Xilinx ISE 14.7 WebPACK installed, with a valid licence

Open ISE and open the "reboot65" project

## Programming the FPGA

copy the "container.bit" file to a USB-stick,
put the USB-stick into the USB-port of the Nexys board,
DIP switches,
turn ON the nexys board.

The End.
