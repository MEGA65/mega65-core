
# New MEGAFLASH

This directory contains the MEGAFLASH utility. It comes in two variants, one is embedded
into the bitstreams initial memory (src/vhdl/shadowram*.vhdl), the other is called
`mflash.prg` and can be run standalone.

MEGAFLASH plays a vital role in the MEGA65's startup process. HYPPO will call MEGAFLASH
during startup, and MEGAFLASH might reconfigure the system to start a different bitstream
from flash. MEGAFLASH also allows the user to interrupt the boot process, so that they
can change the flash or select a different bitstream manually.

## Standalone Mode

This requires userspace SPI access, which is enabled by setting DIP switch #3 to ON.

It's primary purpose is for debugging and development. It contains all the possible
flashers and modes, and can work with or without attic ram.

## Integrated Mode

This version is space optimised, as it needs to fit below HYPPO. To archive this, all
the text and strings, as well as some data structures are place in upper memory at the
end of bank 4. `screenbuilder.py` is used to archive this.

# Building

The global Makefile has targets for `megaflash-*.prg` (integrated versions, flash chip
specific) and `mflash.prg` (standalone debug version, driver autodetect).

## Compiler Defines

### High-Level

**STANDALONE**
: enable standalone mode

**FLASH_INSPECT**
: add the flash inspector to the code, which will allow reading and erasing flash by hand

**FIRMWARE_UPGRADE**
: enable flashing of slot 0 for firmware upgrades

**NO_ATTIC**
: compile without Attic RAM support

**TAB_FOR_MENU**
: normally holding NO-SCROLL will interrupt boot and bring up the MEGAFLASH menu. With
this enabled you can also use the TAB key instead.

### QSPI Driver Low-Level

**QSPI_VERBOSE**
: enable verbose output for qspi routines

**QSPI_HW_ASSIST**
: enable hardware assisted (i.e. VHDL integrated) flashing

**QSPI_NO_BIT_BASH**
: remove all bit bashing code (this enables **QSPI_HW_ASSIST**)

**QSPI_S25FLXXXL**
: include s25flxxxl driver (wukong pcbs)

**QSPI_S25FLXXXS**
: include s25flxxxs driver (mega65 pcbs and nexys boards)
