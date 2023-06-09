
# Changelog

Please look into [mega65-core](https://github.com/MEGA65/mega65-core/)
for a complete changelog.

## Release 0.96 (commit hash tbd)

This is the Batch 3 Release (August 2023). All issues with a star '*'
are not yet finished.

 - MEGAFLASH - more secure Slot 0 flashing
   [#625](https://github.com/MEGA65/mega65-core/issues/625)*
 - Cartridge handling (fix Ultimax mode)
   [#684](https://github.com/MEGA65/mega65-core/issues/684)*
   [#683](https://github.com/MEGA65/mega65-core/issues/683)*
 - Mouse 1351 jumps
   [#694](https://github.com/MEGA65/mega65-core/issues/694)
 - wrong VIC-II multicolour colours
   [#571](https://github.com/MEGA65/mega65-core/issues/571)
   [PR#657](https://github.com/MEGA65/mega65-core/issues/657)
 - missing pixel lines
   [#671](https://github.com/MEGA65/mega65-core/issues/671)
   [#681](https://github.com/MEGA65/mega65-core/issues/681)
   [#682](https://github.com/MEGA65/mega65-core/issues/682)
 - C65 VIC bug compability flag
   [#685](https://github.com/MEGA65/mega65-core/issues/685)
 - double vertical resolution for fonts in Y200 mode
   [#678](https://github.com/MEGA65/mega65-core/issues/678)
 - RRB row masking
   [#340](https://github.com/MEGA65/mega65-core/issues/340)
 - Audio DMA distortion fixes
   [#651](https://github.com/MEGA65/mega65-core/issues/651)*
 - Keyboard test info about cursor key behaviour
   [#649](https://github.com/MEGA65/mega65-core/issues/649)
 - new Development setup using Jenkins and Dockers
 - upgrade to Vivado 2022.2
 - new target MEGAphone R4 (WiP)
 - new target MEGA65R4 (WiP)
 - new target QMTech (WiP)
   [PR#650](https://github.com/MEGA65/mega65-core/pull/650)
   [#642](https://github.com/MEGA65/mega65-core/issues/642)*
 - SD-Card related fixes
   [#643](https://github.com/MEGA65/mega65-core/issues/643)
   [#646](https://github.com/MEGA65/mega65-core/issues/646)
   [PR#647](https://github.com/MEGA65/mega65-core/pull/647)
   [#669](https://github.com/MEGA65/mega65-core/issues/669)
 - Documentation
   [#639](https://github.com/MEGA65/mega65-core/issues/639)
 - Plumbing for Composite Video board
   [#638](https://github.com/MEGA65/mega65-core/issues/638)*
 - MK-II Keyboard support for 100T boards and Nexys
   [#637](https://github.com/MEGA65/mega65-core/issues/637)
 - Hyppo All-RAM access (ROMLOAD, fonts)
   [#634](https://github.com/MEGA65/mega65-core/issues/634)
   [#676](https://github.com/MEGA65/mega65-core/issues/676)
 - Ethernet changes - EtherLoad capability
   [#565](https://github.com/MEGA65/mega65-core/issues/565)
   [#633](https://github.com/MEGA65/mega65-core/issues/633)*
   [#636](https://github.com/MEGA65/mega65-core/issues/636)*
   [#673](https://github.com/MEGA65/mega65-core/issues/673)*
   [#693](https://github.com/MEGA65/mega65-core/issues/693)*
   [#696](https://github.com/MEGA65/mega65-core/issues/696)*

## Release 0.95 (commit hash 93d55f0)

This is the Batch 2 Release (October 2022).

 - MEGAFLASH/jtagflash security fixes
   [#589](https://github.com/MEGA65/mega65-core/issues/589)
   [#612](https://github.com/MEGA65/mega65-core/issues/612)
   [#611](https://github.com/MEGA65/mega65-core/issues/611)
   [#612](https://github.com/MEGA65/mega65-core/issues/612)
 - fixed placement of I/O components to improve build quality
   [#603](https://github.com/MEGA65/mega65-core/issues/603)
 - fdisk tool improvements (rescan bus, skip or select population)
   [fdisk#10](https://github.com/MEGA65/mega65-fdisk/issues/10)
   [fdisk#11](https://github.com/MEGA65/mega65-fdisk/issues/11)
   [fdisk#12](https://github.com/MEGA65/mega65-fdisk/issues/12)
   [fdisk#13](https://github.com/MEGA65/mega65-fdisk/issues/13)
 - onboarding fixes (date format, day one off bug)
 - configure menu updates (date format, mac address)
   [#560](https://github.com/MEGA65/mega65-core/issues/560)
 - Hyppo improvements
   [#620](https://github.com/MEGA65/mega65-core/issues/620)
   [#550](https://github.com/MEGA65/mega65-core/issues/550)
   [#568](https://github.com/MEGA65/mega65-core/issues/568)
   [#552](https://github.com/MEGA65/mega65-core/issues/552)
   [#578](https://github.com/MEGA65/mega65-core/issues/578)
   [#493](https://github.com/MEGA65/mega65-core/issues/493)
 - Grove RTC support (external RTC)
   [#591](https://github.com/MEGA65/mega65-core/issues/591)
 - MAX10 FPGA communication fixes
 - Unify date/time display and entry between tools
   [#542](https://github.com/MEGA65/mega65-core/issues/542)
   [#540](https://github.com/MEGA65/mega65-core/issues/540)
 - VIC-IV Raster IRQ fixes
   [#604](https://github.com/MEGA65/mega65-core/issues/604)
   [#609](https://github.com/MEGA65/mega65-core/issues/609)
 - 50/60Hz TOD flag for CIA
   [#587](https://github.com/MEGA65/mega65-core/issues/587)
 - matrix monitor @ fix
   [#596](https://github.com/MEGA65/mega65-core/issues/596)
 - freezer updates (mounting, audiomixer, sprited)
   [#548](https://github.com/MEGA65/mega65-core/issues/548)
   [#590](https://github.com/MEGA65/mega65-core/issues/590)
   [freezer#54](https://github.com/MEGA65/mega65-freezemenu/issues/54)
   [freezer#53](https://github.com/MEGA65/mega65-freezemenu/issues/53)
   [freezer#52](https://github.com/MEGA65/mega65-freezemenu/issues/52)
   [freezer#51](https://github.com/MEGA65/mega65-freezemenu/issues/51)
   [freezer#50](https://github.com/MEGA65/mega65-freezemenu/issues/50)
   [freezer#49](https://github.com/MEGA65/mega65-freezemenu/issues/49)
   [freezer#48](https://github.com/MEGA65/mega65-freezemenu/issues/48)
   [freezer#47](https://github.com/MEGA65/mega65-freezemenu/issues/47)
   [freezer#44](https://github.com/MEGA65/mega65-freezemenu/issues/44)
   [freezer#42](https://github.com/MEGA65/mega65-freezemenu/issues/42)
   [freezer#41](https://github.com/MEGA65/mega65-freezemenu/issues/41)
   [freezer#39](https://github.com/MEGA65/mega65-freezemenu/issues/39)
   [freezer#34](https://github.com/MEGA65/mega65-freezemenu/issues/34)
   [freezer#33](https://github.com/MEGA65/mega65-freezemenu/issues/33)
   [freezer#31](https://github.com/MEGA65/mega65-freezemenu/issues/31)
   [freezer#23](https://github.com/MEGA65/mega65-freezemenu/issues/23)
 - MC Text mode fixes
   [#420](https://github.com/MEGA65/mega65-core/issues/420)
 - MCM + VIC-III/IV behaviour less surprising
   [#571](https://github.com/MEGA65/mega65-core/issues/571)
 - inline DMA jobs
   [#580](https://github.com/MEGA65/mega65-core/issues/580)
 - tiled Sprite end pos
   [#579](https://github.com/MEGA65/mega65-core/issues/579)
 - Hyppotest improvements
   [#525](https://github.com/MEGA65/mega65-core/issues/525)
 - Joystick port interface via PMOD
   [#521](https://github.com/MEGA65/mega65-core/issues/521)
 - vFAT fixes
   [#539](https://github.com/MEGA65/mega65-core/issues/539)
 - DMA line improvements
   [#401](https://github.com/MEGA65/mega65-core/issues/401)
 - 32bit opcode next op bugfix
   [#535](https://github.com/MEGA65/mega65-core/issues/535)
 - fix ASCII keyscanner tables
   [#532](https://github.com/MEGA65/mega65-core/issues/532)
 - SID Frequenzy correction 1MHz
   [#449](https://github.com/MEGA65/mega65-core/issues/449)
 - SID 8580 waveform
   [#477](https://github.com/MEGA65/mega65-core/issues/477)
 - ethernet enhancements
   [#523](https://github.com/MEGA65/mega65-core/issues/523)
 - remove 1541/6502 from mega65r2 target
 - lots of documentation fixes (iomap.txt, user-guide)

## Release 0.9 (commit hash f7554a8)

This is the Batch 1 Release (January 2022). Please look into
[mega65-core](https://github.com/MEGA65/mega65-core/) for a
complete changelog.
