
# MEGA65 Core Release 0.95 Release Candidate

Target system: ${RM_TARGET}

**WARNING:** This is an **unstable** and **experimental** test core. Please watch
for files starting with `WARNING` in the archive and read the logs if you want to
know the test results.

**NOTE:** The `#UNSAFE` tag in the version and the `ATTENTION_THIS_COULD_BRICK_YOUR_MEGA65`
warning file in the archive refers to the possibility that a untested core *might*
have a temporary negative effect on your system. But using a JTAG interface you
are always able to restore your system to a working state.

## Contents

- `*.bit`: bistream file for use with the JTAG adapter (direct transfer to FPGA)
- `*.cor`: MEGA COR file for flashing with the MEGA65 Flasher
- `*.mcs`: Vivado Format for flashing via JTAG using Vivado
- `sdcard-files`: all the basic files needed to add to your boot SD card
- `extra`: contains files you normally don't need, like `HICKUP.M65`. Note: you **don't** need this!
- `log`: regression test logs

## How to use a core

There is an extensive
[How to load or flash a core tutorial](https://files.mega65.org?ar=280a57a6-fb84-40fc-96ac-6da603302aa7)
on filehost.

## How to use the SD card files

There is a
[How to prepare your SD card](https://files.mega65.org?ar=bf23ac42-5786-48f7-a117-4e6f81edd802)
tutorial on filehost. Please follow this tutorial to prepare your SD card.

Again: **don't** use `HICKUP.M65`!

You will also need a ROM for your disk. Either get a
[Closed ROM](https://files.mega65.org?id=54e69439-f25e-4124-8c78-22ea7ddc0f1c) or
patch your own, if you don't have access, by using a
[ROM diff file](https://files.mega65.org?id=fd2c40b9-f337-41f7-8a81-0254b1e09fb5).
