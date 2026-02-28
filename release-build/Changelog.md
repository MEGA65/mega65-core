
# Changelog

This Changelog does provide a broad overview over the changes made, it
does not aim to be complete.

Please look into [mega65-core](https://github.com/MEGA65/mega65-core/),
[mega65-freezemenu](https://github.com/MEGA65/mega65-freezemenu/), and
[mega65-fdisk](https://github.com/MEGA65/mega65-fdisk/) git histories
for complete changes.

Starting with 0.98 we will also have Projects for each release, see
the [GitHub Projects Page](https://github.com/orgs/MEGA65/projects/).

Please check the [mega65-core repository](https://github.com/MEGA65/mega65-core/releases).
for our tagged releases.

## Release 0.98 (t.b.d.)

This is perhaps the second release in 2025, we will see...

You can find issues and pull requests ssociated with this release in the
[Release 0.98 Project](https://github.com/orgs/MEGA65/projects/2/views/2).

### ROM Release 0.98

t.b.d.

### Changes 0.98

nothing here yet...

### Known Bugs 0.98

we'll see...

## Release 0.97.2 (M65TARGET bugfix for R6)

Second bugfix release for 0.97, only for R6 and later boards.

The R6A board (PCB Revision R7) is a production update that replaces some parts that
are no longer available. During the process a bug in the I2C communication came to light,
which needed fixing. This fix was 0.97.1, but it was rushed and got it wrong! So this
second patch release was needed to *really* fix the problem.

- [Release 0.97.2](https://github.com/orgs/MEGA65/projects/9/views/2)

### Changes 0.97.2

- M65MODEL is filled with wrong value
  [#920](https://github.com/MEGA65/mega65-core/issues/920)

## Release 0.97.1 (I2C bugfix for R6)

**WARNING:** This fix messes up M65TARGET and should not be used!

First bugfix release for 0.97, only for R6 and later boards.

The R6A board (PCB Revision R7) is a production update that replaces some parts that
are no longer available. During the process a bug in the I2C communication came to light,
which needed fixing.

- [Release 0.97.1](https://github.com/orgs/MEGA65/projects/8/views/2)

### Changes 0.97.1

- MEGA65R6A Bringup fixes
  [#915](https://github.com/MEGA65/mega65-core/issues/915)

## Release 0.97 (10th Anniversary Edition)

This is the first 2025 Release.

You can find issues associated with this release by following these links:

- [Release 0.97](https://github.com/orgs/MEGA65/projects/1/views/8)
- [mega65-core](https://github.com/MEGA65/mega65-core/milestone/9?closed=1)
- [mega65-freezemenu](https://github.com/MEGA65/mega65-freezemenu/milestone/7?closed=1)
- [mega65-fdisk](https://github.com/MEGA65/mega65-fdisk/milestone/6?closed=1)

Note: It is possible that not all changes were marked with the milestone.

### ROM Release 0.97

The 0.97 Release came with ROM Version 920413.

Please see the
[ROM Changelog](https://github.com/MEGA65/mega65-rom-public/blob/main/CHANGELOG.md)
for more information.

### Changes 0.97

- **MEGAFLASH**: refactor low level flashing interface
  [#782](https://github.com/MEGA65/mega65-core/issues/782):
  - This does make it work for non-r3a/r4/r5/r6 Platforms again
    (in 0.96 this was not supported)
  - CRC check fix for attic-less boards (plus Wukong build fix)
    [PR#839](https://github.com/MEGA65/mega65-core/pull/839)
  - Update mf_selectcore.c to correct a small typo
    [PR#875](https://github.com/MEGA65/mega65-core/pull/875)
  - QSPI: Some operations do not return to idle (CS# high, SCK high)
    [#764](https://github.com/MEGA65/mega65-core/issues/764)
  - QSPI: Busy flag sdio_busy is unreliable
    [#763](https://github.com/MEGA65/mega65-core/issues/763)
  - QSPI: Read errors due to skipping dummy (latency) cycles
    [#762](https://github.com/MEGA65/mega65-core/issues/762)
  - CARTRIDGE: define a MEGA65 style cartridge
    [#711](https://github.com/MEGA65/mega65-core/issues/711)
- HYPPO-DOS 1.3
  - HDOS 1.3 (partial)
    [#760](https://github.com/MEGA65/mega65-core/issues/760)
    - also includes implementation of NO DISK option
  - add attach, rmfile, and writefile for 0.97
    [#866](https://github.com/MEGA65/mega65-core/issues/866)
  - Implemented trap_dos_writefile and trap_dos_rmfile
    [PR#748](https://github.com/MEGA65/mega65-core/pull/748)
  - refactor d81attach / d81detach calls
    [#628](https://github.com/MEGA65/mega65-core/issues/628)
- Features:
  - Disable PALEMU scanlines if V400 is enabled
    [#854](https://github.com/MEGA65/mega65-core/issues/854)
  - Various basic SID improvements from Bobby Tables fork
    [PR#851](https://github.com/MEGA65/mega65-core/pull/851)
  - Implement hardware-accelerated cycle-exact IEC bus controller device
    [#736](https://github.com/MEGA65/mega65-core/issues/736)
    - Needed workaround for IEC transfer in 40 MHz mode
      [#283](https://github.com/MEGA65/mega65-core/issues/283)
    - IEC communications is flaky
      [#341](https://github.com/MEGA65/mega65-core/issues/341)
    - Fix various issues found during testing
      [PR#818](https://github.com/MEGA65/mega65-core/pull/818)
    - 4541 - Add $4C, $50, and $70 commands
      [PR#825](https://github.com/MEGA65/mega65-core/pull/825)
    - nexys4ddr stuck in ROM startup
      [#857](https://github.com/MEGA65/mega65-core/issues/857)
  - HWERRATA register should return maximum errata level supported
    [#829](https://github.com/MEGA65/mega65-core/issues/829)
  - Allow DMA src/dst addresses to cross MB boundaries
    [#826](https://github.com/MEGA65/mega65-core/issues/826)
  - Audio DMA IRQs for advanced buffering
    [#811](https://github.com/MEGA65/mega65-core/issues/811)
  - Add Wukong A100T V2 platform target
    [PR#808](https://github.com/MEGA65/mega65-core/pull/808)
  - Add support for the DIY Keyboard to mega65r4-6
    [PR#804](https://github.com/MEGA65/mega65-core/pull/804)
  - CONFIG: Add option to disable floppy drive sounds while accessing SD
    [#622](https://github.com/MEGA65/mega65-core/issues/622)
- Bugfixes:
  - Lengthen the keyboard debounce
    [#880](https://github.com/MEGA65/mega65-core/pull/880)
  - OPL2 - Correct setting Cx registers
    [#859](https://github.com/MEGA65/mega65-core/issues/859)
    [PR#879](https://github.com/MEGA65/mega65-core/pull/879)
  - Sometimes keys double trigger while writing
    [#870](https://github.com/MEGA65/mega65-core/issues/870)
  - add freeze region for 0xFFD3084
    [PR#868](https://github.com/MEGA65/mega65-core/pull/868)
  - fix Reverse shifting order of the CIA shift register
    [#537](https://github.com/MEGA65/mega65-core/issues/537)
    [PR#538](https://github.com/MEGA65/mega65-core/pull/538)
  - Fix for blemishes in 640x400 - 16 colour bitplane mode
    [#689](https://github.com/MEGA65/mega65-core/issues/689)
    [PR#850](https://github.com/MEGA65/mega65-core/pull/850)
  - Disallow interrupts while stepping through code
    [#847](https://github.com/MEGA65/mega65-core/issues/847)
    [PR#848](https://github.com/MEGA65/mega65-core/pull/848)
  - RRB sprite number count limited because of colour ram wrap-around
    [#789](https://github.com/MEGA65/mega65-core/issues/789)
  - Integrate HDMI audio bugfix from the Tyto 2 project
    [PR#833](https://github.com/MEGA65/mega65-core/pull/833)
  - POT lines jittering in bit 1
    [#828](https://github.com/MEGA65/mega65-core/issues/828)
  - CIA Oneshot timer handled incorrectly
    [#821](https://github.com/MEGA65/mega65-core/issues/821)
  - Sprites not correctly hidden by border
    [#815](https://github.com/MEGA65/mega65-core/issues/815)
  - Fix critical warnings and SDRAM DQ drive
    [PR#812](https://github.com/MEGA65/mega65-core/pull/813)
  - Fix pmod1_en for mega65r4,5,6
    [#809](https://github.com/MEGA65/mega65-core/issues/809)
  - Fix pblock component assignment
    [PR#806](https://github.com/MEGA65/mega65-core/pull/806)
  - Various audio mixing and SID fixes
    [#801](https://github.com/MEGA65/mega65-core/issues/801)
    - Direct drive audio DAC has unusual stepwise behaviors
      [#794](https://github.com/MEGA65/mega65-core/issues/794)
    - Direct drive audio DAC has unusual stepwise behaviors
      [#793](https://github.com/MEGA65/mega65-core/issues/793)
    - SID 8580 won't play certain notes on first invocation
      [#631](https://github.com/MEGA65/mega65-core/issues/631)
  - RRB Reverse Y-row adjust
    [#796](https://github.com/MEGA65/mega65-core/issues/796)
  - RTS immediate mode instruction completely broken
    [#790](https://github.com/MEGA65/mega65-core/issues/790)
  - CONFIGURE: POWER-CYCLE screen has color issue on VGA only
    [#788](https://github.com/MEGA65/mega65-core/issues/788)
  - CONFIGURE: MAC address typed in is not correctly mangled
    [#787](https://github.com/MEGA65/mega65-core/issues/787)
  - HW Division round off problem
    [#786](https://github.com/MEGA65/mega65-core/issues/786)
  - A few modern C64 carts not detected as C64 carts by core selector
    [#781](https://github.com/MEGA65/mega65-core/issues/781)
  - Alternate ROMs in Slot 9
    [#664](https://github.com/MEGA65/mega65-core/issues/664)
  - sdcardio: D6A1.3 SDFDC:SILENT seems to have no effect
    [#621](https://github.com/MEGA65/mega65-core/issues/621)
- FREEZER (updated to 0.4.0)
  - Correct makedisk header
    [#96](https://github.com/MEGA65/mega65-freezemenu/pull/96)
  - Implement NO DISK support
    [#94](https://github.com/MEGA65/mega65-freezemenu/issues/94)
  - Support new dos_attach HDOS 1.3 call
    [#91](https://github.com/MEGA65/mega65-freezemenu/issues/91)
  - Key descriptions: HELP listed twice, F9 is not
    [#90](https://github.com/MEGA65/mega65-freezemenu/issues/90)
  - Tapping RESTORE key in Freezer menu causes unwanted chaotic behaviour
    [#89](https://github.com/MEGA65/mega65-freezemenu/issues/89)
- FDISK (updated to 0.35)
  - Fix population problem connected to MEGAFLASH QSPI core changes
    [#26](https://github.com/MEGA65/mega65-fdisk/issues/26)
- Build framework:
  - Switch to mega65-tools release 1.00, use coretool, don't build MCS for everything
    [#792](https://github.com/MEGA65/mega65-core/issues/792)
- Documentation:
  - Replace c65gs with mega65 and 48 MHz with 40.5 MHz
    [PR#860](https://github.com/MEGA65/mega65-core/pull/860)
  - Hyppo Register docstring updates
  - Various general Register docstring updates
  - CHXSGN is described inverted
    [#807](https://github.com/MEGA65/mega65-core/pull/807)
- Changes probably already fixed in 0.96 (or earlier)
  - Thumbnails are blank in freezer
    [#757](https://github.com/MEGA65/mega65-core/issues/757)
  - Enable mounting of D64 disk images
    [#531](https://github.com/MEGA65/mega65-core/issues/531)
  - review gitstring generated by version.sh (done for 0.96)
    [#291](https://github.com/MEGA65/mega65-core/issues/291)
  - Documentation for VIC-IV XPOS ($D050/$D051) is wrong
    [#287](https://github.com/MEGA65/mega65-core/issues/287)

### Known Bugs 0.97

At the moment of release there where no known breaking bugs.

## Release 0.96 (commit hash 3c10488)

This is the Batch 3 Release (February 2024), which is mainly aimed at the new
mega65r6 board for the Batch 3 production.

You can find issues associated with this release by following these links:

- [mega65-core](https://github.com/MEGA65/mega65-core/milestone/8?closed=1)
- [mega65-freezemenu](https://github.com/MEGA65/mega65-freezemenu/milestone/6?closed=1)
- [mega65-fdisk](https://github.com/MEGA65/mega65-fdisk/milestone/5?closed=1)

Note: It is possible that not all changes were marked with the milestone.

### ROM Release 0.96

The 0.96 Release came with ROM Version 920395.

Please see the
[ROM Changelog](https://github.com/MEGA65/mega65-rom-public/blob/main/CHANGELOG.md)
for more information.

### Changes 0.96

- **new MEGAFLASH** version [#683](https://github.com/MEGA65/mega65-core/issues/683):
  - More secure Slot 0 flashing
    [#625](https://github.com/MEGA65/mega65-core/issues/625)
    [#783](https://github.com/MEGA65/mega65-core/issues/783)
  - Cartridge handling (fix Ultimax mode)
    [#567](https://github.com/MEGA65/mega65-core/issues/567)
    [#684](https://github.com/MEGA65/mega65-core/issues/684)
  - Add LFN support to core picker
    [#697](https://github.com/MEGA65/mega65-core/issues/697)
  - Set autoboot slot via flashmenu
    [#370](https://github.com/MEGA65/mega65-core/issues/370)
- **Ethernet Support** for system tools (mega65_ftp and etherload)
  [#565](https://github.com/MEGA65/mega65-core/issues/565)
  [#633](https://github.com/MEGA65/mega65-core/issues/633)
  [#636](https://github.com/MEGA65/mega65-core/issues/636)
  [#673](https://github.com/MEGA65/mega65-core/issues/673)
  [#693](https://github.com/MEGA65/mega65-core/issues/693)
  [#696](https://github.com/MEGA65/mega65-core/issues/696)
  [#708](https://github.com/MEGA65/mega65-core/issues/708)
- General Build improvements, including:
  - New Development setup using Jenkins and Docker
  - Upgrade to Vivado 2023.2
- New hardware platforms supported:
  - MEGA65R4, R5, R6 (these are the iterations towards the Batch 3 board)
  - MEGAphone R4 (WiP)
  - New target QMTech (WiP)
    [PR#650](https://github.com/MEGA65/mega65-core/pull/650)
  - MK-II Keyboard support for 100T boards and Nexys
    [#637](https://github.com/MEGA65/mega65-core/issues/637)
- New Features:
  - Complete D619 PETSCIIKEY implementation
    [PR#720](https://github.com/MEGA65/mega65-core/pull/720)
    [#582](https://github.com/MEGA65/mega65-core/issues/582)
- Bugfixes:
  - C65 VIC bug compability flag
    [#685](https://github.com/MEGA65/mega65-core/issues/685)
  - Mouse 1351 jumps
    [#694](https://github.com/MEGA65/mega65-core/issues/694)
  - Wrong VIC-II multicolour colours
    [#571](https://github.com/MEGA65/mega65-core/issues/571)
    [PR#657](https://github.com/MEGA65/mega65-core/pull/657)
  - Missing pixel lines
    [#671](https://github.com/MEGA65/mega65-core/issues/671)
    [#681](https://github.com/MEGA65/mega65-core/issues/681)
    [#682](https://github.com/MEGA65/mega65-core/issues/682)
  - Double vertical resolution for fonts in Y200 mode
    [#678](https://github.com/MEGA65/mega65-core/issues/678)
  - RRB row masking
    [#340](https://github.com/MEGA65/mega65-core/issues/340)
  - Keyboard test info about cursor key behaviour
    [#649](https://github.com/MEGA65/mega65-core/issues/649)
  - VIC-IV should reset D076 SPRENV400
    [#771](https://github.com/MEGA65/mega65-core/issues/771)
  - Right most character pixel not drawn with H640 disabled
    [#682](https://github.com/MEGA65/mega65-core/issues/682)
  - RRB GOTOX is off by 1
    [#337](https://github.com/MEGA65/mega65-core/issues/337)
  - Hyppo All-RAM access (ROMLOAD, fonts)
    [#634](https://github.com/MEGA65/mega65-core/issues/634)
    [#676](https://github.com/MEGA65/mega65-core/issues/676)
  - SD-Card related fixes
    [#643](https://github.com/MEGA65/mega65-core/issues/643)
    [#646](https://github.com/MEGA65/mega65-core/issues/646)
    [PR#647](https://github.com/MEGA65/mega65-core/pull/647)
    [#669](https://github.com/MEGA65/mega65-core/issues/669)
- FREEZER updated to release 0.3.0
  - Disable EXROM/GAME so cartidge ROM does not kill freezer
    [freezer#56](https://github.com/MEGA65/mega65-freezemenu/issues/56)
  - Don't allow freeze when no slot != 0 was selected
    [freezer#61](https://github.com/MEGA65/mega65-freezemenu/issues/61)
  - Make slot restore/save menu key line clearer and don't allow wrong presses
    [freezer#66](https://github.com/MEGA65/mega65-freezemenu/issues/66)
  - Always restore charset when entering FREEZER from `CHARSET.M65` or `MEGA65.ROM`
    [freezer#67](https://github.com/MEGA65/mega65-freezemenu/issues/67)
  - Fix corrupted computer frame
    [freezer#68](https://github.com/MEGA65/mega65-freezemenu/issues/68)
  - AUDIOMIX: fix simple mode (now changes HDMI and jack at the same time)
    [freezer#69](https://github.com/MEGA65/mega65-freezemenu/issues/69)
  - MEGAINFO: support for new PCBs (r4 - r6)
    [freezer#71](https://github.com/MEGA65/mega65-freezemenu/issues/71)
  - Always chdir root after image selection, so tools will start
    [freezer#79](https://github.com/MEGA65/mega65-freezemenu/issues/79)
  - MEGAINFO: add version check for ETHLOAD.M65, remove ONBOARD.M65
    [freezer#83](https://github.com/MEGA65/mega65-freezemenu/issues/83)
  - ROMLOAD: file selector sorts directories to the top and `ROMS` to the very top
    [freezer#84](https://github.com/MEGA65/mega65-freezemenu/issues/84)
  - Faster navigation (left/right, up/down, comma/period, home)
    [freezer#85](https://github.com/MEGA65/mega65-freezemenu/issues/85)
  - Don't allow F5-RESET on slots != 0
    [freezer#86](https://github.com/MEGA65/mega65-freezemenu/issues/86)
  - Set 40 MHz mode correctly
    [freezer#87](https://github.com/MEGA65/mega65-freezemenu/issues/87)
- FDISK update ro release 0.30
  - Change name of the FAT volume to MEGA65FDISK (prior name was illegal)
    [fdisk#18](https://github.com/MEGA65/mega65-fdisk/issues/18)
  - Erase Config Block
    [fdisk#19](https://github.com/MEGA65/mega65-fdisk/issues/19)
  - Fix sdcard fragmentation issues
    [fdisk#21](https://github.com/MEGA65/mega65-fdisk/issues/21)
  - Populate SD card sees 8 slots on R3
    [fdisk#20](https://github.com/MEGA65/mega65-fdisk/issues/20)
  - Populate SD does not know r4-6 yet
    [fdisk#24](https://github.com/MEGA65/mega65-fdisk/issues/24)
- Documentation
  [#639](https://github.com/MEGA65/mega65-core/issues/639)

### Known Bugs 0.96

- There are still some open issues with the Expansion Port, so some cartridges
  are not detected correctly by the MEGA65 core (moved to 0.97 Release)
  [#778](https://github.com/MEGA65/mega65-core/issues/778)
  [#781](https://github.com/MEGA65/mega65-core/issues/781)
- Mouse Support has open issues
  [#751](https://github.com/MEGA65/mega65-core/issues/751)
- MEGAFLASH does not work for A100T platforms (Nexys, R2), please use
  JTAG based flashing.

## Release 0.95 (commit hash 93d55f0)

This is the Batch 2 Release (October 2022).

### ROM Release 0.95

The 0.95 Release came with ROM Version 920377.

Please see the
[ROM Changelog](https://github.com/MEGA65/mega65-rom-public/blob/main/CHANGELOG.md)
for more information.

### Changes 0.95

- MEGAFLASH/jtagflash security fixes
  [#589](https://github.com/MEGA65/mega65-core/issues/589)
  [#616](https://github.com/MEGA65/mega65-core/issues/616)
  [#611](https://github.com/MEGA65/mega65-core/issues/611)
  [#612](https://github.com/MEGA65/mega65-core/issues/612)
- Fixed placement of I/O components to improve build quality
  [#603](https://github.com/MEGA65/mega65-core/issues/603)
- Fdisk tool improvements (rescan bus, skip or select population)
  [fdisk#10](https://github.com/MEGA65/mega65-fdisk/issues/10)
  [fdisk#11](https://github.com/MEGA65/mega65-fdisk/issues/11)
  [fdisk#12](https://github.com/MEGA65/mega65-fdisk/issues/12)
  [fdisk#13](https://github.com/MEGA65/mega65-fdisk/issues/13)
- Onboarding fixes (date format, day one off bug)
- Configure menu updates (date format, mac address)
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
- Matrix monitor @ fix
  [#596](https://github.com/MEGA65/mega65-core/issues/596)
- check if hyppo_configsector_apply handles PAL/NTSC switch correctly
  [#615](https://github.com/MEGA65/mega65-core/issues/615)
- FREEZER updates (mounting, audiomixer, sprited, romload)
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
  [freezer#27](https://github.com/MEGA65/mega65-freezemenu/issues/27)
  [freezer#23](https://github.com/MEGA65/mega65-freezemenu/issues/23)
- MC Text mode fixes
  [#420](https://github.com/MEGA65/mega65-core/issues/420)
- MCM + VIC-III/IV behaviour less surprising
  [#571](https://github.com/MEGA65/mega65-core/issues/571)
- Inline DMA jobs
  [#580](https://github.com/MEGA65/mega65-core/issues/580)
- Tiled Sprite end pos
  [#579](https://github.com/MEGA65/mega65-core/issues/579)
- Hyppotest improvements
  [#525](https://github.com/MEGA65/mega65-core/issues/525)
- Joystick port interface via PMOD
  [#521](https://github.com/MEGA65/mega65-core/issues/521)
- VFAT fixes
  [#539](https://github.com/MEGA65/mega65-core/issues/539)
- DMA line improvements
  [#401](https://github.com/MEGA65/mega65-core/issues/401)
- 32bit opcode next op bugfix
  [#535](https://github.com/MEGA65/mega65-core/issues/535)
- Fix ASCII keyscanner tables
  [#532](https://github.com/MEGA65/mega65-core/issues/532)
- SID Frequenzy correction 1MHz
  [#449](https://github.com/MEGA65/mega65-core/issues/449)
- SID 8580 waveform
  [#477](https://github.com/MEGA65/mega65-core/issues/477)
- Ethernet enhancements
  [#523](https://github.com/MEGA65/mega65-core/issues/523)
- Remove 1541/6502 from mega65r2 target
- Lots of documentation fixes (iomap.txt, user-guide)

## Release 0.9 (commit hash f7554a8)

This is the Batch 1 Release (January 2022). Please look into
[mega65-core](https://github.com/MEGA65/mega65-core/) for a
complete changelog.

### ROM Release 0.9

The 0.9 Release came with ROM Version 920287.

Please see the
[ROM Changelog](https://github.com/MEGA65/mega65-rom-public/blob/main/CHANGELOG.md)
for more information.
