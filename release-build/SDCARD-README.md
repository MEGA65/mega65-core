# MEGA65 SDCARD Quick Tips

This file was put here by fdisk sdcard population.

We have a lot of information gathered on Filehost in the
[MEGA65 SD card FAQ](https://files.mega65.org?ar=e8dcb0a3-894a-40ae-851c-b69620accebe)
and the
[Tutorial: How to prepare your SD card](https://files.mega65.org?ar=bf23ac42-5786-48f7-a117-4e6f81edd802).

Some quick information:

- `CORE/` - here you can put your .cor files for quick access and
  without cluttering your root directory.
- `ROMS/` - here you can put ROM files for the MEGA65 core for
  quick FREEZER-ROMLOAD access while keeping readable names.
  You can also put extra charsets here, as ROMLOAD can apply those
  too!
- `BANNER.M65` is loaded on startup by HYPPO and displayed above the
  boot messages
- `MEGA65.ROM` is the ROM that is loaded by default
  - you can add `MEGA650.ROM` to `MEGA659.ROM` with different ROM
    versions, and access them by holding down the respective number
    key on boot
- `ETHLOAD.M65` this file will  be started (if you have ethernet enabled),
  when you use `etherload` on your PC to connect to your MEGA65
- `FREEZER.M65` is loaded when you hold RESTORE for 1-2 seconds and
  release it
- `CHARSET.M65` is loaded by FREEZER to restore a readable charset
- the other `*.M65` files are tools started from FREEZER

Some files that should **not** be on your SD Card:

- `HICKUP.M65` is used to override the HYPPO inside the MEGA65 core.
  Unless you are a developer and know what you are doing, this should
  **not** be on your SD Card.
