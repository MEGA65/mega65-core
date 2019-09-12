## This is the 'hardware' documentation file.

## Introduction

This document lists the supported hardware platforms for the MEGA65, and
any relevant notes.

## FPGA boards / motherboards

### Digilent Nexys4-DDR FPGA develoment board

This is the primary development board.  The DDR RAM is not supported.
Ethernet and microphone are both supported, as is VGA output with 12-bit
colour depth using the on-board VGA connector, as well as via PMOD connectors
together with the necessary signals to drive a small LCD panel.  SD cards
are supported in 1-bit SPI mode (3MB/sec max).

### Digilent Nexys A7

This is the new name for the Nexys4-DDR, and thus should be identical hardware
and thus _should_ work. We would appreciated it if someone could confirm this
in the field.

### Digilent Nexys4 (original version) FPGA develoment board

Idential to the Nexys4-DDR board, except that it has an 8MB PSRAM instead
of the DDR RAM.  The PSRAM was previously supported, and will be supported
again in the future.

### MEGA65 rev1 development main board

This is the first revision of the MEGA65 PCB, and some hardware modifications
are required to make it work.  The SD card must be fitted in a special hacked-on
SD card holder, but is otherwise fully supported. Ethernet, cartridge port, floppy
connector and VGA are all fully supported.  HDMI video is not yet supported.
C65-compatible keyboard and C64 joysticks are also supported, as are Amiga mice (which
can be used with the built-in 1351 hardware emulation function).  Paddles and 1351
mice require further hardware modifications to be used.  The normal Commodore serial
floppy drive / printer bus functions, but does not support C65/C128 fast mode.
This board contains no built-in expansion memory.  The PMOD and 50-pin expansion
connectors are place-holders only.  Cartridge port has some limitations due to lack
of direction control on some IO lines.

### MEGA65 rev2 pre-series main boards

This is the second revision of the MEGA65 PCB.  It corrects problems with the SD card,
IEC serial drive port, and floppy interface.  Pull-ups do need to be added to various
lines however. Also, at the time of writing, only the VGA display is working, and the
ethernet and real-time clock are yet to be activated.

### MEGAphone rev1 prototype board

This board requires a significant amount of re-work to function correctly, and thus
is not recommended for future work.  The latest revision of the MEGAphone prototype
board should be used in preference.

### MEGAphone rev2 prototype board

This board is in the process of being assembled, and thus has not yet been tested.
It corrects many of the problems with the revision 1 MEGAphone board.

## Monitors

The MEGA65 requires a monitor that can do 800x600 at both 50Hz and 60Hz.
If the monitor will do only one of those modes, it is possible to configure the MEGA65
to use exactly one of those modes.  Note that the MEGA65 does not (currently) query
a monitor for EDID information. This might change in the future.

Diagram to go here ![mega65logo](./images/mega65_64x64.png)

