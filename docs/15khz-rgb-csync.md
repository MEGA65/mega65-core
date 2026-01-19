# 15kHz RGB CSYNC Video Output

## Overview

The MEGA65 supports 15kHz RGB video output with composite sync (CSYNC) on the
VGA connector. This mode is designed for connecting to classic CRT monitors
like the Commodore 1084S, 1084S-D2, or any monitor that accepts 15kHz RGB with
composite sync input (commonly via SCART).

In this mode:
- Horizontal sync rate: ~15.6kHz (PAL) or ~15.7kHz (NTSC)
- CSYNC is output on both VGA pin 13 and pin 14 (active low)
- RGB video uses the same pins as standard VGA

The HDMI output continues to operate at 31kHz regardless of this setting.

## Enabling 15kHz Mode

15kHz mode is automatically detected via the VGA DDC pins (pins 12 and 15).
The MEGA65 drives pin 12 (SDA) LOW and senses pin 15 (SCL) with an internal pull-up.
Build a 15kHz cable with a **470Ω resistor** between VGA pins 12 and 15.
(The board has a strong 5V pull-up on pin 15, so a low value resistor is required.)

| Cable Type                       | VGA Pin 15 State | Video Mode         |
|----------------------------------|------------------|--------------------|
| Standard VGA cable               | HIGH (pull-up)   | Standard 31kHz VGA |
| 15kHz cable with resistor 12-15  | LOW (via resistor)| 15kHz RGB CSYNC   |

This detection happens at the hardware level, so 15kHz mode is active from
the very first frame - including the core selection menu and all boot screens.
Works on all MEGA65 board revisions (R3, R4, R5, R6).

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

    15kHz Auto-Detection:
    Pin 12 (SDA)   <---[470Ω]----   Pin 15 (SCL)

    Not connected:
    - DB-9 Pin 6 (Intensity) - not used
    - DB-9 Pins 8, 9 - not used

    Note: CSYNC is available on both VGA pin 13 (HSYNC) and pin 14 (VSYNC)
    for flexibility with different adapters.
```

The 470Ω resistor between VGA pins 12 and 15 enables automatic 15kHz mode detection.
Pin 12 is driven LOW by the MEGA65, and pin 15 has an external 5V pull-up on the board.
When the resistor bridges them, pin 15 is pulled below the logic threshold, enabling 15kHz mode.
Without this resistor, the MEGA65 outputs standard 31kHz VGA.

## Interlace Support for V400 Modes

When 15kHz mode is enabled and the VIC-IV is in V400 mode (e.g., 80x50 text mode),
interlace is automatically enabled. This ensures all 400 vertical lines are
displayed by alternating between odd and even fields on successive frames.

Without interlace, V400 modes would only show every other scanline, resulting in
half the vertical resolution being lost.

The interlace auto-enable only affects the 15kHz VGA output - HDMI output
continues to use progressive scan regardless of this setting.

## Notes

- The 15kHz mode uses the same PAL/NTSC timing as the internal video system,
  so PAL regions get 50Hz and NTSC regions get 60Hz output.
- If your monitor loses sync briefly when switching between screens, this is
  normal as the video mode stabilizes.
- Interlace mode can also be manually controlled via VIC-IV register `$D031`
  bit 0 if needed for other purposes.
