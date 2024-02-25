
# How to Upgrade your MEGA65 FACTORY CORE

The README already explains where you can find information on how
to install the core on your MEGA65. But sometimes it is necessary
to replace Slot 0 "FACTORY CORE".

Make sure that you only use cores that are designated as
*REPLACEMENT FACTORY CORES* for this purpose. Normally this applies
to all the Release Cores.

Upgrading slot 0 involves a bit of a risk, as the slot 0 core
handles all the bootup work, and without it, this is no longer
possible.

Because of this, we will first explain the possible ways of
rescuing a MEGA65 without a valid slot 0 core.

## Rescue with the Xilinx JTAG

If you do have a JTAG, you are basically save, as you can always
just send a bitstream to your MEGA65 using `m65`.

In this running bitstream you can then use the flasher integrated
into the bitstream or the standalone upgrade tool to flash 0
again.

Test sending a bitstream via JTAG: `m65 --bit-only mega65.bit`

You should try this before flashing your slot 0, so that you are
confident that you can use this procedure.

## Rescue by fall-through booting of Slot 1

The other option makes use of the fact that the automatic bitstream
loading from flash during power on will look for a bitstream
signature in the flash, and only start transfering the data to the
FPGA, if this signature could be found.

The flashing process makes sure that the signature is **first**
removed from the flash, and the new signature is written **last**
(this is actually done by flashing the bitstream form end to start).

There is a very small window in which the first sector is written,
if an accident occurs in this window, the procedure will **fail**.
Then only a JTAG (see last section) can help.

If the flashing process is interrupted and the signature was not
written, then the procedure works beautifully: the FPGA won't find
the signature in slot 0, and keeps searching for it onwards, until
it hits slot 1 (this takes about 20-30 seconds). There it will find
slot 1's signature and loads the bitstream into the FPGA: the MEGA65
starts!

Things to ensure:

* make sure that you have a recent MEGA65 core in your slot 1
* make sure that this core starts without problems

# Upgrade Procedure

## Preparing the System

First you need to copy the COR file to your SD Card. Please rename
the COR to `UPGRADE0.COR`. Always use the **internal SD Card Slot**!

**Never** put a card into the external slot while upgrading!

Then switch DIP Switch 3 to on. This enables flash access from
the running system.

Now power on your MEGA65. It will stop at the Boot screen with a
colour-cycling border and ask you the press `RUN/STOP`. Do this, but 
don't do it to early, wait till you are asked to do it!

After this you will land in the `MONITOR` of `BASIC65`. Exit it with
`X` and `RETURN`.

## JTAG or UART

If you have a JTAG or a simple UART serial interface, then you can
send the `upgrade0.prg` to your MEGA65 using m65:

```bash
m65 -4 -r upgrade0.prg
```

(you might need to specify a serial device using `-l`)

## Etherload

The other option is to use `etherload` to do it. For this you need
a recent MEGA65 Core (post Release 0.95 'Batch 2'). Always use a cable
connection!

1) enable DIP switch 2
2) start MEGA65
3) press SHIFT-POUND (left LED starts alternating yellow/green)
4) send via etherload: `etherload -i BROADCAST-IP -4 -r upgrade0.prg`

## Running upgrade0.prg

The upgrade tool will guide you through the process. It will show you
some information, and it will abort if anything looks wrong (perhaps
you forgot to enable DIP switch #3?).

There is no fileselection, it will always load the `UPGRADE0.COR` file
you did put on your SD card during preperation.

It will then check the CRC32 checksum of the core to ensure that it
was loaded correctly into the Attic RAM of your MEGA65.

After everthing went good, it will then start flashing.

After a short while you will have a MEGA65 with a new Slot 0 core!

# If anything goes wrong?

Remember what we explained above?

* you can always start a bitstream via JTAG and reflash
* you can wait the blue ambulance lights until slot 1 starts and reflash

If anything gets more complicated: please contact us via the various
methods that are available, we will always try to help!
