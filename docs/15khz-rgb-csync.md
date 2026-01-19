# 15kHz RGB CSYNC Video Output

## Overview

The MEGA65 supports 15kHz RGB video output with composite sync (CSYNC) on the
VGA connector. This mode is designed for connecting to classic CRT monitors
like the Commodore 1084S, 1084S-D2, or any monitor that accepts 15kHz RGB with
composite sync input (commonly via SCART).

In this mode:
- Horizontal sync rate: ~15.6kHz (PAL) or ~15.7kHz (NTSC)
- CSYNC is output on VGA pin 13 (active low)
- VSYNC (pin 14) is held high (unused)
- RGB video uses the same pins as standard VGA

The HDMI output continues to operate at 31kHz regardless of this setting.

## Enabling 15kHz Mode

15kHz RGB CSYNC mode is controlled by **DIP switch 4** on the MEGA65 board.

| DIP Switch 4 | Video Mode         |
|--------------|--------------------|
| OFF          | Standard 31kHz VGA |
| ON           | 15kHz RGB CSYNC    |

The DIP switch setting takes effect immediately at power-on, so 15kHz mode
is active from the very first frame - including the core selection menu and
all boot screens.

## Compatible Monitors

This mode should work with monitors that accept 15kHz RGB with composite sync:
- Commodore 1084S, 1084S-D2
- Sony PVM series (via RGB input)
- Any TV/monitor with SCART RGB input
- Arcade monitors (via appropriate adapter)

At time of writing, this has been tested with a 1084S-D2 using an appropriate
cable.

## VGA to DB-9 RGB Cable Wiring

To connect the MEGA65 VGA output to a Commodore monitor with a DB-9 analog RGB
input (like the 1084S-D2), you need a custom cable with the following wiring:

```
    VGA (DB-15 Male)                    DB-9 RGB (Male)
    ================                    ===============

    Pin 1  (Red)   <-----------------   Pin 3 (Red)
    Pin 2  (Green) <-----------------   Pin 4 (Green)
    Pin 3  (Blue)  <-----------------   Pin 5 (Blue)
    Pin 13 (HSYNC) <-----------------   Pin 7 (Composite Sync)

    Pin 5  (GND)   <-----------------   Pin 1 (Ground)
    Pin 6  (GND)   <-----------------   Pin 2 (Ground)
    Pin 10 (GND)   <----+
                        +------------   Ground wire

    Not connected:
    - DB-9 Pin 6 (Intensity) - not used
    - DB-9 Pins 8, 9 - not used
```

## Notes

- The 15kHz mode uses the same PAL/NTSC timing as the internal video system,
  so PAL regions get 50Hz and NTSC regions get 60Hz output.
- If your monitor loses sync briefly when switching between screens, this is
  normal as the video mode stabilizes.
