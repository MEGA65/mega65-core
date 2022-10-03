
# MEGA65 Core Release 0.95 Release Candidate

Target system: ${RM_TARGET}

**WARNING**: This is an **unstable** and **experimental** test core. Please watch
for files starting with `WARNING` in the archive and read the logs if you want to
know the test results.

## Contents

- `*.bit`: bistream file for use with the JTAG adapter (direct transfer to FPGA)
- `*.cor`: MEGA COR file for flashing with the MEGA65 Flasher
- `*.mcs`: Vivado Format for flashing via JTAG using Vivado
- `sdcard-files`: all the basic files needed to add to your boot SD card
- `extra`: contains files you don't need, like `HICKUP.M65`. Note: you **don't** need this!
- `log`: regression test logs

## How to use a core

There is an extensive
[How to load or flash a core tutorial](https://files.mega65.org?ar=280a57a6-fb84-40fc-96ac-6da603302aa7)
on filehost.

## How to use sd card files

There is a tutorial on 
[SDcard Preparation and File handling](https://files.mega65.org?ar=8169dc91-a958-4529-8593-621b40a18c9e)
on filehost. Make sure to not simply overwrite files, as this might result in file
fragmentation. Best practice is to rename and delete each file on the SD you want to
replace.

Again: **don't** use `HICKUP.M65`!

You will also need a ROM for your disc. You can get ROMs here:
[Closed ROM](https://files.mega65.org?id=54e69439-f25e-4124-8c78-22ea7ddc0f1c).
